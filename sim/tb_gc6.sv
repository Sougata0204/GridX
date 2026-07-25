`timescale 1ns/1ps
module tb_gc6;
    reg clk;
    reg rst_n;
    reg dcr_enter_req_i;
    reg dcr_exit_req_i;
    reg dcr_retention_i;
    reg [31:0] dcr_watchdog_thresh_i;
    reg all_pipelines_empty_i;
    reg [6:0] outstanding_mem_i;
    reg [3:0] tensor_inflight_i;
    wire context_save_req_o;
    reg context_save_ack_i;
    wire context_restore_req_o;
    reg context_restore_ack_i;
    reg pll_lock_i;
    wire power_gate_enable_o;
    wire clock_gate_enable_o;
    wire retention_enable_o;
    wire [2:0] gc6_state_o;
    wire gc6_watchdog_fault_o;
    wire gc6_active_o;
    wire gc6_powered_off_o;

    gc6_power_fsm dut (.*);

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

    integer timeout;

    initial begin
        $dumpfile("build/gc6.vcd");
        $dumpvars(0, tb_gc6);

        rst_n = 0;
        dcr_enter_req_i = 0;
        dcr_exit_req_i = 0;
        dcr_retention_i = 0;
        dcr_watchdog_thresh_i = 0;
        all_pipelines_empty_i = 0;
        outstanding_mem_i = 0;
        tensor_inflight_i = 0;
        context_save_ack_i = 0;
        context_restore_ack_i = 0;
        pll_lock_i = 1;
        tick(4);
        rst_n = 1;

        $display("[gc6] test_gc6_basic_entry_exit ...");
        assert_eq(gc6_state_o, 0, "Initial state should be ACTIVE (0)");

        dcr_retention_i = 1;
        dcr_enter_req_i = 1;
        tick(1);
        dcr_enter_req_i = 0;

        timeout = 100;
        while (gc6_state_o !== 1 && timeout > 0) begin tick(1); timeout = timeout - 1; end
        assert_eq(timeout > 0, 1, "Timed out waiting for PRE_SLEEP state");

        context_save_ack_i = 1; tick(1); context_save_ack_i = 0;

        timeout = 50;
        while (gc6_state_o !== 3 && timeout > 0) begin tick(1); timeout = timeout - 1; end
        assert_eq(timeout > 0, 1, "Timed out reaching POWERED_OFF");

        dcr_exit_req_i = 1; tick(1); dcr_exit_req_i = 0;

        timeout = 200;
        while (gc6_state_o !== 5 && timeout > 0) begin tick(1); timeout = timeout - 1; end
        assert_eq(timeout > 0, 1, "Timed out reaching RESTORING");

        context_restore_ack_i = 1; tick(1); context_restore_ack_i = 0;

        timeout = 50;
        while (gc6_state_o !== 0 && timeout > 0) begin tick(1); timeout = timeout - 1; end
        assert_eq(timeout > 0, 1, "Timed out returning to ACTIVE");

        if (failures == 0) $display("PASS\n");
        $finish;
    end
endmodule
