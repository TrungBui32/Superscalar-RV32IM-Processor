`timescale 1ns / 1ps

module tb_branch_predictor;
    // Parameters
    parameter PC_WIDTH = 32;
    parameter TABLE_BITS = 7;                              // 128 entries total (reduced from 256)
    parameter RAS_DEPTH = 8;
    parameter BANK_BITS = 3;

    // Clock period
    parameter CLK_PERIOD = 10;
    
    // DUT signals
    reg clk;
    reg [PC_WIDTH-1:0] pc;
    reg is_jump;
    reg is_call;
    reg is_return;
    wire predict;
    wire [PC_WIDTH-1:0] predict_target;
    
    reg update_conditional;                              // high to update the predictor
    reg update_branch_conditional;                       // 1: branch was taken, 0: branch was not taken
    reg [PC_WIDTH-1:0] update_pc_conditional;            // address of the branch
    reg [TABLE_BITS-1:0] update_pc_index_conditional;
    reg [PC_WIDTH-1:0] update_target_conditional;        // actual target address of the branch
    
    // update unconditional interface
    reg update_unconditional;                            // high to update the predictor
    reg [PC_WIDTH-1:0] update_pc_unconditional;          // address of the branch
    reg [TABLE_BITS-1:0] update_pc_index_unconditional;
    reg [PC_WIDTH-1:0] update_target_unconditional;       // actual target address of the branch
    
    // DUT instantiation
    branch_predictor dut (
        .clk(clk),
        .pc(pc),
        .is_jump(is_jump),
        .is_call(is_call),
        .is_return(is_return),
        .predict(predict),
        .predict_target(predict_target),
        .update_conditional(update_conditional),
        .update_branch_conditional(update_branch_conditional),
        .update_pc_conditional(update_pc_conditional),
        .update_pc_index_conditional(update_pc_index_conditional),
        .update_target_conditional(update_target_conditional),
        .update_unconditional(update_unconditional),
        .update_pc_unconditional(update_pc_unconditional),
        .update_pc_index_unconditional(update_pc_index_unconditional),
        .update_target_unconditional(update_target_unconditional)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    initial begin
        #20;
        pc = 0;
        is_jump = 0;
        is_call = 0;
        is_return = 0;
        
        #10;
        @(posedge clk);
        
        // test 1: conditional
        pc = 32'h0000_0010;
        @(posedge clk);
        pc = 32'h0000_0020;
        @(posedge clk);
        pc = 32'h0000_0030;
        @(posedge clk);
        pc = 0;
        @(posedge clk);
        
        // test 2: update conditional
        update_conditional = 1;                           
        update_branch_conditional = 1;               
        update_pc_conditional = 32'h0000_0010;    
        update_pc_index_conditional = 7'b000_0100;
        update_target_conditional = 32'h0000_0100;
        @(posedge clk);
        update_conditional = 1;                           
        update_branch_conditional = 1;               
        update_pc_conditional = 32'h0000_0020;    
        update_pc_index_conditional = 7'b000_1000;
        update_target_conditional = 32'h0000_0200;
        @(posedge clk);
        update_conditional = 1;                           
        update_branch_conditional = 1;               
        update_pc_conditional = 32'h0000_0030;    
        update_pc_index_conditional = 7'b000_1100;
        update_target_conditional = 32'h0000_0300;
        @(posedge clk);
        update_conditional = 0;                           
        update_branch_conditional = 0;               
        update_pc_conditional = 0;    
        update_pc_index_conditional = 0;
        update_target_conditional = 0;
        @(posedge clk);
        pc = 32'h0000_0010;
        @(posedge clk);
        pc = 32'h0000_0020;
        @(posedge clk);
        pc = 32'h0000_0030;
        @(posedge clk);
        pc = 0;
        @(posedge clk);
        
        
        // test 3: unconditional
        pc = 32'h0000_0040;
        is_jump = 1;
        @(posedge clk);
        pc = 32'h0000_0050;
        is_jump = 1;
        @(posedge clk);
        pc = 32'h0000_0060;
        is_jump = 1;
        @(posedge clk);
        pc = 0;
        is_jump = 0;
        @(posedge clk);
        
        // test 4: update unconditional
        update_unconditional = 1;                  
        update_pc_unconditional = 32'h0000_0040;        
        update_pc_index_unconditional = 7'b001_0000;
        update_target_unconditional = 32'h0000_0400;
        @(posedge clk);
        update_unconditional = 1;                  
        update_pc_unconditional = 32'h0000_0050;        
        update_pc_index_unconditional = 7'b001_0100;
        update_target_unconditional = 32'h0000_0500;
        @(posedge clk);
        update_unconditional = 1;                  
        update_pc_unconditional = 32'h0000_0060;        
        update_pc_index_unconditional = 7'b001_1000;
        update_target_unconditional = 32'h0000_0600;
        @(posedge clk);
        update_unconditional = 0;                  
        update_pc_unconditional = 0;        
        update_pc_index_unconditional = 0;
        update_target_unconditional = 0;
        @(posedge clk);
        pc = 32'h0000_0040;
        is_jump = 1;
        @(posedge clk);
        pc = 32'h0000_0050;
        is_jump = 1;
        @(posedge clk);
        pc = 32'h0000_0060;
        is_jump = 1;
        @(posedge clk);
        pc = 0;
        is_jump = 0;
        @(posedge clk);
        
        
        // test 5: ras
        pc = 32'h0001_0000;
        is_call = 1;
        is_return = 0;
        @(posedge clk);
        
        pc = 32'h0002_0000;
        is_call = 1;
        is_return = 0;
        @(posedge clk);
        
        pc = 32'h0003_0000;
        is_call = 1;
        is_return = 0;
        @(posedge clk);
        
        pc = 32'h0030_0000;
        is_call = 0;
        is_return = 1;
        @(posedge clk);
        
        pc = 32'h0004_0000;
        is_call = 1;
        is_return = 0;
        @(posedge clk);
        
        pc = 32'h0040_0000;
        is_call = 0;
        is_return = 1;
        @(posedge clk);
        
        pc = 32'h0020_0000;
        is_call = 0;
        is_return = 1;
        @(posedge clk);
        
        pc = 32'h0010_0000;
        is_call = 0;
        is_return = 1;
        @(posedge clk);
        
        pc = 0;
        is_call = 0;
        is_return = 0;
        @(posedge clk);
        
        
        // end
        @(posedge clk);
        pc = 0;
        is_jump = 0;
        is_call = 0;
        is_return = 0;
        update_conditional = 0;                           
        update_branch_conditional = 0;               
        update_pc_conditional = 0;    
        update_pc_index_conditional = 0;
        update_target_conditional = 0;
    
        update_unconditional = 0;                  
        update_pc_unconditional = 0;        
        update_pc_index_unconditional = 0;
        update_target_unconditional = 0;
        repeat(5) @(posedge clk);
        $finish;
    end

endmodule


