
`default_nettype none
`timescale 1ns/1ns

module async_load_tracker #(
    parameter WARPS_PER_CORE = 1,
    parameter MAX_OUTSTANDING_PER_WARP = 2,
    parameter REG_ADDR_BITS = 4,
    parameter WARP_ID_W = (WARPS_PER_CORE > 1) ? $clog2(WARPS_PER_CORE) : 1
) (
    input wire clk,
    input wire reset,
    input wire enqueue_valid,
    input wire [WARP_ID_W-1:0] enqueue_warp_id,
    input wire [REG_ADDR_BITS-1:0] enqueue_dest_reg,
    input wire [15:0] enqueue_tag,
    input wire dequeue_valid,
    input wire [WARP_ID_W-1:0] dequeue_warp_id,
    input wire [15:0] dequeue_tag,
    output reg [REG_ADDR_BITS-1:0] dequeued_dest_reg,
    output reg dequeue_found,
    output wire [WARPS_PER_CORE-1:0] warp_has_pending,
    output wire [WARPS_PER_CORE-1:0] warp_queue_full,
    output wire [$clog2(MAX_OUTSTANDING_PER_WARP):0] pending_count [WARPS_PER_CORE-1:0]
);
    localparam ENTRY_WIDTH = 1 + 16 + REG_ADDR_BITS;
    reg [ENTRY_WIDTH-1:0] tracker_queue [WARPS_PER_CORE-1:0][MAX_OUTSTANDING_PER_WARP-1:0];
    reg [$clog2(MAX_OUTSTANDING_PER_WARP):0] queue_count [WARPS_PER_CORE-1:0];
    genvar w;
    generate
        for (w = 0; w < WARPS_PER_CORE; w = w + 1) begin : status_gen
            assign warp_has_pending[w] = (queue_count[w] > 0);
            assign warp_queue_full[w] = (queue_count[w] >= MAX_OUTSTANDING_PER_WARP);
            assign pending_count[w] = queue_count[w];
        end
    endgenerate
    integer i, j;
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < WARPS_PER_CORE; i = i + 1) begin
                queue_count[i] <= 0;
                for (j = 0; j < MAX_OUTSTANDING_PER_WARP; j = j + 1) begin
                    tracker_queue[i][j] <= {ENTRY_WIDTH{1'b0}};
                end
            end
        end else begin
            if (enqueue_valid && !warp_queue_full[enqueue_warp_id]) begin
                reg enqueued;
                enqueued = 0;
                for (i = 0; i < MAX_OUTSTANDING_PER_WARP; i = i + 1) begin
                    if (!enqueued && !tracker_queue[enqueue_warp_id][i][ENTRY_WIDTH-1]) begin
                        tracker_queue[enqueue_warp_id][i] <= {1'b1, enqueue_tag, enqueue_dest_reg};
                        queue_count[enqueue_warp_id] <= queue_count[enqueue_warp_id] + 1;
                        enqueued = 1;
                    end
                end
            end
            if (dequeue_valid) begin
                reg dequeued;
                dequeued = 0;
                for (i = 0; i < MAX_OUTSTANDING_PER_WARP; i = i + 1) begin
                    if (!dequeued && tracker_queue[dequeue_warp_id][i][ENTRY_WIDTH-1] &&
                        tracker_queue[dequeue_warp_id][i][REG_ADDR_BITS+15:REG_ADDR_BITS] == dequeue_tag) begin
                        tracker_queue[dequeue_warp_id][i][ENTRY_WIDTH-1] <= 1'b0;
                        if (queue_count[dequeue_warp_id] > 0)
                            queue_count[dequeue_warp_id] <= queue_count[dequeue_warp_id] - 1;
                        dequeued = 1;
                    end
                end
            end
        end
    end
    always @(*) begin
        dequeue_found = 0;
        dequeued_dest_reg = 0;
        if (dequeue_valid) begin
            automatic logic found = 0;
            for (integer k = 0; k < MAX_OUTSTANDING_PER_WARP; k = k + 1) begin
                if (!found && tracker_queue[dequeue_warp_id][k][ENTRY_WIDTH-1] &&
                    tracker_queue[dequeue_warp_id][k][REG_ADDR_BITS+15:REG_ADDR_BITS] == dequeue_tag) begin
                    dequeued_dest_reg = tracker_queue[dequeue_warp_id][k][REG_ADDR_BITS-1:0];
                    dequeue_found = 1;
                    found = 1;
                end
            end
        end
    end
endmodule
