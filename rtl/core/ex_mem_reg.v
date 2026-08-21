// EX → MEM pipeline register
module ex_mem_reg(
  input  wire        clk,
  input  wire        rst,
  input  wire        en,              // 0=hold
  input  wire        flush,           // 1=bubble (zero control)

  // From EX stage
  input  wire [31:0] pc_ex,
  input  wire [31:0] pcplus4_ex,
  input  wire [31:0] alu_out_ex,
  input  wire [31:0] store_data_ex,   // rs2 after forwarding
  input  wire [4:0]  rd_idx_ex,
  input  wire        MCycle_ex,
  input  wire [31:0] MCycle_Result_ex,

  input  wire        is_cond_jump_ex,
  input  wire        is_jal_ex,
  input  wire        is_jalr_ex,
  input  wire [31:0] PC_branch_ex,

  input  wire [2:0] funct3_ex,
  input  wire [6:0] opcode_ex,
  input  wire        RegWrite_ex,
  input  wire [2:0]  MemWrite_ex,
  input  wire        MemRead_ex,
  input  wire        MemToReg_ex,
  input wire [4:0]  LwSizeSel_ex,
  input wire [2:0] ALUFlags_ex,

  input branch_pred_ex,
  input [31:0] branch_pred_target_ex,
  input is_ebreak_ex,

  // To MEM stage
  output reg  [31:0] pc_mem,
  output reg  [31:0] pcplus4_mem,
  output reg  [31:0] alu_out_mem,
  output reg  [31:0] store_data_mem,
  output reg         MCycle_mem,
  output reg  [31:0] MCycle_Result_mem,
  output reg  [4:0]  rd_idx_mem,

  output reg         is_cond_jump_mem,
  output reg         is_jal_mem,
  output reg         is_jalr_mem,
  output reg  [31:0] PC_branch_mem,

  output reg  [2:0]  funct3_mem,
  output reg  [6:0]  opcode_mem,
  output reg         RegWrite_mem,
  output reg  [2:0]  MemWrite_mem,
  output reg         MemRead_mem,
  output reg         MemToReg_mem,
  output reg  [4:0]  LwSizeSel_mem,
  output reg  [2:0]  ALUFlags_mem,

  output reg branch_pred_mem,
  output reg [31:0] branch_pred_target_mem,
  output reg is_ebreak_mem
);
  always @(posedge clk) begin
    if (rst) begin
      pc_mem             <= 32'b0;
      pcplus4_mem        <= 32'b0;
      alu_out_mem        <= 32'b0;
      store_data_mem     <= 32'b0;
      rd_idx_mem         <= 5'b0;
      MCycle_mem         <= 1'b0;
      MCycle_Result_mem  <= 32'b0;
      funct3_mem         <= 3'b0;
      opcode_mem         <= 7'b0;

      is_cond_jump_mem   <= 1'b0;
      is_jal_mem         <= 1'b0;
      is_jalr_mem        <= 1'b0;
      PC_branch_mem      <= 32'b0;

      RegWrite_mem       <= 1'b0;
      MemWrite_mem       <= 4'b0000;
      MemRead_mem        <= 1'b0;
      MemToReg_mem       <= 1'b0;
      LwSizeSel_mem      <= 5'b0;
      ALUFlags_mem       <= 3'b0;
      branch_pred_mem    <= 1'b0;
      branch_pred_target_mem <= 32'b0;
      is_ebreak_mem      <= 1'b0;
    end else if (flush) begin
      pc_mem             <= 32'b0;
      pcplus4_mem        <= 32'b0;
      alu_out_mem        <= 32'b0;
      store_data_mem     <= 32'b0;
      rd_idx_mem         <= 5'b0;
      MCycle_mem         <= 1'b0;
      MCycle_Result_mem  <= 32'b0;
      funct3_mem         <= 3'b0;
      opcode_mem         <= 7'b0;

      is_cond_jump_mem   <= 1'b0;
      is_jal_mem         <= 1'b0;
      is_jalr_mem        <= 1'b0;
      PC_branch_mem      <= 32'b0;

      RegWrite_mem       <= 1'b0;
      MemWrite_mem       <= 4'b0000;
      MemRead_mem        <= 1'b0;
      MemToReg_mem       <= 1'b0;
      LwSizeSel_mem      <= 5'b0;
      ALUFlags_mem       <= 3'b0;
      branch_pred_mem    <= 1'b0;
      branch_pred_target_mem <= 32'b0;
      is_ebreak_mem      <= 1'b0;
    end else if (en) begin
      pc_mem             <= pc_ex;
      pcplus4_mem        <= pcplus4_ex;
      alu_out_mem        <= alu_out_ex;
      store_data_mem     <= store_data_ex;
      rd_idx_mem         <= rd_idx_ex;
      MCycle_mem         <= MCycle_ex;
      MCycle_Result_mem  <= MCycle_Result_ex;
      funct3_mem         <= funct3_ex;
      opcode_mem         <= opcode_ex;

      is_cond_jump_mem   <= is_cond_jump_ex;
      is_jal_mem         <= is_jal_ex;
      is_jalr_mem        <= is_jalr_ex;
      PC_branch_mem      <= PC_branch_ex;

      RegWrite_mem       <= RegWrite_ex;
      MemWrite_mem       <= MemWrite_ex;
      MemRead_mem        <= MemRead_ex;
      MemToReg_mem       <= MemToReg_ex;
      LwSizeSel_mem      <= LwSizeSel_ex;
      ALUFlags_mem       <= ALUFlags_ex;
      branch_pred_mem    <= branch_pred_ex;
      branch_pred_target_mem <= branch_pred_target_ex;
      is_ebreak_mem      <= is_ebreak_ex;
    end
  end
endmodule
