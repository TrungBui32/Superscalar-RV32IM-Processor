// IF → ID pipeline register
module if_id_reg
(
  input  wire        clk,
  input  wire        rst,
  input  wire        en,              // 0=hold (stall IF/ID)
  input  wire        flush,           // 1=insert NOP into ID

  input wire fetch_fault_if,
  output reg fetch_fault_id,
  input wire valid_if,
  output reg valid_id,

  // From IF stage
  input  wire [31:0] pc_if,
  input wire [31:0] pcplus4_if,
  input  wire [31:0] instr_if,

  input wire is_jal_if,
  input wire is_jalr_if,
  input wire is_cond_jump_if,

  input wire branch_pred_if,
  input wire [31:0] branch_pred_target_if,
  input wire is_ebreak_if,

  // To ID stage
  output reg  [31:0] pc_id,
  output reg  [31:0] pcplus4_id,
  output reg  [31:0] instr_id,
  

  output reg is_jal_id,
  output reg is_jalr_id,
  output reg is_cond_jump_id,

  output reg is_ebreak_id,

  output reg branch_pred_id,
  output reg [31:0] branch_pred_target_id
);
  localparam [31:0] NOP = 32'h0000_0000; // ADD x0,x0,x0

  always @(posedge clk) begin
    if (rst || flush) fetch_fault_id <= 1'b0;
    else if (en) fetch_fault_id <= fetch_fault_if;
  end
  always @(posedge clk) begin
    if (rst) begin
      instr_id   <= NOP;
      valid_id <= 1'b0;

      is_cond_jump_id <= 1'b0;
      is_jal_id <= 1'b0;
      is_jalr_id <= 1'b0;

      branch_pred_id <= 1'b0;
      is_ebreak_id <= 1'b0;
    end else if (flush) begin
      instr_id   <= NOP;
      valid_id <= 1'b0;

      is_cond_jump_id <= 1'b0;
      is_jal_id <= 1'b0;
      is_jalr_id <= 1'b0;

      branch_pred_id <= 1'b0;
      is_ebreak_id <= 1'b0;
    end else if (en) begin
      instr_id   <= instr_if;
      valid_id <= valid_if;

      is_cond_jump_id <= is_cond_jump_if;
      is_jal_id <= is_jal_if;
      is_jalr_id <= is_jalr_if;

      branch_pred_id <= branch_pred_if;
      is_ebreak_id <= is_ebreak_if;
    end
  end
  // Flush kills validity and side-effect controls above. Payload is ignored
  // in a bubble, so it may capture without a high-fanout flush/reset mux.
  // A real stall still holds the payload (and refreshes EX bypass operands).
  always @(posedge clk) begin
    if (rst) begin
      pc_id <= 'b0;
      pcplus4_id <= 'b0;
      branch_pred_target_id <= 'b0;
    end else if (en) begin
      pc_id <= pc_if;
      pcplus4_id <= pcplus4_if;
      branch_pred_target_id <= branch_pred_target_if;
    end
  end
endmodule
