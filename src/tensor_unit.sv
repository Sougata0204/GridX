
`default_nettype none
`timescale 1ns/1ns

module tensor_unit (
    input wire clk,
    input wire reset,
    input wire start,
    output reg done,
    output reg busy,
    input wire signed [3:0][3:0][15:0] matrix_a,
    input wire signed [3:0][3:0][15:0] matrix_b,
    input wire signed [3:0][3:0][31:0] matrix_c,
    output reg signed [3:0][3:0][31:0] matrix_d
);
    reg [2:0] cycle_count;
    reg computing;
    reg signed [3:0][3:0][15:0] reg_a;
    reg signed [3:0][3:0][15:0] reg_b;
    reg signed [3:0][3:0][31:0] acc;
    integer i, j, k;
    always @(posedge clk) begin
        if (reset) begin
            cycle_count <= 0;
            computing <= 0;
            done <= 0;
            busy <= 0;
            for (i=0; i<4; i=i+1) begin
                for (j=0; j<4; j=j+1) begin
                    matrix_d[i][j] <= 0;
                    acc[i][j] <= 0;
                    reg_a[i][j] <= 0;
                    reg_b[i][j] <= 0;
                end
            end
        end else begin
            done <= 0;
            if (start && !busy) begin
                reg_a <= matrix_a;
                reg_b <= matrix_b;
                acc <= matrix_c;
                computing <= 1;
                busy <= 1;
                cycle_count <= 0;
            end else if (computing) begin
                if (cycle_count < 4) begin
                    for (j=0; j<4; j=j+1) begin
                       reg signed [31:0] dot_prod;
                       dot_prod = 0;
                       for (k=0; k<4; k=k+1) begin
                           dot_prod = dot_prod + ({{16{reg_a[cycle_count][k][15]}}, reg_a[cycle_count][k]} * {{16{reg_b[k][j][15]}}, reg_b[k][j]});
                       end
                       matrix_d[cycle_count][j] <= dot_prod + acc[cycle_count][j];
                    end
                    cycle_count <= cycle_count + 1;
                end else begin
                    computing <= 0;
                    busy <= 0;
                    done <= 1;
                end
            end
        end
    end
endmodule
