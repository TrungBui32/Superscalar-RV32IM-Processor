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
    output reg [559:0] lower_bounds,
    output reg [559:0] upper_bounds
);
    wire [15:0] decoded_active;
    wire [559:0] decoded_lower, decoded_upper;
    pmp_decode decode(.config_bytes(config_bytes),.addresses(addresses),
        .active_entries(decoded_active),.lower_bounds(decoded_lower),.upper_bounds(decoded_upper));
    always @(posedge clk) begin
        if (rst) begin
            refresh_pending<=0;
            cached_config<=0;
            active_entries<=0;
            lower_bounds<=0;
            upper_bounds<=0;
        end else begin
            refresh_pending<=update_accepted;
            cached_config<=config_bytes;
            active_entries<=decoded_active;
            lower_bounds<=decoded_lower;
            upper_bounds<=decoded_upper;
        end
    end
endmodule
