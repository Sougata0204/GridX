
`default_nettype none
`timescale 1ns/1ns

module virtual_channel #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 16,
    parameter FIFO_DEPTH = 4
) (
    input wire clk,
    input wire reset,
    input wire in_valid,
    input wire in_is_response,
    input wire [ADDR_WIDTH-1:0] in_addr,
    input wire [DATA_WIDTH-1:0] in_data,
    input wire in_write,
    output wire in_ready,
    output wire vc0_valid,
    output wire [ADDR_WIDTH-1:0] vc0_addr,
    output wire [DATA_WIDTH-1:0] vc0_data,
    output wire vc0_write,
    input wire vc0_ready,
    output wire vc1_valid,
    output wire [ADDR_WIDTH-1:0] vc1_addr,
    output wire [DATA_WIDTH-1:0] vc1_data,
    input wire vc1_ready,
    output reg [31:0] perf_vc0_packets,
    output reg [31:0] perf_vc1_packets,
    output reg [31:0] perf_vc0_blocked_cycles,
    output reg [31:0] perf_vc1_blocked_cycles
);
    reg [ADDR_WIDTH+DATA_WIDTH:0] vc0_fifo [FIFO_DEPTH-1:0];
    reg [$clog2(FIFO_DEPTH):0] vc0_count;
    reg [$clog2(FIFO_DEPTH)-1:0] vc0_head, vc0_tail;
    wire vc0_full = (vc0_count == FIFO_DEPTH);
    wire vc0_empty = (vc0_count == 0);
    assign vc0_valid = !vc0_empty;
    assign vc0_addr = vc0_fifo[vc0_head][ADDR_WIDTH+DATA_WIDTH:DATA_WIDTH+1];
    assign vc0_data = vc0_fifo[vc0_head][DATA_WIDTH:1];
    assign vc0_write = vc0_fifo[vc0_head][0];
    reg [ADDR_WIDTH+DATA_WIDTH-1:0] vc1_fifo [FIFO_DEPTH-1:0];
    reg [$clog2(FIFO_DEPTH):0] vc1_count;
    reg [$clog2(FIFO_DEPTH)-1:0] vc1_head, vc1_tail;
    wire vc1_full = (vc1_count == FIFO_DEPTH);
    wire vc1_empty = (vc1_count == 0);
    assign vc1_valid = !vc1_empty;
    assign vc1_addr = vc1_fifo[vc1_head][ADDR_WIDTH+DATA_WIDTH-1:DATA_WIDTH];
    assign vc1_data = vc1_fifo[vc1_head][DATA_WIDTH-1:0];
    assign in_ready = in_is_response ? !vc1_full : !vc0_full;
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            vc0_count <= 0;
            vc0_head <= 0;
            vc0_tail <= 0;
            vc1_count <= 0;
            vc1_head <= 0;
            vc1_tail <= 0;
            perf_vc0_packets <= 0;
            perf_vc1_packets <= 0;
            perf_vc0_blocked_cycles <= 0;
            perf_vc1_blocked_cycles <= 0;
        end else begin
            if (in_valid && in_ready) begin
                if (!in_is_response) begin
                    vc0_fifo[vc0_tail] <= {in_addr, in_data, in_write};
                    vc0_tail <= vc0_tail + 1;
                    vc0_count <= vc0_count + 1;
                    perf_vc0_packets <= perf_vc0_packets + 1;
                end else begin
                    vc1_fifo[vc1_tail] <= {in_addr, in_data};
                    vc1_tail <= vc1_tail + 1;
                    vc1_count <= vc1_count + 1;
                    perf_vc1_packets <= perf_vc1_packets + 1;
                end
            end
            if (vc0_valid && vc0_ready) begin
                vc0_head <= vc0_head + 1;
                vc0_count <= vc0_count - 1;
            end
            if (vc1_valid && vc1_ready) begin
                vc1_head <= vc1_head + 1;
                vc1_count <= vc1_count - 1;
            end
            if (vc0_valid && !vc0_ready) begin
                perf_vc0_blocked_cycles <= perf_vc0_blocked_cycles + 1;
            end
            if (vc1_valid && !vc1_ready) begin
                perf_vc1_blocked_cycles <= perf_vc1_blocked_cycles + 1;
            end
        end
    end
endmodule
