`timescale 1ns/1ps
module tb_ch;
    reg clk;
    reg rst_n;
    reg [7:0] ch_runnable_i;
    reg [15:0] ch_priority_i;
    reg [7:0] ch_block_done_i;
    reg [31:0] dcr_timeslice_p0_i;
    reg [31:0] dcr_timeslice_p1_i;
    reg [31:0] dcr_timeslice_p2_i;
    reg [31:0] dcr_timeslice_p3_i;
    reg [31:0] dcr_aging_thresh_i;
    wire [7:0] ch_running_o;
    wire [15:0] ch_state_o;
    wire [7:0] ch_preempt_o;
    wire [7:0] ch_aged_promotion_o;
    wire all_channels_idle_o;
    wire [2:0] active_channel_o;

    channel_scheduler dut (.*);

    initial begin
        clk = 1;
        forever #5 clk = ~clk;
    end

    integer failures = 0;

    task tick(input integer n);
        integer i;
        for (i=0; i<n; i=i+1) @(posedge clk);
    endtask

    task assert_eq(input integer a, input integer b, input string msg);
        if (a !== b) begin
            $display("ASSERTION FAILED: %s (Expected %0d, Got %0d)", msg, b, a);
            failures = failures + 1;
        end
    endtask

    initial begin
        $dumpfile("build/ch.vcd");
        $dumpvars(0, tb_ch);

        rst_n = 0;
        ch_runnable_i = 0;
        ch_priority_i = 0;
        ch_block_done_i = 0;
        dcr_timeslice_p0_i = 256;
        dcr_timeslice_p1_i = 512;
        dcr_timeslice_p2_i = 1024;
        dcr_timeslice_p3_i = 2048;
        dcr_aging_thresh_i = 4096;
        tick(4);
        rst_n = 1;

        $display("[ch] test_ch_priority_preemption ...");
        dcr_timeslice_p2_i = 10000;
        dcr_timeslice_p0_i = 256;
        ch_runnable_i = 8'b00000001;
        ch_priority_i = 16'b0000000000000010;
        tick(5);
        assert_eq(ch_running_o & 1, 1, "ch0 should be running");

        ch_runnable_i = 8'b00000011;
        ch_priority_i = 16'b0000000000000010;
        tick(5);
        assert_eq(ch_running_o & 1, 0, "ch0 must be preempted by ch1");
        assert_eq((ch_running_o & 2) >> 1, 1, "ch1 must be running after preempting ch0");

        if (failures == 0) $display("PASS\n");
        $finish;
    end
endmodule
