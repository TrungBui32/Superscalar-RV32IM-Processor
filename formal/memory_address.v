// Memory flags qualify hazard addresses. Prove that the decoded memory
// operation's general result path is exactly an unconditional operand sum.
module memory_address_equivalence(
 input [31:0] instruction, operand_a, operand_b, csr_data, link_pc,
 output equivalent
);
 wire read_mem, csr_read;
 wire [2:0] write_mem;
 wire [3:0] control;
 decode_unit decode(.Instruction(instruction),.Opcode(instruction[6:0]),
  .Funct3(instruction[14:12]),.Funct7(instruction[31:25]),.Rs1(instruction[19:15]),
  .MemRead(read_mem),.MemWrite(write_mem),.csr_rvalid(csr_read),.ALUControl(control));
 wire [31:0] result;
 alu execute(.Src_A(operand_a),.Src_B(operand_b),.ALUControl(control),.ALUResult(result),.ALUFlags());
 wire jump=instruction[6:0]==7'h6f || instruction[6:0]==7'h67;
 wire [31:0] original_address=csr_read?csr_data:jump?link_pc:result;
 wire [31:0] sum=operand_a+operand_b;
 assign equivalent=!(read_mem || |write_mem) || original_address==sum;
endmodule
