`timescale 1ns/1ps
module coremark_sim(input clk, input rst, output reg done, output reg failed,
                    output [31:0] pc, output reg [63:0] cycles);
    reg [31:0] imem[0:8191];
    reg [31:0] dmem[0:4095];
    reg [2047:0] imem_file,dmem_file;
    integer i,lane;
    wire [31:0] a0,a1,d0,d1;
    wire [2:0] w0,w1;
    function [31:0] instruction;
        input [31:0] a;
        begin instruction=(a>=32'h00400000 && a<32'h00408000) ? imem[(a-32'h00400000)>>2] : 32'h00000013; end
    endfunction
    function [31:0] read_data;
        input [31:0] a;
        begin
            if(a>=32'h10010000 && a<32'h10014000)read_data=dmem[(a-32'h10010000)>>2]>>(a[1:0]*8);
            else if(a==32'hffff0008)read_data=1;
            else read_data=0;
        end
    endfunction
    wire [31:0] r0=read_data(a0),r1=read_data(a1);
    core #(.PC_INIT(32'h00400000),.ATOMIC_BASE(32'h10010000),.ATOMIC_MASK(32'hffffc000),
           .MISALIGNED_BASE(32'h10010000),.MISALIGNED_MASK(32'hffff0000)) dut(
        .CLK(clk),.RESET(rst),.locked(1'b1),.imem_fault(2'b0), .dmem_fault(2'b0), .imem_ready(1'b1),.dmem_ready(1'b1),
        .irq_software(1'b0),.irq_timer(1'b0),.irq_external(1'b0),.time_value(cycles),
        .Instr_pipe0(instruction(pc)),.Instr_pipe1(instruction(pc+4)),
        .ReadData_in_pipe0(r0),.ReadData_in_pipe1(r1),.PC(pc),
        .ALUResult_pipe0(a0),.ALUResult_pipe1(a1),.MemWrite_out_pipe0(w0),
        .MemWrite_out_pipe1(w1),.WriteData_out_pipe0(d0),.WriteData_out_pipe1(d1)
    );
    task write_mmio;
        input [31:0] a,d;
        begin
            if(a==32'hffff000c)$write("%c",d[7:0]);
            if(a>=32'hffff00e0 && a<32'hffff00ec)$display("RTL TRAP address=%h value=%h pc=%h",a,d,pc);
            if(a==32'hffff00f0)begin done<=1;failed<=d!=1;end
        end
    endtask
    always @(posedge clk) begin
        if(rst)begin done<=0;failed<=0;cycles<=0;end
        else begin
            cycles<=cycles+1;
            for(lane=0;lane<4;lane=lane+1)begin
                if(lane<(w0[2]?4:w0[1]?2:w0[0]?1:0) && a0>=32'h10010000 && a0+lane<32'h10014000)
                    dmem[(a0+lane-32'h10010000)>>2][((a0+lane)&3)*8+:8]<=d0[lane*8+:8];
                if(lane<(w1[2]?4:w1[1]?2:w1[0]?1:0) && a1>=32'h10010000 && a1+lane<32'h10014000)
                    dmem[(a1+lane-32'h10010000)>>2][((a1+lane)&3)*8+:8]<=d1[lane*8+:8];
            end
            if(|w0)write_mmio(a0,d0);
            if(|w1)write_mmio(a1,d1);
        end
    end
    initial begin
        for(i=0;i<8192;i=i+1)imem[i]=32'h00000013;
        for(i=0;i<4096;i=i+1)dmem[i]=0;
        if(!$value$plusargs("imem=%s",imem_file))$fatal(1,"missing imem");
        if(!$value$plusargs("dmem=%s",dmem_file))$fatal(1,"missing dmem");
        $readmemh(imem_file,imem);$readmemh(dmem_file,dmem);
    end
endmodule
