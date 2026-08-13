
`default_nettype none
`timescale 1ns/1ns

module rtCore (
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

    reg stage1Valid, stage2Valid, stage3Valid, stage4Valid;
    assign ready = !stage1Valid;
    assign busy = stage1Valid | stage2Valid | stage3Valid | stage4Valid;
    assign done = stage4Valid;
    assign pipelineFillLevel = stage1Valid + stage2Valid + stage3Valid + stage4Valid;

    reg [3:0] stage1Tag;
    reg signed [16:0] s1T0X, s1T0Y, s1T0Z;
    reg signed [16:0] s1T1X, s1T1Y, s1T1Z;
    reg signed [15:0] s1InvX, s1InvY, s1InvZ;

    reg [3:0] stage2Tag;
    reg signed [31:0] s2T0sX, s2T0sY, s2T0sZ;
    reg signed [31:0] s2T1sX, s2T1sY, s2T1sZ;

    reg [3:0] stage3Tag;
    reg signed [31:0] s3Tmin, s3Tmax;

    reg [3:0] stage4Tag;
    reg signed [31:0] s4Hit;
    reg signed [31:0] s4T;

    assign tagOut = stage4Tag;

    genvar r, c;
    generate
        for (r=0; r<4; r++) begin : rdw
            for (c=0; c<4; c++) begin : cdw
                if (r==0 && c==0) assign matrixD[r][c] = s4Hit;
                else if (r==0 && c==1) assign matrixD[r][c] = s4T;
                else assign matrixD[r][c] = 0;
            end
        end
    endgenerate

    function automatic signed [31:0] fMin(input signed [31:0] a, input signed [31:0] b);
        fMin = (a < b) ? a : b;
    endfunction
    function automatic signed [31:0] fMax(input signed [31:0] a, input signed [31:0] b);
        fMax = (a > b) ? a : b;
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            stage1Valid <= 0;
            stage2Valid <= 0;
            stage3Valid <= 0;
            stage4Valid <= 0;
        end else begin

            if (start && ready) begin
                stage1Valid <= 1;
                stage1Tag   <= tagIn;

                s1T0X <= $signed(matrixB[0][0]) - $signed(matrixA[0][0]);
                s1T0Y <= $signed(matrixB[0][1]) - $signed(matrixA[0][1]);
                s1T0Z <= $signed(matrixB[0][2]) - $signed(matrixA[0][2]);

                s1T1X <= $signed(matrixB[1][0]) - $signed(matrixA[0][0]);
                s1T1Y <= $signed(matrixB[1][1]) - $signed(matrixA[0][1]);
                s1T1Z <= $signed(matrixB[1][2]) - $signed(matrixA[0][2]);

                s1InvX <= matrixA[1][0];
                s1InvY <= matrixA[1][1];
                s1InvZ <= matrixA[1][2];
            end else begin
                stage1Valid <= 0;
            end

            if (stage1Valid) begin
                stage2Valid <= 1;
                stage2Tag   <= stage1Tag;

                s2T0sX <= (s1T0X * s1InvX) >>> 8;
                s2T0sY <= (s1T0Y * s1InvY) >>> 8;
                s2T0sZ <= (s1T0Z * s1InvZ) >>> 8;

                s2T1sX <= (s1T1X * s1InvX) >>> 8;
                s2T1sY <= (s1T1Y * s1InvY) >>> 8;
                s2T1sZ <= (s1T1Z * s1InvZ) >>> 8;
            end else begin
                stage2Valid <= 0;
            end

            if (stage2Valid) begin
                stage3Valid <= 1;
                stage3Tag   <= stage2Tag;

                s3Tmin <= fMax(fMax(fMin(s2T0sX, s2T1sX), fMin(s2T0sY, s2T1sY)), fMin(s2T0sZ, s2T1sZ));

                s3Tmax <= fMin(fMin(fMax(s2T0sX, s2T1sX), fMax(s2T0sY, s2T1sY)), fMax(s2T0sZ, s2T1sZ));
            end else begin
                stage3Valid <= 0;
            end

            if (stage3Valid) begin
                stage4Valid <= 1;
                stage4Tag <= stage3Tag;
                if (s3Tmin <= s3Tmax && s3Tmax >= 0) begin
                    s4Hit <= 1;
                    s4T <= s3Tmin;
                end else begin
                    s4Hit <= 0;
                    s4T <= -1;
                end
            end else begin
                stage4Valid <= 0;
            end
        end
    end

endmodule
