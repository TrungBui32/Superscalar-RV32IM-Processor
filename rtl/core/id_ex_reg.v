// ID → EX pipeline register
module id_ex_reg
(
  input  wire        clk,
  input  wire        rst,
  input  wire        en,              // 0=hold (stall into EX)
  input  wire        flush,           // 1=bubble (zero control signals)
  // Preserve bypassed operands if a consumer remains in EX after WB moves on.
  input wire [31:0] rs1_forward_ex,
  input wire [31:0] rs2_forward_ex,

  input wire fetch_fault_id,
  output reg fetch_fault_ex,
  input wire  valid_id,
  output reg  valid_ex,
  input wire [31:0] instruction_id,
  output reg [31:0] instruction_ex,
  input wire  illegal_id,
  output reg  illegal_ex,

  // From ID stage (data)
  input  wire [31:0] pc_id,
  input  wire [31:0] pcplus4_id,
  input  wire [31:0] rs1_val_id,
  input  wire [31:0] rs2_val_id,
  input  wire [31:0] imm_id,
  input  wire [4:0]  rs1_idx_id,
  input  wire [4:0]  rs2_idx_id,
  input  wire [4:0]  rd_idx_id,
  input  wire [2:0]  funct3_id,
  input  wire [6:0]  opcode_id,       // optional, handy for JAL/JALR/AUIPC/LUI

  input wire         is_cond_jump_id,
  input wire         is_jal_id,
  input wire         is_jalr_id,
  

  input wire branch_pred_id,
  input wire [31:0] branch_pred_target_id,

  input wire csr_rvalid_id,
  input  wire [31:0] csr_rdata_id,
  input  wire [11:0] csr_addr_id,
  input  wire        csr_wvalid_id,
  input  wire        csr_rillegal_id,

  // From ID stage (control)
  input  wire        RegWrite_id,
  input  wire [2:0]  MemWrite_id,
  input  wire        MemRead_id,
  input  wire        MemToReg_id,
  input  wire [4:0]  LwSizeSel_id,
  input  wire [1:0]  AluSrcA_id,    // 0=rs1, 1=pc (for AUIPC/JAL/JALR)
  input  wire [1:0]  AluSrcB_id,     // 00=rs2, 01=imm, 10=4 (for AUIPC/JAL/JALR)
  input  wire [3:0]  AluOp_id,
  input wire         MCycle_id,       // optional, for MUL/DIV
  input wire [1:0]   MCycleOp_id,     // optional, for MUL/DIV
  input wire        is_ebreak_id,

  // To EX stage
  output reg  [31:0] pc_ex,
  output reg  [31:0] pcplus4_ex,
  output reg  [31:0] rs1_val_ex,
  output reg  [31:0] rs2_val_ex,
  output reg  [31:0] imm_ex,
  output reg  [4:0]  rs1_idx_ex,
  output reg  [4:0]  rs2_idx_ex,
  output reg  [4:0]  rd_idx_ex,
  output reg  [2:0]  funct3_ex,
  output reg  [6:0]  opcode_ex,

  output reg         is_cond_jump_ex,
  output reg         is_jal_ex,
  output reg         is_jalr_ex,

  output reg branch_pred_ex,
  output reg [31:0] branch_pred_target_ex,

  output reg csr_rvalid_ex,
  output reg  [31:0] csr_rdata_ex,
  output reg  [11:0] csr_addr_ex,
  output reg         csr_wvalid_ex,
  output reg         csr_rillegal_ex,

  output reg         RegWrite_ex,
  output reg  [2:0]  MemWrite_ex,
  output reg         MemRead_ex,
  output reg         MemToReg_ex,
  output reg  [4:0]  LwSizeSel_ex,
  output  reg [1:0]  AluSrcA_ex,    // 0=rs1, 1=pc (for AUIPC/JAL/JALR)
  output  reg [1:0]  AluSrcB_ex,     // 00=rs2, 01=imm, 10=4 (for AUIPC/JAL/JALR)
  output reg  [3:0]  AluOp_ex,
  output reg         MCycle_ex,       // optional, for MUL/DIV
  output reg [1:0]   MCycleOp_ex,     // optional, for MUL/DIV
  output reg         is_ebreak_ex
);
  // Flush inserts a bubble by clearing validity and side-effect controls.
  always @(posedge clk) begin
    if (rst || flush) fetch_fault_ex <= 1'b0;
    else if (en) fetch_fault_ex <= fetch_fault_id;
  end
  always @(posedge clk) begin
    if (rst) begin
      illegal_ex <= 'b0;
      instruction_ex <= 'b0;
      valid_ex <= 'b0;
      rs1_idx_ex   <= 5'b0;
      rs2_idx_ex   <= 5'b0;
      rd_idx_ex    <= 5'b0;
      funct3_ex    <= 3'b0;
      opcode_ex    <= 7'b0;

      is_cond_jump_ex <= 1'b0;
      is_jal_ex    <= 1'b0;
      is_jalr_ex   <= 1'b0;

      branch_pred_ex <= 1'b0;
      is_ebreak_ex <= 1'b0;

      csr_rvalid_ex <= 1'b0;

      csr_wvalid_ex <= 1'b0;
      csr_rillegal_ex <= 1'b0;

      RegWrite_ex  <= 1'b0;
      MemWrite_ex  <= 3'b0;
      MemRead_ex   <= 1'b0;
      MemToReg_ex  <= 1'b0;
      AluSrcA_ex   <= 2'b0;
      AluSrcB_ex   <= 2'b0;
      AluOp_ex     <= 4'b0;
      MCycle_ex    <= 1'b0;
      MCycleOp_ex  <= 2'b0;
      LwSizeSel_ex <= 5'b0;
    end else if (flush) begin
      illegal_ex <= 'b0;
      instruction_ex <= 'b0;
      valid_ex <= 'b0;
      rs1_idx_ex   <= 5'b0;
      rs2_idx_ex   <= 5'b0;
      rd_idx_ex    <= 5'b0;
      funct3_ex    <= 3'b0;
      opcode_ex    <= 7'b0;

      is_cond_jump_ex <= 1'b0;
      is_jal_ex    <= 1'b0;
      is_jalr_ex   <= 1'b0;
      is_ebreak_ex <= 1'b0;

      branch_pred_ex <= 1'b0;

      csr_rvalid_ex <= 1'b0;

      csr_wvalid_ex <= 1'b0;
      csr_rillegal_ex <= 1'b0;

      RegWrite_ex  <= 1'b0;
      MemWrite_ex  <= 3'b0;
      MemRead_ex   <= 1'b0;
      MemToReg_ex  <= 1'b0;
      AluSrcA_ex   <= 2'b0;
      AluSrcB_ex   <= 2'b0;
      AluOp_ex     <= 4'b0;
      MCycle_ex    <= 1'b0;
      MCycleOp_ex  <= 2'b0;
      LwSizeSel_ex <= 5'b0;

    end else if (en) begin
      illegal_ex <= illegal_id;
      instruction_ex <= instruction_id;
      valid_ex <= valid_id;
      rs1_idx_ex   <= rs1_idx_id;
      rs2_idx_ex   <= rs2_idx_id;
      rd_idx_ex    <= rd_idx_id;
      funct3_ex    <= funct3_id;
      opcode_ex    <= opcode_id;
      MCycle_ex    <= MCycle_id;
      MCycleOp_ex  <= MCycleOp_id;
      
      is_cond_jump_ex <= is_cond_jump_id;
      is_jal_ex    <= is_jal_id;
      is_jalr_ex   <= is_jalr_id;
      is_ebreak_ex <= is_ebreak_id;

      branch_pred_ex <= branch_pred_id;

      csr_rvalid_ex <= csr_rvalid_id;

      csr_wvalid_ex <= csr_wvalid_id;
      csr_rillegal_ex <= csr_rillegal_id;

      RegWrite_ex  <= RegWrite_id;
      MemWrite_ex  <= MemWrite_id;
      MemRead_ex   <= MemRead_id;
      MemToReg_ex  <= MemToReg_id;
      AluSrcA_ex   <= AluSrcA_id;
      AluSrcB_ex   <= AluSrcB_id;
      AluOp_ex     <= AluOp_id;
      LwSizeSel_ex <= LwSizeSel_id;
    end
  end
  // Flush kills validity and side-effect controls above. Payload is ignored
  // in a bubble, so it may capture without a high-fanout flush/reset mux.
  // A real stall still holds the payload (and refreshes EX bypass operands).
  always @(posedge clk) begin
    if (rst) begin
      pc_ex <= 'b0;
      pcplus4_ex <= 'b0;
      rs1_val_ex <= 'b0;
      rs2_val_ex <= 'b0;
      imm_ex <= 'b0;
      csr_rdata_ex <= 'b0;
      csr_addr_ex <= 'b0;
      branch_pred_target_ex <= 'b0;
    end else if (en) begin
      pc_ex <= pc_id;
      pcplus4_ex <= pcplus4_id;
      rs1_val_ex <= rs1_val_id;
      rs2_val_ex <= rs2_val_id;
      imm_ex <= imm_id;
      csr_rdata_ex <= csr_rdata_id;
      csr_addr_ex <= csr_addr_id;
      branch_pred_target_ex <= branch_pred_target_id;
    end else begin
      rs1_val_ex <= rs1_forward_ex;
      rs2_val_ex <= rs2_forward_ex;
    end
  end
endmodule
