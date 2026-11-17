`timescale 1ns/1ps
module tb_atomic_core;
    localparam BASE=32'h80000000;
    reg clk=0,rst=1,imem_ready=1,dmem_ready=1,irq=0;
    always #5 clk=~clk;
    reg [31:0] mem[0:65535];
    wire [31:0] pc,addr0,addr1,wdata0,wdata1;
    wire [2:0] we0,we1;
    integer seed=0,inject=0,hold_count=0,cycles=0,limit=250000,unused,i,lane;
    integer requests=0,responses=0,atomic_reads=0,atomic_writes=0,owner0=0,owner1=0,traps=0;
    reg injected=0;
    reg [31:0] random_state=1,tohost=0;
    reg [2047:0] image;
    function [31:0] read_word(input [31:0] a);
        // Upper 256 KiB is a deliberate normal-access alias, used to verify
        // conservative reservation invalidation with aliased backing RAM.
        if(a>=BASE && a<BASE+32'h80000)read_word=mem[((a-BASE)&32'h3ffff)>>2];
        else read_word=0;
    endfunction
    wire [31:0] instr0=read_word(pc),instr1=read_word(pc+4);
    wire [31:0] rdata0=read_word(addr0)>>(addr0[1:0]*8);
    wire [31:0] rdata1=read_word(addr1)>>(addr1[1:0]*8);
    wire [63:0] ticks={32'b0,cycles[31:0]};
    core #(.PC_INIT(BASE),.ATOMIC_BASE(BASE),.ATOMIC_MASK(32'hfffc0000)) dut(
        .CLK(clk),.RESET(rst),.locked(1'b1),.imem_ready(imem_ready),.dmem_ready(dmem_ready),
        .irq_software(1'b0),.irq_timer(irq),.irq_external(1'b0),.time_value(ticks),
        .Instr_pipe0(instr0),.Instr_pipe1(instr1),.ReadData_in_pipe0(rdata0),.ReadData_in_pipe1(rdata1),
        .PC(pc),.MemWrite_out_pipe0(we0),.MemWrite_out_pipe1(we1),
        .ALUResult_pipe0(addr0),.ALUResult_pipe1(addr1),
        .WriteData_out_pipe0(wdata0),.WriteData_out_pipe1(wdata1)
    );
    always @(negedge clk) if(!rst)begin
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        imem_ready=seed==0 || random_state[3:0]!=0;
        dmem_ready=seed==0 || random_state[1:0]!=0;
        if(hold_count>0)begin dmem_ready=0;hold_count--;end
        if(tohost!=0 && read_word(tohost)!=0)begin
            if(read_word(tohost)!==1)$fatal(1,"FAIL cycles=%0d test=%0d cause=%h mepc=%h tval=%h",cycles,read_word(tohost)>>1,dut.csr_inst.mcause,dut.csr_inst.mepc,dut.csr_inst.mtval);
            if(requests!=responses)$fatal(1,"unconsumed atomic response");
            if(inject && (!injected || traps!=1))$fatal(1,"interrupt not exercised");
            $display("PASS cycles=%0d requests=%0d reads=%0d writes=%0d owners=%0d/%0d traps=%0d",cycles,requests,atomic_reads,atomic_writes,owner0,owner1,traps);
            $finish;
        end
    end
    always @(posedge clk)if(!rst)begin
        cycles++;
        if(cycles>limit)$fatal(1,"timeout pc=%h cause=%h tval=%h",pc,dut.csr_inst.mcause,dut.csr_inst.mtval);
        if(dut.atomic_inst.request_fire)begin requests++;if(dut.atomic_owner1)owner1++;else owner0++;end
        if(dut.atomic_rsp_valid && dut.atomic_rsp_ready)responses++;
        if(dut.atomic_bus_fire)begin
            if(!dut.atomic_lock_req || !dut.atomic_present)$fatal(1,"unowned atomic access");
            if(dut.atomic_mem0 && dut.atomic_mem1)$fatal(1,"two atomic owners");
            if(dut.atomic_bus_write)atomic_writes++;else atomic_reads++;
        end
        if(dut.atomic_present)begin
            if((dut.atomic_mem0 && dut.valid_mem_pipe1) || (dut.atomic_mem1 && dut.valid_mem_pipe0))$fatal(1,"atomic was not serialized");
            if(dut.atomic_mem0 && (we1 || dut.LwSizeSel_pipe1))$fatal(1,"pipe1 interleaved atomic");
            if(dut.atomic_mem1 && (we0 || dut.LwSizeSel_pipe0))$fatal(1,"pipe0 interleaved atomic");
        end
        if(dut.valid_mem_pipe0 && dut.sync_fault0 && (we0 || dut.LwSizeSel_pipe0))$fatal(1,"fault0 leaked memory access");
        if(dut.valid_mem_pipe1 && dut.sync_fault1 && (we1 || dut.LwSizeSel_pipe1))$fatal(1,"fault1 leaked memory access");
        if((!imem_ready || !dmem_ready) && (we0 || we1))$fatal(1,"write during bus stall");
        if(dut.csr_trap_fire)traps++;
        if(inject && !injected &&
           ((inject==1 && dut.atomic_bus_fire && !dut.atomic_bus_write) ||
            (inject==2 && dut.atomic_bus_fire && dut.atomic_bus_write) ||
            (inject==3 && dut.atomic_rsp_valid)))begin
            irq<=1;injected<=1;hold_count=3;
        end
        if(dut.irq_fire)begin
            if(dut.atomic_present || dut.atomic_lock_req)$fatal(1,"interrupt split an atomic");
            irq<=0;
        end
        for(lane=0;lane<4;lane++)begin
            if(lane<(we0[2]?4:we0[1]?2:we0[0]?1:0) && addr0>=BASE && addr0+lane<BASE+32'h80000)
                mem[(((addr0+lane)-BASE)&32'h3ffff)>>2][((addr0+lane)&3)*8+:8]<=wdata0[lane*8+:8];
            if(lane<(we1[2]?4:we1[1]?2:we1[0]?1:0) && addr1>=BASE && addr1+lane<BASE+32'h80000)
                mem[(((addr1+lane)-BASE)&32'h3ffff)>>2][((addr1+lane)&3)*8+:8]<=wdata1[lane*8+:8];
        end
    end
    initial begin
        for(i=0;i<65536;i++)mem[i]=0;
        if(!$value$plusargs("mem=%s",image))$fatal(1,"missing image");
        unused=$value$plusargs("tohost=%h",tohost);
        unused=$value$plusargs("seed=%d",seed);
        unused=$value$plusargs("inject=%d",inject);
        random_state=seed==0 ? 1:seed;
        $readmemh(image,mem);
        repeat(4)@(negedge clk);rst=0;
    end
endmodule
