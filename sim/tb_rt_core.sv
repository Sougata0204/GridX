`timescale 1ns/1ps
module tb_rt_core;

    reg clk;
    reg reset;
    reg start;
    reg signed [3:0][3:0][15:0] matrix_a;
    reg signed [3:0][3:0][15:0] matrix_b;
    reg signed [3:0][3:0][31:0] matrix_c;
    reg [3:0] tag_in;

    wire ready, done;
    wire signed [3:0][3:0][31:0] matrix_d;
    wire [3:0] tag_out;
    wire busy;
    wire [2:0] pipeline_fill_level;

    rt_core dut(.*);

    initial begin
        clk = 1;
        forever #5 clk = ~clk;
    end

    task tick(input integer n);
        integer i;
        for (i=0; i<n; i=i+1) @(posedge clk);
    endtask

    integer failures = 0;
    task assert_eq(input integer a, input integer b, input string msg);
        if (a !== b) begin
            $display("ASSERTION FAILED: %s (Expected %0d, Got %0d)", msg, b, a);
            failures = failures + 1;
        end
    endtask

    initial begin
        $dumpfile("build/rt_core.vcd");
        $dumpvars(0, tb_rt_core);
        reset = 1;
        start = 0;
        tag_in = 0;
        matrix_a = 0;
        matrix_b = 0;
        matrix_c = 0;

        tick(4);
        reset = 0;
        $display("[rt_core] Starting Hardware AABB Ray-Box tests...");

        matrix_a[0][0] = 0;
        matrix_a[0][1] = 0;
        matrix_a[0][2] = -256;

        matrix_a[1][0] = 32767;
        matrix_a[1][1] = 32767;
        matrix_a[1][2] = 256;

        matrix_b[0][0] = -256;
        matrix_b[0][1] = -256;
        matrix_b[0][2] = -256;

        matrix_b[1][0] = 256;
        matrix_b[1][1] = 256;
        matrix_b[1][2] = 256;

        start = 1;
        tag_in = 1;
        tick(1);
        start = 0;

        tick(3);
        #1;

        assert_eq(done, 1, "Done flag should be 1 after 4 cycles");
        assert_eq(tag_out, 1, "Tag out should match 1");
        assert_eq(matrix_d[0][0], 1, "Hit flag should be true (1) for direct hit");
        assert_eq(matrix_d[0][1], 0, "Wait, t_min.z = (minZ - orgZ) * invDz = (-256 - -256)*256 = 0");

        tick(2);

        matrix_a[0][0] = 1024;
        matrix_a[0][1] = 1024;
        matrix_a[0][2] = 0;

        start = 1;
        tag_in = 5;
        tick(1);
        start = 0;

        tick(3);
        #1;
        assert_eq(done, 1, "Done flag should be 1 after 4 cycles");
        assert_eq(tag_out, 5, "Tag out should match 5");
        assert_eq(matrix_d[0][0], 0, "Hit flag should be false (0) for complete miss");

        if (failures == 0) $display("PASS\n");
        $finish;
    end
endmodule
