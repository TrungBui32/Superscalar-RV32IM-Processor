`timescale 1ns / 1ps


module reg_file(
    input CLK,
    input WE_pipe0,
    input WE_pipe1,
    input [4:0] rs1_pipe0,
    input [4:0] rs2_pipe0,
    input [4:0] rd_pipe0,

    input [4:0] rs1_pipe1,
    input [4:0] rs2_pipe1,
    input [4:0] rd_pipe1,

    input [31:0] WD_pipe0,
    input [31:0] WD_pipe1,

    output reg [31:0] RD1_pipe0,
    output reg [31:0] RD2_pipe0,
    output reg [31:0] RD1_pipe1,
    output reg [31:0] RD2_pipe1
    );
    
    // declare RegBank
    reg [31:0] RegBank[0:31];
        // 32 addresses, each a 32-bit word
        // (1 to 31) is sufficient as R15 is not stored. Kept it as (0 to 31) just to supress a warning
	integer i;
	initial begin
	   for(i = 0; i < 32; i=i+1) begin
	       RegBank[i] = 32'h0000_0000;
	   end
	end
    // read
    always@(*)	// change to @posedge CLK only if using synch read. In that case, the output is RD1E, RD2E directly
    begin
    	RD1_pipe0 <= (rs1_pipe0 == 5'b00000) ? 32'd0 : RegBank[rs1_pipe0]; 
    	RD2_pipe0 <= (rs2_pipe0 == 5'b00000) ? 32'd0 : RegBank[rs2_pipe0];
            
    	RD1_pipe1 <= (rs1_pipe1 == 5'b00000) ? 32'd0 : RegBank[rs1_pipe1]; 
    	RD2_pipe1 <= (rs2_pipe1 == 5'b00000) ? 32'd0 : RegBank[rs2_pipe1];
    end 
    
    // write
    always@(posedge CLK)
    begin
        if((rd_pipe0 != 5'b00000) & (WE_pipe0)) // x0 is hardwired to 0
            RegBank[rd_pipe0] <= WD_pipe0;
        if((rd_pipe1 != 5'b00000) & (WE_pipe1)) // x0 is hardwired to 0
            RegBank[rd_pipe1] <= WD_pipe1;
    end
    
endmodule













