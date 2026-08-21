`timescale 1ns / 1ps

module tb_dip_led #(
	   parameter N_LEDs_OUT	= 8,					
	   parameter N_DIPs		= 16,
	   parameter N_PBs		= 3 
	)
	(
	);
	
	// Signals for the Unit Under Test (UUT)
	reg  [N_DIPs-1:0] DIP = 0;		
	reg  [N_PBs-1:0] PB = 0;			
	wire [N_LEDs_OUT-1:0] LED_OUT;
	wire [6:0] LED_PC;			
	wire [31:0] SEVENSEGHEX;	
	wire [7:0] UART_TX;
	reg  UART_TX_ready = 0;
	wire UART_TX_valid;
	reg  [7:0] UART_RX = 0;
	reg  UART_RX_valid = 0;
	wire UART_RX_ack;
	wire OLED_Write;
	wire [6:0] OLED_Col;
	wire [5:0] OLED_Row;
	wire [23:0] OLED_Data;
	reg [31:0] ACCEL_Data;
	wire ACCEL_DReady;			
	reg  RESET = 0;	
	reg  CLK = 0;				
	
	// Instantiate UUT
    soc_top dut(DIP, PB, LED_OUT, LED_PC, SEVENSEGHEX, UART_TX, UART_TX_ready, UART_TX_valid, UART_RX, UART_RX_valid, UART_RX_ack, OLED_Write, OLED_Col, OLED_Row, OLED_Data, ACCEL_Data, ACCEL_DReady, RESET, CLK);

	
	// Note: This testbench is for the Hello World program. Other assembly programs require appropriate modifications.
	// Run for about 6 us. Set UART_TX radix to ASCII to see the printed messages.
	// STIMULI
    initial
    begin
	RESET = 1; #10; RESET = 0; //hold reset state for 10 ns.

        DIP = 16'hFFFF; // Set all DIP switches to ON
        #120;
        DIP = 16'hAAAA; // Set all DIP switches to alternate on-off pattern
        #150;
        DIP = 16'h5555; // Set all DIP switches to flipped alternate on-off pattern
        #150;
        DIP = 16'h0000; // Set all DIP switches to OFF
		#150;
		//insert rest of the stimuli here
    end
	
	// GENERATE CLOCK       
    always          
    begin
       #5 CLK = ~CLK; // invert clk every 5 time units 
    end
    
endmodule
