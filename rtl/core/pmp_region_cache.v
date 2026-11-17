`timescale 1ns/1ps
// One shared register boundary between PMP CSR storage and permission checks.
// Configuration, activity and bounds are sampled atomically on every clock.
// The core masks accesses during the one-cycle refresh after a PMP CSR write.
module pmp_region_cache(
    input clk,
    input rst,
    input update_accepted,
    output reg refresh_pending,
    input [127:0] config_bytes,
    input [511:0] addresses,
    output reg [127:0] cached_config,
    output reg [15:0] active_entries,
    output reg [543:0] lower_last_words,
    output reg [543:0] upper_last_words
);
    wire [15:0] decoded_active;
    wire [559:0] decoded_lower, decoded_upper;
    pmp_decode decode(.config_bytes(config_bytes),.addresses(addresses),
        .active_entries(decoded_active),.lower_bounds(decoded_lower),.upper_bounds(decoded_upper));
    wire [543:0] decoded_lower_last, decoded_upper_last;
    genvar i;
    generate for (i=0; i<16; i=i+1) begin: predecessors
        // The extra sign bit represents -1 for a zero boundary. It also
        // preserves the full unsigned 33-bit word-bound input domain.
        assign decoded_lower_last[i*34 +:34]={1'b0,decoded_lower[i*35+2 +:33]}-34'd1;
        assign decoded_upper_last[i*34 +:34]={1'b0,decoded_upper[i*35+2 +:33]}-34'd1;
    end endgenerate
    always @(posedge clk) begin
        if (rst) begin
            refresh_pending<=0;
            cached_config<=0;
            active_entries<=0;
            lower_last_words<={544{1'b1}};
            upper_last_words<={544{1'b1}};
        end else begin
            refresh_pending<=update_accepted;
            cached_config<=config_bytes;
            active_entries<=decoded_active;
            lower_last_words<=decoded_lower_last;
            upper_last_words<=decoded_upper_last;
        end
    end
endmodule
