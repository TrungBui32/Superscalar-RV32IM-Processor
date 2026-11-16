`timescale 1ns/1ps
// Parallel M-mode permission checks against shared, decoded PMP ranges.
// The lowest entry matching any byte wins; partial matches always fault.
module pmp_check(
    input [127:0] config_bytes,
    input [15:0] active_entries,
    input [559:0] lower_bounds,
    input [559:0] upper_bounds,
    input [31:0] address,
    input [2:0] size,
    input [2:0] access_type, // X W R
    output allow,
    output reg [31:0] fault_address
);
    wire [34:0] first_byte={3'b0,address};
    wire [34:0] end_byte=first_byte+{32'b0,size};
    wire [15:0] entry_matches, permissions;
    // Isolate the first match without a serial chain through all 16 entries.
    wire [15:0] winner=entry_matches & (~entry_matches+16'd1);
    wire [511:0] fault_candidates;
    assign allow=(end_byte<=35'h100000000) &&
                 (!(|entry_matches) || |(winner & permissions));
    genvar i;
    generate for (i=0; i<16; i=i+1) begin: entry
        wire [7:0] cfg=config_bytes[i*8 +:8];
        wire [34:0] lower=lower_bounds[i*35 +:35];
        wire [34:0] upper=upper_bounds[i*35 +:35];
        assign entry_matches[i]=active_entries[i] && first_byte<upper && end_byte>lower;
        assign permissions[i]=(first_byte>=lower && end_byte<=upper) &&
                              (!cfg[7] || (cfg[2:0] & access_type)==access_type);
        assign fault_candidates[i*32 +:32]=(first_byte>=lower && end_byte>upper) ?
                                         upper[31:0] : address;
    end endgenerate
    integer j;
    always @(*) begin
        fault_address=0;
        for (j=0; j<16; j=j+1)
            fault_address=fault_address | ({32{winner[j]}} & fault_candidates[j*32 +:32]);
        if (!(|entry_matches)) fault_address=address;
    end
endmodule
