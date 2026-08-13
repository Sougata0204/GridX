
`default_nettype none
`timescale 1ns/1ns

module tensorUnitPipelined (
    input  wire clk,
    input  wire reset,
    input  wire start,
    input  wire signed [3:0][3:0][15:0] matrixA,
    input  wire signed [3:0][3:0][15:0] matrixB,
    input  wire signed [3:0][3:0][31:0] matrixC,
    input  wire [3:0] tagIn,
    output wire ready,
    output wire done,
    output wire signed [3:0][3:0][31:0] matrixD,
    output wire [3:0] tagOut,
    output wire busy,
    output wire [2:0] pipelineFillLevel
);
    reg [4:0] stageValid;
    reg signed [3:0][3:0][15:0] pipeA [4:0];
    reg signed [3:0][3:0][15:0] pipeB [4:0];
    reg signed [3:0][3:0][31:0] pipeAcc [4:0];
    reg [3:0] pipeTag [4:0];

    assign ready = !stageValid[0];
    assign busy = |stageValid;
    assign done = stageValid[4];
    assign tagOut = pipeTag[4];
    assign pipelineFillLevel = stageValid[0] + stageValid[1] + stageValid[2] + stageValid[3] + stageValid[4];
    assign matrixD = pipeAcc[4];

    integer i, j, k;
    always @(posedge clk) begin
        if (reset) begin
            stageValid <= 5'b00000;
            for (i = 0; i < 5; i++) begin
                pipeTag[i] <= 0;
                for (j = 0; j < 4; j++) begin
                    for (k = 0; k < 4; k++) begin
                        pipeA[i][j][k] <= 0;
                        pipeB[i][j][k] <= 0;
                        pipeAcc[i][j][k] <= 0;
                    end
                end
            end
        end else begin
            // Stage 0: Input latch
            if (start && ready) begin
                stageValid[0] <= 1;
                pipeA[0] <= matrixA;
                pipeB[0] <= matrixB;
                pipeAcc[0] <= matrixC;
                pipeTag[0] <= tagIn;
            end else begin
                stageValid[0] <= 0;
            end

            // Stage 1 (row 0 computation)
            if (stageValid[0]) begin
                for (j = 0; j < 4; j++) begin
                    automatic logic signed [31:0] dot = 0;
                    for (k = 0; k < 4; k++) begin
                        dot = dot + $signed(pipeA[0][0][k]) * $signed(pipeB[0][k][j]);
                    end
                    pipeAcc[1][0][j] <= pipeAcc[0][0][j] + dot;
                end
                pipeAcc[1][1] <= pipeAcc[0][1];
                pipeAcc[1][2] <= pipeAcc[0][2];
                pipeAcc[1][3] <= pipeAcc[0][3];
                
                pipeA[1] <= pipeA[0];
                pipeB[1] <= pipeB[0];
                pipeTag[1] <= pipeTag[0];
                stageValid[1] <= 1;
            end else begin
                stageValid[1] <= 0;
            end

            // Stage 2 (row 1 computation)
            if (stageValid[1]) begin
                for (j = 0; j < 4; j++) begin
                    automatic logic signed [31:0] dot = 0;
                    for (k = 0; k < 4; k++) begin
                        dot = dot + $signed(pipeA[1][1][k]) * $signed(pipeB[1][k][j]);
                    end
                    pipeAcc[2][1][j] <= pipeAcc[1][1][j] + dot;
                end
                pipeAcc[2][0] <= pipeAcc[1][0]; // propagate row 0
                pipeAcc[2][2] <= pipeAcc[1][2];
                pipeAcc[2][3] <= pipeAcc[1][3];
                
                pipeA[2] <= pipeA[1];
                pipeB[2] <= pipeB[1];
                pipeTag[2] <= pipeTag[1];
                stageValid[2] <= 1;
            end else begin
                stageValid[2] <= 0;
            end

            // Stage 3 (row 2 computation)
            if (stageValid[2]) begin
                for (j = 0; j < 4; j++) begin
                    automatic logic signed [31:0] dot = 0;
                    for (k = 0; k < 4; k++) begin
                        dot = dot + $signed(pipeA[2][2][k]) * $signed(pipeB[2][k][j]);
                    end
                    pipeAcc[3][2][j] <= pipeAcc[2][2][j] + dot;
                end
                pipeAcc[3][0] <= pipeAcc[2][0]; // propagate row 0
                pipeAcc[3][1] <= pipeAcc[2][1]; // propagate row 1
                pipeAcc[3][3] <= pipeAcc[2][3];
                
                pipeA[3] <= pipeA[2];
                pipeB[3] <= pipeB[2];
                pipeTag[3] <= pipeTag[2];
                stageValid[3] <= 1;
            end else begin
                stageValid[3] <= 0;
            end

            // Stage 4 (row 3 computation)
            if (stageValid[3]) begin
                for (j = 0; j < 4; j++) begin
                    automatic logic signed [31:0] dot = 0;
                    for (k = 0; k < 4; k++) begin
                        dot = dot + $signed(pipeA[3][3][k]) * $signed(pipeB[3][k][j]);
                    end
                    pipeAcc[4][3][j] <= pipeAcc[3][3][j] + dot;
                end
                pipeAcc[4][0] <= pipeAcc[3][0]; // propagate row 0
                pipeAcc[4][1] <= pipeAcc[3][1]; // propagate row 1
                pipeAcc[4][2] <= pipeAcc[3][2]; // propagate row 2
                
                pipeA[4] <= pipeA[3];
                pipeB[4] <= pipeB[3];
                pipeTag[4] <= pipeTag[3];
                stageValid[4] <= 1;
            end else begin
                stageValid[4] <= 0;
            end
        end
    end
`ifdef DEBUG
    reg [31:0] debugCycle;
    always @(posedge clk) begin
        if (reset) debugCycle <= 0;
        else debugCycle <= debugCycle + 1;
    end
    always @(posedge clk) begin
        if (start) begin
            $display("[tUnit] Cycle %d START: ready=%b start=%b tag=%d a0=%h b0=%h c0=%h",
                     debugCycle, ready, start, tagIn, matrixA[0][0], matrixB[0][0], matrixC[0][0]);
        end
        if (|stageValid) begin
            $display("[tUnit] Cycle %d PIPELINE: valid=%b tags=%d %d %d %d %d done=%b acc00=%h result00=%h",
                     debugCycle, stageValid, pipeTag[0], pipeTag[1], pipeTag[2], pipeTag[3], pipeTag[4],
                     done, pipeAcc[0][0][0], matrixD[0][0]);
        end
    end
`endif
endmodule
