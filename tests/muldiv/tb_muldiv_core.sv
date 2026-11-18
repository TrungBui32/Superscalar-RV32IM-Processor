`timescale 1ns/1ps
module tb_muldiv_core;
reg clk=0,rst=1,dr=1,ir=1;
reg [31:0] random_state=32'h41729;always #5 clk=~clk;
reg[31:0]rom[0:63];wire[31:0]pc;
integer i,cycles=0,accepts=0,stall=0,slot=0,redirect=0,mixed=0,junk;
core #(.PC_INIT(0), .DEBUG_HALT_ON_EBREAK(1)) dut(
    .CLK(clk), .RESET(rst), .locked(1'b1), .imem_fault(2'b0), .dmem_fault(2'b0), .imem_ready(ir), .dmem_ready(dr),
    .irq_software(1'b0), .irq_timer(1'b0), .irq_external(1'b0), .time_value(64'b0),
    .Instr_pipe0(rom[pc[7:2]]), .Instr_pipe1(rom[pc[7:2]+6'd1]),
    .ReadData_in_pipe0(32'b0), .ReadData_in_pipe1(32'b0), .PC(pc)
);
always@(posedge clk)if(!rst)begin
 cycles++;
 if(dut.muldiv_unit1.request_fire)accepts++;
 if(cycles>1000)$fatal(1,"timeout");
end
initial begin
 junk=$value$plusargs("stall=%d",stall);
 junk=$value$plusargs("slot=%d",slot);
 junk=$value$plusargs("mixed=%d",mixed);
 junk=$value$plusargs("redirect=%d",redirect);
 for(i=0;i<64;i++)rom[i]=32'h13;
 rom[0]=32'h00700093;rom[1]=32'h00900113;
 if(mixed)begin
  rom[0]=32'hff900093;rom[1]=32'h00300113;
  rom[2]=32'h022081b3; // mul x3,x1,x2 = -21
  rom[3]=32'h0220c233; // div x4,x1,x2 = -2
  rom[4]=32'h0220e2b3; // rem x5,x1,x2 = -1
  rom[5]=32'h0220a333; // mulhsu x6,x1,x2 = -1 (high)
  rom[6]=32'h0220b3b3; // mulhu x7,x1,x2 = 2 (high)
  rom[7]=32'h02209433; // mulh x8,x1,x2 = -1 (high)
  rom[8]=32'h0220d4b3; // divu x9,x1,x2
  rom[9]=32'h0220f533; // remu x10,x1,x2
  rom[10]=32'h0200c5b3; // div x11,x1,x0 = -1
  rom[11]=32'h0200e633; // rem x12,x1,x0 = -7
  rom[12]=32'h00118693; // addi x13,x3,1
  rom[13]=32'h02468733; // mul x14,x13,x4 = 40 (forwarded operands)
  rom[14]=32'h022747b3; // div x15,x14,x2 = 13
  rom[15]=32'h02276833; // rem x16,x14,x2 = 1
  rom[16]=32'h030788b3; // mul x17,x15,x16 = 13
  rom[17]=32'h00188913;rom[18]=32'h00100073;
 end else if(redirect)begin
  rom[2]=32'h00000663; // beq x0,x0,+12
  rom[3]=32'h00600313; // discarded alongside branch
  rom[4]=32'h022081b3; // wrong-path multiply must be discarded
  rom[5]=32'h022082b3; // target: mul x5,x1,x2
  rom[6]=32'h00128213; // addi x4,x5,1
  rom[7]=32'h00100073;
 end else begin
  rom[2+slot]=32'h022081b3;
  rom[3+slot]=32'h00118213;
  rom[4+slot]=32'h00100073;
 end
 repeat(4)@(negedge clk);rst=0;
 wait(dut.is_ebreak_wb);@(negedge clk);
 if(mixed)begin
  if(dut.reg_file_inst.RegBank[3]!==32'hffffffeb ||
     dut.reg_file_inst.RegBank[4]!==32'hfffffffe ||
     dut.reg_file_inst.RegBank[5]!==32'hffffffff ||
     dut.reg_file_inst.RegBank[6]!==32'hffffffff ||
     dut.reg_file_inst.RegBank[7]!==2 ||
     dut.reg_file_inst.RegBank[8]!==32'hffffffff ||
     dut.reg_file_inst.RegBank[9]!==32'h55555553 ||
     dut.reg_file_inst.RegBank[10]!==0 ||
     dut.reg_file_inst.RegBank[11]!==32'hffffffff ||
     dut.reg_file_inst.RegBank[12]!==32'hfffffff9 ||
     dut.reg_file_inst.RegBank[13]!==32'hffffffec ||
     dut.reg_file_inst.RegBank[14]!==40 ||
     dut.reg_file_inst.RegBank[15]!==13 ||
     dut.reg_file_inst.RegBank[16]!==1 ||
     dut.reg_file_inst.RegBank[17]!==13 ||
     dut.reg_file_inst.RegBank[18]!==14)$fatal(1,"mixed arithmetic result");
 end else if((!redirect && dut.reg_file_inst.RegBank[3]!==63) ||
    (redirect && (dut.reg_file_inst.RegBank[3]!==0 || dut.reg_file_inst.RegBank[5]!==63 || dut.reg_file_inst.RegBank[6]!==0)) ||
    dut.reg_file_inst.RegBank[4]!==64)$fatal(1,"wrong result");
 if(accepts!=(mixed ? 14 : redirect ? 2 : 1))$fatal(1,"replayed instruction accepts=%0d",accepts);
 $display("PASS mixed=%0d slot=%0d redirect=%0d stall=%0d accepts=%0d cycles=%0d",mixed,slot,redirect,stall,accepts,cycles);$finish;
end
// Stall exactly across completion: the held EX request must never replay.
initial begin
 wait(!rst);
 if(stall==1)begin wait(accepts==1);wait(!dut.MCycle_Busy);@(negedge clk);dr=0;repeat(2)@(negedge clk);dr=1;end
end
always @(negedge clk) if(!rst && stall==2)begin
 random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
 dr=random_state[1:0]!=0;ir=random_state[3:0]!=0;
end
endmodule
