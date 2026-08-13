
`default_nettype none
`timescale 1ns/1ns

module sparseMma #(
    parameter DIM = 4,
    parameter DATA_IN_BITS = 16,
    parameter DATA_OUT_BITS = 32,
    parameter SPARSITY_RATIO = 2
) (
    input  wire clk,
    input  wire reset,
    input  wire start,

    input  wire signed [DIM-1:0][DIM-1:0][DATA_IN_BITS-1:0] matrixA,
    input  wire signed [DIM-1:0][DIM-1:0][DATA_IN_BITS-1:0] matrixB,
    input  wire signed [DIM-1:0][DIM-1:0][DATA_OUT_BITS-1:0] matrixC,

    input  wire [DIM-1:0][DIM/2-1:0][1:0] sparseIdxA,

    input  wire sparseEnable,

    input  wire [1:0] precisionMode,

    output reg  done,
    output reg  busy,
    output reg  signed [DIM-1:0][DIM-1:0][DATA_OUT_BITS-1:0] matrixD,

    output reg  [15:0] macsExecuted,
    output reg  [15:0] macsSkipped
);

    reg [1:0] stageValid;
    reg signed [DIM-1:0][DIM-1:0][DATA_OUT_BITS-1:0] acc [1:0];

    integer row, col, k;
    reg signed [DATA_OUT_BITS-1:0] dot;
    reg [1:0] idx;
    integer effectiveK;

    always @(posedge clk) begin
        if (reset) begin
            done <= 0;
            busy <= 0;
            stageValid <= 0;
            macsExecuted <= 0;
            macsSkipped <= 0;
        end else begin
            done <= 0;

            if (start && !busy) begin
                busy <= 1;
                stageValid[0] <= 1;
                for (row = 0; row < DIM; row = row + 1) begin
                    for (col = 0; col < DIM; col = col + 1) begin
                        dot = matrixC[row][col];
                        if (sparseEnable) begin

                            for (k = 0; k < DIM/2; k = k + 1) begin
                                idx = sparseIdxA[row][k];
                                effectiveK = idx;
                                dot = dot + matrixA[row][effectiveK] * matrixB[effectiveK][col];
                                macsExecuted <= macsExecuted + 1;
                            end
                            macsSkipped <= macsSkipped + DIM/2;
                        end else begin

                            for (k = 0; k < DIM; k = k + 1) begin
                                dot = dot + matrixA[row][k] * matrixB[k][col];
                                macsExecuted <= macsExecuted + 1;
                            end
                        end
                        acc[0][row][col] <= dot;
                    end
                end
            end else if (!start) begin
                stageValid[0] <= 0;
            end

            stageValid[1] <= stageValid[0];
            if (stageValid[0]) begin
                acc[1] <= acc[0];
            end

            if (stageValid[1]) begin
                matrixD <= acc[1];
                done <= 1;
                busy <= 0;
            end
        end
    end

endmodule
