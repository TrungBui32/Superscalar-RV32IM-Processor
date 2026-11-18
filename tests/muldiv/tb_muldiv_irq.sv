`timescale 1ns/1ps
module tb_muldiv_irq;
    reg clk=0, rst=1, irq=0, data_ready=1;
    always #5 clk=~clk;
    reg [31:0] rom[0:511];
    wire [31:0] pc;
    integer mode=0, slot=0, stalls=0, arrival=0, unused, i, op_index;
    integer cycles=0, requests=0, traps=0, returns=0;
    reg [31:0] saved_pc, saved_cause;
    core #(.PC_INIT(0), .DEBUG_HALT_ON_EBREAK(1)) dut(
        .CLK(clk), .RESET(rst), .locked(1'b1),
        .imem_fault(2'b0), .dmem_fault(2'b0), .imem_ready(1'b1), .dmem_ready(data_ready),
        .irq_software(1'b0), .irq_timer(irq), .irq_external(1'b0), .time_value(64'b0),
        .Instr_pipe0(rom[pc[10:2]]), .Instr_pipe1(rom[pc[10:2]+9'd1]),
        .ReadData_in_pipe0(32'b0), .ReadData_in_pipe1(32'b0), .PC(pc)
    );
    function [31:0] addi(input [4:0] rd, rs, input [11:0] imm);
        addi={imm,rs,3'b0,rd,7'h13};
    endfunction
    function [31:0] csr(input [2:0] f, input [4:0] rd, input [11:0] addr, input [4:0] rs);
        csr={addr,rs,f,rd,7'h73};
    endfunction
    function [31:0] mdu(input [2:0] f, input [4:0] rd, rs1, rs2);
        mdu={7'b0000001,rs2,rs1,f,rd,7'h33};
    endfunction
    always @(posedge clk) if(!rst) begin
        cycles++;
        if(dut.muldiv_unit1.request_fire) requests++;
        if(dut.csr_trap_fire) begin
            traps++;
            saved_pc=dut.csr_trap_pc;
            saved_cause=dut.trap_cause;
        end
        if(dut.mret_fire) returns++;
        if(cycles>1500) $fatal(1,"muldiv IRQ timeout");
    end
    initial begin
        unused=$value$plusargs("mode=%d",mode);
        unused=$value$plusargs("slot=%d",slot);
        unused=$value$plusargs("stalls=%d",stalls);
        unused=$value$plusargs("arrival=%d",arrival);
        for(i=0;i<512;i++) rom[i]=32'h13;
        rom[0]=addi(30,0,'h600); rom[1]=csr(1,0,'h305,30);
        rom[2]=addi(2,0,'h80); rom[3]=csr(1,0,'h304,2);
        rom[4]=csr(6,0,'h300,8); // enable machine interrupts
        rom[5]=addi(1,0,-21); rom[6]=addi(2,0,4);
        op_index=8+slot;
        rom[op_index]=mdu(mode ? 4 : 0,3,1,2);
        rom[op_index+1]=addi(20,20,1);
        rom[op_index+2]=mdu(0,4,3,2);
        rom[op_index+3]=addi(21,21,1);
        rom[op_index+4]=32'h00100073;
        // Reuse the unit inside the handler before returning to main code.
        rom[384]=csr(2,10,'h342,0); rom[385]=csr(2,11,'h341,0);
        rom[386]=mdu(0,12,1,2); rom[387]=mdu(4,13,12,2);
        rom[388]=32'h30200073;
        repeat(4) @(negedge clk);
        rst=0;
        wait(dut.is_ebreak_wb); @(negedge clk);
        if(traps!=1 || returns!=1 || saved_cause!==32'h80000007 ||
           saved_pc<(op_index+1)*4 || saved_pc>(op_index+3)*4 || saved_pc[1:0]!=0)
            $fatal(1,"imprecise IRQ traps=%0d returns=%0d cause=%h pc=%h",traps,returns,saved_cause,saved_pc);
        if(requests!=4 || dut.reg_file_inst.RegBank[3]!==(mode ? -32'd5 : -32'd84) ||
           dut.reg_file_inst.RegBank[4]!==(mode ? -32'd20 : -32'd336) ||
           dut.reg_file_inst.RegBank[12]!==-32'd84 || dut.reg_file_inst.RegBank[13]!==-32'd21 ||
           dut.reg_file_inst.RegBank[20]!==1 || dut.reg_file_inst.RegBank[21]!==1)
            $fatal(1,"lost/replayed muldiv across IRQ requests=%0d",requests);
        $display("PASS IRQ mode=%0d slot=%0d stalls=%0d arrival=%0d cycles=%0d",mode,slot,stalls,arrival,cycles);
        $finish;
    end
    initial begin
        wait(!rst);
        wait(requests==1);
        if(arrival) wait(!dut.MCycle_Busy);
        @(negedge clk); irq=1;
        if(stalls) begin
            data_ready=0;
            repeat(3) @(negedge clk);
            data_ready=1;
        end
        wait(traps==1);
        @(negedge clk); irq=0;
    end
endmodule
