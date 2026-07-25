
`default_nettype none
`timescale 1ns/1ns

module mshr #(
    parameter ENTRIES = 32,
    parameter ADDR_WIDTH = 22,
    parameter WARP_ID_WIDTH = 3,
    parameter REG_ID_WIDTH = 4
) (
    input  wire clk,
    input  wire reset,

    input  wire                      alloc_valid,
    input  wire [ADDR_WIDTH-1:0]     alloc_addr,
    input  wire [WARP_ID_WIDTH-1:0]  alloc_warp_id,
    input  wire [REG_ID_WIDTH-1:0]   alloc_dest_reg,
    output wire                      alloc_ready,

    input  wire                      resp_valid,
    input  wire [ADDR_WIDTH-1:0]     resp_addr,

    output reg                       wakeup_valid,
    output reg  [WARP_ID_WIDTH-1:0]  wakeup_warp_id,
    output reg  [REG_ID_WIDTH-1:0]   wakeup_dest_reg,
    output wire                      mshr_full
);

    reg [ENTRIES-1:0]       valid;
    reg [ADDR_WIDTH-1:0]    addr      [ENTRIES-1:0];
    reg [WARP_ID_WIDTH-1:0] warp_id   [ENTRIES-1:0];
    reg [REG_ID_WIDTH-1:0]  dest_reg  [ENTRIES-1:0];

    wire [ENTRIES-1:0] free_slots = ~valid;
    assign mshr_full = (free_slots == 0);
    assign alloc_ready = !mshr_full;

    reg [$clog2(ENTRIES)-1:0] free_idx;
    always @(*) begin
        free_idx = 0;
        for (integer i = ENTRIES-1; i >= 0; i = i - 1) begin
            if (!valid[i]) free_idx = i;
        end
    end

    reg [$clog2(ENTRIES)-1:0] match_idx;
    reg                       match_found;
    always @(*) begin
        match_idx = 0;
        match_found = 0;
        for (integer i = 0; i < ENTRIES; i = i + 1) begin
            if (valid[i] && addr[i] == resp_addr) begin
                match_idx = i;
                match_found = 1;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            valid <= 0;
            wakeup_valid <= 0;
        end else begin
            wakeup_valid <= 0;

            if (alloc_valid && alloc_ready) begin
                valid[free_idx] <= 1;
                addr[free_idx] <= alloc_addr;
                warp_id[free_idx] <= alloc_warp_id;
                dest_reg[free_idx] <= alloc_dest_reg;
            end

            if (resp_valid && match_found) begin
                valid[match_idx] <= 0;
                wakeup_valid <= 1;
                wakeup_warp_id <= warp_id[match_idx];
                wakeup_dest_reg <= dest_reg[match_idx];
            end
        end
    end

endmodule
