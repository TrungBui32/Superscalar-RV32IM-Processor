`timescale 1ns/1ps
// PMP bounds have 4-byte granularity. Compare the first word against each
// boundary, then use equality for boundaries crossed by the remaining bytes.
// Lowest matching entry wins; a partially covered access always faults.
module pmp_check(
    input [127:0] config_bytes,
    input [15:0] active_entries,
    input [559:0] lower_bounds,
    input [559:0] upper_bounds,
    input [31:0] address,
    input [2:0] size, // RV32 byte count: 1, 2 or 4.
    input [2:0] access_type, // X W R
    output allow,
    output reg [31:0] fault_address
);
    wire [32:0] first_word={3'b0,address[31:2]};
    wire [32:0] next_word=first_word+33'd1;
    wire [3:0] extent={2'b0,address[1:0]}+{1'b0,size};
    wire cross_one=extent>4'd4;
    wire [32:0] end_byte={1'b0,address}+{30'b0,size};
    wire no_wrap=!end_byte[32] || end_byte[31:0]==0;
    wire [15:0] entry_matches, permissions, high_faults;
    wire [15:0] winner=entry_matches & (~entry_matches+16'd1);
    wire [15:0] fault_select=winner & high_faults;
    assign allow=(size==3'd1 || size==3'd2 || size==3'd4) && no_wrap && (!(|entry_matches) || |(winner & permissions));
    genvar i;
    generate for (i=0; i<16; i=i+1) begin: entry
        wire [7:0] cfg=config_bytes[i*8 +:8];
        wire [32:0] lower=lower_bounds[i*35+2 +:33];
        wire [32:0] upper=upper_bounds[i*35+2 +:33];
        wire below_lower=first_word<lower;
        wire below_upper=first_word<upper;
        wire reaches_lower=cross_one && lower==next_word;
        wire crosses_upper=cross_one && upper==next_word;
        assign entry_matches[i]=active_entries[i] && below_upper &&
                                (!below_lower || reaches_lower);
        assign permissions[i]=!below_lower && below_upper && !crosses_upper &&
                              (!cfg[7] || (cfg[2:0] & access_type)==access_type);
        assign high_faults[i]=!below_lower && crosses_upper;
    end endgenerate
    // Select a boundary only for a partial high-end match. All other cases
    // report the original address, avoiding a 32-bit mux in every entry.
    integer j;
    always @(*) begin
        fault_address=0;
        for (j=0; j<16; j=j+1)
            fault_address=fault_address | ({32{fault_select[j]}} & {upper_bounds[j*35+2 +:30],2'b00});
        if (!(|fault_select)) fault_address=address;
    end
endmodule
