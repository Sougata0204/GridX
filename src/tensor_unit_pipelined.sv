
`default_nettype none
`timescale 1ns/1ns

module tensor_unit_pipelined (
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
    reg [4:0] stage_valid;
    reg signed [3:0][3:0][15:0] pipe_a [4:0];
    reg signed [3:0][3:0][15:0] pipe_b [4:0];
    reg signed [3:0][3:0][31:0] pipe_acc [4:0];
    reg [3:0] pipe_tag [4:0];

    assign ready = !stage_valid[0];
    assign busy = |stage_valid;
    assign done = stage_valid[4];
    assign tag_out = pipe_tag[4];
    assign pipeline_fill_level = stage_valid[0] + stage_valid[1] + stage_valid[2] + stage_valid[3] + stage_valid[4];
    assign matrix_d = pipe_acc[4];

    integer i, j, k;
    always @(posedge clk) begin
        if (reset) begin
            stage_valid <= 5'b00000;
            for (i = 0; i < 5; i++) begin
                pipe_tag[i] <= 0;
                for (j = 0; j < 4; j++) begin
                    for (k = 0; k < 4; k++) begin
                        pipe_a[i][j][k] <= 0;
                        pipe_b[i][j][k] <= 0;
                        pipe_acc[i][j][k] <= 0;
                    end
                end
            end
        end else begin
            // Stage 0: Input latch
            if (start && ready) begin
                stage_valid[0] <= 1;
                pipe_a[0] <= matrix_a;
                pipe_b[0] <= matrix_b;
                pipe_acc[0] <= matrix_c;
                pipe_tag[0] <= tag_in;
            end else begin
                stage_valid[0] <= 0;
            end

            // Stage 1 (row 0 computation)
            if (stage_valid[0]) begin
                for (j = 0; j < 4; j++) begin
                    automatic logic signed [31:0] dot = 0;
                    for (k = 0; k < 4; k++) begin
                        dot = dot + pipe_a[0][0][k] * pipe_b[0][k][j];
                    end
                    pipe_acc[1][0][j] <= pipe_acc[0][0][j] + dot;
                end
                pipe_acc[1][1] <= pipe_acc[0][1];
                pipe_acc[1][2] <= pipe_acc[0][2];
                pipe_acc[1][3] <= pipe_acc[0][3];
                
                pipe_a[1] <= pipe_a[0];
                pipe_b[1] <= pipe_b[0];
                pipe_tag[1] <= pipe_tag[0];
                stage_valid[1] <= 1;
            end else begin
                stage_valid[1] <= 0;
            end

            // Stage 2 (row 1 computation)
            if (stage_valid[1]) begin
                for (j = 0; j < 4; j++) begin
                    automatic logic signed [31:0] dot = 0;
                    for (k = 0; k < 4; k++) begin
                        dot = dot + pipe_a[1][1][k] * pipe_b[1][k][j];
                    end
                    pipe_acc[2][1][j] <= pipe_acc[1][1][j] + dot;
                end
                pipe_acc[2][0] <= pipe_acc[1][0]; // propagate row 0
                pipe_acc[2][2] <= pipe_acc[1][2];
                pipe_acc[2][3] <= pipe_acc[1][3];
                
                pipe_a[2] <= pipe_a[1];
                pipe_b[2] <= pipe_b[1];
                pipe_tag[2] <= pipe_tag[1];
                stage_valid[2] <= 1;
            end else begin
                stage_valid[2] <= 0;
            end

            // Stage 3 (row 2 computation)
            if (stage_valid[2]) begin
                for (j = 0; j < 4; j++) begin
                    automatic logic signed [31:0] dot = 0;
                    for (k = 0; k < 4; k++) begin
                        dot = dot + pipe_a[2][2][k] * pipe_b[2][k][j];
                    end
                    pipe_acc[3][2][j] <= pipe_acc[2][2][j] + dot;
                end
                pipe_acc[3][0] <= pipe_acc[2][0]; // propagate row 0
                pipe_acc[3][1] <= pipe_acc[2][1]; // propagate row 1
                pipe_acc[3][3] <= pipe_acc[2][3];
                
                pipe_a[3] <= pipe_a[2];
                pipe_b[3] <= pipe_b[2];
                pipe_tag[3] <= pipe_tag[2];
                stage_valid[3] <= 1;
            end else begin
                stage_valid[3] <= 0;
            end

            // Stage 4 (row 3 computation)
            if (stage_valid[3]) begin
                for (j = 0; j < 4; j++) begin
                    automatic logic signed [31:0] dot = 0;
                    for (k = 0; k < 4; k++) begin
                        dot = dot + pipe_a[3][3][k] * pipe_b[3][k][j];
                    end
                    pipe_acc[4][3][j] <= pipe_acc[3][3][j] + dot;
                end
                pipe_acc[4][0] <= pipe_acc[3][0]; // propagate row 0
                pipe_acc[4][1] <= pipe_acc[3][1]; // propagate row 1
                pipe_acc[4][2] <= pipe_acc[3][2]; // propagate row 2
                
                pipe_a[4] <= pipe_a[3];
                pipe_b[4] <= pipe_b[3];
                pipe_tag[4] <= pipe_tag[3];
                stage_valid[4] <= 1;
            end else begin
                stage_valid[4] <= 0;
            end
        end
    end
`ifdef DEBUG
    reg [31:0] debug_cycle;
    always @(posedge clk) begin
        if (reset) debug_cycle <= 0;
        else debug_cycle <= debug_cycle + 1;
    end
    always @(posedge clk) begin
        if (start) begin
            $display("[T_UNIT] Cycle %d START: ready=%b start=%b tag=%d a0=%h b0=%h c0=%h",
                     debug_cycle, ready, start, tag_in, matrix_a[0][0], matrix_b[0][0], matrix_c[0][0]);
        end
        if (|stage_valid) begin
            $display("[T_UNIT] Cycle %d PIPELINE: valid=%b tags=%d %d %d %d %d done=%b acc0_0=%h result0_0=%h",
                     debug_cycle, stage_valid, pipe_tag[0], pipe_tag[1], pipe_tag[2], pipe_tag[3], pipe_tag[4],
                     done, pipe_acc[0][0][0], matrix_d[0][0]);
        end
    end
`endif
endmodule
