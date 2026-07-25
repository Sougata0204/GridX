
`default_nettype none
`timescale 1ns/1ns

module rt_core (
    input  wire clk,
    input  wire reset,
    input  wire start,
    input  wire signed [3:0][3:0][15:0] matrix_a,
    input  wire signed [3:0][3:0][15:0] matrix_b,
    input  wire signed [3:0][3:0][31:0] matrix_c,
    input  wire [3:0] tag_in,
    output wire ready,
    output wire done,
    output wire signed [3:0][3:0][31:0] matrix_d,
    output wire [3:0] tag_out,
    output wire busy,
    output wire [2:0] pipeline_fill_level
);

    reg stage1_valid, stage2_valid, stage3_valid, stage4_valid;
    assign ready = !stage1_valid;
    assign busy = stage1_valid | stage2_valid | stage3_valid | stage4_valid;
    assign done = stage4_valid;
    assign pipeline_fill_level = stage1_valid + stage2_valid + stage3_valid + stage4_valid;

    reg [3:0] stage1_tag;
    reg signed [16:0] s1_t0_x, s1_t0_y, s1_t0_z;
    reg signed [16:0] s1_t1_x, s1_t1_y, s1_t1_z;
    reg signed [15:0] s1_inv_x, s1_inv_y, s1_inv_z;

    reg [3:0] stage2_tag;
    reg signed [31:0] s2_t0s_x, s2_t0s_y, s2_t0s_z;
    reg signed [31:0] s2_t1s_x, s2_t1s_y, s2_t1s_z;

    reg [3:0] stage3_tag;
    reg signed [31:0] s3_tmin, s3_tmax;

    reg [3:0] stage4_tag;
    reg signed [31:0] s4_hit;
    reg signed [31:0] s4_t;

    assign tag_out = stage4_tag;

    genvar r, c;
    generate
        for (r=0; r<4; r++) begin : rdw
            for (c=0; c<4; c++) begin : cdw
                if (r==0 && c==0) assign matrix_d[r][c] = s4_hit;
                else if (r==0 && c==1) assign matrix_d[r][c] = s4_t;
                else assign matrix_d[r][c] = 0;
            end
        end
    endgenerate

    function automatic signed [31:0] f_min(input signed [31:0] a, input signed [31:0] b);
        f_min = (a < b) ? a : b;
    endfunction
    function automatic signed [31:0] f_max(input signed [31:0] a, input signed [31:0] b);
        f_max = (a > b) ? a : b;
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            stage1_valid <= 0;
            stage2_valid <= 0;
            stage3_valid <= 0;
            stage4_valid <= 0;
        end else begin

            if (start && ready) begin
                stage1_valid <= 1;
                stage1_tag   <= tag_in;

                s1_t0_x <= $signed(matrix_b[0][0]) - $signed(matrix_a[0][0]);
                s1_t0_y <= $signed(matrix_b[0][1]) - $signed(matrix_a[0][1]);
                s1_t0_z <= $signed(matrix_b[0][2]) - $signed(matrix_a[0][2]);

                s1_t1_x <= $signed(matrix_b[1][0]) - $signed(matrix_a[0][0]);
                s1_t1_y <= $signed(matrix_b[1][1]) - $signed(matrix_a[0][1]);
                s1_t1_z <= $signed(matrix_b[1][2]) - $signed(matrix_a[0][2]);

                s1_inv_x <= matrix_a[1][0];
                s1_inv_y <= matrix_a[1][1];
                s1_inv_z <= matrix_a[1][2];
            end else begin
                stage1_valid <= 0;
            end

            if (stage1_valid) begin
                stage2_valid <= 1;
                stage2_tag   <= stage1_tag;

                s2_t0s_x <= (s1_t0_x * s1_inv_x) >>> 8;
                s2_t0s_y <= (s1_t0_y * s1_inv_y) >>> 8;
                s2_t0s_z <= (s1_t0_z * s1_inv_z) >>> 8;

                s2_t1s_x <= (s1_t1_x * s1_inv_x) >>> 8;
                s2_t1s_y <= (s1_t1_y * s1_inv_y) >>> 8;
                s2_t1s_z <= (s1_t1_z * s1_inv_z) >>> 8;
            end else begin
                stage2_valid <= 0;
            end

            if (stage2_valid) begin
                stage3_valid <= 1;
                stage3_tag   <= stage2_tag;

                s3_tmin <= f_max(f_max(f_min(s2_t0s_x, s2_t1s_x), f_min(s2_t0s_y, s2_t1s_y)), f_min(s2_t0s_z, s2_t1s_z));

                s3_tmax <= f_min(f_min(f_max(s2_t0s_x, s2_t1s_x), f_max(s2_t0s_y, s2_t1s_y)), f_max(s2_t0s_z, s2_t1s_z));
            end else begin
                stage3_valid <= 0;
            end

            if (stage3_valid) begin
                stage4_valid <= 1;
                stage4_tag <= stage3_tag;
                if (s3_tmin <= s3_tmax && s3_tmax >= 0) begin
                    s4_hit <= 1;
                    s4_t <= s3_tmin;
                end else begin
                    s4_hit <= 0;
                    s4_t <= -1;
                end
            end else begin
                stage4_valid <= 0;
            end
        end
    end

endmodule
