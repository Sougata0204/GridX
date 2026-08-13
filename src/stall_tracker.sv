
`default_nettype none
`timescale 1ns/1ns

module stallTracker #(
    parameter NUM_WARPS = 1,
    parameter WARP_ID_WIDTH = 2,
    parameter AGE_WIDTH = 16
) (
    input wire clk,
    input wire reset,
    input wire [NUM_WARPS-1:0] warpActive,
    input wire [NUM_WARPS-1:0] warpWaitingMem,
    input wire [NUM_WARPS-1:0] warpWaitingShared,
    input wire [NUM_WARPS-1:0] warpWaitingTensor,
    input wire [NUM_WARPS-1:0] warpWaitingDep,
    input wire issueValid,
    input wire [WARP_ID_WIDTH-1:0] issuedWarpId,
    output reg [2:0] stallReason [NUM_WARPS-1:0],
    output reg [AGE_WIDTH-1:0] warpAge [NUM_WARPS-1:0],
    output wire [WARP_ID_WIDTH-1:0] oldestReadyWarp,
    output wire oldestReadyValid,
    output reg [31:0] perfStallCyclesMem,
    output reg [31:0] perfStallCyclesShared,
    output reg [31:0] perfStallCyclesTensor,
    output reg [31:0] perfStallCyclesDep
);
    localparam READY        = 3'd0;
    localparam WAIT_MEM     = 3'd1;
    localparam WAIT_SHARED  = 3'd2;
    localparam WAIT_TENSOR  = 3'd3;
    localparam WAIT_DEP     = 3'd4;
    integer w;
    always @(posedge clk) begin
        if (reset) begin
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                stallReason[w] <= READY;
                warpAge[w] <= 0;
            end
            perfStallCyclesMem <= 0;
            perfStallCyclesShared <= 0;
            perfStallCyclesTensor <= 0;
            perfStallCyclesDep <= 0;
        end else begin
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                if (!warpActive[w]) begin
                    stallReason[w] <= READY;
                end else if (warpWaitingMem[w]) begin
                    stallReason[w] <= WAIT_MEM;
                    perfStallCyclesMem <= perfStallCyclesMem + 1;
                end else if (warpWaitingShared[w]) begin
                    stallReason[w] <= WAIT_SHARED;
                    perfStallCyclesShared <= perfStallCyclesShared + 1;
                end else if (warpWaitingTensor[w]) begin
                    stallReason[w] <= WAIT_TENSOR;
                    perfStallCyclesTensor <= perfStallCyclesTensor + 1;
                end else if (warpWaitingDep[w]) begin
                    stallReason[w] <= WAIT_DEP;
                    perfStallCyclesDep <= perfStallCyclesDep + 1;
                end else begin
                    stallReason[w] <= READY;
                end
                if (issueValid && issuedWarpId == w[WARP_ID_WIDTH-1:0]) begin
                    warpAge[w] <= 0;
                end else if (stallReason[w] == READY && warpActive[w]) begin
                    warpAge[w] <= warpAge[w] + 1;
                end
            end
        end
    end
    reg [WARP_ID_WIDTH-1:0] oldestId;
    reg [AGE_WIDTH-1:0] oldestAge;
    reg foundReady;
    always @(*) begin
        oldestId = 0;
        oldestAge = 0;
        foundReady = 0;
        for (w = 0; w < NUM_WARPS; w = w + 1) begin
            if (warpActive[w] && stallReason[w] == READY) begin
                if (!foundReady || warpAge[w] > oldestAge) begin
                    oldestId = w[WARP_ID_WIDTH-1:0];
                    oldestAge = warpAge[w];
                    foundReady = 1;
                end
            end
        end
    end
    assign oldestReadyWarp = oldestId;
    assign oldestReadyValid = foundReady;
endmodule
