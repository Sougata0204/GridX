
`default_nettype none
`timescale 1ns/1ps

// Response buffer queuing memory read completions and routing them back to the requesting core with tag-based matching.
module responseBuffer #(
    parameter BUFFER_DEPTH = 4,
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 16,
    parameter WARP_ID_WIDTH = 2,
    parameter NUM_WARPS = 1
) (
    input wire clk,
    input wire reset,
    input wire respValid,
    input wire [ADDR_WIDTH-1:0] respAddr,
    input wire [DATA_WIDTH-1:0] respData,
    input wire [WARP_ID_WIDTH-1:0] respWarpId,
    output wire respReady,
    input wire [NUM_WARPS-1:0] warpHasPendingLoad,
    input wire [3:0] warpPendingCount [NUM_WARPS-1:0],
    output wire outValid,
    output wire [ADDR_WIDTH-1:0] outAddr,
    output wire [DATA_WIDTH-1:0] outData,
    output wire [WARP_ID_WIDTH-1:0] outWarpId,
    input wire outReady,
    output reg [NUM_WARPS-1:0] warpCanResume,
    output reg [31:0] perfEarlyWakeups,
    output reg [31:0] perfTotalResponses,
    output reg [31:0] perfBufferFullStalls
);
    reg [ADDR_WIDTH-1:0] bufAddr [BUFFER_DEPTH-1:0];
    reg [DATA_WIDTH-1:0] bufData [BUFFER_DEPTH-1:0];
    reg [WARP_ID_WIDTH-1:0] bufWarp [BUFFER_DEPTH-1:0];
    reg [BUFFER_DEPTH-1:0] bufValid = 0;
    reg [$clog2(BUFFER_DEPTH):0] bufCount = 0;
    reg [$clog2(BUFFER_DEPTH)-1:0] head = 0, tail = 0;
    integer i;
    reg [3:0] warpReceived [NUM_WARPS-1:0];
    wire bufFull = (bufCount == BUFFER_DEPTH);
    wire bufEmpty = (bufCount == 0);
    assign respReady = !bufFull;

    assign outValid = !bufEmpty;
    assign outAddr  = bufAddr[head];
    assign outData  = bufData[head];
    assign outWarpId = bufWarp[head];

    always_comb begin
        warpCanResume = 0;
        for (int w = 0; w < NUM_WARPS; w = w + 1) begin
            if (warpHasPendingLoad[w] &&
                warpReceived[w] >= warpPendingCount[w] &&
                warpPendingCount[w] > 0) begin
                warpCanResume[w] = 1;
            end
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            bufValid <= 0;
            bufCount <= 0;
            head <= 0;
            tail <= 0;
            perfEarlyWakeups <= 0;
            perfTotalResponses <= 0;
            perfBufferFullStalls <= 0;
            for (i = 0; i < BUFFER_DEPTH; i = i + 1) begin
                bufAddr[i] <= 0;
                bufData[i] <= 0;
                bufWarp[i] <= 0;
            end
            for (int w = 0; w < NUM_WARPS; w = w + 1) begin
                warpReceived[w] <= 0;
            end
        end else begin
            if (respValid && respReady) begin
                `ifdef GRIDX_RB_DEBUG
                $display("[RB_WRITE] tail %d addr=%h data=%h warp=%d",
                         tail, respAddr, respData, respWarpId);
                `endif
                bufAddr[tail] <= respAddr;
                bufData[tail] <= respData;
                bufWarp[tail] <= respWarpId;
                bufValid[tail] <= 1;
                tail <= tail + 1;
                warpReceived[respWarpId] <= warpReceived[respWarpId] + 1;
                perfTotalResponses <= perfTotalResponses + 1;
            end
            if (respValid && !respReady) begin
                perfBufferFullStalls <= perfBufferFullStalls + 1;
            end
            if (respValid && respReady && !(!bufEmpty && outReady)) begin
                bufCount <= bufCount + 1;
            end else if (!(respValid && respReady) && (!bufEmpty && outReady)) begin
                bufCount <= bufCount - 1;
            end
            
            if (!bufEmpty && outReady) begin
                `ifdef GRIDX_RB_DEBUG
                $display("[RB_POP] head %d, data=%h",
                         head, bufData[head]);
                `endif
                bufValid[head] <= 0;
                head <= head + 1;
            end
            `ifdef GRIDX_RB_DEBUG
            $display("[RB_STATUS] bufCount=%d head=%d tail=%d outValid=%b outData=%h",
                     bufCount, head, tail, outValid, outData);
            if (respValid) begin
                $display("[RB_INPUT] Cycle %0d: respValid=1 respReady=%b respWarpId=%0d (binary: %b) warpReceived[respWarpId]=%0d",
                         $time, respReady, respWarpId, respWarpId, warpReceived[respWarpId]);
            end
            for (int w = 0; w < NUM_WARPS; w = w + 1) begin
                if (warpPendingCount[w] > 0) begin
                    $display("[RB_WAKEUP] Cycle %0d: Warp %0d pending=%0d received=%0d hasPendingLoad=%b canResume=%b",
                             $time, w, warpPendingCount[w], warpReceived[w], warpHasPendingLoad[w], warpCanResume[w]);
                end
            end
            `endif
            for (int w = 0; w < NUM_WARPS; w = w + 1) begin
                if (warpCanResume[w] && !warpHasPendingLoad[w]) begin
                    warpReceived[w] <= 0;
                    perfEarlyWakeups <= perfEarlyWakeups + 1;
                end
            end
        end
    end
endmodule
