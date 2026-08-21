`timescale 1ns / 1ps


module next_pc( // This is a combinational module, unlike ARM. See the note below.
	input is_branch,	// 00 for non-control, 01 for conditional branch, 10 for jal, 11 for jalr
	input [2:0] Funct3,	// condition specified in the instruction (eq / ne / lt / ge / ltu / geu)
	input [2:0] ALUFlags, 	// {eq, lt, ltu}
	output reg[1:0] PCSrc	// will need to be expanded to 2 bits to support jalr
    );
    
    /* 
    	Important Note : ALUFlags are not *stored* in flag registers in RISC-V, unlike ARM and most other processors.
    	In RISC-V, the flags are produced and consumed in the same branch instruction. 
    	The effect of CMP R1, R2 and BEQ LABEL in ARM is beq x1, x2, LABEL in RISC-V.
    */
    localparam Funct3_BEQ  = 3'b000;
	localparam Funct3_BNE  = 3'b001;
	localparam Funct3_BLT  = 3'b100;
	localparam Funct3_BGE  = 3'b101;
	localparam Funct3_BLTU = 3'b110;
	localparam Funct3_BGEU = 3'b111;
    
	// todo: conditional logic goes here
	always @(*) begin
		if(is_branch)
			case(Funct3)
				Funct3_BEQ:  PCSrc = {1'b0, ALUFlags[2]};       // eq
				Funct3_BNE:  PCSrc = {1'b0, ~ALUFlags[2]};      // ne
				Funct3_BLT:  PCSrc = {1'b0, ALUFlags[1]};       // lt
				Funct3_BGE:  PCSrc = {1'b0, ~ALUFlags[1]};      // ge
				Funct3_BLTU: PCSrc = {1'b0, ALUFlags[0]};       // ltu
				Funct3_BGEU: PCSrc = {1'b0, ~ALUFlags[0]};      // geu
				default:     PCSrc = 1'b0;               // should not occur
			endcase
		else
			PCSrc = 2'b00; // not a branch
	end
endmodule













