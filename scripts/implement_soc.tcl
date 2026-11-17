# Vivado 2023.2: vivado -mode batch -source scripts/implement_soc.tcl
# Optional Tcl args: output-directory board (nexys4 or nexys4_ddr).
set repo_root [file normalize [file join [file dirname [info script]] ..]]
proc build_soc {repo out board} {
    set part xc7a100tcsg324-1
    set_param general.maxThreads 4
    file mkdir $out
    cd $out
    create_project -force soc_project project -part $part
    set_property target_language Verilog [current_project]
    set_property simulator_language Mixed [current_project]
    file mkdir src/core src/soc mem
    foreach area {core soc} {
        foreach f [glob [file join $repo rtl $area *]] {
            if {[file extension $f] in {.v .vhd}} {file copy -force $f [file join src $area [file tail $f]]}
        }
    }
    foreach name {IMEM DMEM} {file copy -force [file join $repo mem ${name}.coe] mem/${name}.coe}
    # Pin assignments and input oscillator clock; remove the legacy blanket
    # inter-clock max-delay, which would hide real 100 MHz/50 MHz crossings.
    set f [open [file join $repo constraints ${board}.xdc] r]
    set original_xdc [read $f]
    close $f
    set f [open board.xdc w]
    foreach line [split $original_xdc \n] {
        if {[regexp {^\s*set_max_delay\s+20\s+-from\s+\[all_clocks\]} $line]} {
            puts "SOC AUDIT: omitted legacy blanket 20 ns inter-clock exception"
        } else {puts $f $line}
    }
    close $f
    create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0
    set_property -dict [list CONFIG.PRIM_IN_FREQ 100.000 CONFIG.PRIM_SOURCE No_buffer \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 50.000 CONFIG.CLKOUT2_USED true \
        CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 100.000 CONFIG.USE_RESET true \
        CONFIG.RESET_TYPE ACTIVE_HIGH CONFIG.USE_LOCKED true] [get_ips clk_wiz_0]
    foreach {module depth bytes coe} {blk_mem_gen_0 8192 false IMEM blk_mem_gen_1 4096 true DMEM} {
        create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.4 -module_name $module
        set_property -dict [list CONFIG.Memory_Type True_Dual_Port_RAM \
            CONFIG.Write_Width_A 32 CONFIG.Read_Width_A 32 CONFIG.Write_Depth_A $depth \
            CONFIG.Write_Width_B 32 CONFIG.Read_Width_B 32 \
            CONFIG.Enable_A Use_ENA_Pin CONFIG.Enable_B Use_ENB_Pin \
            CONFIG.Use_RSTA_Pin true CONFIG.Use_RSTB_Pin true \
            CONFIG.Register_PortA_Output_of_Memory_Primitives false \
            CONFIG.Register_PortB_Output_of_Memory_Primitives false \
            CONFIG.Register_PortA_Output_of_Memory_Core false \
            CONFIG.Register_PortB_Output_of_Memory_Core false \
            CONFIG.Assume_Synchronous_Clk true CONFIG.Use_Byte_Write_Enable $bytes \
            CONFIG.Byte_Size 8 CONFIG.Operating_Mode_A READ_FIRST CONFIG.Operating_Mode_B READ_FIRST \
            CONFIG.Load_Init_File true CONFIG.Coe_File [file normalize mem/${coe}.coe] \
            CONFIG.Fill_Remaining_Memory_Locations true CONFIG.Remaining_Memory_Locations 0] [get_ips $module]
    }
    create_ip -name c_counter_binary -vendor xilinx.com -library ip -version 12.0 -module_name c_counter_binary_0
    set_property -dict [list CONFIG.Output_Width 32 CONFIG.SCLR true CONFIG.CE false \
        CONFIG.Count_Mode UP CONFIG.Increment_Value 1] [get_ips c_counter_binary_0]
    # Synthesize IP with the whole design rather than leaving OOC black boxes.
    foreach ip [get_ips] {
        generate_target all $ip
        set_property generate_synth_checkpoint false [get_files [get_property IP_FILE $ip]]
        report_property -all -file [get_property NAME $ip]_config.rpt $ip
    }
    read_verilog [glob src/core/*.v]
    read_verilog [glob src/soc/*.v]
    read_vhdl [glob src/soc/*.vhd]
    read_xdc board.xdc
    update_compile_order -fileset sources_1
    set_property top fpga_top [current_fileset]
    synth_design -top fpga_top -part $part -flatten_hierarchy rebuilt
    # Real MMCM-generated clocks are retained and timed together. No OOC
    # virtual clock source, asynchronous clock groups, or multicycle blanket.
    set_clock_uncertainty 0.100 [get_clocks]
    if {[llength [get_cells -hier -filter {IS_BLACKBOX == 1}]]} {error "Unresolved black boxes remain in the SoC"}
    write_checkpoint -force synthesized.dcp
    report_clocks -file clocks.rpt
    report_clock_interaction -file clock_interaction.rpt
    report_exceptions -file exceptions.rpt
    report_utilization -hierarchical -file utilization_synth.rpt
    check_timing -verbose -file check_timing_synth.rpt
    report_drc -file drc_synth.rpt
    opt_design
    place_design
    write_checkpoint -force placed.dcp
    report_timing_summary -report_unconstrained -file timing_placed.rpt
    phys_opt_design
    route_design
    write_checkpoint -force routed.dcp
    report_route_status -file route_status.rpt
    report_utilization -hierarchical -file utilization_routed.rpt
    report_timing_summary -report_unconstrained -check_timing_verbose -max_paths 20 -file timing_routed.rpt
    report_timing -delay_type max -max_paths 30 \
        -path_type full_clock_expanded -input_pins -file critical_paths.rpt
    report_timing -delay_type min -max_paths 10 \
        -path_type full_clock_expanded -file hold_paths.rpt
    report_drc -file drc_routed.rpt
    report_clock_interaction -file clock_interaction_routed.rpt
    set f [open summary.txt w]
    puts $f "Top: fpga_top; part: $part; board: $board"
    puts $f "100 MHz board input; requested 50 MHz CPU, 100 MHz BRAM; user uncertainty 0.100 ns"
    puts $f "Scope: complete implemented board top; asynchronous/external I/O delays remain unspecified."
    puts $f "Legacy blanket max-delay omitted; clocks retain real MMCM relationships."
    foreach delay {max min} {
        set path [get_timing_paths -delay_type $delay -max_paths 1]
        puts $f "Delay type: $delay"
        foreach prop {SLACK REQUIREMENT DATAPATH_DELAY LOGIC_LEVELS STARTPOINT_PIN ENDPOINT_PIN} {
            puts $f "$prop: [get_property $prop $path]"
        }
    }
    close $f
    puts "SOC AUDIT: synthesis and routed implementation complete (see reports for violations)"
}
set out [file join $repo_root sim build vivado_soc]
set board nexys4
if {[llength $argv]>0} {set out [file normalize [file join $repo_root [lindex $argv 0]]]}
if {[llength $argv]>1} {set board [lindex $argv 1]}
if {$board ni {nexys4 nexys4_ddr}} {error "Board must be nexys4 or nexys4_ddr"}
if {[catch {build_soc $repo_root $out $board} message options]} {
    puts stderr "SOC AUDIT FAILED: $message"
    puts stderr [dict get $options -errorinfo]
    exit 1
}
exit 0
