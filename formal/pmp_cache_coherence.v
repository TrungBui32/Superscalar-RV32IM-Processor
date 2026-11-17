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
    wire [543:0] lower, upper, expected_lower, expected_upper;
    wire [559:0] reference_lower, reference_upper;
    genvar i;
    generate for (i=0; i<16; i=i+1) begin: reference_predecessors
        assign expected_lower[i*34 +:34]={1'b0,reference_lower[i*35+2 +:33]}-34'd1;
        assign expected_upper[i*34 +:34]={1'b0,reference_upper[i*35+2 +:33]}-34'd1;
    end endgenerate
    pmp_region_cache dut(.clk(clk),.rst(rst),.update_accepted(accepted),
        .config_bytes(raw_config),.addresses(raw_addresses),.refresh_pending(pending),
        .cached_config(cached_config),.active_entries(active),.lower_last_words(lower),.upper_last_words(upper));
    pmp_decode reference_decode(.config_bytes(raw_config),.addresses(raw_addresses),
        .active_entries(reference_active),.lower_bounds(reference_lower),.upper_bounds(reference_upper));
    wire coherent=cached_config==raw_config && active==reference_active &&
                  lower==expected_lower && upper==expected_upper;
    assign equivalent=(pending || coherent) && (!was_blocked || (!pending && coherent));
endmodule
