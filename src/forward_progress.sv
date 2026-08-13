
`default_nettype none
`timescale 1ns/1ns

module forwardProgress #(
    parameter NUM_WARPS = 1,
    parameter WARP_ID_WIDTH = 1,
    parameter WATCHDOG_CYCLES = 10000,
    parameter COUNTER_WIDTH = 16
) (
    input wire clk,
    input wire reset,
    input wire [NUM_WARPS-1:0] warpActive,
    input wire [NUM_WARPS-1:0] warpMadeProgress,
    input wire memReqIssued,
    input wire [15:0] memReqId,
    input wire memReqCompleted,
    input wire [15:0] memCompletedId,
    output reg timeoutDetected,
    output reg [WARP_ID_WIDTH-1:0] timeoutWarpId,
    output reg [15:0] pendingMemRequests,
    output reg dumpTrigger,
    output reg [NUM_WARPS-1:0] stalledWarps,
    output reg [COUNTER_WIDTH-1:0] warpStallCycles [NUM_WARPS-1:0],
    output wire assertWarpTimeout,
    output wire assertMemLeak
);
    reg [COUNTER_WIDTH-1:0] warpWatchdog [NUM_WARPS-1:0];
    integer w;
    always @(posedge clk) begin
        if (reset) begin
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                warpWatchdog[w] <= 0;
                warpStallCycles[w] <= 0;
            end
            timeoutDetected <= 0;
            timeoutWarpId <= 0;
            stalledWarps <= 0;
            dumpTrigger <= 0;
        end else begin
            timeoutDetected <= 0;
            dumpTrigger <= 0;
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                if (warpActive[w]) begin
                    if (warpMadeProgress[w]) begin
                        warpWatchdog[w] <= 0;
                        stalledWarps[w] <= 0;
                    end else begin
                        warpWatchdog[w] <= warpWatchdog[w] + 1;
                        warpStallCycles[w] <= warpStallCycles[w] + 1;
                        if (warpWatchdog[w] >= WATCHDOG_CYCLES) begin
                            timeoutDetected <= 1;
                            timeoutWarpId <= w[WARP_ID_WIDTH-1:0];
                            stalledWarps[w] <= 1;
                            dumpTrigger <= 1;
                            `ifdef SIMULATION
                                $display("[forwardProgress] TIMEOUT: Warp %0d stalled for %0d cycles",
                                         w, WATCHDOG_CYCLES);
                            `endif
                        end
                    end
                end else begin
                    warpWatchdog[w] <= 0;
                    stalledWarps[w] <= 0;
                end
            end
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            pendingMemRequests <= 0;
        end else begin
            if (memReqIssued && !memReqCompleted) begin
                pendingMemRequests <= pendingMemRequests + 1;
            end else if (!memReqIssued && memReqCompleted) begin
                pendingMemRequests <= pendingMemRequests - 1;
            end
        end
    end
    assign assertWarpTimeout = timeoutDetected;
    assign assertMemLeak = (pendingMemRequests > 1000);
endmodule
