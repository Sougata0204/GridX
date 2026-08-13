
`default_nettype none
`timescale 1ns/1ns

module zeroSkipCtrl #(
    parameter DIM = 4,
    parameter DATA_BITS = 16
) (
    input  wire clk,
    input  wire reset,

    input  wire signed [DIM-1:0][DIM-1:0][DATA_BITS-1:0] matrixA,
    input  wire signed [DIM-1:0][DIM-1:0][DATA_BITS-1:0] matrixB,

    input  wire scanValid,

    output reg  [DIM-1:0] aRowZeroMask,
    output reg  [DIM-1:0] bColZeroMask,
    output reg             scanDone,

    output reg  [15:0] totalRowsSkipped,
    output reg  [15:0] totalColsSkipped
);

    integer r, c;
    reg rowAllZero, colAllZero;

    always @(posedge clk) begin
        if (reset) begin
            aRowZeroMask <= 0;
            bColZeroMask <= 0;
            scanDone <= 0;
            totalRowsSkipped <= 0;
            totalColsSkipped <= 0;
        end else begin
            scanDone <= 0;

            if (scanValid) begin

                for (r = 0; r < DIM; r = r + 1) begin
                    rowAllZero = 1;
                    for (c = 0; c < DIM; c = c + 1) begin
                        if (matrixA[r][c] != 0) rowAllZero = 0;
                    end
                    aRowZeroMask[r] <= rowAllZero;
                    if (rowAllZero) totalRowsSkipped <= totalRowsSkipped + 1;
                end

                for (c = 0; c < DIM; c = c + 1) begin
                    colAllZero = 1;
                    for (r = 0; r < DIM; r = r + 1) begin
                        if (matrixB[r][c] != 0) colAllZero = 0;
                    end
                    bColZeroMask[c] <= colAllZero;
                    if (colAllZero) totalColsSkipped <= totalColsSkipped + 1;
                end

                scanDone <= 1;
            end
        end
    end

endmodule
