
`default_nettype none
`timescale 1ns/1ns

module expressLink #(
    parameter DATA_WIDTH   = 512,
    parameter ADDR_WIDTH   = 22,
    parameter FIFO_DEPTH   = 4,
    parameter LINK_LATENCY = 2
) (
    input  wire clk,
    input  wire reset,

    input  wire                    aTxValid,
    input  wire [DATA_WIDTH-1:0]   aTxData,
    input  wire [ADDR_WIDTH-1:0]   aTxAddr,
    input  wire                    aTxWrite,
    output wire                    aTxReady,

    output wire                    aRxValid,
    output wire [DATA_WIDTH-1:0]   aRxData,
    output wire [ADDR_WIDTH-1:0]   aRxAddr,
    output wire                    aRxWrite,
    input  wire                    aRxReady,

    input  wire                    bTxValid,
    input  wire [DATA_WIDTH-1:0]   bTxData,
    input  wire [ADDR_WIDTH-1:0]   bTxAddr,
    input  wire                    bTxWrite,
    output wire                    bTxReady,

    output wire                    bRxValid,
    output wire [DATA_WIDTH-1:0]   bRxData,
    output wire [ADDR_WIDTH-1:0]   bRxAddr,
    output wire                    bRxWrite,
    input  wire                    bRxReady,

    output wire [3:0]              aToBOccupancy,
    output wire [3:0]              bToAOccupancy,
    output reg  [15:0]             totalFlitsForwarded
);

    localparam PIPE_W = DATA_WIDTH + ADDR_WIDTH + 1;

    reg [PIPE_W-1:0] abPipe [LINK_LATENCY-1:0];
    reg [LINK_LATENCY-1:0] abPipeValid;

    reg [PIPE_W-1:0] baPipe [LINK_LATENCY-1:0];
    reg [LINK_LATENCY-1:0] baPipeValid;

    reg [PIPE_W-1:0] abFifo [FIFO_DEPTH-1:0];
    reg [$clog2(FIFO_DEPTH):0] abWrPtr, abRdPtr;
    wire [$clog2(FIFO_DEPTH):0] abCount = abWrPtr - abRdPtr;
    wire abFull  = (abCount >= FIFO_DEPTH);
    wire abEmpty = (abCount == 0);

    reg [PIPE_W-1:0] baFifo [FIFO_DEPTH-1:0];
    reg [$clog2(FIFO_DEPTH):0] baWrPtr, baRdPtr;
    wire [$clog2(FIFO_DEPTH):0] baCount = baWrPtr - baRdPtr;
    wire baFull  = (baCount >= FIFO_DEPTH);
    wire baEmpty = (baCount == 0);

    assign aTxReady = !abFull;
    assign bTxReady = !baFull;

    assign aToBOccupancy = abCount;
    assign bToAOccupancy = baCount;

    assign bRxValid = !abEmpty;
    assign {bRxWrite, bRxAddr, bRxData} = abFifo[abRdPtr[$clog2(FIFO_DEPTH)-1:0]];

    assign aRxValid = !baEmpty;
    assign {aRxWrite, aRxAddr, aRxData} = baFifo[baRdPtr[$clog2(FIFO_DEPTH)-1:0]];

    integer s;

    always @(posedge clk) begin
        if (reset) begin
            for (s = 0; s < LINK_LATENCY; s = s + 1) begin
                abPipeValid[s] <= 0;
                baPipeValid[s] <= 0;
            end
            abWrPtr <= 0;
            abRdPtr <= 0;
            baWrPtr <= 0;
            baRdPtr <= 0;
            totalFlitsForwarded <= 0;
        end else begin

            if (aTxValid && !abFull) begin
                abPipe[0] <= {aTxWrite, aTxAddr, aTxData};
                abPipeValid[0] <= 1;
            end else begin
                abPipeValid[0] <= 0;
            end

            for (s = 1; s < LINK_LATENCY; s = s + 1) begin
                abPipe[s] <= abPipe[s-1];
                abPipeValid[s] <= abPipeValid[s-1];
            end

            if (abPipeValid[LINK_LATENCY-1]) begin
                abFifo[abWrPtr[$clog2(FIFO_DEPTH)-1:0]] <= abPipe[LINK_LATENCY-1];
                abWrPtr <= abWrPtr + 1;
                totalFlitsForwarded <= totalFlitsForwarded + 1;
            end

            if (!abEmpty && bRxReady) begin
                abRdPtr <= abRdPtr + 1;
            end

            if (bTxValid && !baFull) begin
                baPipe[0] <= {bTxWrite, bTxAddr, bTxData};
                baPipeValid[0] <= 1;
            end else begin
                baPipeValid[0] <= 0;
            end

            for (s = 1; s < LINK_LATENCY; s = s + 1) begin
                baPipe[s] <= baPipe[s-1];
                baPipeValid[s] <= baPipeValid[s-1];
            end

            if (baPipeValid[LINK_LATENCY-1]) begin
                baFifo[baWrPtr[$clog2(FIFO_DEPTH)-1:0]] <= baPipe[LINK_LATENCY-1];
                baWrPtr <= baWrPtr + 1;
                totalFlitsForwarded <= totalFlitsForwarded + 1;
            end

            if (!baEmpty && aRxReady) begin
                baRdPtr <= baRdPtr + 1;
            end
        end
    end

endmodule
