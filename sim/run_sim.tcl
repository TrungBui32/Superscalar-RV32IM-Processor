# ============================================================
# Vivado Non-GUI Simulation Script (Single-folder version)
# ============================================================

# Create simulation directory
set simdir ./sim
file mkdir $simdir
cd $simdir

# ============================================================
# Compile and Elaborate
# ============================================================
# Since test_tb.v is in the same folder as run_sim.tcl, use relative path ./test_tb.v
exec xvlog -sv ../sim/tb_soc.v

# Elaborate the testbench top-level module
exec xelab tb_soc -s tb_soc_sim

# ============================================================
# Simulation Control File
# ============================================================

# Create a Tcl batch file for simulation commands
set fp [open sim_cmds.tcl w]
puts $fp {
    ############################################################
    # Log selected signals
    ############################################################

    # Log UART_TX signal from Wrapper
    log_wave [get_objects /soc_top/UART_TX]

    # Log all signals from Wrapper/RV hierarchy (recursively)
    log_wave -r [get_objects -r /soc_top/core/*]

    ############################################################
    # Run simulation and save waveform
    ############################################################
    run 3ms
    write_waveform -force test_tb.wdb
    exit
}
close $fp

# ============================================================
# Launch simulation
# ============================================================
exec xsim tb_soc_sim -tclbatch sim_cmds.tcl
exit
