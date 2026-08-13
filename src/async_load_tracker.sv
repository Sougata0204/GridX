
`default_nettype none
`timescale 1ns/1ns

module asyncLoadTracker #(
    parameter WARPS_PER_CORE = 1,
    parameter MAX_OUTSTANDING_PER_WARP = 2,
    parameter REG_ADDR_BITS = 4,
    parameter WARP_ID_W = (WARPS_PER_CORE > 1) ? $clog2(WARPS_PER_CORE) : 1
) (
    input wire clk,
    input wire reset,
    input wire enqueueValid,
    input wire [WARP_ID_W-1:0] enqueueWarpId,
    input wire [REG_ADDR_BITS-1:0] enqueueDestReg,
    input wire [15:0] enqueueTag,
    input wire dequeueValid,
    input wire [WARP_ID_W-1:0] dequeueWarpId,
    input wire [15:0] dequeueTag,
    output reg [REG_ADDR_BITS-1:0] dequeuedDestReg,
    output reg dequeueFound,
    output wire [WARPS_PER_CORE-1:0] warpHasPending,
    output wire [WARPS_PER_CORE-1:0] warpQueueFull,
    output wire [$clog2(MAX_OUTSTANDING_PER_WARP):0] pendingCount [WARPS_PER_CORE-1:0]
);
    localparam ENTRY_WIDTH = 1 + 16 + REG_ADDR_BITS;
    reg [ENTRY_WIDTH-1:0] trackerQueue [WARPS_PER_CORE-1:0][MAX_OUTSTANDING_PER_WARP-1:0];
    reg [$clog2(MAX_OUTSTANDING_PER_WARP):0] queueCount [WARPS_PER_CORE-1:0];
    genvar w;
    generate
        for (w = 0; w < WARPS_PER_CORE; w = w + 1) begin : statusGen
            assign warpHasPending[w] = (queueCount[w] > 0);
            assign warpQueueFull[w] = (queueCount[w] >= MAX_OUTSTANDING_PER_WARP);
            assign pendingCount[w] = queueCount[w];
        end
    endgenerate
    integer i, j;
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < WARPS_PER_CORE; i = i + 1) begin
                queueCount[i] <= 0;
                for (j = 0; j < MAX_OUTSTANDING_PER_WARP; j = j + 1) begin
                    trackerQueue[i][j] <= {ENTRY_WIDTH{1'b0}};
                end
            end
        end else begin
            if (enqueueValid && !warpQueueFull[enqueueWarpId]) begin
                reg enqueued;
                enqueued = 0;
                for (i = 0; i < MAX_OUTSTANDING_PER_WARP; i = i + 1) begin
                    if (!enqueued && !trackerQueue[enqueueWarpId][i][ENTRY_WIDTH-1]) begin
                        trackerQueue[enqueueWarpId][i] <= {1'b1, enqueueTag, enqueueDestReg};
                        queueCount[enqueueWarpId] <= queueCount[enqueueWarpId] + 1;
                        enqueued = 1;
                    end
                end
            end
            if (dequeueValid) begin
                reg dequeued;
                dequeued = 0;
                for (i = 0; i < MAX_OUTSTANDING_PER_WARP; i = i + 1) begin
                    if (!dequeued && trackerQueue[dequeueWarpId][i][ENTRY_WIDTH-1] &&
                        trackerQueue[dequeueWarpId][i][REG_ADDR_BITS+15:REG_ADDR_BITS] == dequeueTag) begin
                        trackerQueue[dequeueWarpId][i][ENTRY_WIDTH-1] <= 1'b0;
                        if (queueCount[dequeueWarpId] > 0)
                            queueCount[dequeueWarpId] <= queueCount[dequeueWarpId] - 1;
                        dequeued = 1;
                    end
                end
            end
        end
    end
    always @(*) begin
        dequeueFound = 0;
        dequeuedDestReg = 0;
        if (dequeueValid) begin
            automatic logic found = 0;
            for (integer k = 0; k < MAX_OUTSTANDING_PER_WARP; k = k + 1) begin
                if (!found && trackerQueue[dequeueWarpId][k][ENTRY_WIDTH-1] &&
                    trackerQueue[dequeueWarpId][k][REG_ADDR_BITS+15:REG_ADDR_BITS] == dequeueTag) begin
                    dequeuedDestReg = trackerQueue[dequeueWarpId][k][REG_ADDR_BITS-1:0];
                    dequeueFound = 1;
                    found = 1;
                end
            end
        end
    end
endmodule
