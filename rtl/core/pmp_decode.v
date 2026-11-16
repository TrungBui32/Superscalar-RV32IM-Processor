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
        // Prefix state encodes zero-counts of the lower address bits:
        // trailing[j] means no zero yet; one_zero[j] means exactly one zero.
        // These produce NAPOT bounds and the NA4 increment without wide
        // additions of variable region sizes.
        wire [32:0] trailing, one_zero;
        wire [31:0] napot_first, napot_end_low, na4_end_low;
        assign trailing[0]=1'b1;
        assign one_zero[0]=1'b0;
        genvar bit_index;
        for (bit_index=0; bit_index<32; bit_index=bit_index+1) begin: prefix
            assign trailing[bit_index+1]=trailing[bit_index] & encoded[bit_index];
            assign one_zero[bit_index+1]=(one_zero[bit_index] & encoded[bit_index]) |
                                        (trailing[bit_index] & ~encoded[bit_index]);
            assign napot_first[bit_index]=encoded[bit_index] & ~trailing[bit_index];
            assign napot_end_low[bit_index]=(encoded[bit_index] ^ one_zero[bit_index]) &
                                           ~trailing[bit_index];
            assign na4_end_low[bit_index]=encoded[bit_index] ^ trailing[bit_index];
        end
        wire [34:0] napot_lower={1'b0,napot_first,2'b00};
        wire [34:0] napot_upper={(trailing[32] | one_zero[32]),napot_end_low,2'b00};
        wire [34:0] na4_upper={trailing[32],na4_end_low,2'b00};
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
            mode==2'b10 ? na4_upper :
            mode==2'b11 ? napot_upper : 35'b0;
    end endgenerate
endmodule
