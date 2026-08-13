
`default_nettype none
`timescale 1ns/1ns

module virtualChannel #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 16,
    parameter FIFO_DEPTH = 4
) (
    input wire clk,
    input wire reset,
    input wire inValid,
    input wire inIsResponse,
    input wire [ADDR_WIDTH-1:0] inAddr,
    input wire [DATA_WIDTH-1:0] inData,
    input wire inWrite,
    output wire inReady,
    output wire vc0Valid,
    output wire [ADDR_WIDTH-1:0] vc0Addr,
    output wire [DATA_WIDTH-1:0] vc0Data,
    output wire vc0Write,
    input wire vc0Ready,
    output wire vc1Valid,
    output wire [ADDR_WIDTH-1:0] vc1Addr,
    output wire [DATA_WIDTH-1:0] vc1Data,
    input wire vc1Ready,
    output reg [31:0] perfVc0Packets,
    output reg [31:0] perfVc1Packets,
    output reg [31:0] perfVc0BlockedCycles,
    output reg [31:0] perfVc1BlockedCycles
);
    reg [ADDR_WIDTH+DATA_WIDTH:0] vc0Fifo [FIFO_DEPTH-1:0];
    reg [$clog2(FIFO_DEPTH):0] vc0Count;
    reg [$clog2(FIFO_DEPTH)-1:0] vc0Head, vc0Tail;
    wire vc0Full = (vc0Count == FIFO_DEPTH);
    wire vc0Empty = (vc0Count == 0);
    assign vc0Valid = !vc0Empty;
    assign vc0Addr = vc0Fifo[vc0Head][ADDR_WIDTH+DATA_WIDTH:DATA_WIDTH+1];
    assign vc0Data = vc0Fifo[vc0Head][DATA_WIDTH:1];
    assign vc0Write = vc0Fifo[vc0Head][0];
    reg [ADDR_WIDTH+DATA_WIDTH-1:0] vc1Fifo [FIFO_DEPTH-1:0];
    reg [$clog2(FIFO_DEPTH):0] vc1Count;
    reg [$clog2(FIFO_DEPTH)-1:0] vc1Head, vc1Tail;
    wire vc1Full = (vc1Count == FIFO_DEPTH);
    wire vc1Empty = (vc1Count == 0);
    assign vc1Valid = !vc1Empty;
    assign vc1Addr = vc1Fifo[vc1Head][ADDR_WIDTH+DATA_WIDTH-1:DATA_WIDTH];
    assign vc1Data = vc1Fifo[vc1Head][DATA_WIDTH-1:0];
    assign inReady = inIsResponse ? !vc1Full : !vc0Full;
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            vc0Count <= 0;
            vc0Head <= 0;
            vc0Tail <= 0;
            vc1Count <= 0;
            vc1Head <= 0;
            vc1Tail <= 0;
            perfVc0Packets <= 0;
            perfVc1Packets <= 0;
            perfVc0BlockedCycles <= 0;
            perfVc1BlockedCycles <= 0;
        end else begin
            if (inValid && inReady) begin
                if (!inIsResponse) begin
                    vc0Fifo[vc0Tail] <= {inAddr, inData, inWrite};
                    vc0Tail <= vc0Tail + 1;
                    vc0Count <= vc0Count + 1;
                    perfVc0Packets <= perfVc0Packets + 1;
                end else begin
                    vc1Fifo[vc1Tail] <= {inAddr, inData};
                    vc1Tail <= vc1Tail + 1;
                    vc1Count <= vc1Count + 1;
                    perfVc1Packets <= perfVc1Packets + 1;
                end
            end
            if (vc0Valid && vc0Ready) begin
                vc0Head <= vc0Head + 1;
                vc0Count <= vc0Count - 1;
            end
            if (vc1Valid && vc1Ready) begin
                vc1Head <= vc1Head + 1;
                vc1Count <= vc1Count - 1;
            end
            if (vc0Valid && !vc0Ready) begin
                perfVc0BlockedCycles <= perfVc0BlockedCycles + 1;
            end
            if (vc1Valid && !vc1Ready) begin
                perfVc1BlockedCycles <= perfVc1BlockedCycles + 1;
            end
        end
    end
endmodule
