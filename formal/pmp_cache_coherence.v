// Raw PMP state may change arbitrarily on accepted writes. Prove that every
// usable cache image matches current raw state, including after reset, and
// that a blocked live access becomes coherent after one refresh edge.
module pmp_cache_coherence(
    input clk, rst, request, live_mem,
    input [127:0] next_config,
    input [511:0] next_addresses,
    output equivalent
);
    reg [127:0] raw_config;
    reg [511:0] raw_addresses;
    reg was_blocked;
    wire pending;
    wire blocked=pending && live_mem;
    wire accepted=request && !blocked;
    always @(posedge clk) begin
        if (rst) begin
            raw_config<=0; raw_addresses<=0; was_blocked<=0;
        end else begin
            was_blocked<=blocked;
            if (accepted) begin raw_config<=next_config; raw_addresses<=next_addresses; end
        end
    end
    wire [127:0] cached_config;
    wire [15:0] active, reference_active;
    wire [559:0] lower, upper, reference_lower, reference_upper;
    pmp_region_cache dut(.clk(clk),.rst(rst),.update_accepted(accepted),
        .config_bytes(raw_config),.addresses(raw_addresses),.refresh_pending(pending),
        .cached_config(cached_config),.active_entries(active),.lower_bounds(lower),.upper_bounds(upper));
    pmp_decode reference_decode(.config_bytes(raw_config),.addresses(raw_addresses),
        .active_entries(reference_active),.lower_bounds(reference_lower),.upper_bounds(reference_upper));
    wire coherent=cached_config==raw_config && active==reference_active &&
                  lower==reference_lower && upper==reference_upper;
    assign equivalent=(pending || coherent) && (!was_blocked || (!pending && coherent));
endmodule
