
`default_nettype none
`timescale 1ns/1ns

module sparse_mma #(
    parameter DIM = 4,
    parameter DATA_IN_BITS = 16,
    parameter DATA_OUT_BITS = 32,
    parameter SPARSITY_RATIO = 2
) (
    input  wire clk,
    input  wire reset,
    input  wire start,

    input  wire signed [DIM-1:0][DIM-1:0][DATA_IN_BITS-1:0] matrix_a,
    input  wire signed [DIM-1:0][DIM-1:0][DATA_IN_BITS-1:0] matrix_b,
    input  wire signed [DIM-1:0][DIM-1:0][DATA_OUT_BITS-1:0] matrix_c,

    input  wire [DIM-1:0][DIM/2-1:0][1:0] sparse_idx_a,

    input  wire sparse_enable,

    input  wire [1:0] precision_mode,

    output reg  done,
    output reg  busy,
    output reg  signed [DIM-1:0][DIM-1:0][DATA_OUT_BITS-1:0] matrix_d,

    output reg  [15:0] macs_executed,
    output reg  [15:0] macs_skipped
);

    reg [1:0] stage_valid;
    reg signed [DIM-1:0][DIM-1:0][DATA_OUT_BITS-1:0] acc [1:0];

    integer row, col, k;
    reg signed [DATA_OUT_BITS-1:0] dot;
    reg [1:0] idx;
    integer effective_k;

    always @(posedge clk) begin
        if (reset) begin
            done <= 0;
            busy <= 0;
            stage_valid <= 0;
            macs_executed <= 0;
            macs_skipped <= 0;
        end else begin
            done <= 0;

            if (start && !busy) begin
                busy <= 1;
                stage_valid[0] <= 1;
                for (row = 0; row < DIM; row = row + 1) begin
                    for (col = 0; col < DIM; col = col + 1) begin
                        dot = matrix_c[row][col];
                        if (sparse_enable) begin

                            for (k = 0; k < DIM/2; k = k + 1) begin
                                idx = sparse_idx_a[row][k];
                                effective_k = idx;
                                dot = dot + matrix_a[row][effective_k] * matrix_b[effective_k][col];
                                macs_executed <= macs_executed + 1;
                            end
                            macs_skipped <= macs_skipped + DIM/2;
                        end else begin

                            for (k = 0; k < DIM; k = k + 1) begin
                                dot = dot + matrix_a[row][k] * matrix_b[k][col];
                                macs_executed <= macs_executed + 1;
                            end
                        end
                        acc[0][row][col] <= dot;
                    end
                end
            end else if (!start) begin
                stage_valid[0] <= 0;
            end

            stage_valid[1] <= stage_valid[0];
            if (stage_valid[0]) begin
                acc[1] <= acc[0];
            end

            if (stage_valid[1]) begin
                matrix_d <= acc[1];
                done <= 1;
                busy <= 0;
            end
        end
    end

endmodule
