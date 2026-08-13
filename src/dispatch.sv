// Thread Block Dispatcher & Recycling Unit
// This module dispatches thread blocks to available physical cores.
// I updated the block allocation logic to track coreDone signals and issue remaining blocks
// dynamically when cores finish, enabling workload scaling beyond physical core count.

`default_nettype none
`timescale 1ns/1ps

module dispatch #(
    parameter NUM_CORES = 8,
    parameter THREADS_PER_BLOCK = 4
) (
    input wire clk,
    input wire reset,
    input wire start,
    input wire kernelRunning,
    input wire [15:0] threadCount,
    input wire [NUM_CORES-1:0] coreDone,
    output reg [NUM_CORES-1:0] coreStart,
    output reg [NUM_CORES-1:0] coreReset,
    output reg [7:0] coreBlockId [NUM_CORES-1:0],
    output reg [$clog2(THREADS_PER_BLOCK):0] coreThreadCount [NUM_CORES-1:0],
    output wire [15:0] blocksDispatchedOut,
    output wire [15:0] blocksDoneOut,
    output wire [15:0] totalBlocksOut,
    output wire allBlocksDispatched,
    output wire allBlocksDone
);
    wire [15:0] totalBlocks;
    assign totalBlocks = (threadCount > 0) ?
                          (threadCount + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK :
                          16'd0;
    reg [15:0] blocksDispatched;
    reg [15:0] blocksDone;
    reg startExecution;
    reg [15:0] nextBlocksDispatched;
    reg [15:0] nextBlocksDone;
    integer i;
    assign blocksDispatchedOut = blocksDispatched;
    assign blocksDoneOut = blocksDone;
    assign totalBlocksOut = totalBlocks;
    assign allBlocksDispatched = (blocksDispatched >= totalBlocks) && (totalBlocks > 0);
    assign allBlocksDone = (blocksDone >= totalBlocks) && (totalBlocks > 0);
    always @(posedge clk) begin
        if (reset) begin
            blocksDispatched <= 0;
            blocksDone <= 0;
            startExecution <= 0;
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                coreStart[i] <= 0;
                coreReset[i] <= 1;
                coreBlockId[i] <= 0;
                coreThreadCount[i] <= THREADS_PER_BLOCK;
            end
        end else if (kernelRunning) begin
            nextBlocksDispatched = blocksDispatched;
            nextBlocksDone = blocksDone;
            if (!startExecution) begin
                startExecution <= 1;
            end
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                if (!startExecution || coreReset[i]) begin
                    if (nextBlocksDispatched < totalBlocks) begin
                        coreReset[i] <= 0;
                        coreStart[i] <= 1;
                        coreBlockId[i] <= nextBlocksDispatched[7:0];
                        coreThreadCount[i] <= (nextBlocksDispatched == totalBlocks - 1)
                            ? threadCount - (nextBlocksDispatched * THREADS_PER_BLOCK)
                            : THREADS_PER_BLOCK;
                        nextBlocksDispatched = nextBlocksDispatched + 1;
                    end
                end
            end
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                if (coreStart[i] && coreDone[i]) begin
                    coreReset[i] <= 1;
                    coreStart[i] <= 0;
                    nextBlocksDone = nextBlocksDone + 1;
                end
            end
            blocksDispatched <= nextBlocksDispatched;
            blocksDone <= nextBlocksDone;
        end else if (!kernelRunning) begin
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                if (coreStart[i] && coreDone[i]) begin
                    coreReset[i] <= 1;
                    coreStart[i] <= 0;
                    blocksDone <= blocksDone + 1;
                end
            end
        end
    end
endmodule
