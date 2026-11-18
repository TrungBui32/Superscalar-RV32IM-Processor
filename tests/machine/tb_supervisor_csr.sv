`timescale 1ns/1ps
module tb_supervisor_csr;
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
    reg sret_valid=0;
    wire [1:0] current_privilege,data_privilege;
    wire allow_sret,allow_wfi;
    wire [31:0] supervisor_return_pc;
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
    task ret_m;
        begin @(negedge clk);mret_valid=1;@(negedge clk);mret_valid=0;#1;end
    endtask
    task ret_s;
        begin @(negedge clk);sret_valid=1;@(negedge clk);sret_valid=0;#1;end
    endtask
    task take(input [31:0] cause,pc,value);
        begin @(negedge clk);trap_cause=cause;trap_pc=pc;trap_value=value;trap_valid=1;
        @(negedge clk);trap_valid=0;#1;end
    endtask
    task bad(input [11:0] addr);
        begin csr_raddr_pipe0=addr;csr_raddr_pipe1=addr;#1;
            if(!csr_rillegal_pipe0 || !csr_rillegal_pipe1)$fatal(1,"forbidden read %h mode=%0d",addr,current_privilege);
            csr_waddr_pipe0=addr;csr_wdata_pipe0=32'hffffffff;csr_wvalid_pipe0=1;#1;
            if(!csr_willegal_pipe0)$fatal(1,"forbidden write %h",addr);
            @(negedge clk);csr_wvalid_pipe0=0;
        end
    endtask
    initial begin
        @(negedge clk);rst=0;
        if(current_privilege!==3)$fatal(1,"reset privilege");
        ck('h301,'h40141101);ck('h180,0);wr('h180,32'hffffffff);ck('h180,0);
        wr('h302,32'hffffffff);ck('h302,'h3ff);wr('h302,0);
        wr('h303,32'hffffffff);ck('h303,'h222);
        wr('h300,32'hffffffff);ck('h100,'h122);
        wr('h100,0);ck('h300,'h621888);
        wr('h100,32'hffffffff);ck('h300,'h6219aa);
        wr('h304,'haaa);ck('h104,'h222);
        wr('h104,0);ck('h304,'h888);
        wr('h344,'h222);ck('h144,'h222);
        wr('h144,0);ck('h344,'h220); // S-view only writes SSIP.
        forward_valid=4'b0011;
        forward_addr={24'b0,12'h100,12'h300};
        forward_data={64'b0,32'h22,32'h1888};
        ck('h300,'h18aa);ck('h100,'h22);
        forward_addr={24'b0,12'h104,12'h304};
        forward_data={64'b0,32'h222,32'h888};
        ck('h304,'haaa);ck('h104,'h222);
        forward_valid=0;
        wr('h344,0);wr('h304,0);
        wr('h300,'h1000);ck('h300,0); // Reserved MPP=2 coerces to U.
        wr('h306,5);wr('h106,1);wr('h300,'h880);ret_m;
        if(current_privilege!==1)$fatal(1,"MRET to S");
        bad('h300);ck('hc00,dut.mcycle[31:0]);bad('hc01);
        ck('hc02,dut.minstret[31:0]);ck('h100,0);
        wr('h141,'h207);ck('h141,'h204);wr('h100,'h20);ret_s;
        if(current_privilege!==0 || supervisor_return_pc!=='h204)$fatal(1,"SRET to U");
        ck('hc00,dut.mcycle[31:0]);bad('hc02);bad('h100);bad('h300);
        take(2,'h3000,'hdead); // No delegation: U -> M.
        ck('h341,'h3000);ck('h342,2);ck('h343,'hdead);
        if(current_privilege!==3 || dut.mstatus[12:11]!==0)$fatal(1,"U -> M trap stack");
        wr('h302,'h304); // Delegate illegal instruction and U/S ECALL.
        wr('h105,'h101);wr('h305,'h201);
        trap_cause=8;#1;if(trap_vector!=='h200)$fatal(1,"M trap delegated downward");
        take(8,'h444,0);if(current_privilege!==3)$fatal(1,"M trap target");ret_m;
        wr('h300,'h80);ret_m; // M -> U.
        trap_cause=8;#1;if(trap_vector!=='h100)$fatal(1,"sync delegated trap must use base");
        take(8,'h800,0);
        if(current_privilege!==1)$fatal(1,"U ECALL target");
        ck('h141,'h800);ck('h142,8);ck('h143,0);
        if(dut.mstatus[8]!==0 || dut.mstatus[1]!==0)$fatal(1,"U -> S status");
        wr('h100,2);take(9,'h900,0);
        ck('h142,9);
        if(!dut.mstatus[8] || !dut.mstatus[5] || dut.mstatus[1])$fatal(1,"S -> S status");
        ret_s;if(current_privilege!==1 || !dut.mstatus[1] || dut.mstatus[8])$fatal(1,"SRET to S status");
        // Machine interrupt ignores MIE while running S; S CSR state survives.
        take(32'h80000007,'h904,0);
        if(current_privilege!==3 || dut.mstatus[12:11]!==1)$fatal(1,"S -> M interrupt");
        ck('h142,9);ck('h141,'h900);ret_m;
        if(current_privilege!==1)$fatal(1,"machine return to interrupted S");
        take(7,'h908,'h5000); // Nondelegated store access fault returns to M.
        wr('h302,0);wr('h303,2);wr('h304,2);wr('h344,2);wr('h300,2);
        #1;if(interrupt_pending)$fatal(1,"delegated IRQ delivered in M");
        wr('h300,'h80);ret_m; // U receives S IRQ even with SIE=0.
        if(!interrupt_pending || interrupt_cause!==32'h80000001)$fatal(1,"U supervisor IRQ enable");
        trap_cause=32'h80000001;#1;if(trap_vector!=='h104)$fatal(1,"supervisor vectored IRQ");
        take(32'h80000001,'h1000,0);
        if(current_privilege!==1 || interrupt_pending)$fatal(1,"S IRQ mask on trap");
        wr('h144,0);ret_s;if(interrupt_pending)$fatal(1,"SSIP clear");
        take(2,'h1000,0);
        wr('h304,'h888);wr('h300,0);irq_timer=1;#1;
        if(interrupt_pending)$fatal(1,"MIE ignored in M");
        wr('h300,'h800);ret_m; // MIE remains zero, but S is interruptible by M.
        if(!interrupt_pending || interrupt_cause!==32'h80000007)$fatal(1,"machine IRQ blocked in S");
        irq_timer=0;take(9,'h1100,0);
        wr('h300,'h700880);ret_m;
        if(allow_sret || allow_wfi)$fatal(1,"TSR/TW/TVM ignored");
        ck('h180,0);if(dut.mstatus[20])$fatal(1,"TVM must be zero in Bare");take(9,'h1200,0);
        wr('h300,'h20000);
        if(data_privilege!==0 || current_privilege!==3)$fatal(1,"MPRV effective U");
        ret_m;
        if(current_privilege!==0 || dut.mstatus[17])$fatal(1,"MRET failed to clear MPRV");
        take(2,'h1300,0);
        wr('h300,'h20000);wr('h100,'h20);ret_s;
        if(current_privilege!==0 || dut.mstatus[17])$fatal(1,"M-mode SRET/MPRV");
        $display("PASS supervisor CSR aliases, privilege access, delegation, IRQ routing, xRET, Bare/TSR/TW, MPRV");$finish;
    end
    initial begin #100000;$fatal(1,"supervisor CSR timeout");end
endmodule
