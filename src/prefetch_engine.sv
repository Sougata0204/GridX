
`default_nettype none
`timescale 1ns/1ps

// Hardware prefetch engine detecting stride and stream access patterns to issue speculative memory requests ahead of demand.
module prefetchEngine #(
    parameter ADDR_WIDTH    = 22,
    parameter DATA_WIDTH    = 8,
    parameter NUM_ENTRIES   = 8,
    parameter PREFETCH_DIST = 4
) (
    input  wire                    clk,
    input  wire                    reset,

    input  wire                    lsuLoadValid,
    input  wire [ADDR_WIDTH-1:0]   lsuLoadAddr,

    output reg                     pfReqValid,
    output reg  [ADDR_WIDTH-1:0]   pfReqAddr,
    input  wire                    pfReqReady,

    output wire [3:0]              activeStreams,
    output reg  [15:0]             pfIssuedCount,
    output reg  [15:0]             pfHitCount
);

    localparam ENTRY_IDX_W = $clog2(NUM_ENTRIES);

    reg                     entryValid   [NUM_ENTRIES-1:0];
    reg [ADDR_WIDTH-1:0]    entryLast    [NUM_ENTRIES-1:0];
    reg signed [ADDR_WIDTH-1:0] entryStride [NUM_ENTRIES-1:0];
    reg [3:0]               entryConf    [NUM_ENTRIES-1:0];
    reg [ADDR_WIDTH-1:0]    entryPfAddr  [NUM_ENTRIES-1:0];

    reg [3:0] activeCnt;
    assign activeStreams = activeCnt;

    wire [NUM_ENTRIES-1:0]               matchVec;
    wire signed [ADDR_WIDTH-1:0]         calcStride [NUM_ENTRIES-1:0];

    genvar gi;
    generate
        for (gi = 0; gi < NUM_ENTRIES; gi = gi + 1) begin : gen_match
            wire [ADDR_WIDTH-1:0] addrDiff = (lsuLoadAddr >= entryLast[gi]) ?
                                             (lsuLoadAddr - entryLast[gi]) :
                                             (entryLast[gi] - lsuLoadAddr);
            assign matchVec[gi] = entryValid[gi] && (addrDiff < 22'd256);
            assign calcStride[gi] = (lsuLoadAddr >= entryLast[gi]) ?
                                    $signed({1'b0, addrDiff}) :
                                    -$signed({1'b0, addrDiff});
        end
    endgenerate

    reg                   matchFound;
    reg [ENTRY_IDX_W-1:0] matchIdx;
    reg signed [ADDR_WIDTH-1:0] observedStride;

    always_comb begin
        matchFound     = 1'b0;
        matchIdx       = '0;
        observedStride = '0;
        for (int i = 0; i < NUM_ENTRIES; i = i + 1) begin
            if (matchVec[i] && !matchFound) begin
                matchFound     = 1'b1;
                matchIdx       = i[ENTRY_IDX_W-1:0];
                observedStride = calcStride[i];
            end
        end
    end

    reg [ENTRY_IDX_W-1:0] freeIdx;
    reg                   hasInvalid;

    always_comb begin
        freeIdx    = '0;
        hasInvalid = 1'b0;
        for (int i = 0; i < NUM_ENTRIES; i = i + 1) begin
            if (!entryValid[i] && !hasInvalid) begin
                freeIdx    = i[ENTRY_IDX_W-1:0];
                hasInvalid = 1'b1;
            end
        end
        if (!hasInvalid) begin
            for (int i = 0; i < NUM_ENTRIES; i = i + 1) begin
                if (entryConf[i] < entryConf[freeIdx])
                    freeIdx = i[ENTRY_IDX_W-1:0];
            end
        end
    end

    reg [ENTRY_IDX_W-1:0] pfRr;
    reg                   pfPending;
    reg [ADDR_WIDTH-1:0]  pfPendingAddr;

    integer k;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pfReqValid     <= 1'b0;
            pfReqAddr      <= '0;
            pfIssuedCount  <= 16'd0;
            pfHitCount     <= 16'd0;
            pfPending      <= 1'b0;
            pfPendingAddr  <= '0;
            pfRr           <= '0;
            activeCnt      <= 4'd0;
            for (k = 0; k < NUM_ENTRIES; k = k + 1) begin
                entryValid[k]   <= 1'b0;
                entryLast[k]    <= '0;
                entryStride[k]  <= '0;
                entryConf[k]    <= 4'd0;
                entryPfAddr[k]  <= '0;
            end
        end else begin
            pfReqValid <= 1'b0;

            if (lsuLoadValid) begin
                if (matchFound) begin
                    if (observedStride == entryStride[matchIdx] && observedStride != 0) begin
                        if (entryConf[matchIdx] < 4'd15)
                            entryConf[matchIdx] <= entryConf[matchIdx] + 4'd1;
                        entryLast[matchIdx]   <= lsuLoadAddr;
                        entryPfAddr[matchIdx] <= lsuLoadAddr + (observedStride * PREFETCH_DIST);

                        if (entryConf[matchIdx] >= 4'd2) begin
                            pfPending     <= 1'b1;
                            pfPendingAddr <= lsuLoadAddr + (observedStride * PREFETCH_DIST);
                            pfHitCount    <= pfHitCount + 16'd1;
                        end
                    end else begin
                        entryStride[matchIdx] <= observedStride;
                        entryLast[matchIdx]   <= lsuLoadAddr;
                        entryConf[matchIdx]   <= 4'd1;
                    end
                end else begin
                    entryValid[freeIdx]   <= 1'b1;
                    entryLast[freeIdx]    <= lsuLoadAddr;
                    entryStride[freeIdx]  <= '0;
                    entryConf[freeIdx]    <= 4'd1;
                    entryPfAddr[freeIdx]  <= lsuLoadAddr;
                end
            end

            if (pfPending && pfReqReady) begin
                pfReqValid     <= 1'b1;
                pfReqAddr      <= pfPendingAddr;
                pfPending      <= 1'b0;
                pfIssuedCount  <= pfIssuedCount + 16'd1;
            end

            begin
                automatic int count = 0;
                for (int c = 0; c < NUM_ENTRIES; c = c + 1) begin
                    if (entryValid[c] && entryConf[c] >= 4'd2)
                        count = count + 1;
                end
                activeCnt <= count[3:0];
            end
        end
    end

endmodule
