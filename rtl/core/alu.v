`timescale 1ns / 1ps


module alu(
	input [31:0] Src_A,
	input [31:0] Src_B,
	input [3:0] ALUControl, // 0000 for add, 0001 for sub, 1110 for and, 1100 for or, 0010 for sll, 1010 for srl, 1011 for sra.
	output reg [31:0] ALUResult,
	output [2:0] ALUFlags //{eq, lt, ltu}
);
    
	// Shifter signals
	reg [1:0] Sh;
	reg [4:0] Shamt5;
	wire [31:0] ShIn;
	wire [31:0] ShOut;
	
	// Other signals
	wire [32:0] S_wider;
	reg [32:0] Src_A_comp;
	reg [32:0] Src_B_comp;
	reg [31:0] C_0;
	wire N, Z, C, V; 	// optional intermediate values to derive eq, lt, ltu
				// Hint: We need to care about V only for subtraction
	wire LT, LTU;
	// Hint: lt is signed less than, ltu is unsigned less than.
	
	assign S_wider = Src_A_comp + Src_B_comp + C_0;
    
	always@(*) begin
        // default values; help avoid latches
		C_0 = 0; 
		Src_A_comp = {1'b0, Src_A};
		Src_B_comp = {1'b0, Src_B};
    
		case(ALUControl)
			4'b0000: ALUResult = S_wider[31:0];	//add          
	        4'b0001: begin				//sub
				C_0[0] = 1;  
				Src_B_comp = {1'b0, ~ Src_B};
				ALUResult = S_wider[31:0];
			end
	        4'b1110: ALUResult = Src_A & Src_B;	// and
	        4'b1100: ALUResult = Src_A | Src_B; 	// or
	        4'b1101: ALUResult = Src_A ^ Src_B; 	// xor
			4'b1001: begin
				C_0[0] = 1;
				Src_B_comp = {1'b0, ~ Src_B};
				ALUResult = {31'b0, LTU}; // sltu: unsigned less than
			end
			4'b1000: begin
				C_0[0] = 1;
				Src_B_comp = {1'b0, ~ Src_B};
				ALUResult = {31'b0, LT}; // slt: signed less than
			end
			// include cases for shifts		// shifts
			4'b0010, 4'b1010, 4'b1011: ALUResult = ShOut; // sll, srl, sra
			default: ALUResult = 32'bx;
	    endcase
	end

	assign Z = (ALUResult == 0) ? 1 : 0;
	assign N = S_wider[31];
	assign V = (Src_A[31] ^ Src_B[31]) & (Src_A[31] ^ S_wider[31]); // overflow only for subtraction
	assign LT = N ^ V; // signed less than
	assign C = S_wider[32]; // carry out
	assign LTU = ~C;

	assign ALUFlags = {Z, LT, LTU}; 	//{eq, lt, ltu} - all except eq are placeholders. 
    						// todo: Will need to be modified in lab 3 to support blt, bltu, bge, bgeu.
    
    
	// todo: make shifter connections here
	// Sh signals can be derived directly from the appropriate ALUControl bits
    always @(*) begin
		case(ALUControl)
			4'b0010: Sh = 2'b00; // sll
			4'b1010: Sh = 2'b01; // srl
			4'b1011: Sh = 2'b10; // sra
			default: Sh = 2'bxx; // default to sll
		endcase
	end

	always @(*) begin
		case(ALUControl)
			4'b0010, 4'b1010, 4'b1011: Shamt5 = Src_B[4:0]; // sll, srl, sra
			default: Shamt5 = 5'b00000; // default to 0
		endcase
	end
    
	assign ShIn = Src_A;
	// Instantiate Shifter        
	barrel_shifter barrel_shifter_inst(
                Sh,
        	Shamt5,
        	ShIn,
        	ShOut
        );
     
endmodule
