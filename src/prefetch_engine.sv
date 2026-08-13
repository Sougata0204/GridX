
`default_nettype none
`timescale 1ns/1ns

module prefetchEngine #(
    parameter ADDR_WIDTH   = 22,
    parameter DATA_WIDTH   = 8,
    parameter NUM_ENTRIES  = 8,
    parameter PREFETCH_DIST = 4
) (
    input  wire clk,
    input  wire reset,

    input  wire                    lsuLoadValid,
    input  wire [ADDR_WIDTH-1:0]   lsuLoadAddr,

    output reg                     pfReqValid,
    output reg  [ADDR_WIDTH-1:0]   pfReqAddr,
    input  wire                    pfReqReady,

    output wire [3:0]              activeStreams,
    output reg  [15:0]             pfIssuedCount,
    output reg  [15:0]             pfHitCount
);

    reg                    entryValid   [NUM_ENTRIES-1:0];
    reg [ADDR_WIDTH-1:0]   entryLast    [NUM_ENTRIES-1:0];
    reg signed [ADDR_WIDTH-1:0] entryStride [NUM_ENTRIES-1:0];
    reg [3:0]              entryConf    [NUM_ENTRIES-1:0];
    reg [ADDR_WIDTH-1:0]   entryPfAddr [NUM_ENTRIES-1:0];

    reg [3:0] activeCnt;
    assign activeStreams = activeCnt;

    integer i;
    reg [3:0] tempActive;

    reg [$clog2(NUM_ENTRIES)-1:0] matchIdx;
    reg                           matchFound;
    reg signed [ADDR_WIDTH-1:0]   observedStride;

    always @(*) begin
        matchFound = 0;
        matchIdx = 0;
        observedStride = 0;
        for (i = NUM_ENTRIES-1; i >= 0; i = i - 1) begin
            if (entryValid[i]) begin

                if (lsuLoadAddr >= entryLast[i]) begin
                    if ((lsuLoadAddr - entryLast[i]) < 256) begin
                        matchFound = 1;
                        matchIdx = i;
                        observedStride = lsuLoadAddr - entryLast[i];
                    end
                end else begin
                    if ((entryLast[i] - lsuLoadAddr) < 256) begin
                        matchFound = 1;
                        matchIdx = i;
                        observedStride = -$signed(entryLast[i] - lsuLoadAddr);
                    end
                end
            end
        end
    end

    reg [$clog2(NUM_ENTRIES)-1:0] freeIdx;
    always @(*) begin
        freeIdx = 0;
        for (i = NUM_ENTRIES-1; i >= 0; i = i - 1) begin
            if (!entryValid[i]) freeIdx = i;
            else if (entryConf[i] < entryConf[freeIdx]) freeIdx = i;
        end
    end

    reg [$clog2(NUM_ENTRIES)-1:0] pfRr;
    reg pfPending;
    reg [ADDR_WIDTH-1:0] pfPendingAddr;

    always @(posedge clk) begin
        if (reset) begin
            pfReqValid <= 0;
            pfIssuedCount <= 0;
            pfHitCount <= 0;
            pfPending <= 0;
            pfRr <= 0;
            activeCnt <= 0;
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                entryValid[i]   <= 0;
                entryLast[i]    <= 0;
                entryStride[i]  <= 0;
                entryConf[i]    <= 0;
                entryPfAddr[i] <= 0;
            end
        end else begin
            pfReqValid <= 0;

            if (lsuLoadValid) begin
                if (matchFound) begin

                    entryLast[matchIdx] <= lsuLoadAddr;
                    if (observedStride == entryStride[matchIdx]) begin

                        if (entryConf[matchIdx] < 15)
                            entryConf[matchIdx] <= entryConf[matchIdx] + 1;

                        entryPfAddr[matchIdx] <= lsuLoadAddr +
                            (entryStride[matchIdx] * PREFETCH_DIST);
                    end else begin

                        entryStride[matchIdx] <= observedStride;
                        entryConf[matchIdx] <= 1;
                    end

                    if (lsuLoadAddr == entryPfAddr[matchIdx])
                        pfHitCount <= pfHitCount + 1;
                end else begin

                    entryValid[freeIdx]   <= 1;
                    entryLast[freeIdx]    <= lsuLoadAddr;
                    entryStride[freeIdx]  <= 0;
                    entryConf[freeIdx]    <= 0;
                    entryPfAddr[freeIdx] <= 0;
                end
            end

            if (!pfPending) begin
                for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                    if (entryValid[(pfRr + i) % NUM_ENTRIES] &&
                        entryConf[(pfRr + i) % NUM_ENTRIES] >= 4 &&
                        entryPfAddr[(pfRr + i) % NUM_ENTRIES] != 0 &&
                        !pfPending) begin
                        pfPending <= 1;
                        pfPendingAddr <= entryPfAddr[(pfRr + i) % NUM_ENTRIES];
                        pfRr <= ((pfRr + i + 1) % NUM_ENTRIES);
                    end
                end
            end

            if (pfPending) begin
                pfReqValid <= 1;
                pfReqAddr  <= pfPendingAddr;
                if (pfReqReady) begin
                    pfPending <= 0;
                    pfIssuedCount <= pfIssuedCount + 1;
                end
            end

            tempActive = 0;
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                if (entryValid[i] && entryConf[i] >= 4)
                    tempActive = tempActive + 1;
            end
            activeCnt <= tempActive;
        end
    end

endmodule
