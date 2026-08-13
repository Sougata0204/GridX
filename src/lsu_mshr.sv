
`default_nettype none
`timescale 1ns/1ns

module lsuMshr #(
    parameter NUM_ENTRIES = 4,
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8,
    parameter REG_WIDTH = 16,
    parameter TAG_WIDTH = $clog2(NUM_ENTRIES)
) (
    input  wire clk,
    input  wire reset,
    input  wire allocValid,
    input  wire [ADDR_WIDTH-1:0] allocAddr,
    input  wire [3:0] allocDestReg,
    input  wire [1:0] allocWarpId,
    output wire allocReady,
    output wire [TAG_WIDTH-1:0] allocTag,
    input  wire fillValid,
    input  wire [TAG_WIDTH-1:0] fillTag,
    input  wire [DATA_WIDTH-1:0] fillData,
    output wire fillAccepted,
    output reg  wbValid,
    output reg  [3:0] wbDestReg,
    output reg  [1:0] wbWarpId,
    output reg  [REG_WIDTH-1:0] wbData,
    input  wire wbAck,
    input  wire [3:0] checkReg,
    input  wire [1:0] checkWarp,
    output wire checkPending,
    output wire [$clog2(NUM_ENTRIES):0] entriesUsed,
    output wire mshrFull,
    output wire mshrEmpty
);
    reg [NUM_ENTRIES-1:0] entryValid;
    reg [NUM_ENTRIES-1:0] entryFilled;
    reg [ADDR_WIDTH-1:0]  entryAddr [NUM_ENTRIES-1:0];
    reg [3:0]             entryDest [NUM_ENTRIES-1:0];
    reg [1:0]             entryWarp [NUM_ENTRIES-1:0];
    reg [DATA_WIDTH-1:0]  entryData [NUM_ENTRIES-1:0];
    wire [NUM_ENTRIES-1:0] freeMask;
    assign freeMask = ~entryValid;

    function automatic int countBits;
        input [NUM_ENTRIES-1:0] vec;
        int cnt;
        begin
            cnt = 0;
            for (int i = 0; i < NUM_ENTRIES; i++) begin
                if (vec[i]) cnt = cnt + 1;
            end
            countBits = cnt;
        end
    endfunction
    assign entriesUsed = countBits(entryValid);
    assign mshrFull = (entriesUsed == NUM_ENTRIES);
    assign mshrEmpty = (entriesUsed == 0);
    assign allocReady = !mshrFull;
    reg [TAG_WIDTH-1:0] freeEntry;
    reg foundFree;
    always @(*) begin
        foundFree = 0;
        freeEntry = 0;
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            if (!entryValid[i] && !foundFree) begin
                freeEntry = i[TAG_WIDTH-1:0];
                foundFree = 1;
            end
        end
    end
    assign allocTag = freeEntry;
    assign fillAccepted = fillValid && entryValid[fillTag] && !entryFilled[fillTag];
    reg [TAG_WIDTH-1:0] wbEntry;
    reg foundWb;
    always @(*) begin
        foundWb = 0;
        wbEntry = 0;
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            if (entryValid[i] && entryFilled[i] && !foundWb) begin
                wbEntry = i[TAG_WIDTH-1:0];
                foundWb = 1;
            end
        end
    end
    reg checkHit;
    always @(*) begin
        checkHit = 0;
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            if (entryValid[i] &&
                entryDest[i] == checkReg &&
                entryWarp[i] == checkWarp) begin
                checkHit = 1;
            end
        end
    end
    assign checkPending = checkHit;
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            entryValid <= 0;
            entryFilled <= 0;
            wbValid <= 0;
            wbDestReg <= 0;
            wbWarpId <= 0;
            wbData <= 0;
            for (i = 0; i < NUM_ENTRIES; i++) begin
                entryAddr[i] <= 0;
                entryDest[i] <= 0;
                entryWarp[i] <= 0;
                entryData[i] <= 0;
            end
        end else begin
            if (wbAck) begin
                wbValid <= 0;
            end
            if (allocValid && allocReady) begin
                entryValid[freeEntry] <= 1;
                entryFilled[freeEntry] <= 0;
                entryAddr[freeEntry] <= allocAddr;
                entryDest[freeEntry] <= allocDestReg;
                entryWarp[freeEntry] <= allocWarpId;
            end
            if (fillAccepted) begin
                entryFilled[fillTag] <= 1;
                entryData[fillTag] <= fillData;
            end
            if (foundWb && !wbValid) begin
                wbValid <= 1;
                wbDestReg <= entryDest[wbEntry];
                wbWarpId <= entryWarp[wbEntry];
                wbData <= {{(REG_WIDTH-DATA_WIDTH){1'b0}}, entryData[wbEntry]};
                entryValid[wbEntry] <= 0;
                entryFilled[wbEntry] <= 0;
            end
        end
    end
endmodule
