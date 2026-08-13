
`default_nettype none
`timescale 1ns/1ns

module asyncFifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 8,
    parameter PTR_WIDTH  = $clog2(DEPTH)
) (

    input  wire                  wrClk,
    input  wire                  wrRst,
    input  wire                  wrEn,
    input  wire [DATA_WIDTH-1:0] wrData,
    output wire                  wrFull,

    input  wire                  rdClk,
    input  wire                  rdRst,
    input  wire                  rdEn,
    output wire [DATA_WIDTH-1:0] rdData,
    output wire                  rdEmpty
);

    reg [DATA_WIDTH-1:0] mem [DEPTH-1:0];

    reg [PTR_WIDTH:0] wrPtrBin, wrPtrGray;
    reg [PTR_WIDTH:0] rdPtrBin, rdPtrGray;

    reg [PTR_WIDTH:0] wrPtrGrayRdSync1, wrPtrGrayRdSync2;
    reg [PTR_WIDTH:0] rdPtrGrayWrSync1, rdPtrGrayWrSync2;

    function automatic [PTR_WIDTH:0] bin2gray(input [PTR_WIDTH:0] bin);
        bin2gray = bin ^ (bin >> 1);
    endfunction

    wire [PTR_WIDTH:0] wrPtrBinNext = wrPtrBin + (wrEn && !wrFull);
    wire wrFullInternal = (wrPtrGray == {~rdPtrGrayWrSync2[PTR_WIDTH:PTR_WIDTH-1],
                                              rdPtrGrayWrSync2[PTR_WIDTH-2:0]});
    assign wrFull = wrFullInternal;

    always @(posedge wrClk) begin
        if (wrRst) begin
            wrPtrBin  <= 0;
            wrPtrGray <= 0;
        end else begin
            if (wrEn && !wrFullInternal) begin
                mem[wrPtrBin[PTR_WIDTH-1:0]] <= wrData;
                wrPtrBin  <= wrPtrBinNext;
                wrPtrGray <= bin2gray(wrPtrBinNext);
            end
        end
    end

    always @(posedge wrClk) begin
        if (wrRst) begin
            rdPtrGrayWrSync1 <= 0;
            rdPtrGrayWrSync2 <= 0;
        end else begin
            rdPtrGrayWrSync1 <= rdPtrGray;
            rdPtrGrayWrSync2 <= rdPtrGrayWrSync1;
        end
    end

    wire [PTR_WIDTH:0] rdPtrBinNext = rdPtrBin + (rdEn && !rdEmpty);
    wire rdEmptyInternal = (rdPtrGray == wrPtrGrayRdSync2);
    assign rdEmpty = rdEmptyInternal;
    assign rdData = mem[rdPtrBin[PTR_WIDTH-1:0]];

    always @(posedge rdClk) begin
        if (rdRst) begin
            rdPtrBin  <= 0;
            rdPtrGray <= 0;
        end else begin
            if (rdEn && !rdEmptyInternal) begin
                rdPtrBin  <= rdPtrBinNext;
                rdPtrGray <= bin2gray(rdPtrBinNext);
            end
        end
    end

    always @(posedge rdClk) begin
        if (rdRst) begin
            wrPtrGrayRdSync1 <= 0;
            wrPtrGrayRdSync2 <= 0;
        end else begin
            wrPtrGrayRdSync1 <= wrPtrGray;
            wrPtrGrayRdSync2 <= wrPtrGrayRdSync1;
        end
    end

endmodule
