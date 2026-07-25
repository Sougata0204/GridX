`timescale 1ns/1ps
module tb_simt;
    reg clk;
    reg reset;
    reg start;
    reg kernel_running;
    reg [3:0] tensor_done;
    reg power_sleep_req;
    reg [63:0] decoded_packet;
    reg [63:0] latched_packet;
    reg [2:0] fetcher_state;
    reg [1:0] lsu_state [63:0];
    wire [7:0] current_pc;
    reg [7:0] next_pc [63:0];
    wire [3:0] core_state;
    wire [3:0] warp_state [3:0];
    wire [1:0] active_warp_id;
    wire [3:0] warp_issue_enable;
    wire [3:0] warp_stalled_on_reg;
    wire [3:0] warp_stalled_on_mem;
    wire tracker_enqueue_valid;
    wire [3:0] tracker_enqueue_dest_reg;
    wire [15:0] tracker_enqueue_tag;
    reg tracker_dequeue_valid;
    reg [3:0] tracker_dequeued_dest_reg;
    reg tracker_dequeue_found;
    reg [3:0] tracker_warp_has_pending;
    reg [3:0] tracker_warp_queue_full;
    reg sb_hazard;
    reg [1:0] sb_hazard_type;
    wire perf_stall_mem_pulse;
    wire perf_stall_shared_pulse;
    wire perf_stall_tensor_pulse;
    wire perf_stall_dep_pulse;
    wire perf_stall_ready_pulse;
    reg [3:0] warp_early_wakeup;
    wire [15:0] active_mask;
    wire done;

    scheduler #(
        .THREADS_PER_BLOCK(64),
        .WARPS_PER_CORE(4),
        .MAX_OUTSTANDING_LOADS(4),
        .NUM_REGS(16)
    ) dut (.*);

    initial begin
        clk = 1;
        forever #5 clk = ~clk;
    end

    integer failures = 0;

    task tick(input integer n);
        integer i;
        for (i=0; i<n; i=i+1) begin
            @(posedge clk);
            $display("Time %0t: state=%0d pc=%0d mask=%0h (idx=%0d)", $time, dut.warp_state[0], dut.warp_pc[0], dut.warp_active_mask[0], dut.active_warp_id);
        end
    endtask

    task assert_eq(input integer a, input integer b, input string msg);
        if (a !== b) begin
            $display("ASSERTION FAILED: %s (Expected %0x, Got %0x)", msg, b, a);
            failures = failures + 1;
        end
    endtask

    integer i;

    initial begin
        $dumpfile("build/simt.vcd");
        $dumpvars(0, tb_simt);
        reset = 1;
        start = 0;
        kernel_running = 0;
        tensor_done = 0;
        power_sleep_req = 0;
        decoded_packet = 0;
        latched_packet = 0;
        fetcher_state = 0;
        for (i=0; i<64; i=i+1) lsu_state[i] = 0;
        for (i=0; i<64; i=i+1) next_pc[i] = 0;
        tracker_dequeue_valid = 0;
        tracker_dequeued_dest_reg = 0;
        tracker_dequeue_found = 0;
        tracker_warp_has_pending = 0;
        tracker_warp_queue_full = 0;
        sb_hazard = 0;
        sb_hazard_type = 0;
        warp_early_wakeup = 0;

        tick(4);
        reset = 0;
        kernel_running = 1;

        $display("[simt] Starting SIMT Divergence Test...");

        start = 1;
        tick(1);
        start = 0;

        tick(1);
        fetcher_state = 3'b010;
        tick(1);

        decoded_packet = 64'h0;
        tick(1);
        tick(1);

        for (i=0; i<8; i=i+1) next_pc[i] = 10;
        for (i=8; i<16; i=i+1) next_pc[i] = 20;

        tick(1);
        tick(1);
        #1;

        assert_eq(active_mask, 16'h00FF, "Wait! Active mask should be bottom 8 lanes");
        assert_eq(current_pc, 10, "PC should follow taken path");

        fetcher_state = 3'b010;
        tick(1);
        decoded_packet = 64'h0;
        decoded_packet[49] = 1'b1;
        latched_packet[49] = 1'b1;
        tick(1);
        tick(1);
        tick(1);
        tick(1);
        #1;

        assert_eq(active_mask, 16'hFF00, "Active mask should be popped top 8 lanes");
        assert_eq(current_pc, 20, "PC should follow fallthrough path");

        if (failures == 0) $display("PASS\n");
        $finish;
    end
endmodule
