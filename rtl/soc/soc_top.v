`timescale 1ns / 1ps


//>>>>>>>>>>>> ******* FOR SIMULATION. DO NOT SYNTHESIZE THIS DIRECTLY (This is used as a component in TOP.vhd for Synthesis) ******* <<<<<<<<<<<<

module soc_top
#(
	parameter N_LEDs_OUT = 8,        // Number of LEDs displaying Result. LED(15 downto 15-N_LEDs_OUT+1). 8 by default
	parameter N_DIPs = 16,           // Number of DIPs. 16 by default
	parameter N_PBs  = 3             // Number of PushButtons. 3 by default
		                             // [2:0] -> BTNL, BTNC, BTNR. Note that BTNU is used as PAUSE and BTND is used as RESET
)
(
    input  [N_DIPs-1:0] DIP, 		// 16-bit DIP switch inputs. Not debounced.
	input  [N_PBs-1:0] PB,  		// 3-bit PB switch inputs. Not debounced.
	output reg [N_LEDs_OUT-1:0] LED_OUT, 	// 8-bit LED[7:0]
	output [6:0] LED_PC, 			// LED[15:9] showing PC[8:2].
	output reg [31:0] SEVENSEGHEX, 		// 32-bit value for 8-digit 7 Seg LED Display. 
	output reg [7:0] UART_TX,           	// 8-bit CONSOLE (UART TX) Output. Character sent to PC/testbench via UART.
						// s/w should check if UART_TX_ready is set before writing to this location esp if your CLK_DIV_BITS is small. No consecutive stores
	input UART_TX_ready,			// A status that it is ok to write to the UART_TX.
		                                // This bit should be set in the testbench to indicate readiness to transmit new character.
	output reg UART_TX_valid,           	// A signal from Wrapper to UART hardware that the processor has written a new data byte to be transmitted.
	input [7:0] UART_RX,                	// 8-bit CONSOLE (UART RX) Input. Character received from PC/testbench via UART.
	                                        // s/w should check if UART_RX_valid flag is set before reading from this location. No consecutive loads
	input  	UART_RX_valid,               	// A status that there is a new data byte waiting to be read from UART_RX.
	                                        // This bit should be set in the testbench to indicate a new character.
	output reg UART_RX_ack,              	// A signal from to UART hardware that the processor has read the newly received data byte.
	                                        // The testbench should clear UART_RX_valid when this is set.
	output reg OLED_Write,			// Indicates that the pixel is to be updated. This could happen when you change row or col or data depending on OLED_CTRL[3:0]
	output reg [6:0] OLED_Col = 7'd0,
	output reg [5:0] OLED_Row = 6'd0,
	output reg [23:0] OLED_Data,		// 24-bit pixel so as to see easily on the display. <5R, 6G, 8B>, each extended to 8 bits left aligned.
	input [31:0] ACCEL_Data,		// Packed <Temp, X, Y, Z> from MSB to LSB. X, Y, Z are in +/-2g range, 8-bit signed.
	input ACCEL_DReady,			// Accelerometer data ready signal. Mostly not necessary unless you are reading at a very high rate.
	input  RESET,				// Active high. Implemented in TOP as not(BTND) or Internal_reset.
	input  CLK				// Divided Clock from TOP, shown on LED[8].				
);

// Set the base address according to your memory configuration in RARS. Set the size (Depth bits) appropriately as well.
localparam IROM_BASE = 32'h0040_0000;		// make sure this is the same as the .txt address based on the Memory Configuration set in the assembler/linker 
                                            	// and the PC default value as well as reset value in **ProgramCounter.v** 
localparam DMEM_BASE = 32'h1001_0000;    	// make sure this is the same as the .data address based on the Memory Configuration set in the assembler/linker
localparam MMIO_BASE = 32'hFFFF_0000;
localparam PC_INIT = IROM_BASE;			// PC initialization value - same as IROM_BASE

localparam IROM_DEPTH_BITS = 14;		//	4096 rows
localparam DMEM_DEPTH_BITS = 1;		// 	4096 rows
localparam MMIO_DEPTH_BITS = 8;

// Memory-mapped peripheral register offsets
localparam UART_RX_VALID_OFF 	= 8'h00; //RO, status bit
localparam UART_RX_OFF 			= 8'h04; //RO
localparam UART_TX_READY_OFF 	= 8'h08; //RO, status bit
localparam UART_TX_OFF 			= 8'h0C; //WO
localparam OLED_COL_OFF 		= 8'h20; //WO
localparam OLED_ROW_OFF 		= 8'h24; //WO
localparam OLED_DATA_OFF 		= 8'h28; //WO
localparam OLED_CTRL_OFF 		= 8'h2C; //WO
localparam ACCEL_DATA_OFF 		= 8'h40; //RO
localparam ACCEL_DREADY_OFF 	= 8'h44; //RO, status bit
localparam LED_OFF 				= 8'h60; //WO
localparam DIP_OFF 				= 8'h64; //RO
localparam PB_OFF  				= 8'h68; //RO
localparam SEVENSEG_OFF 		= 8'h80; //WO
localparam CYCLECOUNT_OFF 		= 8'hA0; //RO

// params for memory
localparam DATA_WIDTH = 32;
localparam ADDR_WIDTH = 13;		// 4096 rows
localparam INSTR_WIDTH = 64;
                                      
//----------------------------------------------------------------
// RV signals
//----------------------------------------------------------------
wire [31:0] PC;
wire [31:0] Instr_pipe0;
wire [31:0] Instr_pipe1;
reg [31:0] ReadData_in_pipe0;
reg [31:0] ReadData_in_pipe1;
wire MemRead;
wire [2:0] MemWrite_out_pipe0;
wire [2:0] MemWrite_out_pipe1;
wire [31:0] ALUResult_pipe0;
wire [31:0] ALUResult_pipe1;
wire [31:0] WriteData_out_pipe0;
wire [31:0] WriteData_out_pipe1;
wire [4:0]  LwSizeSel_pipe0;
wire [4:0]  LwSizeSel_pipe1;

//wire dec_MMIO_read;	// any MMIO register is being read?
//reg dec_DMEM_W = 1'b0;
//reg dec_MMIO_read_W = 1'b0;  // delayed versions of the decoded signals for output multiplexing
//reg bad_MEM_addr;	// bad data memory address. Can be used as interrupt
//wire MemWrite;		// overall MemWrite

wire [31:0] cycle_count; // Max 42 seconds at 100 MHz clock

wire cycle_count_read_pipe0;
assign cycle_count_read_pipe0 = (ALUResult_pipe0[DATA_WIDTH-1:16] == MMIO_BASE[31:16] && ALUResult_pipe0[MMIO_DEPTH_BITS-1:0] == CYCLECOUNT_OFF);
wire cycle_count_read_pipe1;
assign cycle_count_read_pipe1 = (ALUResult_pipe1[DATA_WIDTH-1:16] == MMIO_BASE[31:16] && ALUResult_pipe1[MMIO_DEPTH_BITS-1:0] == CYCLECOUNT_OFF);

wire uart_tx_ready_read_pipe0;
assign uart_tx_ready_read_pipe0 = (ALUResult_pipe0[DATA_WIDTH-1:16] == MMIO_BASE[31:16] && ALUResult_pipe0[MMIO_DEPTH_BITS-1:0] == UART_TX_READY_OFF);

wire uart_tx_ready_read_pipe1;
assign uart_tx_ready_read_pipe1 = (ALUResult_pipe1[DATA_WIDTH-1:16] == MMIO_BASE[31:16] && ALUResult_pipe1[MMIO_DEPTH_BITS-1:0] == UART_TX_READY_OFF);


// DMEM signals, simple dual port bram: A WRITE - B READ
wire [ADDR_WIDTH-2:0] dmem_addra;
wire dmem_clka;
wire [DATA_WIDTH-1:0] dmem_dina;
wire [DATA_WIDTH-1:0] dmem_douta;
wire dmem_ena;
wire dmem_rsta;
wire [3:0] dmem_wea;
    
wire [ADDR_WIDTH-2:0] dmem_addrb; 
wire dmem_clkb;
wire [DATA_WIDTH-1:0] dmem_dinb;
wire [DATA_WIDTH-1:0] dmem_doutb;
wire dmem_enb;
wire dmem_rstb;
wire [3:0] dmem_web;

// IROM signals
wire [ADDR_WIDTH-1:0] irom_addra;
wire irom_clka;
wire [DATA_WIDTH-1:0] irom_dina;
wire [DATA_WIDTH-1:0] irom_douta;
wire irom_ena;
wire irom_rsta;
wire irom_wea;

wire [ADDR_WIDTH-1:0] irom_addrb;
wire irom_clkb;
wire [DATA_WIDTH-1:0] irom_dinb;
wire [DATA_WIDTH-1:0] irom_doutb;
wire irom_enb;
wire irom_rstb;
wire irom_web;

// Clocking Wizard signals
wire reset;
wire clk_in1;
wire clk_out1;      // 100MHz
wire clk_out2;      // 200MHz
wire locked;
wire clk1 = clk_out1;
wire clk2 = clk_out2;

wire [1:0] fetch_fault, data_fault, data_write_intent;
wire [2:0] data_size0, data_size1;
soc_access_check address_check(
    .pc(PC), .address0(ALUResult_pipe0), .address1(ALUResult_pipe1),
    .size0(data_size0), .size1(data_size1), .write_intent(data_write_intent),
    .fetch_fault(fetch_fault), .data_fault(data_fault)
);

// Machine timer MMIO uses the same byte-lane formatting as DMEM stores.
wire [31:0] timer_rdata_pipe0, timer_rdata_pipe1;
wire timer_hit_pipe0, timer_hit_pipe1, timer_irq, timer_software_irq;
wire [63:0] machine_time;
machine_timer machine_timer_inst(
    .clk(clk1), .rst(RESET),
    .addr_pipe0(ALUResult_pipe0), .addr_pipe1(ALUResult_pipe1),
    .wdata_pipe0(dmem_dina), .wdata_pipe1(dmem_dinb),
    .wstrb_pipe0(dmem_wea), .wstrb_pipe1(dmem_web),
    .rdata_pipe0(timer_rdata_pipe0), .rdata_pipe1(timer_rdata_pipe1),
    .hit_pipe0(timer_hit_pipe0), .hit_pipe1(timer_hit_pipe1),
    .irq_timer(timer_irq), .irq_software(timer_software_irq), .time_value(machine_time)
);

// Connect DMEM signals

reg [DATA_WIDTH-1:0] sel_bytes_pipe0;
reg [DATA_WIDTH-1:0] sel_bytes_pipe1;

wire [1:0] byte_select0;
wire [1:0] byte_select1;

reg [3:0] dmem_wea_reg;
reg [3:0] dmem_web_reg;

reg [DATA_WIDTH-1:0] dmem_dina_reg;
reg [DATA_WIDTH-1:0] dmem_dinb_reg;

always @(*) begin
    dmem_dina_reg = 32'd0;
    dmem_dinb_reg = 32'd0;
    dmem_wea_reg = 4'b0000;
    dmem_web_reg = 4'b0000;
    if(MemWrite_out_pipe0 == 3'b001) begin
        if(ALUResult_pipe0[1:0] == 2'b00) begin
            dmem_dina_reg = {24'd0, WriteData_out_pipe0[7:0]};
            dmem_wea_reg = 4'b0001;
        end else if(ALUResult_pipe0[1:0] == 2'b01) begin
            dmem_dina_reg = {16'd0, WriteData_out_pipe0[7:0], 8'd0};
            dmem_wea_reg = 4'b0010;
        end else if(ALUResult_pipe0[1:0] == 2'b10) begin
            dmem_dina_reg = {8'd0, WriteData_out_pipe0[7:0], 16'd0};
            dmem_wea_reg = 4'b0100;
        end else if(ALUResult_pipe0[1:0] == 2'b11) begin
            dmem_dina_reg = {WriteData_out_pipe0[7:0], 24'd0};
            dmem_wea_reg = 4'b1000;
        end
    end else if(MemWrite_out_pipe0 == 3'b010) begin
        if(ALUResult_pipe0[1:0] == 2'b00) begin
            dmem_dina_reg = {16'd0, WriteData_out_pipe0[15:0]};
            dmem_wea_reg = 4'b0011;
        end else if(ALUResult_pipe0[1:0] == 2'b10) begin
            dmem_dina_reg = {WriteData_out_pipe0[15:0], 16'd0};
            dmem_wea_reg = 4'b1100;
        end
    end else if(MemWrite_out_pipe0 == 3'b100) begin
        dmem_dina_reg = WriteData_out_pipe0;
        dmem_wea_reg = 4'b1111;
    end 

    if(MemWrite_out_pipe1 == 3'b001) begin
        if(ALUResult_pipe1[1:0] == 2'b00) begin
            dmem_dinb_reg = {24'd0, WriteData_out_pipe1[7:0]};
            dmem_web_reg = 4'b0001;
        end else if(ALUResult_pipe1[1:0] == 2'b01) begin
            dmem_dinb_reg = {16'd0, WriteData_out_pipe1[7:0], 8'd0};
            dmem_web_reg = 4'b0010;
        end else if(ALUResult_pipe1[1:0] == 2'b10) begin
            dmem_dinb_reg = {8'd0, WriteData_out_pipe1[7:0], 16'd0};
            dmem_web_reg = 4'b0100;
        end else if(ALUResult_pipe1[1:0] == 2'b11) begin
            dmem_dinb_reg = {WriteData_out_pipe1[7:0], 24'd0};
            dmem_web_reg = 4'b1000;
        end
    end else if(MemWrite_out_pipe1 == 3'b010) begin
        if(ALUResult_pipe1[1:0] == 2'b00) begin
            dmem_dinb_reg = {16'd0, WriteData_out_pipe1[15:0]};
            dmem_web_reg = 4'b0011;
        end else if(ALUResult_pipe1[1:0] == 2'b10) begin
            dmem_dinb_reg = {WriteData_out_pipe1[15:0], 16'd0};
            dmem_web_reg = 4'b1100;
        end
    end else if(MemWrite_out_pipe1 == 3'b100) begin
        dmem_dinb_reg = WriteData_out_pipe1;
        dmem_web_reg = 4'b1111;
    end
end

assign byte_select0 = ALUResult_pipe0[1:0];
assign byte_select1 = ALUResult_pipe1[1:0];

always @(*) begin
    case(LwSizeSel_pipe0)
        5'b00001, 5'b01000: begin  
            case(byte_select0)
                2'b00: sel_bytes_pipe0 = {24'd0, dmem_douta[7:0]};
                2'b01: sel_bytes_pipe0 = {24'd0, dmem_douta[15:8]};
                2'b10: sel_bytes_pipe0 = {24'd0, dmem_douta[23:16]};
                2'b11: sel_bytes_pipe0 = {24'd0, dmem_douta[31:24]};
            endcase
        end
        5'b00010, 5'b10000: begin 
            case(byte_select0[1])
                1'b0: sel_bytes_pipe0 = {16'd0, dmem_douta[15:0]};
                1'b1: sel_bytes_pipe0 = {16'd0, dmem_douta[31:16]};
            endcase
        end
        5'b00100: begin  
            sel_bytes_pipe0 = dmem_douta;
        end
        default: begin
            sel_bytes_pipe0 = dmem_douta;  
        end
    endcase
end

always @(*) begin
    case(LwSizeSel_pipe1)
        5'b00001, 5'b01000: begin  
            case(byte_select1)
                2'b00: sel_bytes_pipe1 = {24'd0, dmem_doutb[7:0]};
                2'b01: sel_bytes_pipe1 = {24'd0, dmem_doutb[15:8]};
                2'b10: sel_bytes_pipe1 = {24'd0, dmem_doutb[23:16]};
                2'b11: sel_bytes_pipe1 = {24'd0, dmem_doutb[31:24]};
            endcase
        end
        5'b00010, 5'b10000: begin  
            case(byte_select1[1])
                1'b0: sel_bytes_pipe1 = {16'd0, dmem_doutb[15:0]};
                1'b1: sel_bytes_pipe1 = {16'd0, dmem_doutb[31:16]};
            endcase
        end
        5'b00100: begin  
            sel_bytes_pipe1 = dmem_doutb;
        end
        default: begin
            sel_bytes_pipe1 = dmem_doutb; 
        end
    endcase
end


assign dmem_addrb = (ALUResult_pipe1 - DMEM_BASE) >> 2;
assign dmem_enb = ((ALUResult_pipe1[31:14] == DMEM_BASE[31:14]) & (LwSizeSel_pipe1 != 5'b00000 || MemWrite_out_pipe1 != 3'b000))? 1'b1: 1'b0;
assign dmem_dinb = dmem_dinb_reg;
assign dmem_web = dmem_web_reg;
  
always @(*) begin
	if (timer_hit_pipe1)
        ReadData_in_pipe1 = timer_rdata_pipe1 >> (ALUResult_pipe1[1:0]*8);
    else if (cycle_count_read_pipe1)
		ReadData_in_pipe1 = cycle_count;
	else if( uart_tx_ready_read_pipe1)
		ReadData_in_pipe1 = {31'd0, UART_TX_ready};
	else
		ReadData_in_pipe1 = sel_bytes_pipe1;
end


assign dmem_addra = (ALUResult_pipe0 - DMEM_BASE) >> 2;
assign dmem_wea = dmem_wea_reg;
assign dmem_ena = ((ALUResult_pipe0[31:14] == DMEM_BASE[31:14]) & (LwSizeSel_pipe0 != 5'b00000 || MemWrite_out_pipe0 != 3'b000))? 1'b1: 1'b0;
assign dmem_dina = dmem_dina_reg;

always @(*) begin
	if (timer_hit_pipe0)
        ReadData_in_pipe0 = timer_rdata_pipe0 >> (ALUResult_pipe0[1:0]*8);
    else if (cycle_count_read_pipe0)
		ReadData_in_pipe0 = cycle_count;
	else if(uart_tx_ready_read_pipe0)
		ReadData_in_pipe0 = {31'd0, UART_TX_ready};
	else
		ReadData_in_pipe0 = sel_bytes_pipe0;
end


assign dmem_rstb = RESET;				// done
assign dmem_rsta = RESET;				// done
assign dmem_clka = clk2;				// done
assign dmem_clkb = clk2;				// done

// connect IROM signals
assign irom_addra = (PC - IROM_BASE) >> 2;
assign irom_addrb = (PC + 4 - IROM_BASE) >> 2;

assign Instr_pipe0 = irom_douta;
assign Instr_pipe1 = irom_doutb;

assign irom_clka = clk2;				// done
assign irom_dina = 0;					// done
assign irom_ena = 1'b1;
assign irom_rsta = RESET;				// done
assign irom_wea = 0;					// done

assign irom_clkb = clk2;				// done
assign irom_dinb = 0;					// done
assign irom_enb = 1'b1;
assign irom_rstb = RESET;				// done
assign irom_web = 0;					// done

// connect clocking wizard signals
assign reset = RESET;

//----------------------------------------------------------------
// Address Decode signals
//---------------------------------------------------------------
// 'enable' signals from data memory address decoding
reg 
dec_DMEM					,
dec_UART_RX_VALID			,
dec_UART_RX					,
dec_UART_TX_READY			,
dec_UART_TX					,
dec_OLED_COL				,
dec_OLED_ROW				,
dec_OLED_DATA				,
dec_OLED_CTRL				,
dec_ACCEL_DATA				,
dec_ACCEL_DREADY			,
dec_LED						,
dec_DIP						,
dec_PB						,
dec_SEVENSEG				,
dec_CYCLECOUNT				// Cycle count signal
;

// //----------------------------------------------------------------
// // Memory declaration
// //-----------------------------------------------------------------
// reg [31:0] IROM	[0:2**(IROM_DEPTH_BITS-2)-1];	// instruction memory aka IROM
// reg [31:0] DMEM	[0:2**(DMEM_DEPTH_BITS-2)-1];	// data (constant + variable) memory.

//----------------------------------------------------------------
// Memory initialisation
//----------------------------------------------------------------
// initial begin
// // Make sure that the .mem files (hexadecimal text memory dump from RARS - name it with .mem extension) are added to the project as 'Design Sources'. Alternatively, specify the full path.
// 	// The files start with AA so that it is easier t find in the file open/save dialog box 
// // If you checked "Copy sources into project", make sure that subsequent dumps from RARS are to projectName/projectName.srcs/sources_1/imports/orignalSourceFolderName 
// 	// IMP: "Relaunch Simulation" (top menu broken clock-wise button) may not be enough if you change your .mem file. Do SIMULATION > Run Simulation > Run Behavioural Simulation. 
// 	// In simulation, check the memory contents under test_Wrapper>dut (Wrapper)> IROM (and other memories) if unsure the correct contents are used.
// // If you click Generate Bitstream after updating the .mem file, Vivado does not rerun synthesis using the new file, as it does not know that the file was modified externally. 
// 	// Rerun the synthesis and then bitstream generation though Vivado says it is up to date. 
	
// $readmemh("AA_IROM.mem", IROM);
// $readmemh("AA_DMEM.mem", DMEM);
// // AA_DMEM.mem will generate a warning of having more than necessary data as the assembler dumps the entire data segment including DMEM and MMIO,
// 	// This is ok as only the first part of it will be used to initialize DMEM.

// end

////----------------------------------------------------------------
//// Memory and Peripheral outputs to be multiplexed
////----------------------------------------------------------------
//// reg [31:0] ReadData_DMEM;
//reg [31:0] ReadData_MMIO;

//// reg [DATA_WIDTH-1:0] ReadData_DMEM;


////----------------------------------------------------------------
//// Data memory address decoding
////----------------------------------------------------------------
//always@(*) begin
//	dec_DMEM 				<= 1'b0;
//	bad_MEM_addr 			<= 1'b0;
//	dec_UART_RX_VALID		<= 1'b0;
//	dec_UART_RX				<= 1'b0;
//	dec_UART_TX_READY		<= 1'b0;
//	dec_UART_TX				<= 1'b0;
//	dec_OLED_COL			<= 1'b0;
//	dec_OLED_ROW			<= 1'b0;
//	dec_OLED_DATA			<= 1'b0;
//	dec_OLED_CTRL			<= 1'b0;
//	dec_ACCEL_DATA			<= 1'b0;
//	dec_ACCEL_DREADY		<= 1'b0;
//	dec_LED					<= 1'b0;
//	dec_DIP					<= 1'b0;
//	dec_PB					<= 1'b0;
//	dec_SEVENSEG			<= 1'b0;
//	dec_CYCLECOUNT			<= 1'b0;

//	if(ALUResult[31:DMEM_DEPTH_BITS] == DMEM_BASE[31:DMEM_DEPTH_BITS])
//		dec_DMEM <= 1'b1;
//	else if (ALUResult[31:MMIO_DEPTH_BITS] == MMIO_BASE[31:MMIO_DEPTH_BITS]) begin
//		case (ALUResult[MMIO_DEPTH_BITS-1:2])
//			UART_RX_VALID_OFF[MMIO_DEPTH_BITS-1:2]: dec_UART_RX_VALID <= 1'b1;
//			UART_RX_OFF[MMIO_DEPTH_BITS-1:2]: dec_UART_RX <= 1'b1;
//			UART_TX_READY_OFF[MMIO_DEPTH_BITS-1:2]: dec_UART_TX_READY <= 1'b1;
//			UART_TX_OFF[MMIO_DEPTH_BITS-1:2]: dec_UART_TX <= 1'b1;
//			OLED_COL_OFF[MMIO_DEPTH_BITS-1:2]: dec_OLED_COL <= 1'b1;
//			OLED_ROW_OFF[MMIO_DEPTH_BITS-1:2]: dec_OLED_ROW <= 1'b1;
//			OLED_DATA_OFF[MMIO_DEPTH_BITS-1:2]: dec_OLED_DATA <= 1'b1;
//			OLED_CTRL_OFF[MMIO_DEPTH_BITS-1:2]: dec_OLED_CTRL <= 1'b1;
//			ACCEL_DATA_OFF[MMIO_DEPTH_BITS-1:2]: dec_ACCEL_DATA <= 1'b1;
//			ACCEL_DREADY_OFF[MMIO_DEPTH_BITS-1:2]: dec_ACCEL_DREADY <= 1'b1;
//			LED_OFF[MMIO_DEPTH_BITS-1:2]: dec_LED <= 1'b1;
//			DIP_OFF[MMIO_DEPTH_BITS-1:2]: dec_DIP <= 1'b1;
//			PB_OFF[MMIO_DEPTH_BITS-1:2]: dec_PB <= 1'b1;
//			SEVENSEG_OFF[MMIO_DEPTH_BITS-1:2]: dec_SEVENSEG <= 1'b1;
//			CYCLECOUNT_OFF[MMIO_DEPTH_BITS-1:2]: dec_CYCLECOUNT <= 1'b1;
//			default: bad_MEM_addr <= 1'b1;
//		endcase
//	end
//	else 
//		bad_MEM_addr <= 1'b1;
//end

//assign dec_MMIO_read = MemRead || dec_DIP || dec_PB || dec_UART_RX_VALID || dec_UART_RX || dec_UART_TX_READY || dec_UART_TX || dec_CYCLECOUNT || dec_ACCEL_DATA || dec_ACCEL_DREADY;
//assign MemWrite = MemWrite_out[3] || MemWrite_out[2] || MemWrite_out[1] || MemWrite_out[0];

//----------------------------------------------------------------
// Input (into RV) multiplexing
//----------------------------------------------------------------
//always@(posedge clk1) begin
//if (dec_DMEM_W)
//	ReadData_in <= dmem_doutb; 
//else 		// dec_MMIO_read_W
//	ReadData_in <= ReadData_MMIO;
//end

// //----------------------------------------------------------------
// // DMEM write
// //----------------------------------------------------------------
localparam NUM_COL = 4;
localparam COL_WIDTH = 8;
// integer i;
// always@(posedge CLK) begin
// 	if( MemWrite ) begin
// 		for(i=0;i<NUM_COL;i=i+1) begin
// 			if(MemWrite_out[i]) begin
// 				if( dec_DMEM ) begin
// 					DMEM[ALUResult[DMEM_DEPTH_BITS-1:2]][i*COL_WIDTH +: COL_WIDTH] <= WriteData_out[i*COL_WIDTH +: COL_WIDTH];
// 				end		      
// 			end
// 		end
// 	end
//     //ReadData_DMEM <= DMEM[ALUResult[DMEM_DEPTH_BITS-1:2]]; //Uncomment only if only using synch read for memory
// end

// //----------------------------------------------------------------
// // Asych DMEM read - //Uncomment the following block (3 lines) if NOT using synch read for memory
// //----------------------------------------------------------------
// always@( * ) begin 
//     ReadData_DMEM <= DMEM[ALUResult[DMEM_DEPTH_BITS-1:2]]; // async read
// end

// //----------------------------------------------------------------
// // IROM read
// //----------------------------------------------------------------
// always@( * ) begin // @posedge CLK only if using synch read for memory
//     Instr = ( ( PC[31:IROM_DEPTH_BITS] == IROM_BASE[31:IROM_DEPTH_BITS]) && // To check if address is in the valid range
// 	     				(PC[1:0] == 2'b00) )? // and is word-aligned - we do not support instruction sizes other than 32.
//                  IROM[PC[IROM_DEPTH_BITS-1:2]] : 32'h00000013; // If the address is invalid, the instruction fetched is NOP. 
//                  						// This can be changed to trigger an exception instead if need be.
// end

//----------------------------------------------------------------
// Cycle count read
//----------------------------------------------------------------
// extending this to generate interrupts at fixed intervals that are powers of two is very easy.
// extending this to generate interrupts at programmable intervals or intervals that are not powers of two is not difficult either. This will require another 
// counter that reloads/resets itself with each interrupt. This reload/reset value can be made programmable by having an MMIO register for the purpose. 
    
//----------------------------------------------------------------
// MMIO read
//----------------------------------------------------------------
//always@(posedge clk1) begin // @posedge CLK only if using synch read for memory
//if (dec_DIP)
//	ReadData_MMIO <= { {31-N_DIPs+1{1'b0}}, DIP }; 
//else if (dec_PB)
//	ReadData_MMIO <= { {31-N_PBs+1{1'b0}}, PB }; 
//else if (dec_UART_RX && UART_RX_valid)
//	ReadData_MMIO <= {24'd0, UART_RX};
//else if (dec_UART_RX_VALID)
//	ReadData_MMIO <= {31'd0, UART_RX_valid};	
//else if (dec_UART_TX_READY)
//	ReadData_MMIO <= {31'd0, UART_TX_ready};
//else if (dec_CYCLECOUNT)
//	ReadData_MMIO <= cycle_count;
//else if (dec_ACCEL_DATA)
//	ReadData_MMIO <= ACCEL_Data;	
//else	// dec_ACCEL_DREADY // the default else to avoid the statement from being incomplete
//	ReadData_MMIO <= {31'd0, ACCEL_DReady};
//end

////----------------------------------------------------------------
//// Delaying the decoded signals for multiplexing (delay only if using synch read for memory)
////----------------------------------------------------------------
//always@(posedge clk1) begin // @posedge CLK only if using synch read for memory
//    dec_DMEM_W <= dec_DMEM;
//    dec_MMIO_read_W <= dec_MMIO_read;
//end

////----------------------------------------------------------------
//// SevenSeg write
////----------------------------------------------------------------
//integer j;
//always@(posedge clk1) begin
//	if( MemWrite ) begin
//		for(j=0;j<NUM_COL;j=j+1) begin
//			if(MemWrite_out[j]) begin
//				if (RESET)
//					SEVENSEGHEX <= 32'd0;
//				else if (dec_SEVENSEG)
//					SEVENSEGHEX[j*COL_WIDTH +: COL_WIDTH] <= WriteData_out[j*COL_WIDTH +: COL_WIDTH];		      
//			end
//		end
//	end
//end

////----------------------------------------------------------------
//// Memory-mapped LED write
////----------------------------------------------------------------
//always@(posedge clk1) begin
//    if(RESET)
//        LED_OUT <= 0;
//    else if( MemWrite_out[0] && dec_LED ) 
//        LED_OUT <= WriteData_out[N_LEDs_OUT-1 : 0];
//end

////----------------------------------------------------------------
//// Memory-mapped OLED write
////----------------------------------------------------------------
//reg [7:0] OLED_ctrl_reg = 8'd0;// control register. 
//// Lower nibble controlling whether the row or column or mode is varied. Upper nibble controlling the colour mode. 
//// [3:0] - 0000: vary_pix_data_mode; 0001: vary_col_mode (x); 0010: vary_row_mode (y); 0100: autoadvance_col (row major); 0101: autoadvance_row (column major)
//// [7:4] - 0000: 8-bit colour mode; 0001: 16-bit colour mode; 0010: 24-bit colour mode
//reg autoadvance_row = 1'b0; // good idea to initialize it as the assignment inside the always blk below takes effect only in cycle 2.
//reg autoadvance_col = 1'b0;
//always@(posedge clk1) begin
//	OLED_Write <=  1'b0;
//	case (OLED_ctrl_reg[3:0]) // mapping OLED_Write direclty to TOP will write at the fast clock rate. Not an issue, but unnecessary writes
//		4'b0001: 		//vary_col_mode (x)
//			if(MemWrite_out[0] && dec_OLED_COL) begin
//				OLED_Write <=  1'b1;
//				autoadvance_row <= 1'b0;
//				autoadvance_col <= 1'b0;
//			end
//		4'b0010: 		 //vary_row_mode (y)
//			if(MemWrite_out[0] && dec_OLED_ROW) begin
//				OLED_Write <=  1'b1; 
//				autoadvance_row <= 1'b0;
//				autoadvance_col <= 1'b0;
//			end
//		4'b0100: 		// autoadvance_col (row major)
//			begin
//				if(MemWrite_out[0] && dec_OLED_DATA) begin
//					OLED_Write <= 1'b1;
//					autoadvance_row <= 1'b0;
//					autoadvance_col <= 1'b1;
//					if(autoadvance_col)
//						if(OLED_Col>=95) begin // >= as software could write >95
//							OLED_Col <= 7'd0; 
//							if(OLED_Row==63) OLED_Row <= 6'd0;	// this is redundant, as it will roll over to 0 anyway. Leaving it for comprehensibility, no h/w cost 
//							else OLED_Row <= OLED_Row+1;
//						end
//						else OLED_Col <= OLED_Col+1;
//				end
//			end
//		4'b0101: 		// autoadvance_row (column major)
//			begin
//				if(MemWrite_out[0] && dec_OLED_DATA) begin
//					OLED_Write <= 1'b1;
//					autoadvance_row <= 1'b1;
//					autoadvance_col <= 1'b0;
//     				if(autoadvance_row)
//						if(OLED_Row==63) begin
//					   		OLED_Row <= 6'd0; 	//redundant
//					   		if(OLED_Col>=95) OLED_Col <= 7'd0; 
//					   		else OLED_Col <= OLED_Col+1;
//					  	end
//					   	else OLED_Row <= OLED_Row+1;
//				end
//			end
//		default:
//			begin		//vary_pix_data_mode
//				if(MemWrite && dec_OLED_DATA) begin
//					OLED_Write <=  1'b1; 
//					autoadvance_row <= 1'b0;
//					autoadvance_col <= 1'b0;
//				end
//			end
//	endcase
        
//	case (OLED_ctrl_reg[7:4])
//		4'b0001: 		// 16-bit colour mode 5R-6G-5B - can only be written as whole world or lower half-word.
//			if( MemWrite_out[1] && MemWrite_out[0] && dec_OLED_DATA )
//				OLED_Data <= { WriteData_out[15:11], 3'd0, WriteData_out[10:5], 2'd0, WriteData_out[4:0], 3'd0};
//		4'b0010: 
//			begin		// 24-bit colour mode -  byte, half-word, and whole word accessible
//				if( MemWrite_out[2] && dec_OLED_DATA )
//					OLED_Data[23:16] <= WriteData_out[23:16];  
//				if( MemWrite_out[1] && dec_OLED_DATA )
//					OLED_Data[15:8] <= WriteData_out[15:8];
//				if( MemWrite_out[0] && dec_OLED_DATA )
//					OLED_Data[7:0] <= WriteData_out[7:0];
//			end
//		default: 		// 8-bit colour mode 3R-3G-2B (1 byte) - LSB byte, lower half-word, and whole word accessible
//			if( MemWrite_out[0] && dec_OLED_DATA )
//				OLED_Data <= { WriteData_out[7:5], 5'd0, WriteData_out[4:2], 5'd0, WriteData_out[1:0], 6'd0}; 
//	endcase 
	
//	if( MemWrite_out[0] && dec_OLED_CTRL )
//        OLED_ctrl_reg <= WriteData_out[7:0];
//	if( MemWrite_out[0] && dec_OLED_ROW ) 
//        OLED_Row <= WriteData_out[5:0];
//	if( MemWrite_out[0] && dec_OLED_COL )
//        OLED_Col <= WriteData_out[6:0];
           
//end


////----------------------------------------------------------------
//// UART read / write
////----------------------------------------------------------------
always @(*) begin
    dec_UART_TX = 1'b0;
    if(ALUResult_pipe0[31:MMIO_DEPTH_BITS] == MMIO_BASE[31:MMIO_DEPTH_BITS] && ALUResult_pipe0[MMIO_DEPTH_BITS-1:2] == UART_TX_OFF[MMIO_DEPTH_BITS-1:2]) begin
        dec_UART_TX = 1'b1;
    end
    
    if(ALUResult_pipe1[31:MMIO_DEPTH_BITS] == MMIO_BASE[31:MMIO_DEPTH_BITS] && ALUResult_pipe1[MMIO_DEPTH_BITS-1:2] == UART_TX_OFF[MMIO_DEPTH_BITS-1:2]) begin
        dec_UART_TX = 1'b1;
    end
end

reg[7:0] UART_TX_buf;
reg UART_TX_valid_buf;

always @(posedge clk1) begin
	UART_TX_valid <= UART_TX_valid_buf; // update the output register with the buffered value from the previous cycle
    UART_TX <= UART_TX_buf; // update the output register with the buffered value from the previous cycle
	// if (MemWrite_out_pipe0 && dec_UART_TX && UART_TX_ready)
	// begin
	// 	UART_TX <= WriteData_out_pipe0[7:0];
	// 	UART_TX_valid <= 1'b1;
	// end
	// else if(MemWrite_out_pipe1 && dec_UART_TX && UART_TX_ready)
	// begin
	//    UART_TX <= WriteData_out_pipe1[7:0];
	//    UART_TX_valid <= 1'b1;
	// end
end


always @(posedge clk1) begin
    UART_TX_valid_buf <= 1'b0;
    if (MemWrite_out_pipe0 && dec_UART_TX && UART_TX_ready)
	begin
		UART_TX_buf <= WriteData_out_pipe0[7:0];
		UART_TX_valid_buf <= 1'b1;
	end
	else if(MemWrite_out_pipe1 && dec_UART_TX && UART_TX_ready)
	begin
	   UART_TX_buf <= WriteData_out_pipe1[7:0];
	   UART_TX_valid_buf <= 1'b1;
	end
end

////----------------------------------------------------------------
//// Debug LEDs
////----------------------------------------------------------------
//assign LED_PC = PC[15-N_LEDs_OUT+1 : 2]; // debug showing PC

////----------------------------------------------------------------
//// RV port map
////----------------------------------------------------------------
core #(.PC_INIT(PC_INIT), .ATOMIC_BASE(DMEM_BASE),
       .ATOMIC_MASK(32'hffffc000), .MISALIGNED_BASE(DMEM_BASE),
       .MISALIGNED_MASK(32'hffff0000)) core_inst(
    .irq_software(timer_software_irq), .irq_timer(timer_irq), .irq_external(1'b0),
    .time_value(machine_time),
    .imem_fault(fetch_fault), .dmem_fault(data_fault),
    .dmem_write_intent(data_write_intent),
    .dmem_size_pipe0(data_size0), .dmem_size_pipe1(data_size1),
	.CLK(clk1),			// use 100MHz
	.RESET(RESET),
	.Instr_pipe0(Instr_pipe0),
	.Instr_pipe1(Instr_pipe1),
	.ReadData_in_pipe0(ReadData_in_pipe0),
	.ReadData_in_pipe1(ReadData_in_pipe1),
	.locked(locked),
	.MemRead(),
	.imem_ready(1'b1),		// always ready
	.dmem_ready(1'b1),		// always ready
	.MemWrite_out_pipe0(MemWrite_out_pipe0),
	.MemWrite_out_pipe1(MemWrite_out_pipe1),
	.PC(PC),
	.ALUResult_pipe0(ALUResult_pipe0),
	.ALUResult_pipe1(ALUResult_pipe1),
	.WriteData_out_pipe0(WriteData_out_pipe0),
	.WriteData_out_pipe1(WriteData_out_pipe1),
	.LwSizeSel_pipe0(LwSizeSel_pipe0),
	.LwSizeSel_pipe1(LwSizeSel_pipe1)
);


// IROM initialization, size: 32kB = 8 bytes each row, 4096 rows
blk_mem_gen_0 IROM (
	.addra(irom_addra),
    .clka(irom_clka),
    .dina(irom_dina),
    .douta(irom_douta),
    .ena(irom_ena), 
    .rsta(irom_rsta),
    .wea(irom_wea),
    
    .addrb(irom_addrb),
    .clkb(irom_clkb),
    .dinb(irom_dinb),
    .doutb(irom_doutb),
    .enb(irom_enb),
    .rstb(irom_rstb),
    .web(irom_web)
);

// DMEM initialization, size: 32kB = 8 bytes each row, 4096 rows
blk_mem_gen_1 DMEM (
	.addra(dmem_addra),
    .clka(dmem_clka),
    .dina(dmem_dina),
    .douta(dmem_douta),
    .ena(dmem_ena),
    .rsta(RESET),
    .wea(dmem_wea),
        
    .addrb(dmem_addrb),
    .clkb(dmem_clkb),
    .dinb(dmem_dinb),
    .doutb(dmem_doutb),
    .enb(dmem_enb),
    .rstb(dmem_rstb),
    .web(dmem_web)
);

c_counter_binary_0 cycle_counter(
    .CLK(clk1),
    .SCLR(RESET),
    .Q(cycle_count)
);

clk_wiz_0 CLK_WIZ_0_inst (
    // Clock in ports
    .clk_in1(CLK),      // input clk_in1
    // Clock out ports
    .clk_out1(clk1),     // output clk_out1 50MHz
    .clk_out2(clk2),     // output clk_out2 100MHz
    // Status and control signals
    .reset(reset),// input reset
    .locked(locked)      // output locked
);
endmodule
