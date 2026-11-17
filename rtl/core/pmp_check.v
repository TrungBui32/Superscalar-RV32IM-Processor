`timescale 1ns/1ps
// Cached signed bounds encode (exclusive word boundary - 1). This moves
// successor arithmetic before the cache registers, off the access-address path.
// Lowest matching entry wins; a partially covered access always faults.
module pmp_check(
    input [127:0] config_bytes,
    input [15:0] active_entries,
    input [543:0] lower_last_words,
    input [543:0] upper_last_words,
    input [31:0] address,
    input [2:0] size, // RV32 byte count: 1, 2 or 4.
    input [2:0] access_type, // X W R
    output allow,
    output reg [31:0] fault_address
);
    wire signed [33:0] first_word={4'b0,address[31:2]};
    wire [3:0] extent={2'b0,address[1:0]}+{1'b0,size};
    wire cross_one=extent>4'd4;
    wire no_wrap=!((&address[31:2]) && cross_one);
    wire [15:0] entry_matches, permissions, high_faults;
    wire [15:0] winner=entry_matches & (~entry_matches+16'd1);
    wire [15:0] fault_select=winner & high_faults;
    // A miss has no winner and therefore no denial. This avoids a second
    // wide match reduction alongside the selected entry's permission result.
    assign allow=(size==3'd1 || size==3'd2 || size==3'd4) && no_wrap && !(|(winner & ~permissions));
    genvar i;
    generate for (i=0; i<16; i=i+1) begin: entry
        wire [7:0] cfg=config_bytes[i*8 +:8];
        wire signed [33:0] lower_last=lower_last_words[i*34 +:34];
        wire signed [33:0] upper_last=upper_last_words[i*34 +:34];
        wire below_lower=first_word<=lower_last;
        wire below_upper=first_word<=upper_last;
        wire reaches_lower=cross_one && lower_last==first_word;
        wire crosses_upper=cross_one && upper_last==first_word;
        assign entry_matches[i]=active_entries[i] && below_upper &&
                                (!below_lower || reaches_lower);
        assign permissions[i]=!below_lower && below_upper && !crosses_upper &&
                              (!cfg[7] || (cfg[2:0] & access_type)==access_type);
        assign high_faults[i]=!below_lower && crosses_upper;
    end endgenerate
    // Select a boundary only for a partial high-end match. All other cases
    // report the original address, avoiding a 32-bit mux in every entry.
    wire [29:0] fault_next_word=address[31:2]+30'd1;
    always @(*) begin
        // A partial high-end match implies upper_last == first_word. Compute
        // that boundary from the address in parallel with permission checks,
        // rather than muxing sixteen bounds into a late incrementer.
        fault_address=(|fault_select) ? {fault_next_word,2'b00} : address;
    end
endmodule
