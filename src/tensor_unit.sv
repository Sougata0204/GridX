
`default_nettype none
`timescale 1ns/1ns

module tensorUnit (
    input wire clk,
    input wire reset,
    input wire start,
    output reg done,
    output reg busy,
    input wire signed [3:0][3:0][15:0] matrixA,
    input wire signed [3:0][3:0][15:0] matrixB,
    input wire signed [3:0][3:0][31:0] matrixC,
    output reg signed [3:0][3:0][31:0] matrixD
);
    reg [2:0] cycleCount;
    reg computing;
    reg signed [3:0][3:0][15:0] regA;
    reg signed [3:0][3:0][15:0] regB;
    reg signed [3:0][3:0][31:0] acc;
    integer i, j, k;
    always @(posedge clk) begin
        if (reset) begin
            cycleCount <= 0;
            computing <= 0;
            done <= 0;
            busy <= 0;
            for (i=0; i<4; i=i+1) begin
                for (j=0; j<4; j=j+1) begin
                    matrixD[i][j] <= 0;
                    acc[i][j] <= 0;
                    regA[i][j] <= 0;
                    regB[i][j] <= 0;
                end
            end
        end else begin
            done <= 0;
            if (start && !busy) begin
                regA <= matrixA;
                regB <= matrixB;
                acc <= matrixC;
                computing <= 1;
                busy <= 1;
                cycleCount <= 0;
            end else if (computing) begin
                if (cycleCount < 4) begin
                    for (j=0; j<4; j=j+1) begin
                       reg signed [31:0] dotProd;
                       dotProd = 0;
                       for (k=0; k<4; k=k+1) begin
                           dotProd = dotProd + ({{16{regA[cycleCount][k][15]}}, regA[cycleCount][k]} * {{16{regB[k][j][15]}}, regB[k][j]});
                       end
                       matrixD[cycleCount][j] <= dotProd + acc[cycleCount][j];
                    end
                    cycleCount <= cycleCount + 1;
                end else begin
                    computing <= 0;
                    busy <= 0;
                    done <= 1;
                end
            end
        end
    end
endmodule
