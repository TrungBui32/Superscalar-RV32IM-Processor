`timescale 1ns/1ps
module tb_machine_core;
    reg clk=0,rst=1,ir=1,dr=1;
    reg [31:0] memory[0:16383];
    wire [31:0] pc,a0,a1,w0,w1;
    wire [2:0] we0,we1,size0,size1;
    wire [1:0] writes;
    wire [4:0] re0,re1;
    reg [31:0] bad_addr=32'hffffffff,bad_pc=32'hffffffff;
    integer mode=0,seed=0,cycles=0,i,lane,ignored,traps=0,returns=0;
    reg [31:0] random_state=1;
    reg [2047:0] image;
    reg [31:0] tohost=0;
    wire [1:0] ifault={(pc+4==bad_pc || pc>=65532),(pc==bad_pc || pc>=65536)};
    function failed(input [31:0] addr,input write_access);
        failed=addr>=65536 || (addr==bad_addr && (mode==0 || (mode==1 && !write_access) || (mode==2 && write_access)));
    endfunction
    wire [1:0] dfault={failed(a1,writes[1]),failed(a0,writes[0])};
    wire [31:0] r0=a0<65536 ? memory[a0>>2]>>(a0[1:0]*8) : 0;
    wire [31:0] r1=a1<65536 ? memory[a1>>2]>>(a1[1:0]*8) : 0;
    reg [63:0] ticks=0;
    wire sw_irq,timer_irq;
    wire [31:0] timer_r0,timer_r1;
    wire timer_hit0,timer_hit1;
    wire [3:0] strb0=we0[2]?4'hf:we0[1]?(4'h3<<a0[1:0]):we0[0]?(4'h1<<a0[1:0]):0;
    wire [3:0] strb1=we1[2]?4'hf:we1[1]?(4'h3<<a1[1:0]):we1[0]?(4'h1<<a1[1:0]):0;
    // Optional real CLINT-style timer for the integrated context-switch test.
    reg timer_enabled=0;
    machine_timer timer(.clk(clk),.rst(rst),.addr_pipe0(a0),.addr_pipe1(a1),
        .wdata_pipe0(w0<<(a0[1:0]*8)),.wdata_pipe1(w1<<(a1[1:0]*8)),
        .wstrb_pipe0(strb0),.wstrb_pipe1(strb1),.rdata_pipe0(timer_r0),.rdata_pipe1(timer_r1),
        .hit_pipe0(timer_hit0),.hit_pipe1(timer_hit1),.irq_software(sw_irq),.irq_timer(timer_irq),.time_value());
    core #(.PC_INIT(0)) dut(
        .CLK(clk),.RESET(rst),.locked(1'b1),.imem_ready(ir),.dmem_ready(dr),
        .imem_fault(ifault),.dmem_fault({timer_enabled&&timer_hit1?1'b0:dfault[1],timer_enabled&&timer_hit0?1'b0:dfault[0]}),
        .dmem_write_intent(writes),.dmem_size_pipe0(size0),.dmem_size_pipe1(size1),
        .irq_software(timer_enabled&&sw_irq),.irq_timer(timer_enabled&&timer_irq),.irq_external(1'b0),.time_value(ticks),
        .Instr_pipe0(pc<65536 ? memory[pc>>2] : 32'hffffffff),
        .Instr_pipe1(pc<65532 ? memory[(pc>>2)+1] : 32'hffffffff),
        .ReadData_in_pipe0(timer_enabled&&timer_hit0 ? timer_r0>>(a0[1:0]*8) : r0),
        .ReadData_in_pipe1(timer_enabled&&timer_hit1 ? timer_r1>>(a1[1:0]*8) : r1),
        .PC(pc),.MemRead(),.MemWrite_out_pipe0(we0),.MemWrite_out_pipe1(we1),
        .ALUResult_pipe0(a0),.ALUResult_pipe1(a1),.WriteData_out_pipe0(w0),.WriteData_out_pipe1(w1),
        .LwSizeSel_pipe0(re0),.LwSizeSel_pipe1(re1));
    always #5 clk=~clk;
    always @(negedge clk)if(!rst)begin
        if(seed!=0)begin
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            ir=(random_state[3:0]!=0);dr=(random_state[1:0]!=0);
        end
        if(memory[tohost>>2]!=0)begin
            if(memory[tohost>>2]!==1)$fatal(1,"program failure=%h pc=%h mepc=%h cause=%h tval=%h",memory[tohost>>2],pc,dut.csr_inst.mepc,dut.csr_inst.mcause,dut.csr_inst.mtval);
            $display("PASS cycles=%0d traps=%0d returns=%0d",cycles,traps,returns);$finish;
        end
    end
    always @(posedge clk)if(!rst)begin
        cycles++;ticks<=ticks+1;
        if(cycles>100000)$fatal(1,"timeout pc=%h mepc=%h cause=%h tval=%h",pc,dut.csr_inst.mepc,dut.csr_inst.mcause,dut.csr_inst.mtval);
        if(dut.csr_trap_fire)traps++;
        if(dut.mret_fire)returns++;
        if((!ir || !dr) && (we0 || we1))$fatal(1,"write during stall");
        if((we0 && dfault[0] && !(timer_enabled&&timer_hit0)) || (we1 && dfault[1] && !(timer_enabled&&timer_hit1)))$fatal(1,"faulting store reached bus");
        if(dut.csr_trap_pipe0 && (we1 || re1))$fatal(1,"younger data operation survived older fault");
        for(lane=0;lane<4;lane++)begin
            if(lane<(we0[2]?4:we0[1]?2:we0[0]?1:0) && a0+lane<65536)
                memory[(a0+lane)>>2][((a0+lane)&3)*8 +:8]<=w0[lane*8+:8];
            if(lane<(we1[2]?4:we1[1]?2:we1[0]?1:0) && a1+lane<65536)
                memory[(a1+lane)>>2][((a1+lane)&3)*8 +:8]<=w1[lane*8+:8];
        end
    end
    initial begin
        for(i=0;i<16384;i++)memory[i]=0;
        if(!$value$plusargs("mem=%s",image))$fatal(1,"image required");
        ignored=$value$plusargs("tohost=%h",tohost);
        ignored=$value$plusargs("bad_addr=%h",bad_addr);ignored=$value$plusargs("bad_pc=%h",bad_pc);
        ignored=$value$plusargs("mode=%d",mode);ignored=$value$plusargs("seed=%d",seed);
        timer_enabled=$test$plusargs("timer");random_state=seed==0?1:seed;
        $readmemh(image,memory);repeat(4)@(negedge clk);rst=0;
    end
endmodule
