module forward_ctrl #(
  // Select encodings (keep as params so the EX mux can match them)
  parameter SEL_IDEX  = 4'b0000, // use ID/EX value
  parameter SEL_ALU_EXMEM_PIPE0 = 4'b0001, // use EX/MEM ALU result
  parameter SEL_ALU_MEMWB_PIPE0 = 4'b0010,  //use MEM/WB ALU result
  parameter SEL_MCYCLE_EXMEM_PIPE0 = 4'b0011,
  parameter SEL_MCYCLE_MEMWB_PIPE0 = 4'b0100,
  parameter SEL_LW_MEMWB_PIPE0 = 4'b0101,
  parameter SEL_LW_MEMWB_PIPE1 = 4'b0110,
  parameter SEL_ALU_EXMEM_PIPE1 = 4'b0111, // use EX/MEM ALU result
  parameter SEL_ALU_MEMWB_PIPE1 = 4'b1000,  //use MEM/WB ALU result
  parameter SEL_MCYCLE_EXMEM_PIPE1 = 4'b1001,
  parameter SEL_MCYCLE_MEMWB_PIPE1 = 4'b1010
)(
  // ---------- Consumers (the instruction currently in ID) ----------
    input  wire [4:0] id_rs1_pipe0,     // source register A index in ID
    input  wire [4:0] id_rs2_pipe0,     // source register B index in ID

    input  wire [4:0] id_rs1_pipe1,
    input  wire [4:0] id_rs2_pipe1, 
  // ---------- Consumers (the instruction currently in EX) ----------
    input  wire [4:0] ex_rs1_pipe0,     // source register A index in EX
    input  wire [4:0] ex_rs2_pipe0,     // source register B index in EX

    input  wire [4:0] ex_rs1_pipe1,     // source register A index in EX
    input  wire [4:0] ex_rs2_pipe1,     // source register B index in EX


  // ---------- Producer 1 (one cycle older): EX/MEM ----------
  input  wire       is_load_mem_pipe0,
  input  wire       mem_RegWrite_pipe0, // producer will write a GPR
  input  wire       mem_MCycle_pipe0,   // producer is a longop (MUL/DIV)
  input  wire [4:0] mem_rd_pipe0,       // its destination register index

  input wire       is_load_mem_pipe1,
  input wire       mem_RegWrite_pipe1, // producer will write a GPR
  input wire       mem_MCycle_pipe1,   // producer is a longop (MUL/DIV)
  input wire [4:0] mem_rd_pipe1,       // its destination register index

  // ---------- Producer 2 (two cycles older): MEM/WB ----------
  input  wire       is_load_wb_pipe0,
  input  wire       wb_RegWrite_pipe0, // will write a GPR this cycle
  input  wire       wb_MCycle_pipe0,   // is a longop (MUL/DIV)
  input  wire [4:0] wb_rd_pipe0,       // its destination register index

  input  wire       is_load_wb_pipe1,
  input  wire       wb_RegWrite_pipe1, // will write a GPR this cycle
  input  wire       wb_MCycle_pipe1,   // is a longop (MUL/DIV)
  input  wire [4:0] wb_rd_pipe1,       // its destination register index

  // ---------- Outputs: select codes for EX muxes ----------
  output reg  [3:0] selA_id_pipe0,
  output reg  [3:0] selB_id_pipe0,

  output reg  [3:0] selA_id_pipe1,
  output reg  [3:0] selB_id_pipe1,

  output reg  [3:0] selA_ex_pipe0,
  output reg  [3:0] selB_ex_pipe0,

  output reg  [3:0] selA_ex_pipe1,
  output reg  [3:0] selB_ex_pipe1
);




always @(*) begin
    // Priority 3: Forward from WB stage pipe1
    if (wb_RegWrite_pipe1 && id_rs1_pipe0 != 4'b0000 && (wb_rd_pipe1 == id_rs1_pipe0)) begin
        if (wb_MCycle_pipe1)
            selA_id_pipe0 = SEL_MCYCLE_MEMWB_PIPE1;
        else if (is_load_wb_pipe1)
            selA_id_pipe0 = SEL_LW_MEMWB_PIPE1;
        else
            selA_id_pipe0 = SEL_ALU_MEMWB_PIPE1;
    end
    // Priority 4: Forward from WB stage pipe0
    else if (wb_RegWrite_pipe0 && id_rs1_pipe0 != 4'b0000 && (wb_rd_pipe0 == id_rs1_pipe0)) begin
        if (wb_MCycle_pipe0)
            selA_id_pipe0 = SEL_MCYCLE_MEMWB_PIPE0;
        else if (is_load_wb_pipe0)
            selA_id_pipe0 = SEL_LW_MEMWB_PIPE0;
        else
            selA_id_pipe0 = SEL_ALU_MEMWB_PIPE0;
    end
    // Default: No forwarding needed
    else begin
        selA_id_pipe0 = SEL_IDEX;
    end
end



// Similar pattern for selB_id_pipe0
always @(*) begin
    // Priority 1: Forward from WB stage pipe1
    if (wb_RegWrite_pipe1 && id_rs2_pipe0 != 4'b0000 && (wb_rd_pipe1 == id_rs2_pipe0)) begin
        if (wb_MCycle_pipe1)
            selB_id_pipe0 = SEL_MCYCLE_MEMWB_PIPE1;
        else if (is_load_wb_pipe1)
            selB_id_pipe0 = SEL_LW_MEMWB_PIPE1;
        else
            selB_id_pipe0 = SEL_ALU_MEMWB_PIPE1;
    end
    // Priority 2: Forward from WB stage pipe0
    else if (wb_RegWrite_pipe0 && id_rs2_pipe0 != 4'b0000 && (wb_rd_pipe0 == id_rs2_pipe0)) begin
        if (wb_MCycle_pipe0)
            selB_id_pipe0 = SEL_MCYCLE_MEMWB_PIPE0;
        else if (is_load_wb_pipe0)
            selB_id_pipe0 = SEL_LW_MEMWB_PIPE0;
        else
            selB_id_pipe0 = SEL_ALU_MEMWB_PIPE0;
    end
    // Default: No forwarding needed
    else begin
        selB_id_pipe0 = SEL_IDEX;
    end
end


// Similar pattern for selA_id_pipe1
always @(*) begin
    // Priority 3: Forward from WB stage pipe1
    if (wb_RegWrite_pipe1 && id_rs1_pipe1 != 4'b0000 && (wb_rd_pipe1 == id_rs1_pipe1)) begin
        if (wb_MCycle_pipe1)
            selA_id_pipe1 = SEL_MCYCLE_MEMWB_PIPE1;
        else if (is_load_wb_pipe1)
            selA_id_pipe1 = SEL_LW_MEMWB_PIPE1;
        else
            selA_id_pipe1 = SEL_ALU_MEMWB_PIPE1;
    end
    // Priority 4: Forward from WB stage pipe0
    else if (wb_RegWrite_pipe0 && id_rs1_pipe1 != 4'b0000 && (wb_rd_pipe0 == id_rs1_pipe1)) begin
        if (wb_MCycle_pipe0)
            selA_id_pipe1 = SEL_MCYCLE_MEMWB_PIPE0;
        else if (is_load_wb_pipe0)
            selA_id_pipe1 = SEL_LW_MEMWB_PIPE0;
        else
            selA_id_pipe1 = SEL_ALU_MEMWB_PIPE0;
    end
    // Default: No forwarding needed
    else begin
        selA_id_pipe1 = SEL_IDEX;
    end
end



always @(*) begin
    if(wb_RegWrite_pipe1 && id_rs2_pipe1 != 4'b0000 && (wb_rd_pipe1 == id_rs2_pipe1)) begin
        if(wb_MCycle_pipe1)
            selB_id_pipe1 = SEL_MCYCLE_MEMWB_PIPE1;
        else if(is_load_wb_pipe1)
            selB_id_pipe1 = SEL_LW_MEMWB_PIPE1;
        else
            selB_id_pipe1 = SEL_ALU_MEMWB_PIPE1;
    end
    else if(wb_RegWrite_pipe0 && id_rs2_pipe1 != 4'b0000 && (wb_rd_pipe0 == id_rs2_pipe1)) begin
        if(wb_MCycle_pipe0)
            selB_id_pipe1 = SEL_MCYCLE_MEMWB_PIPE0;
        else if(is_load_wb_pipe0)
            selB_id_pipe1 = SEL_LW_MEMWB_PIPE0;
        else
            selB_id_pipe1 = SEL_ALU_MEMWB_PIPE0;
    end
    else begin
        selB_id_pipe1 = SEL_IDEX;
    end
end



always @(*) begin
    if(mem_RegWrite_pipe1 && ex_rs1_pipe0 != 4'b0000 && !is_load_mem_pipe1 && (mem_rd_pipe1 == ex_rs1_pipe0)) begin
        if(mem_MCycle_pipe1)
            selA_ex_pipe0 = SEL_MCYCLE_EXMEM_PIPE1;
        else
            selA_ex_pipe0 = SEL_ALU_EXMEM_PIPE1;
    end
    else if(mem_RegWrite_pipe0 && ex_rs1_pipe0 != 4'b0000 && !is_load_mem_pipe0 && (mem_rd_pipe0 == ex_rs1_pipe0)) begin
        if(mem_MCycle_pipe0)
            selA_ex_pipe0 = SEL_MCYCLE_EXMEM_PIPE0;
        else
            selA_ex_pipe0 = SEL_ALU_EXMEM_PIPE0;
    end
    else if(wb_RegWrite_pipe1 && ex_rs1_pipe0 != 4'b0000 && (wb_rd_pipe1 == ex_rs1_pipe0)) begin
        if(wb_MCycle_pipe1)
            selA_ex_pipe0 = SEL_MCYCLE_MEMWB_PIPE1;
        else if(is_load_wb_pipe1)
            selA_ex_pipe0 = SEL_LW_MEMWB_PIPE1;
        else
            selA_ex_pipe0 = SEL_ALU_MEMWB_PIPE1;
    end
    else if(wb_RegWrite_pipe0 && ex_rs1_pipe0 != 4'b0000 && (wb_rd_pipe0 == ex_rs1_pipe0)) begin
        if(wb_MCycle_pipe0)
            selA_ex_pipe0 = SEL_MCYCLE_MEMWB_PIPE0;
        else if(is_load_wb_pipe0)
            selA_ex_pipe0 = SEL_LW_MEMWB_PIPE0;
        else
            selA_ex_pipe0 = SEL_ALU_MEMWB_PIPE0;
    end
    else begin
        selA_ex_pipe0 = SEL_IDEX;
    end
end


always @(*) begin
    if(mem_RegWrite_pipe1 && ex_rs2_pipe0 != 4'b0000 && !is_load_mem_pipe1 && (mem_rd_pipe1 == ex_rs2_pipe0)) begin
        if(mem_MCycle_pipe1)
            selB_ex_pipe0 = SEL_MCYCLE_EXMEM_PIPE1;
        else
            selB_ex_pipe0 = SEL_ALU_EXMEM_PIPE1;
    end
    else if(mem_RegWrite_pipe0 && ex_rs2_pipe0 != 4'b0000 && !is_load_mem_pipe0 && (mem_rd_pipe0 == ex_rs2_pipe0)) begin
        if(mem_MCycle_pipe0)
            selB_ex_pipe0 = SEL_MCYCLE_EXMEM_PIPE0;
        else
            selB_ex_pipe0 = SEL_ALU_EXMEM_PIPE0;
    end
    else if(wb_RegWrite_pipe1 && ex_rs2_pipe0 != 4'b0000 && (wb_rd_pipe1 == ex_rs2_pipe0)) begin
        if(wb_MCycle_pipe1)
            selB_ex_pipe0 = SEL_MCYCLE_MEMWB_PIPE1;
        else if(is_load_wb_pipe1)
            selB_ex_pipe0 = SEL_LW_MEMWB_PIPE1;
        else
            selB_ex_pipe0 = SEL_ALU_MEMWB_PIPE1;
    end
    else if(wb_RegWrite_pipe0 && ex_rs2_pipe0 != 4'b0000 && (wb_rd_pipe0 == ex_rs2_pipe0)) begin
        if(wb_MCycle_pipe0)
            selB_ex_pipe0 = SEL_MCYCLE_MEMWB_PIPE0;
        else if(is_load_wb_pipe0)
            selB_ex_pipe0 = SEL_LW_MEMWB_PIPE0;
        else
            selB_ex_pipe0 = SEL_ALU_MEMWB_PIPE0;
    end
    else begin
        selB_ex_pipe0 = SEL_IDEX;
    end
end


always @(*) begin
    if(mem_RegWrite_pipe1 && ex_rs1_pipe1 != 4'b0000 && !is_load_mem_pipe1 && (mem_rd_pipe1 == ex_rs1_pipe1)) begin
        if(mem_MCycle_pipe1)
            selA_ex_pipe1 = SEL_MCYCLE_EXMEM_PIPE1;
        else
            selA_ex_pipe1 = SEL_ALU_EXMEM_PIPE1;
    end
    else if(mem_RegWrite_pipe0 && ex_rs1_pipe1 != 4'b0000 && !is_load_mem_pipe0 && (mem_rd_pipe0 == ex_rs1_pipe1)) begin
        if(mem_MCycle_pipe0)
            selA_ex_pipe1 = SEL_MCYCLE_EXMEM_PIPE0;
        else
            selA_ex_pipe1 = SEL_ALU_EXMEM_PIPE0;
    end
    else if(wb_RegWrite_pipe1 && ex_rs1_pipe1 != 4'b0000 && (wb_rd_pipe1 == ex_rs1_pipe1)) begin
        if(wb_MCycle_pipe1)
            selA_ex_pipe1 = SEL_MCYCLE_MEMWB_PIPE1;
        else if(is_load_wb_pipe1)
            selA_ex_pipe1 = SEL_LW_MEMWB_PIPE1;
        else
            selA_ex_pipe1 = SEL_ALU_MEMWB_PIPE1;
    end
    else if(wb_RegWrite_pipe0 && ex_rs1_pipe1 != 4'b0000 && (wb_rd_pipe0 == ex_rs1_pipe1)) begin
        if(wb_MCycle_pipe0)
            selA_ex_pipe1 = SEL_MCYCLE_MEMWB_PIPE0;
        else if(is_load_wb_pipe0)
            selA_ex_pipe1 = SEL_LW_MEMWB_PIPE0;
        else
            selA_ex_pipe1 = SEL_ALU_MEMWB_PIPE0;
    end
    else begin
        selA_ex_pipe1 = SEL_IDEX;
    end
end


always @(*) begin
    if(mem_RegWrite_pipe1 && ex_rs2_pipe1 != 4'b0000 && !is_load_mem_pipe1 && (mem_rd_pipe1 == ex_rs2_pipe1)) begin
        if(mem_MCycle_pipe1)
            selB_ex_pipe1 = SEL_MCYCLE_EXMEM_PIPE1;
        else
            selB_ex_pipe1 = SEL_ALU_EXMEM_PIPE1;
    end
    else if(mem_RegWrite_pipe0 && ex_rs2_pipe1 != 4'b0000 && !is_load_mem_pipe0 && (mem_rd_pipe0 == ex_rs2_pipe1)) begin
        if(mem_MCycle_pipe0)
            selB_ex_pipe1 = SEL_MCYCLE_EXMEM_PIPE0;
        else
            selB_ex_pipe1 = SEL_ALU_EXMEM_PIPE0;
    end
    else if(wb_RegWrite_pipe1 && ex_rs2_pipe1 != 4'b0000 && (wb_rd_pipe1 == ex_rs2_pipe1)) begin
        if(wb_MCycle_pipe1)
            selB_ex_pipe1 = SEL_MCYCLE_MEMWB_PIPE1;
        else if(is_load_wb_pipe1)
            selB_ex_pipe1 = SEL_LW_MEMWB_PIPE1;
        else
            selB_ex_pipe1 = SEL_ALU_MEMWB_PIPE1;
    end
    else if(wb_RegWrite_pipe0 && ex_rs2_pipe1 != 4'b0000 && (wb_rd_pipe0 == ex_rs2_pipe1)) begin
        if(wb_MCycle_pipe0)
            selB_ex_pipe1 = SEL_MCYCLE_MEMWB_PIPE0;
        else if(is_load_wb_pipe0)
            selB_ex_pipe1 = SEL_LW_MEMWB_PIPE0;
        else
            selB_ex_pipe1 = SEL_ALU_MEMWB_PIPE0;
    end
    else begin
        selB_ex_pipe1 = SEL_IDEX;
    end
end


endmodule
