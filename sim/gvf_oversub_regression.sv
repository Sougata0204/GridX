`default_nettype none
`timescale 1ns/1ns

// ╔══════════════════════════════════════════════════════════════════════╗
// ║  Block Oversubscription Regression - Per-Thread Scoreboard v2      ║
// ║  Fixes:                                                            ║
// ║    1. STR field order: {op, rd_unused, rs=addr_reg, rt=data_reg}   ║
// ║    2. Addresses >= 0x8000 to hit external BRAM (testbench-visible) ║
// ║    3. Per-thread address = base + global_tid (unique per thread)    ║
// ║    4. Per-thread scoreboard loop verifies ALL threads executed      ║
// ║  Identity registers (from registers.sv):                           ║
// ║    r0  = zero register (reads always return 0)                     ║
// ║    r13 = block_id (continuously updated)                           ║
// ║    r14 = THREADS_PER_BLOCK (constant = 4)                          ║
// ║    r15 = THREAD_ID (lane index 0..TPB-1, static per thread)        ║
// ╚══════════════════════════════════════════════════════════════════════╝

module gvf_oversub_regression;

    localparam CLK_PERIOD        = 5.0;
    localparam TIMEOUT           = 100_000;
    localparam PMEM_DEPTH        = 256;
    localparam DMEM_DEPTH        = 1024;
    localparam NUM_CORES         = 4;
    localparam THREADS_PER_BLOCK = 4;
    localparam DATA_ADDR_BITS    = 22;
    localparam DATA_BITS         = 8;
    localparam PROG_ADDR_BITS    = 12;
    localparam PROG_BITS         = 16;

    // BRAM base: CONST 0x80 sign-extends to 0xFF80 (>= 0x8000 → external BRAM)
    // BRAM index = addr[9:0] = 0x380 = 896.  Max 64 threads → index 959 < 1024
    localparam [15:0] BRAM_BASE  = 16'hFF80;
    localparam [9:0]  BRAM_IDX   = BRAM_BASE[9:0]; // 0x380 = 896

    localparam [3:0] OP_NOP   = 4'h0, OP_ADD  = 4'h3, OP_SUB  = 4'h4,
                     OP_MUL   = 4'h5, OP_LDR  = 4'h7, OP_STR  = 4'h8,
                     OP_CONST = 4'h9, OP_RET  = 4'hF;

    reg clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    reg rst_n = 0;

    reg        host_wr_en = 0;
    reg [15:0] host_wr_data = 0;
    reg        host_start = 0;
    wire       kernel_done, kernel_fault;
    wire [2:0] kernel_state;
    wire [31:0] perf_hbm_reads, perf_hbm_writes, perf_total_flits;
    wire [31:0] perf_cycle_count, perf_active_cores;
    wire [7:0]  dbg_core_done_sample;
    wire        dbg_mesh_busy;
    reg        pmem_wr_en = 0;
    reg [PROG_ADDR_BITS-1:0] pmem_wr_addr = 0;
    reg [PROG_BITS-1:0]      pmem_wr_data = 0;
    reg        dmem_wr_en = 0, dmem_rd_en = 0;
    reg [DATA_ADDR_BITS-1:0] dmem_wr_addr = 0, dmem_rd_addr = 0;
    reg [DATA_BITS-1:0]      dmem_wr_data = 0;
    wire [DATA_BITS-1:0]     dmem_rd_data;

    gridx_kernel_top #(
        .CUBE_X(2), .CUBE_Y(2), .CUBE_Z(1),
        .PMEM_DEPTH(PMEM_DEPTH), .DMEM_DEPTH(DMEM_DEPTH), .SIM_TIMEOUT_CYCLES(TIMEOUT)
    ) dut (
        .clk_sys(clk), .rst_n(rst_n),
        .host_wr_en(host_wr_en), .host_wr_data(host_wr_data), .host_start(host_start),
        .kernel_done(kernel_done), .kernel_fault(kernel_fault), .kernel_state_o(kernel_state),
        .perf_hbm_reads(perf_hbm_reads), .perf_hbm_writes(perf_hbm_writes),
        .perf_total_flits(perf_total_flits), .perf_cycle_count(perf_cycle_count),
        .perf_active_cores(perf_active_cores),
        .dbg_core_done_sample(dbg_core_done_sample), .dbg_mesh_busy(dbg_mesh_busy),
        .pmem_wr_en(pmem_wr_en), .pmem_wr_addr(pmem_wr_addr), .pmem_wr_data(pmem_wr_data),
        .dmem_wr_en(dmem_wr_en), .dmem_wr_addr(dmem_wr_addr), .dmem_wr_data(dmem_wr_data),
        .dmem_rd_en(dmem_rd_en), .dmem_rd_addr(dmem_rd_addr), .dmem_rd_data(dmem_rd_data)
    );

    // Counters
    integer suite_num = 0;
    integer tests_passed = 0;
    integer tests_failed = 0;
    integer total_assertions = 0;
    integer cycle_cnt = 0;
    integer sb_pass = 0;
    integer sb_fail = 0;

    // Infrastructure
    function [15:0] enc_const(input [3:0] rd, input [7:0] imm);
        enc_const = {OP_CONST, rd, imm};
    endfunction
    function [15:0] enc_rrr(input [3:0] op, rd, rs, rt);
        enc_rrr = {op, rd, rs, rt};
    endfunction

    task automatic gvf_check(input integer pass, input [8*80-1:0] msg);
        total_assertions = total_assertions + 1;
        if (pass) begin
            tests_passed = tests_passed + 1;
            $display("  [PASS] %0s", msg);
        end else begin
            tests_failed = tests_failed + 1;
            $display("  [FAIL] %0s", msg);
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

    task automatic write_pmem(input [PROG_ADDR_BITS-1:0] addr, input [PROG_BITS-1:0] data);
        @(posedge clk); pmem_wr_en <= 1; pmem_wr_addr <= addr; pmem_wr_data <= data;
        @(posedge clk); pmem_wr_en <= 0;
    endtask

    task automatic write_dcr(input [15:0] data);
        @(posedge clk); host_wr_en <= 1; host_wr_data <= data;
        @(posedge clk); host_wr_en <= 0;
    endtask

    task automatic write_dmem(input [DATA_ADDR_BITS-1:0] addr, input [DATA_BITS-1:0] data);
        @(posedge clk); dmem_wr_en <= 1; dmem_wr_addr <= addr; dmem_wr_data <= data;
        @(posedge clk); dmem_wr_en <= 0;
    endtask

    task automatic read_dmem(input [DATA_ADDR_BITS-1:0] addr);
        @(posedge clk); dmem_rd_en <= 1; dmem_rd_addr <= addr;
        @(posedge clk); dmem_rd_en <= 0;
        @(posedge clk); // read latency
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
        end
    endtask

    // Poison BRAM scoreboard region with 0xAA before each test.
    // After kernel, any location still 0xAA means that thread didn't store.
    task automatic poison_bram(input integer num_threads);
        integer i;
        for (i = 0; i < num_threads; i = i + 1) begin
            // BRAM index = (BRAM_BASE + i) & (DMEM_DEPTH-1) = BRAM_IDX + i
            write_dmem({12'b0, BRAM_IDX} + i, 8'hAA);
        end
        repeat(2) @(posedge clk);
    endtask

    // Per-thread ADD-STORE program (CORRECTED)
    // Computes: global_tid = block_id * TPB + thread_id
    // value      = global_tid + 5
    // address    = 0xFF80 + global_tid  (hits external BRAM)
    // Stores:   DMEM[address] = value
    // STR encoding: {OP_STR, rd=unused, rs=addr_reg, rt=data_reg}
    // rs field → register whose VALUE is used as ADDRESS
    // rt field → register whose VALUE is used as DATA
    task automatic load_prog_add_store_v2;
        write_pmem(0, enc_const(4'h1, 8'h80));                   // r1 = 0xFF80 (sign-ext, external BRAM base)
        write_pmem(1, enc_rrr(OP_MUL, 4'h2, 4'hD, 4'hE));       // r2 = r13 * r14 = block_id * TPB
        write_pmem(2, enc_rrr(OP_ADD, 4'h3, 4'h2, 4'hF));       // r3 = r2 + r15 = global_tid
        write_pmem(3, enc_rrr(OP_ADD, 4'h4, 4'h3, 4'h1));       // r4 = global_tid + 0xFF80 = store addr
        write_pmem(4, enc_const(4'h5, 8'h05));                   // r5 = 5
        write_pmem(5, enc_rrr(OP_ADD, 4'h6, 4'h3, 4'h5));       // r6 = global_tid + 5 = store value
        write_pmem(6, {OP_STR, 4'h0, 4'h4, 4'h6});              // STR: DMEM[r4] = r6
        write_pmem(7, {OP_RET, 12'h000});                        // RET
        repeat(2) @(posedge clk);
    endtask

    // Per-thread SAXPY program (CORRECTED)
    // SAXPY: result = a*x + y = 2*3 + 1 = 7 for all threads
    // Per-thread store to unique address for scoreboard verification.
    // ORIGINAL BUG (load_prog_saxpy in gvf.sv / gvf_2d.sv):
    // CONST r0, 2  ← r0 is zero register, writes ignored on read!
    // CONST r1, 0  ← x = 0
    // MUL r2, r0, r1 → 0 * 0 = 0 (r0 reads as 0)
    // STR {rd=3, rs=1, rt=0} → addr=reg[1]=0, data=reg[0]=0
    // → Stores 0 to shared memory addr 0 (not external BRAM)
    // FIX: Use r1-r12 for operands, store to external BRAM >= 0x8000
    task automatic load_prog_saxpy_v2;
        write_pmem(0,  enc_const(4'h1, 8'h02));                  // r1 = 2 (a)
        write_pmem(1,  enc_const(4'h2, 8'h03));                  // r2 = 3 (x)
        write_pmem(2,  enc_const(4'h3, 8'h01));                  // r3 = 1 (y)
        write_pmem(3,  enc_rrr(OP_MUL, 4'h4, 4'h1, 4'h2));      // r4 = a*x = 6
        write_pmem(4,  enc_rrr(OP_ADD, 4'h5, 4'h4, 4'h3));      // r5 = a*x+y = 7 (result)
        write_pmem(5,  enc_const(4'h6, 8'h80));                  // r6 = 0xFF80 (ext BRAM base)
        write_pmem(6,  enc_rrr(OP_MUL, 4'h7, 4'hD, 4'hE));      // r7 = block_id * TPB
        write_pmem(7,  enc_rrr(OP_ADD, 4'h8, 4'h7, 4'hF));      // r8 = global_tid
        write_pmem(8,  enc_rrr(OP_ADD, 4'h9, 4'h6, 4'h8));      // r9 = 0xFF80 + global_tid
        write_pmem(9,  {OP_STR, 4'h0, 4'h9, 4'h5});             // STR: DMEM[r9] = r5 = 7
        write_pmem(10, {OP_RET, 12'h000});                       // RET
        repeat(2) @(posedge clk);
    endtask

    // Per-thread scoreboard verification
    task automatic scoreboard_check(
        input [8*40-1:0] label,
        input integer total_threads,
        input integer expected_fn_is_saxpy  // 0: ADD-STORE (tid+5), 1: SAXPY (constant 7)
    );
        integer tid;
        reg [7:0] expected;
        reg [7:0] got;
        sb_pass = 0;
        sb_fail = 0;
        for (tid = 0; tid < total_threads; tid = tid + 1) begin
            read_dmem({12'b0, BRAM_IDX} + tid);
            got = dmem_rd_data;
            if (expected_fn_is_saxpy)
                expected = 8'd7;  // SAXPY: a*x+y = 2*3+1 = 7
            else
                expected = (tid + 5) & 8'hFF;  // ADD-STORE: global_tid + 5
            total_assertions = total_assertions + 1;
                tests_passed = tests_passed + 1;
                sb_pass = sb_pass + 1;
            end else begin
                tests_failed = tests_failed + 1;
                sb_fail = sb_fail + 1;
                $display("  [FAIL] %0s thread %0d: DMEM[%0d] = 0x%02h, expected 0x%02h",
                         label, tid, BRAM_IDX + tid, got, expected);
            end
        end
        if (sb_fail == 0)
            $display("  [PASS] All %0d thread stores verified (sb_pass=%0d)", total_threads, sb_pass);
        else
            $display("  [FAIL] %0d/%0d threads FAILED scoreboard", sb_fail, total_threads);
    endtask

    // Run kernel with full per-thread verification
    task automatic run_verified_kernel(
        input [8*40-1:0] label,
        input integer threads,
        input integer is_saxpy
    );
        integer t_start, t_end;
        integer blocks_expected;
        blocks_expected = (threads + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK;
        suite_num = suite_num + 1;
        $display("");
        $display("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        $display("  Suite %0d: %0s", suite_num, label);
        $display("  Threads=%0d  Blocks=%0d  Cores=%0d  Oversub=%.1fx",
                 threads, blocks_expected, NUM_CORES,
                 1.0 * blocks_expected / NUM_CORES);
        $display("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

        do_reset();
        // Poison BRAM locations so unexecuted threads are detectable
        poison_bram(threads);
        // Load program
        if (is_saxpy)
            load_prog_saxpy_v2();
        else
            load_prog_add_store_v2();
        // Configure thread count
        write_dcr(threads[15:0]);
        repeat(5) @(posedge clk);

        // Launch and wait
        t_start = perf_cycle_count;
        launch_kernel();
        wait_kernel(TIMEOUT);
        t_end = perf_cycle_count;

        // Basic completion checks
        gvf_check(kernel_done,   "kernel_done asserted");
        gvf_check(!kernel_fault, "no kernel_fault");
        gvf_check(cycle_cnt < TIMEOUT, "completed before timeout");

        // Per-thread scoreboard
        if (kernel_done && !kernel_fault) begin
            scoreboard_check(label, threads, is_saxpy);
        end else begin
            $display("  [SKIP] Scoreboard skipped — kernel did not complete normally");
        end

        $display("  Cycles=%0d", t_end - t_start);
        $display("[CSV-OVERSUB] %0s,%0d,%0d,%0d,%0d,%0d,%0d",
                 label, threads, blocks_expected, NUM_CORES,
                 t_end - t_start, sb_pass, sb_fail);
    endtask

    // MAIN TEST SEQUENCE
    initial begin
        $display("");
        $display("╔══════════════════════════════════════════════════════════════════╗");
        $display("║  Block Oversubscription Regression v2 — Per-Thread Scoreboard  ║");
        $display("║  CUBE_Z=1 (4 cores)  THREADS_PER_BLOCK=4                      ║");
        $display("║  Program: ADD-STORE (global_tid + 5) to ext BRAM               ║");
        $display("╚══════════════════════════════════════════════════════════════════╝");

        // ADD-STORE ladder: 1×, 1×+1, 2×, 4× oversubscription

        // Case 1: blocks == NUM_CORES (baseline, no oversubscription)
        // 16 threads / 4 tpb = 4 blocks = 4 cores
        run_verified_kernel("AS-1x-Baseline", 16, 0);

        // Case 2: blocks == NUM_CORES + 1 (smallest oversubscription)
        // 20 threads / 4 tpb = 5 blocks on 4 cores
        run_verified_kernel("AS-1x+1-Edge", 20, 0);

        // Case 3: blocks == 2 × NUM_CORES (original deadlock case)
        // 32 threads / 4 tpb = 8 blocks on 4 cores
        run_verified_kernel("AS-2x-Original", 32, 0);

        // Case 4: blocks == 4 × NUM_CORES (heavy oversubscription)
        // 64 threads / 4 tpb = 16 blocks on 4 cores
        run_verified_kernel("AS-4x-Heavy", 64, 0);

        // SAXPY ladder: same oversubscription levels, different kernel
        $display("");
        $display("╔══════════════════════════════════════════════════════════════════╗");
        $display("║  SAXPY Ladder — Per-Thread Scoreboard (a*x+y = 2*3+1 = 7)     ║");
        $display("╚══════════════════════════════════════════════════════════════════╝");

        run_verified_kernel("SAXPY-1x-Baseline", 16, 1);
        run_verified_kernel("SAXPY-1x+1-Edge", 20, 1);
        run_verified_kernel("SAXPY-2x-Original", 32, 1);
        run_verified_kernel("SAXPY-4x-Heavy", 64, 1);

        // FINAL REPORT
        $display("");
        $display("╔══════════════════════════════════════════════════════════════════╗");
        $display("║  Oversubscription Regression v2 — FINAL REPORT                 ║");
        $display("╠══════════════════════════════════════════════════════════════════╣");
        $display("║  Test Suites           : %4d                                   ║", suite_num);
        $display("║  Total Assertions      : %4d                                   ║", total_assertions);
        $display("║  Passed                : %4d                                   ║", tests_passed);
        $display("║  Failed                : %4d                                   ║", tests_failed);
        if (tests_failed == 0) begin
            $display("║                                                                ║");
            $display("║  ✓ ALL PER-THREAD SCOREBOARD TESTS PASSED                     ║");
        end else begin
            $display("║                                                                ║");
            $display("║  ✗ %0d FAILURES — Review per-thread trace above               ║", tests_failed);
        end
        $display("╚══════════════════════════════════════════════════════════════════╝");

        repeat(10) @(posedge clk);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * TIMEOUT * 20);
        $display("[OVERSUB-REG] GLOBAL TIMEOUT");
        $finish;
    end
endmodule
