// MEM → WB pipeline register
module mem_wb_reg(
  input  wire        clk,
  input  wire        rst,
  input  wire        en,              // 0=hold
  input  wire        flush,           // 1=bubble (zero control)

  input wire csr_rvalid_mem,
  input wire [31:0] csr_rdata_mem,

  input wire  valid_mem,
  output reg  valid_wb,
  input wire [31:0] instruction_mem,
  output reg [31:0] instruction_wb,
  input wire  illegal_mem,
  output reg  illegal_wb,
  input wire  csr_wvalid_mem,
  output reg  csr_wvalid_wb,

  // From MEM stage
  input wire [31:0] pcplus4_mem,
  input  wire [31:0] mem_rdata_mem,   // load data
  input  wire [31:0] alu_out_mem,     // ALU passthrough for non-loads
  input wire         MCycle_mem,
  input  wire [31:0] MCycle_Result_mem,
  input  wire [4:0]  rd_idx_mem,


  input  wire [2:0] funct3_mem,
  input  wire [6:0] opcode_mem,
  input  wire        RegWrite_mem,
  input  wire        MemToReg_mem,
  input  wire        is_ebreak_mem,

  // To WB stage
  output reg csr_rvalid_wb,
  output reg [31:0] csr_rdata_wb,
  output reg  [31:0] pcplus4_wb,
  output reg  [31:0] mem_rdata_wb,
  output reg  [31:0] alu_out_wb,
  output reg         MCycle_wb,
  output reg  [31:0] MCycle_Result_wb,
  output reg  [4:0]  rd_idx_wb,

  output reg  [2:0]  funct3_wb,
  output reg  [6:0]  opcode_wb,
  output reg         RegWrite_wb,
  output reg         MemToReg_wb,
  output reg        is_ebreak_wb
);
  always @(posedge clk) begin
    if (rst) begin
      csr_wvalid_wb <= 'b0;
      illegal_wb <= 'b0;
      instruction_wb <= 'b0;
      valid_wb <= 'b0;
      csr_rvalid_wb <= 1'b0;
      csr_rdata_wb      <= 32'b0;
      pcplus4_wb        <= 32'b0;
      mem_rdata_wb      <= 32'b0;
      alu_out_wb        <= 32'b0;
      rd_idx_wb         <= 5'b0;
      MCycle_wb         <= 1'b0;
      MCycle_Result_wb  <= 32'b0;
      funct3_wb         <= 3'b0;
      opcode_wb         <= 7'b0;

      RegWrite_wb       <= 1'b0;
      MemToReg_wb       <= 1'b0;
      is_ebreak_wb      <= 1'b0;
    end else if (flush) begin
      csr_wvalid_wb <= 'b0;
      illegal_wb <= 'b0;
      instruction_wb <= 'b0;
      valid_wb <= 'b0;
      csr_rvalid_wb <= 1'b0;
      csr_rdata_wb      <= 32'b0;
      pcplus4_wb        <= 32'b0;
      mem_rdata_wb      <= 32'b0;
      alu_out_wb        <= 32'b0;
      rd_idx_wb         <= 5'b0;
      MCycle_wb         <= 1'b0;
      MCycle_Result_wb  <= 32'b0;
      funct3_wb         <= 3'b0;
      opcode_wb         <= 7'b0;

      RegWrite_wb       <= 1'b0;
      MemToReg_wb       <= 1'b0;
      is_ebreak_wb      <= 1'b0;
    end else if (en) begin
      csr_wvalid_wb <= csr_wvalid_mem;
      illegal_wb <= illegal_mem;
      instruction_wb <= instruction_mem;
      valid_wb <= valid_mem;
      csr_rvalid_wb <= csr_rvalid_mem;
      csr_rdata_wb      <= csr_rdata_mem;
      pcplus4_wb        <= pcplus4_mem;
      mem_rdata_wb      <= mem_rdata_mem;
      alu_out_wb        <= alu_out_mem;
      rd_idx_wb         <= rd_idx_mem;
      MCycle_wb         <= MCycle_mem;
      MCycle_Result_wb  <= MCycle_Result_mem;
      funct3_wb         <= funct3_mem;
      opcode_wb         <= opcode_mem;

      RegWrite_wb       <= RegWrite_mem;
      MemToReg_wb       <= MemToReg_mem;
      is_ebreak_wb      <= is_ebreak_mem;
    end
  end
endmodule
