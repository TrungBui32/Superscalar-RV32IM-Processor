`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/29/2025 12:17:43 AM
// Design Name: 
// Module Name: test_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_soc();
    
    wire [7:0] uart_output;
    reg UART_TX_ready;
    reg clk;
    reg rst;
    
    // Instantiate the DUT (Device Under Test)
    soc_top dut(
        .CLK(clk),
        .RESET(rst),
        .UART_TX(uart_output),
        .UART_TX_ready(UART_TX_ready)
    );
    
    // Variables for tracking the previous and current uart_output values
    reg [7:0] prev_uart_output;
    
    // Clock generation
    initial begin
        clk = 0;
        rst = 0;
        UART_TX_ready = 0;
        prev_uart_output = 8'b0; // Initialize previous uart_output value to 0
    end
    
    always begin
        #5 clk = ~clk; // Clock toggles every 5ns
    end
    
    // Test procedure
    initial begin
        #5;
        rst = 1;  // Assert reset
        #10;
        rst = 0;  // Deassert reset
        #10;
        UART_TX_ready = 1;  // Set UART_TX_ready to 1
        
        // Monitor UART output for changes
        forever @(posedge clk) begin
            if (uart_output != prev_uart_output) begin
                $display("UART Output changed: %b -> %b at time %t", prev_uart_output, uart_output, $time);
                prev_uart_output = uart_output;  // Update previous value
            end
        end
        
        repeat(1000) @(posedge clk);  // Run the simulation for 1000 clock cycles
        $finish;  // End simulation
    end 
    
endmodule
