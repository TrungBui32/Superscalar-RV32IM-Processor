`timescale 1ns/1ps
module tb_machine_csr;
    reg clk=0,rst=1,trap_valid=0,mret_valid=0;
    reg [31:0] trap_pc=0,trap_cause=2,trap_value=0;
    reg irq_software=0,irq_timer=0,irq_external=0;
    reg [63:0] time_value=0;
    reg [1:0] retire_count=0;
    wire [31:0] trap_vector,return_pc,interrupt_cause;
    wire interrupt_pending;
    reg [3:0] forward_valid=0;
    reg [47:0] forward_addr=0;
    reg [127:0] forward_data=0;
    reg [11:0] csr_raddr_pipe0=0,csr_raddr_pipe1=0,csr_waddr_pipe0=0,csr_waddr_pipe1=0;
    reg [31:0] csr_wdata_pipe0=0,csr_wdata_pipe1=0;
    reg csr_rvalid_pipe0=1,csr_rvalid_pipe1=1,csr_wvalid_pipe0=0,csr_wvalid_pipe1=0;
    wire [31:0] csr_rdata_pipe0,csr_rdata_pipe1;
    wire [63:0] trigger_control, trigger_address; wire trigger_enable;
    wire [127:0] pmp_config; wire [511:0] pmp_address;
    wire csr_rillegal_pipe0,csr_rillegal_pipe1,csr_willegal_pipe0,csr_willegal_pipe1;
    csr dut(.*);
    reg clock_running=1;
    always #5 if(clock_running) clk=~clk;
    task wr(input [11:0] a,input [31:0] v);
        begin @(negedge clk);csr_waddr_pipe0=a;csr_wdata_pipe0=v;csr_wvalid_pipe0=1;
        @(negedge clk);csr_wvalid_pipe0=0;end
    endtask
    task ck(input [11:0] a,input [31:0] v);
        begin csr_raddr_pipe0=a;#1;if(csr_rillegal_pipe0 || csr_rdata_pipe0!==v)
            $fatal(1,"CSR %h got %h expected %h",a,csr_rdata_pipe0,v);end
    endtask
    function address_supported(input [11:0] address);
        begin
            case(address)
                12'h300,12'h301,12'h304,12'h305,12'h306,12'h310,12'h320,
                12'h340,12'h341,12'h342,12'h343,12'h344,
                12'hb00,12'hb02,12'hb80,12'hb82,
                12'hc00,12'hc01,12'hc02,12'hc80,12'hc81,12'hc82,
                12'hf11,12'hf12,12'hf13,12'hf14,12'hf15,
                12'h7a0,12'h7a1,12'h7a2,12'h7a4,12'h7a5: address_supported=1;
                default: address_supported=(address>=12'h3a0 && address<=12'h3a3) ||
                                           (address>=12'h3b0 && address<=12'h3bf);
            endcase
        end
    endfunction
    integer address_index,bit_index;
    initial begin
        @(negedge clk);rst=0;
        // Scan the architectural address space on both ports without writes
        // reaching a clock edge. Reserved and lower-mode CSRs must trap.
        clock_running=0;
        csr_wvalid_pipe0=1;csr_wvalid_pipe1=1;
        for(address_index=0;address_index<4096;address_index++)begin
            csr_raddr_pipe0=address_index;csr_waddr_pipe0=address_index;
            csr_raddr_pipe1=4095-address_index;csr_waddr_pipe1=4095-address_index;
            #1;
            if(csr_rillegal_pipe0!==!address_supported(csr_raddr_pipe0) ||
               csr_rillegal_pipe1!==!address_supported(csr_raddr_pipe1) ||
               csr_willegal_pipe0!==(!address_supported(csr_waddr_pipe0) || csr_waddr_pipe0[11:10]==3) ||
               csr_willegal_pipe1!==(!address_supported(csr_waddr_pipe1) || csr_waddr_pipe1[11:10]==3))
                $fatal(1,"CSR address/privilege/RO decoding at %h/%h",csr_raddr_pipe0,csr_raddr_pipe1);
        end
        csr_wvalid_pipe0=0;csr_wvalid_pipe1=0;clock_running=1;
        for(bit_index=0;bit_index<32;bit_index++)begin
            wr('h300,32'b1<<bit_index);ck('h300,32'h1800 | ((32'b1<<bit_index)&32'h88));
            wr('h304,32'b1<<bit_index);ck('h304,(32'b1<<bit_index)&32'h888);
            wr('h320,32'b1<<bit_index);ck('h320,(32'b1<<bit_index)&32'h5);
        end
        wr('h300,0);wr('h304,0);wr('h320,0);
        ck('h301,'h40001101);wr('h301,0);ck('h301,'h40001101);
        ck('h300,'h1800);wr('h300,32'hffffffff);ck('h300,'h1888);
        wr('h300,0);ck('h300,'h1800);
        wr('h304,32'hffffffff);ck('h304,'h888);
        wr('h310,32'hffffffff);ck('h310,0);
        wr('h306,32'hffffffff);ck('h306,0);
        wr('h305,'h123);ck('h305,'h120);
        wr('h305,'h125);ck('h305,'h125);
        wr('h341,'h123);ck('h341,'h120);
        ck('hf11,0);ck('hf12,0);ck('hf13,0);ck('hf14,0);ck('hf15,0);
        csr_waddr_pipe0='hf14;csr_wvalid_pipe0=1;#1;
        if(!csr_willegal_pipe0)$fatal(1,"read-only write accepted");csr_wvalid_pipe0=0;
        csr_raddr_pipe0='h100;csr_raddr_pipe1='h34a;#1;
        if(!csr_rillegal_pipe0 || !csr_rillegal_pipe1)$fatal(1,"unsupported S/H CSR exposed");
        wr('h344,32'hffffffff);ck('h344,0);
        irq_software=1;irq_timer=1;irq_external=1;ck('h344,'h888);
        if(interrupt_pending)$fatal(1,"global interrupt enable ignored");
        wr('h300,8);#1;if(!interrupt_pending || interrupt_cause!==32'h8000000b)$fatal(1,"external priority");
        irq_external=0;#1;if(interrupt_cause!==32'h80000003)$fatal(1,"software priority");
        irq_software=0;#1;if(interrupt_cause!==32'h80000007)$fatal(1,"timer priority");
        wr('h305,'h101);trap_cause=32'h80000007;#1;
        if(trap_vector!=='h11c)$fatal(1,"vectored interrupt");
        trap_cause=2;#1;if(trap_vector!=='h100)$fatal(1,"synchronous trap must use base");
        @(negedge clk);trap_valid=1;trap_pc='h127;trap_cause=32'h80000007;trap_value='hdeadbeef;
        csr_wvalid_pipe0=1;csr_waddr_pipe0='h340;csr_wdata_pipe0='hbad;
        @(negedge clk);trap_valid=0;csr_wvalid_pipe0=0;
        ck('h341,'h124);ck('h342,32'h80000007);ck('h343,'hdeadbeef);ck('h300,'h1880);ck('h340,0);
        if(interrupt_pending)$fatal(1,"trap did not disable interrupts");
        @(negedge clk);mret_valid=1;@(negedge clk);mret_valid=0;
        ck('h300,'h1888);if(!interrupt_pending || return_pc!=='h124)$fatal(1,"MRET state");
        irq_timer=0;#1;if(interrupt_pending)$fatal(1,"pending did not follow hardware");
        time_value=64'h123456789abcdef0;ck('hc01,'h9abcdef0);ck('hc81,'h12345678);

        wr('h320,32'hffffffff);ck('h320,5);
        wr('hb80,'h1234);wr('hb00,32'hffffffff);
        wr('hb82,0);wr('hb02,32'hfffffffe);
        retire_count=2;
        repeat(2)@(negedge clk);
        ck('hb80,'h1234);ck('hb00,32'hffffffff);ck('hb02,32'hfffffffe);
        wr('h320,0);@(negedge clk);
        ck('hb80,'h1235);ck('hb00,0);ck('hb82,1);ck('hb02,0);
        wr('h320,5);retire_count=0;
        wr('hb02,7);ck('hb02,7);ck('hc02,7);
        $display("PASS: M-mode CSR masks, fixed fields, IRQ ownership/priority, trap/MRET, 64-bit counters");$finish;
    end
    initial begin #200000;$fatal(1,"CSR unit timeout");end
endmodule
