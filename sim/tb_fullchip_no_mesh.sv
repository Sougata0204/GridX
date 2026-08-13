`default_nettype none
`timescale 1ns/1ns

// ╔══════════════════════════════════════════════════════════════════════╗
// ║  GridX 2×2×2 Full Chip Verification (Without MemoryMesh)           ║
// ║  Cores + Local BRAM + HBM3 — 250MHz per-layer clocks              ║
// ╚══════════════════════════════════════════════════════════════════════╝

module tb_fullchip_no_mesh;

    localparam CLK_PERIOD   = 4.0;   // 250 MHz
    localparam TIMEOUT      = 50_000;
    localparam CUBE_X       = 2;
    localparam CUBE_Y       = 2;
    localparam CUBE_Z       = 2;
    localparam NUM_CORES    = 8;

    // ISA Opcodes
    localparam [3:0] OP_NOP   = 4'h0, OP_BR   = 4'h1, OP_CMP  = 4'h2,
                     OP_ADD   = 4'h3, OP_SUB  = 4'h4, OP_MUL  = 4'h5,
                     OP_DIV   = 4'h6, OP_LDR  = 4'h7, OP_STR  = 4'h8,
                     OP_CONST = 4'h9, OP_TLD  = 4'hA, OP_TST  = 4'hB,
                     OP_DMA   = 4'hC, OP_BAR  = 4'hD, OP_TMMA = 4'hE,
                     OP_RET   = 4'hF;

    // Kernel FSM states
    localparam [2:0] K_RESET=0, K_CONFIG=1, K_LAUNCH=2, K_RUNNING=3,
                     K_DRAIN=4, K_DONE=5, K_FAULT=6;

    // ═════════════════════════════════════════════════════════════
    //  CLOCKS & RESET
    // ═════════════════════════════════════════════════════════════
    reg clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    reg [CUBE_Z-1:0] clk_layer;
    initial begin
        clk_layer = 0;
        fork
            forever #(CLK_PERIOD/2) clk_layer[0] = ~clk_layer[0];
            begin #0.2; forever #(CLK_PERIOD/2) clk_layer[1] = ~clk_layer[1]; end
        join
    end
    reg rst_n = 0;

    // ═════════════════════════════════════════════════════════════
    //  DUT SIGNALS
    // ═════════════════════════════════════════════════════════════
    reg host_wr_en = 0;
    reg [15:0] host_wr_data = 0;
    reg host_start = 0;
    wire kernel_done, kernel_fault;
    wire [2:0] kernel_state;
    wire [31:0] perf_hbm_reads, perf_hbm_writes, perf_total_flits;
    wire [31:0] perf_cycle_count, perf_active_cores;
    wire [7:0] dbg_core_done;
    wire dbg_mesh_busy;
    reg pmem_wr_en = 0;
    reg [11:0] pmem_wr_addr = 0;
    reg [15:0] pmem_wr_data = 0;
    reg dmem_wr_en = 0, dmem_rd_en = 0;
    reg [21:0] dmem_wr_addr = 0, dmem_rd_addr = 0;
    reg [7:0] dmem_wr_data = 0;
    wire [7:0] dmem_rd_data;

    gridxKernelTop #(
        .CUBE_X(CUBE_X), .CUBE_Y(CUBE_Y), .CUBE_Z(CUBE_Z),
        .PMEM_DEPTH(256), .DMEM_DEPTH(1024),
        .THREADS_PER_BLOCK(4), .WARPS_PER_CORE(1),
        .SIM_TIMEOUT_CYCLES(200_000),
        .NUM_HBM_NODES(2)
    ) dut (
        .clkSys(clk), .clkLayer(clk_layer), .rstN(rst_n),
        .hostWrEn(host_wr_en), .hostWrData(host_wr_data), .hostStart(host_start),
        .kernelDone(kernel_done), .kernelFault(kernel_fault), .kernelStateO(kernel_state),
        .perfHbmReads(perf_hbm_reads), .perfHbmWrites(perf_hbm_writes),
        .perfTotalFlits(perf_total_flits), .perfCycleCount(perf_cycle_count),
        .perfActiveCores(perf_active_cores),
        .dbgCoreDoneSample(dbg_core_done), .dbgMeshBusy(dbg_mesh_busy),
        .pmemWrEn(pmem_wr_en), .pmemWrAddr(pmem_wr_addr), .pmemWrData(pmem_wr_data),
        .dmemWrEn(dmem_wr_en), .dmemWrAddr(dmem_wr_addr), .dmemWrData(dmem_wr_data),
        .dmemRdEn(dmem_rd_en), .dmemRdAddr(dmem_rd_addr), .dmemRdData(dmem_rd_data)
    );

    // ═════════════════════════════════════════════════════════════
    //  TEST INFRASTRUCTURE
    // ═════════════════════════════════════════════════════════════
    integer tests_run = 0, tests_pass = 0, tests_fail = 0;
    integer cycle_cnt = 0;

    task automatic gvf_check(input integer pass, input [8*80-1:0] msg);
        tests_run = tests_run + 1;
        if (pass) begin tests_pass = tests_pass + 1; $display("  [PASS] %0s", msg); end
        else      begin tests_fail = tests_fail + 1; $display("  [FAIL] %0s", msg); end
    endtask

    task automatic do_reset;
        rst_n = 0; host_wr_en = 0; host_start = 0;
        pmem_wr_en = 0; dmem_wr_en = 0; dmem_rd_en = 0;
        repeat(20) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
    endtask

    task automatic write_pmem(input [11:0] addr, input [15:0] data);
        @(posedge clk); pmem_wr_en <= 1; pmem_wr_addr <= addr; pmem_wr_data <= data;
        @(posedge clk); pmem_wr_en <= 0;
    endtask

    task automatic write_dcr(input [15:0] data);
        @(posedge clk); host_wr_en <= 1; host_wr_data <= data;
        @(posedge clk); host_wr_en <= 0;
    endtask

    task automatic launch;
        @(posedge clk); host_start <= 1;
        @(posedge clk); host_start <= 0;
    endtask

    task automatic wait_done(input integer max_cyc);
        cycle_cnt = 0;
        while (!kernel_done && !kernel_fault && cycle_cnt < max_cyc) begin
            @(posedge clk); cycle_cnt = cycle_cnt + 1;
        end
    endtask

    function [15:0] enc_rrr(input [3:0] op, rd, rs, rt);
        enc_rrr = {op, rd, rs, rt};
    endfunction
    function [15:0] enc_const(input [3:0] rd, input [7:0] imm);
        enc_const = {OP_CONST, rd, imm};
    endfunction

    // ═════════════════════════════════════════════════════════════
    //  MAIN TEST SEQUENCE
    // ═════════════════════════════════════════════════════════════
    initial begin
        integer i;

        $display("");
        $display("╔══════════════════════════════════════════════════════════════════╗");
        $display("║  GridX 2x2x2 Full Chip Verification (No MemoryMesh)            ║");
        $display("║  8 Cores | HBM3 | 250MHz Per-Layer GALS Clocks                 ║");
        $display("╚══════════════════════════════════════════════════════════════════╝");
        $display("");

        // ═══ STAGE 1: Reset Verification ═══
        $display("═══ STAGE 1: Reset & Infrastructure ═══");
        do_reset();
        gvf_check(kernel_state == K_RESET, "kernel_state = RESET after reset");
        gvf_check(!kernel_done,            "kernel_done = 0 after reset");
        gvf_check(!kernel_fault,           "kernel_fault = 0 after reset");
        gvf_check(clk_layer[0] !== 1'bx,   "Layer 0 clock alive");
        gvf_check(clk_layer[1] !== 1'bx,   "Layer 1 clock alive");

        // ═══ STAGE 2: Single Thread RET ═══
        $display("");
        $display("═══ STAGE 2: Single Thread RET ═══");
        do_reset();
        write_pmem(0, {OP_RET, 12'h000});
        repeat(2) @(posedge clk);
        write_dcr(16'd1);
        repeat(5) @(posedge clk);
        gvf_check(kernel_state == K_CONFIG, "CONFIGURED after DCR");
        launch(); wait_done(TIMEOUT);
        gvf_check(kernel_done,  "1T RET: kernel_done");
        gvf_check(!kernel_fault, "1T RET: no fault");
        $display("  [INFO] 1T RET completed in %0d cycles", cycle_cnt);

        // ═══ STAGE 3: 4-Thread NOP+RET ═══
        $display("");
        $display("═══ STAGE 3: 4-Thread NOP+RET ═══");
        do_reset();
        write_pmem(0, {OP_NOP, 12'h000});
        write_pmem(1, {OP_RET, 12'h000});
        repeat(2) @(posedge clk);
        write_dcr(16'd4); repeat(5) @(posedge clk);
        launch(); wait_done(TIMEOUT);
        gvf_check(kernel_done,  "4T NOP+RET: done");
        gvf_check(!kernel_fault, "4T NOP+RET: no fault");
        $display("  [INFO] 4T NOP+RET in %0d cycles", cycle_cnt);

        // ═══ STAGE 4: ALU Compute (4T) ═══
        $display("");
        $display("═══ STAGE 4: ALU Compute (CONST+ADD+MUL+RET) ═══");
        do_reset();
        write_pmem(0, enc_const(4'h0, 8'h07));         // r0 = 7
        write_pmem(1, enc_const(4'h1, 8'h03));         // r1 = 3
        write_pmem(2, enc_rrr(OP_ADD, 4'h2, 4'h0, 4'h1)); // r2 = 10
        write_pmem(3, enc_rrr(OP_MUL, 4'h3, 4'h2, 4'h1)); // r3 = 30
        write_pmem(4, enc_rrr(OP_SUB, 4'h4, 4'h3, 4'h0)); // r4 = 23
        write_pmem(5, {OP_RET, 12'h000});
        repeat(2) @(posedge clk);
        write_dcr(16'd4); repeat(5) @(posedge clk);
        launch(); wait_done(TIMEOUT);
        gvf_check(kernel_done,  "4T ALU: done");
        gvf_check(!kernel_fault, "4T ALU: no fault");
        $display("  [INFO] 4T ALU in %0d cycles", cycle_cnt);

        // ═══ STAGE 5: Multi-Core (8T = 2 blocks) ═══
        $display("");
        $display("═══ STAGE 5: Multi-Core 8T (2 blocks x 4 threads) ═══");
        do_reset();
        write_pmem(0, enc_const(4'h0, 8'h42));
        write_pmem(1, enc_const(4'h1, 8'h05));
        write_pmem(2, enc_rrr(OP_ADD, 4'h2, 4'h0, 4'h1));
        write_pmem(3, {OP_RET, 12'h000});
        repeat(2) @(posedge clk);
        write_dcr(16'd8); repeat(5) @(posedge clk);
        launch(); wait_done(TIMEOUT);
        gvf_check(kernel_done,  "8T multicore: done");
        gvf_check(!kernel_fault, "8T multicore: no fault");
        $display("  [INFO] 8T multicore in %0d cycles", cycle_cnt);

        // ═══ STAGE 6: Full 8-core (32T = 8 blocks) ═══
        $display("");
        $display("═══ STAGE 6: Full 8-Core (32T = 8 blocks) ═══");
        do_reset();
        write_pmem(0, enc_const(4'h0, 8'hAA));
        write_pmem(1, enc_const(4'h1, 8'h55));
        write_pmem(2, enc_rrr(OP_ADD, 4'h2, 4'h0, 4'h1));
        write_pmem(3, enc_rrr(OP_MUL, 4'h3, 4'h2, 4'h1));
        write_pmem(4, {OP_RET, 12'h000});
        repeat(2) @(posedge clk);
        write_dcr(16'd32); repeat(5) @(posedge clk);
        launch(); wait_done(TIMEOUT);
        gvf_check(kernel_done,  "32T full 8-core: done");
        gvf_check(!kernel_fault, "32T full 8-core: no fault");
        $display("  [INFO] 32T full 8-core in %0d cycles", cycle_cnt);

        // ═══ STAGE 7: ALU Stress (DIV chain, 16T) ═══
        $display("");
        $display("═══ STAGE 7: ALU Stress (DIV chain, 16T) ═══");
        do_reset();
        write_pmem(0, enc_const(4'h0, 8'hFF));
        write_pmem(1, enc_const(4'h1, 8'h02));
        write_pmem(2, enc_rrr(OP_DIV, 4'h2, 4'h0, 4'h1)); // 0xFF / 2
        write_pmem(3, enc_rrr(OP_DIV, 4'h3, 4'h2, 4'h1)); // / 2
        write_pmem(4, enc_rrr(OP_DIV, 4'h4, 4'h3, 4'h1)); // / 2
        write_pmem(5, enc_rrr(OP_ADD, 4'h5, 4'h4, 4'h0)); // + 0xFF
        write_pmem(6, {OP_RET, 12'h000});
        repeat(2) @(posedge clk);
        write_dcr(16'd16); repeat(5) @(posedge clk);
        launch(); wait_done(TIMEOUT);
        gvf_check(kernel_done,  "16T DIV stress: done");
        gvf_check(!kernel_fault, "16T DIV stress: no fault");
        $display("  [INFO] 16T DIV stress in %0d cycles", cycle_cnt);

        // ═══ STAGE 8: NOP Sled (16 NOPs + RET, 8T) ═══
        $display("");
        $display("═══ STAGE 8: NOP Sled (16 NOPs + RET, 8T) ═══");
        do_reset();
        for (i = 0; i < 16; i = i + 1)
            write_pmem(i[11:0], {OP_NOP, 12'h000});
        write_pmem(12'd16, {OP_RET, 12'h000});
        repeat(2) @(posedge clk);
        write_dcr(16'd8); repeat(5) @(posedge clk);
        launch(); wait_done(TIMEOUT);
        gvf_check(kernel_done,  "8T NOP sled: done");
        gvf_check(!kernel_fault, "8T NOP sled: no fault");
        $display("  [INFO] 8T NOP sled in %0d cycles", cycle_cnt);

        // ═══ STAGE 9: Back-to-Back Kernel Launches ═══
        $display("");
        $display("═══ STAGE 9: Back-to-Back Kernel Launches (5x) ═══");
        for (i = 0; i < 5; i = i + 1) begin
            do_reset();
            write_pmem(0, enc_const(4'h0, i[7:0]));
            write_pmem(1, enc_rrr(OP_ADD, 4'h1, 4'h0, 4'h0));
            write_pmem(2, {OP_RET, 12'h000});
            repeat(2) @(posedge clk);
            write_dcr(16'd4); repeat(5) @(posedge clk);
            launch(); wait_done(TIMEOUT);
            gvf_check(kernel_done && !kernel_fault, "B2B kernel");
        end
        $display("  [INFO] All 5 back-to-back kernels passed");

        // ═══ STAGE 10: Thread Scaling Sweep ═══
        $display("");
        $display("═══ STAGE 10: Thread Scaling Sweep ═══");
        begin
            integer thread_counts [7:0];
            thread_counts[0] = 1;  thread_counts[1] = 2;
            thread_counts[2] = 4;  thread_counts[3] = 7;
            thread_counts[4] = 8;  thread_counts[5] = 16;
            thread_counts[6] = 24; thread_counts[7] = 32;
            for (i = 0; i < 8; i = i + 1) begin
                do_reset();
                write_pmem(0, enc_const(4'h0, 8'h01));
                write_pmem(1, enc_rrr(OP_ADD, 4'h1, 4'h0, 4'h0));
                write_pmem(2, {OP_RET, 12'h000});
                repeat(2) @(posedge clk);
                write_dcr(thread_counts[i][15:0]);
                repeat(5) @(posedge clk);
                launch(); wait_done(TIMEOUT);
                if (kernel_done && !kernel_fault)
                    $display("  [PASS] T=%0d: done in %0d cycles", thread_counts[i], cycle_cnt);
                else
                    $display("  [FAIL] T=%0d: done=%b fault=%b state=%0d",
                             thread_counts[i], kernel_done, kernel_fault, kernel_state);
                tests_run = tests_run + 1;
                if (kernel_done && !kernel_fault) tests_pass = tests_pass + 1;
                else tests_fail = tests_fail + 1;
            end
        end

        // ═══ STAGE 11: FSM State Coverage ═══
        $display("");
        $display("═══ STAGE 11: FSM Lifecycle Verification ═══");
        do_reset();
        gvf_check(kernel_state == K_RESET, "FSM: RESET");
        write_pmem(0, {OP_RET, 12'h000});
        repeat(2) @(posedge clk);
        write_dcr(16'd4); repeat(3) @(posedge clk);
        gvf_check(kernel_state == K_CONFIG, "FSM: CONFIGURED");
        launch(); repeat(2) @(posedge clk);
        gvf_check(kernel_state == K_LAUNCH || kernel_state == K_RUNNING, "FSM: LAUNCH/RUNNING");
        wait_done(TIMEOUT);
        gvf_check(kernel_state >= K_DRAIN, "FSM: DRAIN/DONE");
        gvf_check(kernel_done, "FSM: kernel_done final");

        // ═══ STAGE 12: Performance & HBM Counters ═══
        $display("");
        $display("═══ STAGE 12: Performance Counters ═══");
        $display("  HBM Reads:     %0d", perf_hbm_reads);
        $display("  HBM Writes:    %0d", perf_hbm_writes);
        $display("  Total Flits:   %0d", perf_total_flits);
        $display("  Cycle Count:   %0d", perf_cycle_count);
        $display("  Active Cores:  %0d", perf_active_cores);
        $display("  Mesh Busy:     %0b", dbg_mesh_busy);

        // ═══ FINAL REPORT ═══
        $display("");
        $display("╔══════════════════════════════════════════════════════════════════╗");
        $display("║  FULL CHIP VERIFICATION REPORT                                   ║");
        $display("╠══════════════════════════════════════════════════════════════════╣");
        $display("║  Tests Run:    %4d                                              ║", tests_run);
        $display("║  Tests Passed: %4d                                              ║", tests_pass);
        $display("║  Tests Failed: %4d                                              ║", tests_fail);
        if (tests_fail == 0)
            $display("║  RESULT: ALL TESTS PASSED                                      ║");
        else
            $display("║  RESULT: %0d FAILURES DETECTED                                  ║", tests_fail);
        $display("╚══════════════════════════════════════════════════════════════════╝");
        $display("");

        repeat(10) @(posedge clk);
        $finish;
    end

    // Safety
    initial begin
        #(CLK_PERIOD * 500_000);
        $display("[GLOBAL TIMEOUT]");
        $finish;
    end
endmodule
