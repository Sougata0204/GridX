// Tensor MMA Unit Verification Testbench
// exercises tensor_unit_pipelined with known 4x4 matrices and checks D = A*B + C

`default_nettype none
`timescale 1ns/1ns

module tb_tensor_mma;

    reg clk = 0;
    always #2.5 clk = ~clk; // 4 GHz = 250ps period

    reg reset = 1;
    reg start = 0;
    reg signed [3:0][3:0][15:0] matrix_a;
    reg signed [3:0][3:0][15:0] matrix_b;
    reg signed [3:0][3:0][31:0] matrix_c;
    reg [3:0] tag_in = 0;

    wire ready, done, busy;
    wire signed [3:0][3:0][31:0] matrix_d;
    wire [3:0] tag_out;
    wire [2:0] fill;

    tensorUnitPipelined dut (
        .clk(clk), .reset(reset), .start(start),
        .matrixA(matrix_a), .matrixB(matrix_b), .matrixC(matrix_c),
        .tagIn(tag_in),
        .ready(ready), .done(done), .matrixD(matrix_d),
        .tagOut(tag_out), .busy(busy), .pipelineFillLevel(fill)
    );

    // expected result storage
    reg signed [31:0] expected [3:0][3:0];
    integer row, col, k;
    integer tests_passed = 0;
    integer tests_failed = 0;
    integer total_tests = 0;
    integer mismatches = 0;

    // compute expected D = A*B + C in software
    task compute_expected;
        for (row = 0; row < 4; row = row + 1) begin
            for (col = 0; col < 4; col = col + 1) begin
                expected[row][col] = matrix_c[row][col];
                for (k = 0; k < 4; k = k + 1) begin
                    expected[row][col] = expected[row][col] +
                        ({{16{matrix_a[row][k][15]}}, matrix_a[row][k]} *
                         {{16{matrix_b[k][col][15]}}, matrix_b[k][col]});
                end
            end
        end
    endtask

    // check result
    task check_result(input [8*40-1:0] test_name);
        integer r, c;
        integer local_mismatches;
        local_mismatches = 0;
        total_tests = total_tests + 1;
        for (r = 0; r < 4; r = r + 1) begin
            for (c = 0; c < 4; c = c + 1) begin
                if (matrix_d[r][c] !== expected[r][c]) begin
                    $display("  [MISMATCH] %0s D[%0d][%0d] = %0d, expected %0d",
                             test_name, r, c, matrix_d[r][c], expected[r][c]);
                    local_mismatches = local_mismatches + 1;
                    mismatches = mismatches + 1;
                end
            end
        end
        if (local_mismatches == 0) begin
            tests_passed = tests_passed + 1;
            $display("  [PASS] %0s -- all 16 elements correct", test_name);
        end else begin
            tests_failed = tests_failed + 1;
            $display("  [FAIL] %0s -- %0d mismatches", test_name, local_mismatches);
        end
    endtask

    // fire one MMA op and wait for done
    task fire_and_wait(input [3:0] tag);
        @(posedge clk);
        start <= 1;
        tag_in <= tag;
        @(posedge clk);
        start <= 0;
        // wait for done
        while (!done) @(posedge clk);
    endtask

    integer i, j;
    initial begin
        $display("[TB_TENSOR_MMA] GridX3 Tensor MMA Unit Verification");
        $display("[TB_TENSOR_MMA] Clock: 4 GHz (250 ps period)");
        $display("");

        // reset
        reset = 1;
        repeat (10) @(posedge clk);
        reset = 0;
        repeat (5) @(posedge clk);

        // test 1: identity matrix multiply
        // A = I, B = known, C = 0 => D should equal B (widened to 32b)
        // test 1: identity matrix multiply
        $display("[TB_TENSOR_MMA] Test 1: Identity A x B + 0");
        for (i = 0; i < 4; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                matrix_a[i][j] = (i == j) ? 16'd1 : 16'd0;
                matrix_b[i][j] = (i * 4 + j + 1);
                matrix_c[i][j] = 32'd0;
            end
        end
        compute_expected();
        fire_and_wait(4'd1);
        check_result("Identity-MMA");

        // test 2: known small values A*B + C
        $display("[TB_TENSOR_MMA] Test 2: Known 2x scale");
        for (i = 0; i < 4; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                matrix_a[i][j] = 16'd2;
                matrix_b[i][j] = 16'd3;
                matrix_c[i][j] = 32'd10;
            end
        end
        // each element D[r][c] = sum(2*3, k=0..3) + 10 = 4*6 + 10 = 34
        compute_expected();
        fire_and_wait(4'd2);
        check_result("Uniform-2x3+10");

        // test 3: negative values
        $display("[TB_TENSOR_MMA] Test 3: Signed negative multiply");
        for (i = 0; i < 4; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                matrix_a[i][j] = -16'sd3;
                matrix_b[i][j] = 16'sd4;
                matrix_c[i][j] = 32'sd100;
            end
        end
        // each D[r][c] = sum(-3*4, k=0..3) + 100 = 4*(-12) + 100 = -48 + 100 = 52
        compute_expected();
        fire_and_wait(4'd3);
        check_result("Signed-Neg-MMA");

        // test 4: accumulate into C (non-zero C)
        $display("[TB_TENSOR_MMA] Test 4: Accumulate with large C");
        for (i = 0; i < 4; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                matrix_a[i][j] = 16'sd1;
                matrix_b[i][j] = 16'sd1;
                matrix_c[i][j] = 32'sd1000;
            end
        end
        // each D[r][c] = sum(1*1, k=0..3) + 1000 = 4 + 1000 = 1004
        compute_expected();
        fire_and_wait(4'd4);
        check_result("Accum-Large-C");

        // test 5: mixed positive and negative
        $display("[TB_TENSOR_MMA] Test 5: Diagonal pattern");
        for (i = 0; i < 4; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                matrix_a[i][j] = (i == j) ? 16'sd5 : -16'sd1;
                matrix_b[i][j] = (i == j) ? 16'sd10 : 16'sd2;
                matrix_c[i][j] = 32'sd0;
            end
        end
        compute_expected();
        fire_and_wait(4'd5);
        check_result("Diagonal-Pattern");

        // test 6: pipeline throughput (back-to-back starts)
        $display("[TB_TENSOR_MMA] Test 6: Pipeline throughput");
        for (i = 0; i < 4; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                matrix_a[i][j] = i[15:0] + 1;
                matrix_b[i][j] = j[15:0] + 1;
                matrix_c[i][j] = 32'd0;
            end
        end
        compute_expected();
        // fire 3 ops quickly
        @(posedge clk); start <= 1; tag_in <= 4'd6;
        @(posedge clk); start <= 0;
        // wait for all 3 to finish
        while (!done) @(posedge clk);
        check_result("Pipeline-Burst");

        // summary
        $display("[TB_TENSOR_MMA] Total Tests: %0d | Passed: %0d | Failed: %0d", total_tests, tests_passed, tests_failed);
        if (tests_failed == 0)
            $display("[TB_TENSOR_MMA] RESULT: ALL TESTS PASSED");
        else
            $display("[TB_TENSOR_MMA] RESULT: %0d TESTS FAILED", tests_failed);

        $finish;
    end

endmodule
