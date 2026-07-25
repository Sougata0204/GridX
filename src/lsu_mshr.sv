
`default_nettype none
`timescale 1ns/1ns

module lsu_mshr #(
    parameter NUM_ENTRIES = 4,
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8,
    parameter REG_WIDTH = 16,
    parameter TAG_WIDTH = $clog2(NUM_ENTRIES)
) (
    input  wire clk,
    input  wire reset,
    input  wire alloc_valid,
    input  wire [ADDR_WIDTH-1:0] alloc_addr,
    input  wire [3:0] alloc_dest_reg,
    input  wire [1:0] alloc_warp_id,
    output wire alloc_ready,
    output wire [TAG_WIDTH-1:0] alloc_tag,
    input  wire fill_valid,
    input  wire [TAG_WIDTH-1:0] fill_tag,
    input  wire [DATA_WIDTH-1:0] fill_data,
    output wire fill_accepted,
    output reg  wb_valid,
    output reg  [3:0] wb_dest_reg,
    output reg  [1:0] wb_warp_id,
    output reg  [REG_WIDTH-1:0] wb_data,
    input  wire wb_ack,
    input  wire [3:0] check_reg,
    input  wire [1:0] check_warp,
    output wire check_pending,
    output wire [$clog2(NUM_ENTRIES):0] entries_used,
    output wire mshr_full,
    output wire mshr_empty
);
    reg [NUM_ENTRIES-1:0] entry_valid;
    reg [NUM_ENTRIES-1:0] entry_filled;
    reg [ADDR_WIDTH-1:0]  entry_addr [NUM_ENTRIES-1:0];
    reg [3:0]             entry_dest [NUM_ENTRIES-1:0];
    reg [1:0]             entry_warp [NUM_ENTRIES-1:0];
    reg [DATA_WIDTH-1:0]  entry_data [NUM_ENTRIES-1:0];
    wire [NUM_ENTRIES-1:0] free_mask;
    assign free_mask = ~entry_valid;

    function automatic int count_bits;
        input [NUM_ENTRIES-1:0] vec;
        int cnt;
        begin
            cnt = 0;
            for (int i = 0; i < NUM_ENTRIES; i++) begin
                if (vec[i]) cnt = cnt + 1;
            end
            count_bits = cnt;
        end
    endfunction
    assign entries_used = count_bits(entry_valid);
    assign mshr_full = (entries_used == NUM_ENTRIES);
    assign mshr_empty = (entries_used == 0);
    assign alloc_ready = !mshr_full;
    reg [TAG_WIDTH-1:0] free_entry;
    reg found_free;
    always @(*) begin
        found_free = 0;
        free_entry = 0;
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            if (!entry_valid[i] && !found_free) begin
                free_entry = i[TAG_WIDTH-1:0];
                found_free = 1;
            end
        end
    end
    assign alloc_tag = free_entry;
    assign fill_accepted = fill_valid && entry_valid[fill_tag] && !entry_filled[fill_tag];
    reg [TAG_WIDTH-1:0] wb_entry;
    reg found_wb;
    always @(*) begin
        found_wb = 0;
        wb_entry = 0;
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            if (entry_valid[i] && entry_filled[i] && !found_wb) begin
                wb_entry = i[TAG_WIDTH-1:0];
                found_wb = 1;
            end
        end
    end
    reg check_hit;
    always @(*) begin
        check_hit = 0;
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            if (entry_valid[i] &&
                entry_dest[i] == check_reg &&
                entry_warp[i] == check_warp) begin
                check_hit = 1;
            end
        end
    end
    assign check_pending = check_hit;
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            entry_valid <= 0;
            entry_filled <= 0;
            wb_valid <= 0;
            wb_dest_reg <= 0;
            wb_warp_id <= 0;
            wb_data <= 0;
            for (i = 0; i < NUM_ENTRIES; i++) begin
                entry_addr[i] <= 0;
                entry_dest[i] <= 0;
                entry_warp[i] <= 0;
                entry_data[i] <= 0;
            end
        end else begin
            if (wb_ack) begin
                wb_valid <= 0;
            end
            if (alloc_valid && alloc_ready) begin
                entry_valid[free_entry] <= 1;
                entry_filled[free_entry] <= 0;
                entry_addr[free_entry] <= alloc_addr;
                entry_dest[free_entry] <= alloc_dest_reg;
                entry_warp[free_entry] <= alloc_warp_id;
            end
            if (fill_accepted) begin
                entry_filled[fill_tag] <= 1;
                entry_data[fill_tag] <= fill_data;
            end
            if (found_wb && !wb_valid) begin
                wb_valid <= 1;
                wb_dest_reg <= entry_dest[wb_entry];
                wb_warp_id <= entry_warp[wb_entry];
                wb_data <= {{(REG_WIDTH-DATA_WIDTH){1'b0}}, entry_data[wb_entry]};
                entry_valid[wb_entry] <= 0;
                entry_filled[wb_entry] <= 0;
            end
        end
    end
endmodule
