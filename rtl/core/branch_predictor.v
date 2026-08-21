// (8×16 banking)
module branch_predictor #(
    parameter PC_WIDTH = 32,
    parameter TABLE_BITS = 7,                              // 128 entries total (reduced from 256)
    parameter RAS_DEPTH = 8,
    parameter BANK_BITS = 3                                // 8 banks × 16 entries = 128
) (
    input clk,
    input [PC_WIDTH-1:0] pc,                               // current instruction address
    input is_jump,                                         // high if current instruction is a jump (not a branch)
    input is_call,                                         // JAL/JALR with rd=x1 or x5
    input is_return,                                       // JALR with rs1=x1/x5, rd=x0

    output reg predict,                                    // 1: predict taken, 0: predict not taken
    output reg [PC_WIDTH-1:0] predict_target,              // predicted target address

    // update conditional interface
    input update_conditional,                              // high to update the predictor
    input update_branch_conditional,                       // 1: branch was taken, 0: branch was not taken
    input [PC_WIDTH-1:0] update_pc_conditional,            // address of the branch
    input [TABLE_BITS-1:0] update_pc_index_conditional,
    input [PC_WIDTH-1:0] update_target_conditional,        // actual target address of the branch
    
    // update unconditional interface
    input update_unconditional,                            // high to update the predictor
    input [PC_WIDTH-1:0] update_pc_unconditional,          // address of the branch
    input [TABLE_BITS-1:0] update_pc_index_unconditional,
    input [PC_WIDTH-1:0] update_target_unconditional       // actual target address of the branch
);
    localparam BTB_ENTRIES = 1 << TABLE_BITS;              // 128
    localparam BHT_ENTRIES = 1 << TABLE_BITS;              // 128
    localparam NUM_BANKS = 1 << BANK_BITS;                 // 8 banks
    localparam ENTRIES_PER_BANK = 1 << (TABLE_BITS - BANK_BITS);  // 16 entries per bank
    localparam INDEX_BITS = TABLE_BITS - BANK_BITS;        // 4 bits for index
    
    localparam COUNTER_WEAK_TAKEN = 2'b10;
    localparam COUNTER_WEAK_NOT_TAKEN = 2'b01;
    localparam COUNTER_STRONG_TAKEN = 2'b11;
    localparam COUNTER_STRONG_NOT_TAKEN = 2'b00;

    // Banking BTB and BHT - 8 banks of 16 entries each
    reg [11:0] btb_banks [0:NUM_BANKS-1][0:ENTRIES_PER_BANK-1];
    reg btb_valid_banks [0:NUM_BANKS-1][0:ENTRIES_PER_BANK-1];
    reg [1:0] bht_banks [0:NUM_BANKS-1][0:ENTRIES_PER_BANK-1];

    // RAS
    reg [PC_WIDTH-1:0] ras [0:RAS_DEPTH-1];
    reg [$clog2(RAS_DEPTH):0] ras_ptr;

    // Address decoding for read
    wire [TABLE_BITS-1:0] pred_idx = pc[TABLE_BITS+1:2];   // 7 bits from PC
    wire [BANK_BITS-1:0] read_bank = pred_idx[BANK_BITS-1:0];      // Lower 3 bits select bank (0-7)
    wire [INDEX_BITS-1:0] read_index = pred_idx[TABLE_BITS-1:BANK_BITS];  // Upper 4 bits select entry (0-15)
    
    // RAS top
    wire [PC_WIDTH-1:0] ras_top = (ras_ptr > 0) ? ras[ras_ptr - 1] : pc + 4;

    // Bank read arrays - 8 parallel outputs
    wire [11:0] btb_read_data [0:NUM_BANKS-1];
    wire btb_read_valid [0:NUM_BANKS-1];
    wire [1:0] bht_read_data [0:NUM_BANKS-1];

    // Generate block for 8 banks
    genvar g;
    generate
        for (g = 0; g < NUM_BANKS; g = g + 1) begin : bank_gen
            // Read logic - all 8 banks read in parallel
            assign btb_read_data[g] = btb_banks[g][read_index];
            assign btb_read_valid[g] = btb_valid_banks[g][read_index];
            assign bht_read_data[g] = bht_banks[g][read_index];
            
            // Write logic - only selected bank writes
            always @(posedge clk) begin
                // Conditional branch updates
                if (update_conditional && (update_pc_index_conditional[BANK_BITS-1:0] == g)) begin
                    if (update_branch_conditional) begin
                        // Update BHT - increment counter
                        bht_banks[g][update_pc_index_conditional[TABLE_BITS-1:BANK_BITS]] <= 
                            (bht_banks[g][update_pc_index_conditional[TABLE_BITS-1:BANK_BITS]] != COUNTER_STRONG_TAKEN) ? 
                            bht_banks[g][update_pc_index_conditional[TABLE_BITS-1:BANK_BITS]] + 1 : COUNTER_STRONG_TAKEN;
                        // Update BTB
                        btb_banks[g][update_pc_index_conditional[TABLE_BITS-1:BANK_BITS]] <= 
                            (update_target_conditional - update_pc_conditional) >> 2;
                        btb_valid_banks[g][update_pc_index_conditional[TABLE_BITS-1:BANK_BITS]] <= 1'b1;
                    end else begin
                        // Update BHT - decrement counter
                        bht_banks[g][update_pc_index_conditional[TABLE_BITS-1:BANK_BITS]] <= 
                            (bht_banks[g][update_pc_index_conditional[TABLE_BITS-1:BANK_BITS]] != COUNTER_STRONG_NOT_TAKEN) ? 
                            bht_banks[g][update_pc_index_conditional[TABLE_BITS-1:BANK_BITS]] - 1 : COUNTER_STRONG_NOT_TAKEN;
                    end
                end
                
                // Unconditional jump updates
                if (update_unconditional && (update_pc_index_unconditional[BANK_BITS-1:0] == g)) begin
                    btb_banks[g][update_pc_index_unconditional[TABLE_BITS-1:BANK_BITS]] <= 
                        (update_target_unconditional - update_pc_unconditional) >> 2;
                    btb_valid_banks[g][update_pc_index_unconditional[TABLE_BITS-1:BANK_BITS]] <= 1'b1;
                end
            end
        end
    endgenerate
    
    // Final 8:1 mux outputs - select from the correct bank
    wire [11:0] btb_offset = btb_read_data[read_bank];
    wire btb_hit = btb_read_valid[read_bank];
    wire bht_taken = bht_read_data[read_bank][1];
    
    // Initialize all 8 banks
    integer j, k;
    initial begin
        for (j = 0; j < NUM_BANKS; j = j + 1) begin
            for (k = 0; k < ENTRIES_PER_BANK; k = k + 1) begin
                btb_banks[j][k] = 12'b0;
                btb_valid_banks[j][k] = 1'b0;
                bht_banks[j][k] = COUNTER_WEAK_NOT_TAKEN;
            end
        end
        ras_ptr = 0;
        for (j = 0; j < RAS_DEPTH; j = j + 1) begin
            ras[j] = 32'b0;
        end
    end

    always @(posedge clk) begin
        // RAS updates
        if (is_call && !is_return) begin
            if (ras_ptr < RAS_DEPTH) begin
                ras[ras_ptr] <= pc + 4;
                ras_ptr <= ras_ptr + 1;
            end
        end else if (is_return && !is_call) begin
            if (ras_ptr > 0) begin
                ras_ptr <= ras_ptr - 1;
            end
        end
    end

    // Main prediction
    always @(*) begin

        // Prediction logic
        predict = 1'b0;
        predict_target = pc + 4;
        
        if (is_return && ras_ptr > 0) begin
            // Return instruction - use RAS
            predict = 1'b1;
            predict_target = ras_top;
        end else if (is_jump || is_call) begin
            // Unconditional jump/call - use BTB if hit
            if (btb_hit) begin
                predict_target = pc + {{18{btb_offset[11]}}, btb_offset, 2'b00};
                predict = 1'b1;
            end
        end else begin
            // Conditional branch - use BTB and BHT
            if (btb_hit && bht_taken) begin
                predict = 1'b1;
                predict_target = pc + {{18{btb_offset[11]}}, btb_offset, 2'b00};
            end
        end
    end

endmodule
