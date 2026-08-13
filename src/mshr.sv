`default_nettype none
`timescale 1ns/1ns

// my mshr tracks outstanding memory requests
module mshr #(
    parameter Entries = 32,
    parameter AddrWidth = 22,
    parameter WarpIdWidth = 3,
    parameter RegIdWidth = 4
) (
    input  wire clk,
    input  wire reset,

    input  wire                      allocValid,
    input  wire [AddrWidth-1:0]      allocAddr,
    input  wire [WarpIdWidth-1:0]    allocWarpId,
    input  wire [RegIdWidth-1:0]     allocDestReg,
    output wire                      allocReady,

    input  wire                      respValid,
    input  wire [AddrWidth-1:0]      respAddr,

    output reg                       wakeupValid,
    output reg  [WarpIdWidth-1:0]    wakeupWarpId,
    output reg  [RegIdWidth-1:0]     wakeupDestReg,
    output wire                      mshrFull
);

    reg [Entries-1:0]       validFlags;
    reg [AddrWidth-1:0]     addrArray      [Entries-1:0];
    reg [WarpIdWidth-1:0]   warpIdArray   [Entries-1:0];
    reg [RegIdWidth-1:0]    destRegArray  [Entries-1:0];

    wire [Entries-1:0] freeSlots = ~validFlags;
    assign mshrFull = (freeSlots == 0);
    assign allocReady = !mshrFull;

    reg [$clog2(Entries)-1:0] freeIdx;
    always @(*) begin
        freeIdx = 0;
        for (integer i = Entries-1; i >= 0; i = i - 1) begin
            if (!validFlags[i]) freeIdx = i;
        end
    end

    reg [$clog2(Entries)-1:0] matchIdx;
    reg                       matchFound;
    always @(*) begin
        matchIdx = 0;
        matchFound = 0;
        for (integer i = 0; i < Entries; i = i + 1) begin
            if (validFlags[i] && addrArray[i] == respAddr) begin
                matchIdx = i;
                matchFound = 1;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            validFlags <= 0;
            wakeupValid <= 0;
        end else begin
            wakeupValid <= 0;

            if (allocValid && allocReady) begin
                validFlags[freeIdx] <= 1;
                addrArray[freeIdx] <= allocAddr;
                warpIdArray[freeIdx] <= allocWarpId;
                destRegArray[freeIdx] <= allocDestReg;
            end

            if (respValid && matchFound) begin
                validFlags[matchIdx] <= 0;
                wakeupValid <= 1;
                wakeupWarpId <= warpIdArray[matchIdx];
                wakeupDestReg <= destRegArray[matchIdx];
            end
        end
    end

endmodule
