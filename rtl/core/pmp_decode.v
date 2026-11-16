`timescale 1ns/1ps
// Decode configuration once for all instruction/data permission checks.
// Bounds are 35 bits so an exclusive end at 2^34 remains representable.
module pmp_decode(
    input [127:0] config_bytes,
    input [511:0] addresses,
    output [15:0] active_entries,
    output [559:0] lower_bounds,
    output [559:0] upper_bounds
);
    genvar i;
    generate for (i=0; i<16; i=i+1) begin: region
        wire [1:0] mode=config_bytes[i*8+3 +:2];
        wire [31:0] encoded=addresses[i*32 +:32];
        // XOR with the incremented address marks its trailing ones plus the
        // next bit. Appending two ones converts that mask to byte addresses.
        // All-ones pmpaddr saturates to the entire 34-bit physical space.
        wire [31:0] next_encoded=encoded+32'd1;
        wire [34:0] napot_mask={1'b0,(encoded ^ next_encoded),2'b11};
        wire [34:0] napot_lower={1'b0,encoded,2'b00} & ~napot_mask;
        wire [34:0] address_bound={1'b0,encoded,2'b00};
        wire [34:0] tor_lower;
        if (i==0) begin: first
            assign tor_lower=35'b0;
        end else begin: subsequent
            assign tor_lower={1'b0,addresses[(i-1)*32 +:32],2'b00};
        end
        // Empty/reversed TOR regions never match. Share this comparison too.
        assign active_entries[i]=mode!=0 && (mode!=2'b01 || tor_lower<address_bound);
        assign lower_bounds[i*35 +:35]=mode==2'b01 ? tor_lower :
            mode==2'b10 ? address_bound : mode==2'b11 ? napot_lower : 35'b0;
        assign upper_bounds[i*35 +:35]=mode==2'b01 ? address_bound :
            mode==2'b10 ? address_bound+35'd4 :
            mode==2'b11 ? napot_lower+napot_mask+35'd1 : 35'b0;
    end endgenerate
endmodule
