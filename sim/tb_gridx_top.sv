`default_nettype none
`timescale 1ns/1ns

// Top-level GridX testbench validating full SoC integration with host interface and memory subsystem.
module tb_gridx_top;

    localparam CLK_PERIOD    = 5.0;
    localparam TIMEOUT       = 200_000;
    localparam PMEM_DEPTH    = 1024;
    localparam DMEM_DEPTH    = 8192;

    reg clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg rst_n = 0;

    reg        host_wr_en   = 0;
    reg [15:0] host_wr_data = 0;
    reg        host_start   = 0;

    wire       kernel_done, kernel_fault;
    wire [2:0] kernel_state;
    wire [31:0] perf_hbm_reads, perf_hbm_writes, perf_total_flits;
    wire [31:0] perf_cycle_count, perf_active_cores;
    wire [7:0]  dbg_core_done_sample;
    wire        dbg_mesh_busy;

    reg        pmem_wr_en   = 0;
    reg [11:0] pmem_wr_addr = 0;
    reg [15:0] pmem_wr_data = 0;

    reg        dmem_wr_en   = 0;
    reg        dmem_rd_en   = 0;
    reg [21:0] dmem_wr_addr = 0;
    reg [21:0] dmem_rd_addr = 0;
    reg [7:0]  dmem_wr_data = 0;
    wire [7:0] dmem_rd_data;

    gridxKernelTop #(
        .PMEM_DEPTH        (PMEM_DEPTH),
        .DMEM_DEPTH        (DMEM_DEPTH),
        .SIM_TIMEOUT_CYCLES(TIMEOUT)
    ) dut (
        .clk_sys       (clk),
        .rst_n         (rst_n),
        .host_wr_en    (host_wr_en),
        .host_wr_data  (host_wr_data),
        .host_start    (host_start),
        .kernel_done   (kernel_done),
        .kernel_fault  (kernel_fault),
        .kernelStateO(kernel_state),
        .perf_hbm_reads   (perf_hbm_reads),
        .perf_hbm_writes  (perf_hbm_writes),
        .perf_total_flits (perf_total_flits),
        .perf_cycle_count (perf_cycle_count),
        .perfActiveCores(perf_active_cores),
        .dbgCoreDoneSample(dbg_core_done_sample),
        .dbg_mesh_busy (dbg_mesh_busy),
        .pmem_wr_en    (pmem_wr_en),
        .pmem_wr_addr  (pmem_wr_addr),
        .pmem_wr_data  (pmem_wr_data),
        .dmem_wr_en    (dmem_wr_en),
        .dmem_wr_addr  (dmem_wr_addr),
        .dmem_wr_data  (dmem_wr_data),
        .dmem_rd_en    (dmem_rd_en),
        .dmem_rd_addr  (dmem_rd_addr),
        .dmem_rd_data  (dmem_rd_data)
    );

    reg [8*16-1:0] state_name;
    always @(*) begin
        case (kernel_state)
            3'd0: state_name = "RESET";
            3'd1: state_name = "CONFIGURED";
            3'd2: state_name = "LAUNCH";
            3'd3: state_name = "RUNNING";
            3'd4: state_name = "DRAIN";
            3'd5: state_name = "DONE";
            3'd6: state_name = "FAULT";
            3'd7: state_name = "PREEMPT";
            default: state_name = "UNKNOWN";
        endcase
    end

    integer test_num     = 0;
    integer tests_passed = 0;
    integer tests_failed = 0;
    integer cycle_cnt    = 0;

    task automatic report(input integer pass, input [8*64-1:0] msg);
        if (pass) begin
            $display("  [PASS] %0s", msg);
            tests_passed = tests_passed + 1;
        end else begin
            $display("  [FAIL] %0s", msg);
            tests_failed = tests_failed + 1;
        end
    endtask

    task automatic do_reset;
        rst_n = 0;
        host_wr_en = 0; host_start = 0; host_wr_data = 0;
        pmem_wr_en = 0; pmem_wr_addr = 0; pmem_wr_data = 0;
        dmem_wr_en = 0; dmem_wr_addr = 0; dmem_wr_data = 0;
        dmem_rd_en = 0; dmem_rd_addr = 0;
        repeat (20) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);
    endtask

    task automatic write_pmem_word(input [11:0] addr, input [15:0] data);
        @(posedge clk);
        pmem_wr_en <= 1; pmem_wr_addr <= addr; pmem_wr_data <= data;
        @(posedge clk);
        pmem_wr_en <= 0;
    endtask

    task automatic write_dcr_word(input [15:0] data);
        @(posedge clk);
        host_wr_en <= 1; host_wr_data <= data;
        @(posedge clk);
        host_wr_en <= 0;
    endtask

    task automatic write_dmem_byte(input [21:0] addr, input [7:0] data);
        @(posedge clk);
        dmem_wr_en <= 1; dmem_wr_addr <= addr; dmem_wr_data <= data;
        @(posedge clk);
        dmem_wr_en <= 0;
    endtask

    task automatic read_dmem_byte(input [21:0] addr);
        @(posedge clk);
        dmem_rd_en <= 1; dmem_rd_addr <= addr;
        @(posedge clk);
        dmem_rd_en <= 0;
        @(posedge clk);
    endtask

    task automatic launch_kernel;
        @(posedge clk); host_start <= 1;
        @(posedge clk); host_start <= 0;
    endtask

    task automatic wait_kernel(input integer max_cycles);
        cycle_cnt = 0;
        while (!kernel_done && !kernel_fault && cycle_cnt < max_cycles) begin
            @(posedge clk);
            cycle_cnt = cycle_cnt + 1;
            if (cycle_cnt % 50000 == 0)
                $display("    ... cycle %0d: state=%0s active=%0d",
                         perf_cycle_count, state_name, perf_active_cores);
        end
    endtask

    task automatic load_saxpy_kernel;
        write_pmem_word(12'h000, 16'h9002);
        write_pmem_word(12'h001, 16'h9100);
        write_pmem_word(12'h002, 16'h5201);
        write_pmem_word(12'h003, 16'h3321);
        write_pmem_word(12'h004, 16'h8310);
        write_pmem_word(12'h005, 16'hF000);
        repeat (3) @(posedge clk);
    endtask

    initial begin
        $display("");
        $display("????????????????????????????????????????????????????????????");
        $display("?       GridX? ? 3D GPU SoC Unified Test Suite           ?");
        $display("?  Architecture: %0d?%0d?%0d = %0d cores",
                 dut.CUBE_X, dut.CUBE_Y, dut.CUBE_Z, dut.NUM_CORES);
        $display("?  Threads/Block: %0d | Warps/Core: %0d",
                 dut.THREADS_PER_BLOCK, dut.WARPS_PER_CORE);
        $display("????????????????????????????????????????????????????????????");
        $display("");

        test_num = 1;
        $display("?? Test %0d: Reset & Init ??", test_num);
        do_reset();
        report(kernel_state == 3'd0, "kernel_state = RESET after reset");
        report(!kernel_done,         "kernel_done = 0 after reset");
        report(!kernel_fault,        "kernel_fault = 0 after reset");
        report(perf_cycle_count > 0, "cycle_counter running");
        report(dmem_rd_data == 8'd0, "dmem_rd_data = 0 (not X)");

        test_num = 2;
        $display("?? Test %0d: DCR Configuration ??", test_num);
        write_dcr_word(16'd4);
        repeat (5) @(posedge clk);
        report(kernel_state == 3'd1, "kernel_state = CONFIGURED after DCR");

        test_num = 3;
        $display("?? Test %0d: SAXPY Kernel (4 threads) ??", test_num);
        do_reset();
        load_saxpy_kernel();
        write_dcr_word(16'd4);
        repeat (5) @(posedge clk);

        $display("    Launching kernel...");
        launch_kernel();
        wait_kernel(TIMEOUT);

        report(kernel_done,  "Kernel completed (DONE)");
        report(!kernel_fault, "No fault");
        $display("    Cycles: %0d | HBM rd: %0d wr: %0d",
                 perf_cycle_count, perf_hbm_reads, perf_hbm_writes);

        test_num = 4;
        $display("?? Test %0d: Data Memory Readback ??", test_num);
        read_dmem_byte(22'd0);
        $display("    DMEM[0] = 0x%02h", dmem_rd_data);

        test_num = 5;
        $display("?? Test %0d: Multi-Block Dispatch (8 threads) ??", test_num);
        do_reset();
        load_saxpy_kernel();
        write_dcr_word(16'd8);
        repeat (5) @(posedge clk);

        launch_kernel();
        wait_kernel(TIMEOUT);

        report(kernel_done,   "Multi-block kernel completed");
        report(!kernel_fault, "No fault on multi-block");
        $display("    Cycles: %0d | Active: %0d",
                 perf_cycle_count, perf_active_cores);

        $display("");
        $display("????????????????????????????????????????????????????????????");
        if (tests_failed == 0) begin
            $display("?  ? ALL %0d TESTS PASSED", tests_passed);
        end else begin
            $display("?  ? %0d PASSED, %0d FAILED", tests_passed, tests_failed);
        end
        $display("????????????????????????????????????????????????????????????");
        $display("");

        repeat (10) @(posedge clk);
        $finish;
    end

endmodule
