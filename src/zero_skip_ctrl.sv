
`default_nettype none
`timescale 1ns/1ns

module zero_skip_ctrl #(
    parameter DIM = 4,
    parameter DATA_BITS = 16
) (
    input  wire clk,
    input  wire reset,

    input  wire signed [DIM-1:0][DIM-1:0][DATA_BITS-1:0] matrix_a,
    input  wire signed [DIM-1:0][DIM-1:0][DATA_BITS-1:0] matrix_b,

    input  wire scan_valid,

    output reg  [DIM-1:0] a_row_zero_mask,
    output reg  [DIM-1:0] b_col_zero_mask,
    output reg             scan_done,

    output reg  [15:0] total_rows_skipped,
    output reg  [15:0] total_cols_skipped
);

    integer r, c;
    reg row_all_zero, col_all_zero;

    always @(posedge clk) begin
        if (reset) begin
            a_row_zero_mask <= 0;
            b_col_zero_mask <= 0;
            scan_done <= 0;
            total_rows_skipped <= 0;
            total_cols_skipped <= 0;
        end else begin
            scan_done <= 0;

            if (scan_valid) begin

                for (r = 0; r < DIM; r = r + 1) begin
                    row_all_zero = 1;
                    for (c = 0; c < DIM; c = c + 1) begin
                        if (matrix_a[r][c] != 0) row_all_zero = 0;
                    end
                    a_row_zero_mask[r] <= row_all_zero;
                    if (row_all_zero) total_rows_skipped <= total_rows_skipped + 1;
                end

                for (c = 0; c < DIM; c = c + 1) begin
                    col_all_zero = 1;
                    for (r = 0; r < DIM; r = r + 1) begin
                        if (matrix_b[r][c] != 0) col_all_zero = 0;
                    end
                    b_col_zero_mask[c] <= col_all_zero;
                    if (col_all_zero) total_cols_skipped <= total_cols_skipped + 1;
                end

                scan_done <= 1;
            end
        end
    end

endmodule
