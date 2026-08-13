
`default_nettype none
`timescale 1ns/1ns

module warpMemUnit #(
    parameter THREADS_PER_WARP = 4,
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8,
    parameter MAX_TRANSACTIONS = 2
) (
    input wire clk,
    input wire reset,
    input wire start,
    input wire isRead,
    output reg busy,
    output reg done,
    input wire [ADDR_WIDTH-1:0] threadAddr [THREADS_PER_WARP-1:0],
    input wire [THREADS_PER_WARP-1:0] threadValid,
    input wire [DATA_WIDTH-1:0] threadWriteData [THREADS_PER_WARP-1:0],
    output reg [MAX_TRANSACTIONS-1:0] txnValid,
    output reg [ADDR_WIDTH-1:0] txnBaseAddr [MAX_TRANSACTIONS-1:0],
    output reg [THREADS_PER_WARP-1:0] txnThreadMask [MAX_TRANSACTIONS-1:0],
    output reg [DATA_WIDTH*THREADS_PER_WARP-1:0] txnWriteData [MAX_TRANSACTIONS-1:0],
    output reg txnIsRead,
    input wire [MAX_TRANSACTIONS-1:0] txnReady,
    input wire [DATA_WIDTH*THREADS_PER_WARP-1:0] txnReadData [MAX_TRANSACTIONS-1:0],
    output reg [DATA_WIDTH-1:0] threadReadData [THREADS_PER_WARP-1:0],
    output reg [THREADS_PER_WARP-1:0] threadReadValid,
    output reg [7:0] coalescedCount,
    output reg [7:0] transactionCount
);
    localparam IDLE = 3'b000,
               ANALYZE = 3'b001,
               EMIT_TXN = 3'b010,
               WAIT_RESP = 3'b011,
               DISTRIBUTE = 3'b100,
               COMPLETE = 3'b101;
    reg [2:0] state;
    reg [1:0] currentTxn;
    localparam SEGMENT_BITS = 6;
    reg [ADDR_WIDTH-SEGMENT_BITS-1:0] segmentBase [MAX_TRANSACTIONS-1:0];
    reg [THREADS_PER_WARP-1:0] segmentMask [MAX_TRANSACTIONS-1:0];
    reg [1:0] numSegments;
    reg [THREADS_PER_WARP-1:0] remainingThreads;
    reg [ADDR_WIDTH-SEGMENT_BITS-1:0] firstSegment;
    integer t, s;
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            currentTxn <= 0;
            numSegments <= 0;
            coalescedCount <= 0;
            transactionCount <= 0;
            for (t = 0; t < MAX_TRANSACTIONS; t = t + 1) begin
                txnValid[t] <= 1'b0;
                txnBaseAddr[t] <= 0;
                txnThreadMask[t] <= 0;
                segmentBase[t] <= 0;
                segmentMask[t] <= 0;
            end
            for (t = 0; t < THREADS_PER_WARP; t = t + 1) begin
                threadReadData[t] <= 0;
            end
            threadReadValid <= 0;
            remainingThreads <= 0;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    if (start && (|threadValid)) begin
                        busy <= 1'b1;
                        state <= ANALYZE;
                        remainingThreads <= threadValid;
                        numSegments <= 0;
                        coalescedCount <= 0;
                        transactionCount <= 0;
                        txnIsRead <= isRead;
                        for (t = 0; t < MAX_TRANSACTIONS; t = t + 1) begin
                            txnValid[t] <= 1'b0;
                            segmentMask[t] <= 0;
                        end
                    end
                end
                ANALYZE: begin
                    firstSegment = 0;
                    for (t = 0; t < THREADS_PER_WARP; t = t + 1) begin
                        if (remainingThreads[t]) begin
                            firstSegment = threadAddr[t][ADDR_WIDTH-1:SEGMENT_BITS];
                            break;
                        end
                    end
                    if (numSegments < MAX_TRANSACTIONS) begin
                        segmentBase[numSegments] <= firstSegment;
                        for (t = 0; t < THREADS_PER_WARP; t = t + 1) begin
                            if (remainingThreads[t]) begin
                                if (threadAddr[t][ADDR_WIDTH-1:SEGMENT_BITS] == firstSegment) begin
                                    segmentMask[numSegments][t] <= 1'b1;
                                    remainingThreads[t] <= 1'b0;
                                    coalescedCount <= coalescedCount + 1;
                                end
                            end
                        end
                        numSegments <= numSegments + 1;
                    end
                    if ((remainingThreads == 0) || (numSegments >= MAX_TRANSACTIONS - 1)) begin
                        state <= EMIT_TXN;
                        currentTxn <= 0;
                    end
                end
                EMIT_TXN: begin
                    for (s = 0; s < MAX_TRANSACTIONS; s = s + 1) begin
                        if (s < numSegments) begin
                            txnValid[s] <= 1'b1;
                            txnBaseAddr[s] <= {segmentBase[s], {SEGMENT_BITS{1'b0}}};
                            txnThreadMask[s] <= segmentMask[s];
                            transactionCount <= transactionCount + 1;
                            if (!isRead) begin
                                for (t = 0; t < THREADS_PER_WARP; t = t + 1) begin
                                    if (segmentMask[s][t]) begin
                                        txnWriteData[s][t*DATA_WIDTH +: DATA_WIDTH] <= threadWriteData[t];
                                    end
                                end
                            end
                        end else begin
                            txnValid[s] <= 1'b0;
                        end
                    end
                    state <= WAIT_RESP;
                end
                WAIT_RESP: begin
                    if ((txnValid & txnReady) == txnValid) begin
                        if (isRead) begin
                            state <= DISTRIBUTE;
                        end else begin
                            state <= COMPLETE;
                        end
                    end
                end
                DISTRIBUTE: begin
                    for (s = 0; s < MAX_TRANSACTIONS; s = s + 1) begin
                        if (txnValid[s]) begin
                            for (t = 0; t < THREADS_PER_WARP; t = t + 1) begin
                                if (txnThreadMask[s][t]) begin
                                    threadReadData[t] <= txnReadData[s][t*DATA_WIDTH +: DATA_WIDTH];
                                    threadReadValid[t] <= 1'b1;
                                end
                            end
                        end
                    end
                    state <= COMPLETE;
                end
                COMPLETE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= IDLE;
                    for (t = 0; t < MAX_TRANSACTIONS; t = t + 1) begin
                        txnValid[t] <= 1'b0;
                    end
                    threadReadValid <= 0;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
