
`default_nettype none
`timescale 1ns/1ps

// Thread block dispatch unit assigning work-groups to available cores based on occupancy and resource availability.
module dispatch #(
    parameter NUM_CORES         = 8,
    parameter THREADS_PER_BLOCK = 4
) (
    input  wire                                clk,
    input  wire                                reset,
    input  wire                                start,
    input  wire                                kernelRunning,
    input  wire [15:0]                         threadCount,
    input  wire [NUM_CORES-1:0]                coreDone,
    output reg  [NUM_CORES-1:0]                coreStart,
    output reg  [NUM_CORES-1:0]                coreReset,
    output reg  [7:0]                          coreBlockId [NUM_CORES-1:0],
    output reg  [$clog2(THREADS_PER_BLOCK):0]  coreThreadCount [NUM_CORES-1:0],
    output wire [15:0]                         blocksDispatchedOut,
    output wire [15:0]                         blocksDoneOut,
    output wire [15:0]                         totalBlocksOut,
    output wire                                allBlocksDispatched,
    output wire                                allBlocksDone
);

    localparam TPB_LOG2 = $clog2(THREADS_PER_BLOCK);
    localparam IS_POW2  = ((1 << TPB_LOG2) == THREADS_PER_BLOCK);

    wire [15:0] totalBlocks;
    generate
        if (IS_POW2) begin : gen_pow2_div
            assign totalBlocks = (threadCount > 0) ?
                                 ((threadCount + (THREADS_PER_BLOCK - 1)) >> TPB_LOG2) : 16'd0;
        end else begin : gen_generic_div
            assign totalBlocks = (threadCount > 0) ?
                                 ((threadCount + (THREADS_PER_BLOCK - 1)) / THREADS_PER_BLOCK) : 16'd0;
        end
    endgenerate

    reg [15:0] blocksDispatched;
    reg [15:0] blocksDone;
    reg startExecution;
    reg [15:0] nextBlocksDispatched;
    reg [15:0] nextBlocksDone;
    integer i;

    assign blocksDispatchedOut = blocksDispatched;
    assign blocksDoneOut       = blocksDone;
    assign totalBlocksOut      = totalBlocks;
    assign allBlocksDispatched = (blocksDispatched >= totalBlocks) && (totalBlocks > 0);
    assign allBlocksDone       = (blocksDone >= totalBlocks) && (totalBlocks > 0);

    function automatic [15:0] calc_threads_for_block(input [15:0] blkIdx, input [15:0] totalT, input [15:0] totB);
        reg [15:0] priorThreads;
        begin
            if (blkIdx == totB - 1) begin
                if (IS_POW2)
                    priorThreads = blkIdx << TPB_LOG2;
                else
                    priorThreads = blkIdx * THREADS_PER_BLOCK;
                calc_threads_for_block = totalT - priorThreads;
            end else begin
                calc_threads_for_block = THREADS_PER_BLOCK;
            end
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            blocksDispatched <= 0;
            blocksDone       <= 0;
            startExecution   <= 0;
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                coreStart[i]       <= 0;
                coreReset[i]       <= 1;
                coreBlockId[i]     <= 0;
                coreThreadCount[i] <= THREADS_PER_BLOCK;
            end
        end else if (kernelRunning) begin
            nextBlocksDispatched = blocksDispatched;
            nextBlocksDone       = blocksDone;

            if (!startExecution) begin
                startExecution <= 1;
                $display("[DISPATCH] Starting kernel execution. threadCount = %0d, totalBlocks = %0d", threadCount, totalBlocks);
            end

            for (i = 0; i < NUM_CORES; i = i + 1) begin
                if (!startExecution || coreReset[i]) begin
                    if (nextBlocksDispatched < totalBlocks) begin
                        coreReset[i]       <= 0;
                        coreStart[i]       <= 1;
                        coreBlockId[i]     <= nextBlocksDispatched[7:0];
                        coreThreadCount[i] <= calc_threads_for_block(nextBlocksDispatched, threadCount, totalBlocks);
                        nextBlocksDispatched = nextBlocksDispatched + 1;
                    end
                end
            end

            for (i = 0; i < NUM_CORES; i = i + 1) begin
                if (coreStart[i] && coreDone[i]) begin
                    coreReset[i]   <= 1;
                    coreStart[i]   <= 0;
                    nextBlocksDone = nextBlocksDone + 1;
                end
            end

            blocksDispatched <= nextBlocksDispatched;
            blocksDone       <= nextBlocksDone;
        end else if (!kernelRunning) begin
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                if (coreStart[i] && coreDone[i]) begin
                    coreReset[i] <= 1;
                    coreStart[i] <= 0;
                    blocksDone   <= blocksDone + 1;
                end
            end
        end
    end

endmodule
