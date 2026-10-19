
`default_nettype none
`timescale 1ns/1ps

// Dual-clock asynchronous FIFO using Gray-code pointer synchronizers for safe GALS clock domain crossings.
module asyncFifo #(
    parameter DATA_WIDTH          = 8,
    parameter DEPTH               = 8,
    parameter PTR_WIDTH           = $clog2(DEPTH),
    parameter SYNC_STAGES         = 2,
    parameter ALMOST_FULL_THRESH  = 1,
    parameter ALMOST_EMPTY_THRESH = 1
) (
    input  wire                  wrClk,
    input  wire                  wrRst,
    input  wire                  wrEn,
    input  wire [DATA_WIDTH-1:0] wrData,
    output wire                  wrFull,
    output wire                  almostFull,

    input  wire                  rdClk,
    input  wire                  rdRst,
    input  wire                  rdEn,
    output wire [DATA_WIDTH-1:0] rdData,
    output wire                  rdEmpty,
    output wire                  almostEmpty
);

    reg [DATA_WIDTH-1:0] mem [DEPTH-1:0];

    reg [PTR_WIDTH:0] wrPtrBin, wrPtrGray;
    reg [PTR_WIDTH:0] rdPtrBin, rdPtrGray;

    (* ASYNC_REG = "TRUE", DONT_TOUCH = "TRUE" *) reg [PTR_WIDTH:0] wrPtrGraySync [SYNC_STAGES-1:0];
    (* ASYNC_REG = "TRUE", DONT_TOUCH = "TRUE" *) reg [PTR_WIDTH:0] rdPtrGraySync [SYNC_STAGES-1:0];

    function automatic [PTR_WIDTH:0] bin2gray(input [PTR_WIDTH:0] bin);
        bin2gray = bin ^ (bin >> 1);
    endfunction

    function automatic [PTR_WIDTH:0] gray2bin(input [PTR_WIDTH:0] gray);
        integer i;
        reg [PTR_WIDTH:0] bin;
        begin
            bin[PTR_WIDTH] = gray[PTR_WIDTH];
            for (i = PTR_WIDTH-1; i >= 0; i = i - 1)
                bin[i] = bin[i+1] ^ gray[i];
            gray2bin = bin;
        end
    endfunction

    wire [PTR_WIDTH:0] wrPtrBinNext = wrPtrBin + (wrEn && !wrFull);
    wire [PTR_WIDTH:0] wrPtrGrayNext = bin2gray(wrPtrBinNext);

    wire [PTR_WIDTH:0] rdPtrInWrDomain = rdPtrGraySync[SYNC_STAGES-1];
    wire wrFullInternal = (wrPtrGray == {~rdPtrInWrDomain[PTR_WIDTH:PTR_WIDTH-1],
                                         rdPtrInWrDomain[PTR_WIDTH-2:0]});
    assign wrFull = wrFullInternal;

    wire [PTR_WIDTH:0] rdPtrBinInWrDomain = gray2bin(rdPtrInWrDomain);
    wire [PTR_WIDTH:0] wrOccupancy = wrPtrBin - rdPtrBinInWrDomain;
    assign almostFull = (wrOccupancy >= (DEPTH - ALMOST_FULL_THRESH)) || wrFullInternal;

    always_ff @(posedge wrClk or posedge wrRst) begin
        if (wrRst) begin
            wrPtrBin  <= '0;
            wrPtrGray <= '0;
        end else begin
            if (wrEn && !wrFullInternal) begin
                mem[wrPtrBin[PTR_WIDTH-1:0]] <= wrData;
                wrPtrBin  <= wrPtrBinNext;
                wrPtrGray <= wrPtrGrayNext;
            end
        end
    end

    integer ws;
    always_ff @(posedge wrClk or posedge wrRst) begin
        if (wrRst) begin
            for (ws = 0; ws < SYNC_STAGES; ws = ws + 1)
                rdPtrGraySync[ws] <= '0;
        end else begin
            rdPtrGraySync[0] <= rdPtrGray;
            for (ws = 1; ws < SYNC_STAGES; ws = ws + 1)
                rdPtrGraySync[ws] <= rdPtrGraySync[ws-1];
        end
    end

    wire [PTR_WIDTH:0] rdPtrBinNext = rdPtrBin + (rdEn && !rdEmpty);
    wire [PTR_WIDTH:0] rdPtrGrayNext = bin2gray(rdPtrBinNext);

    wire [PTR_WIDTH:0] wrPtrInRdDomain = wrPtrGraySync[SYNC_STAGES-1];
    wire rdEmptyInternal = (rdPtrGray == wrPtrInRdDomain);
    assign rdEmpty = rdEmptyInternal;
    assign rdData  = mem[rdPtrBin[PTR_WIDTH-1:0]];

    wire [PTR_WIDTH:0] wrPtrBinInRdDomain = gray2bin(wrPtrInRdDomain);
    wire [PTR_WIDTH:0] rdOccupancy = wrPtrBinInRdDomain - rdPtrBin;
    assign almostEmpty = (rdOccupancy <= ALMOST_EMPTY_THRESH) || rdEmptyInternal;

    always_ff @(posedge rdClk or posedge rdRst) begin
        if (rdRst) begin
            rdPtrBin  <= '0;
            rdPtrGray <= '0;
        end else begin
            if (rdEn && !rdEmptyInternal) begin
                rdPtrBin  <= rdPtrBinNext;
                rdPtrGray <= rdPtrGrayNext;
            end
        end
    end

    integer rs;
    always_ff @(posedge rdClk or posedge rdRst) begin
        if (rdRst) begin
            for (rs = 0; rs < SYNC_STAGES; rs = rs + 1)
                wrPtrGraySync[rs] <= '0;
        end else begin
            wrPtrGraySync[0] <= wrPtrGray;
            for (rs = 1; rs < SYNC_STAGES; rs = rs + 1)
                wrPtrGraySync[rs] <= wrPtrGraySync[rs-1];
        end
    end

`ifndef SYNTHESIS
    property p_wr_gray_single_bit;
        @(posedge wrClk) disable iff (wrRst)
        (wrEn && !wrFullInternal) |=> ($countones(wrPtrGray ^ $past(wrPtrGray)) <= 1);
    endproperty
    assert property (p_wr_gray_single_bit)
        else $error("[CDC_ERROR] Multi-bit Gray code transition on wrPtrGray!");

    property p_rd_gray_single_bit;
        @(posedge rdClk) disable iff (rdRst)
        (rdEn && !rdEmptyInternal) |=> ($countones(rdPtrGray ^ $past(rdPtrGray)) <= 1);
    endproperty
    assert property (p_rd_gray_single_bit)
        else $error("[CDC_ERROR] Multi-bit Gray code transition on rdPtrGray!");

    property p_no_wr_overflow;
        @(posedge wrClk) disable iff (wrRst)
        wrFullInternal |-> !wrEn;
    endproperty

    property p_no_rd_underflow;
        @(posedge rdClk) disable iff (rdRst)
        rdEmptyInternal |-> !rdEn;
    endproperty
`endif

endmodule
