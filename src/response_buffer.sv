
`default_nettype none
`timescale 1ns/1ns

// GridX3 - Response Buffer
// Purpose: Circular FIFO buffering memory responses for warp early-wakeup.
// Architecture: BUFFER_DEPTH-entry circular buffer with per-warp tracking.
// Parameters: BUFFER_DEPTH, DATA_WIDTH, ADDR_WIDTH, WARP_ID_WIDTH, NUM_WARPS
// Timing: 1-cycle enqueue, 1-cycle dequeue.
// Integration: Instantiated in core.sv.

module response_buffer #(
    parameter BUFFER_DEPTH = 4,
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 16,
    parameter WARP_ID_WIDTH = 2,
    parameter NUM_WARPS = 1
) (
    input wire clk,
    input wire reset,
    input wire resp_valid,
    input wire [ADDR_WIDTH-1:0] resp_addr,
    input wire [DATA_WIDTH-1:0] resp_data,
    input wire [WARP_ID_WIDTH-1:0] resp_warp_id,
    output wire resp_ready,
    input wire [NUM_WARPS-1:0] warp_has_pending_load,
    input wire [3:0] warp_pending_count [NUM_WARPS-1:0],
    output reg out_valid,
    output reg [ADDR_WIDTH-1:0] out_addr,
    output reg [DATA_WIDTH-1:0] out_data,
    output reg [WARP_ID_WIDTH-1:0] out_warp_id,
    input wire out_ready,
    output reg [NUM_WARPS-1:0] warp_can_resume,
    output reg [31:0] perf_early_wakeups,
    output reg [31:0] perf_total_responses,
    output reg [31:0] perf_buffer_full_stalls
);
    reg [ADDR_WIDTH-1:0] buf_addr [BUFFER_DEPTH-1:0];
    reg [DATA_WIDTH-1:0] buf_data [BUFFER_DEPTH-1:0];
    reg [WARP_ID_WIDTH-1:0] buf_warp [BUFFER_DEPTH-1:0];
    reg [BUFFER_DEPTH-1:0] buf_valid;
    reg [$clog2(BUFFER_DEPTH):0] buf_count;
    reg [$clog2(BUFFER_DEPTH)-1:0] head, tail;
    integer i, w;
    reg [3:0] warp_received [NUM_WARPS-1:0];
    wire buf_full = (buf_count == BUFFER_DEPTH);
    wire buf_empty = (buf_count == 0);
    assign resp_ready = !buf_full;
    always @(*) begin
        warp_can_resume = 0;
        for (w = 0; w < NUM_WARPS; w = w + 1) begin
            if (warp_has_pending_load[w] &&
                warp_received[w] >= warp_pending_count[w] &&
                warp_pending_count[w] > 0) begin
                warp_can_resume[w] = 1;
            end
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            buf_valid <= 0;
            buf_count <= 0;
            head <= 0;
            tail <= 0;
            out_valid <= 0;
            out_addr <= 0;
            out_data <= 0;
            out_warp_id <= 0;
            perf_early_wakeups <= 0;
            perf_total_responses <= 0;
            perf_buffer_full_stalls <= 0;
            for (i = 0; i < BUFFER_DEPTH; i = i + 1) begin
                buf_addr[i] <= 0;
                buf_data[i] <= 0;
                buf_warp[i] <= 0;
            end
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                warp_received[w] <= 0;
            end
        end else begin
            if (resp_valid && resp_ready) begin
                `ifdef GRIDX_RB_DEBUG
                $display("[RB_WRITE] tail %d addr=%h data=%h warp=%d",
                         tail, resp_addr, resp_data, resp_warp_id);
                `endif
                buf_addr[tail] <= resp_addr;
                buf_data[tail] <= resp_data;
                buf_warp[tail] <= resp_warp_id;
                buf_valid[tail] <= 1;
                tail <= tail + 1;
                warp_received[resp_warp_id] <= warp_received[resp_warp_id] + 1;
                perf_total_responses <= perf_total_responses + 1;
            end
            if (resp_valid && !resp_ready) begin
                perf_buffer_full_stalls <= perf_buffer_full_stalls + 1;
            end
            if (resp_valid && resp_ready && !(!buf_empty && out_ready)) begin
                buf_count <= buf_count + 1;
            end else if (!resp_valid && (!buf_empty && out_ready)) begin
                buf_count <= buf_count - 1;
            end
            
            out_valid <= 0;
            if (!buf_empty && out_ready) begin
                `ifdef GRIDX_RB_DEBUG
                $display("[RB_POP] head %d, data=%h",
                         head, buf_data[head]);
                `endif
                out_valid <= 1;
                out_addr <= buf_addr[head];
                out_data <= buf_data[head];
                out_warp_id <= buf_warp[head];
                buf_valid[head] <= 0;
                head <= head + 1;
            end
            `ifdef GRIDX_RB_DEBUG
            $display("[RB_STATUS] buf_count=%d head=%d tail=%d out_valid=%b out_data=%h",
                     buf_count, head, tail, out_valid, out_data);
            `endif
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                if (warp_can_resume[w] && !warp_has_pending_load[w]) begin
                    warp_received[w] <= 0;
                    perf_early_wakeups <= perf_early_wakeups + 1;
                end
            end
        end
    end
endmodule
