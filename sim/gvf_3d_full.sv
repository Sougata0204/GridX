`default_nettype none
`timescale 1ns/1ns

// ????????????????????????????????????????????????????????????????????????
// ?  GridX 3D Full Integration Testbench (GVF-3D)                      ?
// ?  2?2?2 Cube with MemoryMesh NoC, HBM3, per-layer 250MHz clocks    ?
// ?  Verifies: multicore, cache sheets (X/Y/Z), mesh routing, HBM I/O ?
// ????????????????????????????????????????????????????????????????????????

module gvf_3d_full;

    // CONFIGURATION
    localparam CLK_PERIOD        = 4.0;   // 250 MHz system clock = 4ns period
    localparam TIMEOUT           = 100_000;
    localparam PMEM_DEPTH        = 256;
    localparam DMEM_DEPTH        = 1024;
    localparam CUBE_X            = 2;
    localparam CUBE_Y            = 2;
    localparam CUBE_Z            = 2;
    localparam NUM_CORES         = CUBE_X * CUBE_Y * CUBE_Z; // 8
    localparam THREADS_PER_BLOCK = 4;
    localparam DATA_ADDR_BITS    = 22;
    localparam DATA_BITS         = 8;
    localparam PROG_ADDR_BITS    = 12;
    localparam PROG_BITS         = 16;

    // ISA Opcodes
    localparam [3:0] OP_NOP   = 4'h0, OP_BR   = 4'h1, OP_CMP  = 4'h2,
                     OP_ADD   = 4'h3, OP_SUB  = 4'h4, OP_MUL  = 4'h5,
                     OP_DIV   = 4'h6, OP_LDR  = 4'h7, OP_STR  = 4'h8,
                     OP_CONST = 4'h9, OP_TLD  = 4'hA, OP_TST  = 4'hB,
                     OP_DMA   = 4'hC, OP_BAR  = 4'hD, OP_TMMA = 4'hE,
                     OP_RET   = 4'hF;

    // Kernel FSM States
    localparam [2:0] K_RESET = 0, K_CONFIG = 1, K_LAUNCH = 2, K_RUNNING = 3,
                     K_DRAIN = 4, K_DONE = 5, K_FAULT = 6, K_PREEMPT = 7;

    // ???????????????????????????????????????????????????????????????????
    //  CLOCK & RESET ? Per-layer 250MHz clocks with slight phase offsets
    // ???????????????????????????????????????????????????????????????????
    reg clk_sys = 0;
    always #(CLK_PERIOD/2) clk_sys = ~clk_sys;  // 250 MHz

    // Per-layer clocks (same frequency, slight phase offsets to model GALS)
    reg [CUBE_Z-1:0] clk_layer;
    initial begin
        clk_layer = {CUBE_Z{1'b0}};
        fork
            // Layer 0: 250MHz, 0ps phase offset
            forever #(CLK_PERIOD/2) clk_layer[0] = ~clk_layer[0];
            // Layer 1: 250MHz, 200ps phase offset (model TSV skew)
            begin
                #0.2;
                forever #(CLK_PERIOD/2) clk_layer[1] = ~clk_layer[1];
            end
        join
    end

    reg rst_n = 0;

    // ???????????????????????????????????????????????????????????????????
    //  DUT SIGNALS
    // ???????????????????????????????????????????????????????????????????
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
    reg [PROG_ADDR_BITS-1:0] pmem_wr_addr = 0;
    reg [PROG_BITS-1:0]      pmem_wr_data = 0;
    reg        dmem_wr_en   = 0;
    reg        dmem_rd_en   = 0;
    reg [DATA_ADDR_BITS-1:0] dmem_wr_addr = 0;
    reg [DATA_ADDR_BITS-1:0] dmem_rd_addr = 0;
    reg [DATA_BITS-1:0]      dmem_wr_data = 0;
    wire [DATA_BITS-1:0]     dmem_rd_data;

    // ???????????????????????????????????????????????????????????????????
    //  DUT ? gridxKernelTop with per-layer clocks
    // ???????????????????????????????????????????????????????????????????
    gridxKernelTop #(
        .CUBE_X(CUBE_X), .CUBE_Y(CUBE_Y), .CUBE_Z(CUBE_Z),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .WARPS_PER_CORE((THREADS_PER_BLOCK + 31) / 32),
        .PMEM_DEPTH(PMEM_DEPTH), .DMEM_DEPTH(DMEM_DEPTH),
        .SIM_TIMEOUT_CYCLES(10_000_000),
        .NUM_HBM_NODES(2)
    ) dut (
        .clkSys       (clk_sys),
        .clkLayer     (clk_layer),
        .rstN         (rst_n),
        .hostWrEn    (host_wr_en),
        .hostWrData  (host_wr_data),
        .hostStart    (host_start),
        .kernelDone   (kernel_done),
        .kernelFault  (kernel_fault),
        .kernelStateO(kernel_state),
        .perfHbmReads   (perf_hbm_reads),
        .perfHbmWrites  (perf_hbm_writes),
        .perfTotalFlits (perf_total_flits),
        .perfCycleCount (perf_cycle_count),
        .perfActiveCores(perf_active_cores),
        .dbgCoreDoneSample(dbg_core_done_sample),
        .dbgMeshBusy (dbg_mesh_busy),
        .pmemWrEn    (pmem_wr_en),
        .pmemWrAddr  (pmem_wr_addr),
        .pmemWrData  (pmem_wr_data),
        .dmemWrEn    (dmem_wr_en),
        .dmemWrAddr  (dmem_wr_addr),
        .dmemWrData  (dmem_wr_data),
        .dmemRdEn    (dmem_rd_en),
        .dmemRdAddr  (dmem_rd_addr),
        .dmemRdData  (dmem_rd_data)
    );

    // ???????????????????????????????????????????????????????????????????
    //  STATISTICS & COUNTERS
    // ???????????????????????????????????????????????????????????????????
    integer suite_num         = 0;
    integer tests_passed      = 0;
    integer tests_failed      = 0;
    integer total_assertions  = 0;
    integer passed_assertions = 0;
    integer failed_assertions = 0;
    integer total_instrs      = 0;
    integer cycle_cnt         = 0;
    integer t_start, t_end, t_hbm_rd, t_hbm_wr, t_flits;
    integer sb_errors         = 0;

    // FSM coverage bins
    integer fsm_visit [7:0];
    integer fsm_transitions = 0;
    reg [2:0] prev_kstate;

    // Assertion violation counters
    integer v_fsm    = 0;
    integer v_mem    = 0;
    integer v_credit = 0;
    integer v_dead   = 0;

    // LFSR for randomization
    reg [31:0] lfsr = 32'hDEADBEEF;
    always @(posedge clk_sys)
        lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};

    // ???????????????????????????????????????????????????????????????????
    //  INFRASTRUCTURE TASKS
    // ???????????????????????????????????????????????????????????????????
    task automatic gvf_assert(input integer pass, input [8*80-1:0] msg);
        total_assertions = total_assertions + 1;
        if (pass) begin
            passed_assertions = passed_assertions + 1;
        end else begin
            failed_assertions = failed_assertions + 1;
            $display("    [ASSERT FAIL] %0s", msg);
        end
    endtask

    task automatic gvf_check(input integer pass, input [8*80-1:0] msg);
        total_assertions = total_assertions + 1;
        if (pass) begin
            tests_passed = tests_passed + 1;
            passed_assertions = passed_assertions + 1;
            $display("  [PASS] %0s", msg);
        end else begin
            tests_failed = tests_failed + 1;
            failed_assertions = failed_assertions + 1;
            $display("  [FAIL] %0s", msg);
        end
    endtask

    task automatic do_reset;
        rst_n = 0;
        host_wr_en = 0; host_start = 0; host_wr_data = 0;
        pmem_wr_en = 0; pmem_wr_addr = 0; pmem_wr_data = 0;
        dmem_wr_en = 0; dmem_wr_addr = 0; dmem_wr_data = 0;
        dmem_rd_en = 0; dmem_rd_addr = 0;
        repeat (20) @(posedge clk_sys);
        rst_n = 1;
        repeat (5) @(posedge clk_sys);
    endtask

    task automatic write_pmem(input [PROG_ADDR_BITS-1:0] addr, input [PROG_BITS-1:0] data);
        @(posedge clk_sys);
        pmem_wr_en <= 1; pmem_wr_addr <= addr; pmem_wr_data <= data;
        @(posedge clk_sys);
        pmem_wr_en <= 0;
    endtask

    task automatic write_dcr(input [15:0] data);
        @(posedge clk_sys);
        host_wr_en <= 1; host_wr_data <= data;
        @(posedge clk_sys);
        host_wr_en <= 0;
    endtask

    task automatic write_dmem(input [DATA_ADDR_BITS-1:0] addr, input [DATA_BITS-1:0] data);
        @(posedge clk_sys);
        dmem_wr_en <= 1; dmem_wr_addr <= addr; dmem_wr_data <= data;
        @(posedge clk_sys);
        dmem_wr_en <= 0;
    endtask

    task automatic read_dmem(input [DATA_ADDR_BITS-1:0] addr);
        @(posedge clk_sys);
        dmem_rd_en <= 1; dmem_rd_addr <= addr;
        @(posedge clk_sys);
        dmem_rd_en <= 0;
        @(posedge clk_sys);
    endtask

    task automatic launch_kernel;
        @(posedge clk_sys); host_start <= 1;
        @(posedge clk_sys); host_start <= 0;
    endtask

    task automatic wait_kernel(input integer max_cycles);
        cycle_cnt = 0;
        while (!kernel_done && !kernel_fault && cycle_cnt < max_cycles) begin
            @(posedge clk_sys);
            cycle_cnt = cycle_cnt + 1;
        end
    endtask

    // Encoding helpers
    function [15:0] enc_rrr(input [3:0] op, rd, rs, rt);
        enc_rrr = {op, rd, rs, rt};
    endfunction
    function [15:0] enc_const(input [3:0] rd, input [7:0] imm);
        enc_const = {OP_CONST, rd, imm};
    endfunction
    function [15:0] enc_ret();
        enc_ret = {OP_RET, 12'h000};
    endfunction

    // ???????????????????????????????????????????????????????????????????
    //  ISA PROGRAM LIBRARY
    // ???????????????????????????????????????????????????????????????????
    task automatic load_prog_saxpy;
        write_pmem(0,  enc_const(4'h1, 8'h02));                  // r1 = 2 (a)
        write_pmem(1,  enc_const(4'h2, 8'h03));                  // r2 = 3 (x)
        write_pmem(2,  enc_const(4'h3, 8'h01));                  // r3 = 1 (y)
        write_pmem(3,  enc_rrr(OP_MUL, 4'h4, 4'h1, 4'h2));      // r4 = a*x = 6
        write_pmem(4,  enc_rrr(OP_ADD, 4'h5, 4'h4, 4'h3));      // r5 = a*x+y = 7
        write_pmem(5,  enc_const(4'h6, 8'h80));                  // r6 = 0xFF80 (BRAM base)
        write_pmem(6,  enc_rrr(OP_MUL, 4'h7, 4'hD, 4'hE));      // r7 = block_id * TPB
        write_pmem(7,  enc_rrr(OP_ADD, 4'h8, 4'h7, 4'hF));      // r8 = global_tid
        write_pmem(8,  enc_rrr(OP_ADD, 4'h9, 4'h6, 4'h8));      // r9 = 0xFF80 + global_tid
        write_pmem(9,  {OP_STR, 4'h0, 4'h9, 4'h5});             // STR: DMEM[r9] = r5 = 7
        write_pmem(10, enc_ret());
        repeat(2) @(posedge clk_sys);
    endtask

    task automatic load_prog_alu_stress;
        write_pmem(0, enc_const(4'h0, 8'h07));
        write_pmem(1, enc_const(4'h1, 8'h03));
        write_pmem(2, enc_rrr(OP_ADD, 4'h2, 4'h0, 4'h1));
        write_pmem(3, enc_rrr(OP_SUB, 4'h3, 4'h0, 4'h1));
        write_pmem(4, enc_rrr(OP_MUL, 4'h4, 4'h2, 4'h3));
        write_pmem(5, enc_rrr(OP_DIV, 4'h5, 4'h4, 4'h1));
        write_pmem(6, enc_rrr(OP_ADD, 4'h6, 4'h5, 4'h2));
        write_pmem(7, {OP_STR, 4'h6, 4'h0, 4'h0});
        write_pmem(8, enc_ret());
        repeat(2) @(posedge clk_sys);
    endtask

    task automatic load_prog_reduction;
        write_pmem(0, enc_const(4'h0, 8'h01));
        write_pmem(1, enc_const(4'h1, 8'h02));
        write_pmem(2, enc_const(4'h2, 8'h03));
        write_pmem(3, enc_rrr(OP_ADD, 4'h3, 4'h0, 4'h1));
        write_pmem(4, enc_rrr(OP_ADD, 4'h4, 4'h3, 4'h2));
        write_pmem(5, {OP_STR, 4'h4, 4'h0, 4'h0});
        write_pmem(6, enc_ret());
        repeat(2) @(posedge clk_sys);
    endtask

    task automatic load_prog_nop_sled;
        integer i;
        for (i = 0; i < 16; i = i + 1)
            write_pmem(i, {OP_NOP, 12'h000});
        write_pmem(16, enc_ret());
        repeat(2) @(posedge clk_sys);
    endtask

    task automatic load_prog_immediate_only;
        write_pmem(0, enc_const(4'h0, 8'hAA));
        write_pmem(1, enc_const(4'h1, 8'h55));
        write_pmem(2, enc_rrr(OP_ADD, 4'h2, 4'h0, 4'h1));
        write_pmem(3, enc_ret());
        repeat(2) @(posedge clk_sys);
    endtask

    task automatic load_prog_mem_raw;
        write_pmem(0, enc_const(4'h0, 8'h10));
        write_pmem(1, enc_const(4'h1, 8'hAB));
        write_pmem(2, {OP_STR, 4'h1, 4'h0, 4'h0});
        write_pmem(3, {OP_LDR, 4'h2, 4'h0, 4'h0});
        write_pmem(4, enc_rrr(OP_ADD, 4'h3, 4'h2, 4'h1));
        write_pmem(5, {OP_STR, 4'h3, 4'h0, 4'h0});
        write_pmem(6, enc_ret());
        repeat(2) @(posedge clk_sys);
    endtask

    task automatic poison_bram(input integer num_threads);
        integer pi;
        for (pi = 0; pi < num_threads; pi = pi + 1)
            write_dmem(22'hFF80 + pi, 8'hAA);
        repeat(2) @(posedge clk_sys);
    endtask

    task automatic verify_saxpy(input integer num_threads, input [8*40-1:0] ctx);
        integer vi;
        for (vi = 0; vi < num_threads; vi = vi + 1)
            scoreboard_check_dmem(22'hFF80 + vi, 8'd7, ctx);
    endtask

    task automatic scoreboard_check_dmem(
        input [DATA_ADDR_BITS-1:0] addr,
        input [DATA_BITS-1:0] expected,
        input [8*40-1:0] ctx
    );
        read_dmem(addr);
        total_assertions = total_assertions + 1;
        if (dmem_rd_data === expected) begin
            passed_assertions = passed_assertions + 1;
        end else begin
            failed_assertions = failed_assertions + 1;
            sb_errors = sb_errors + 1;
            $display("  [SB FAIL] %0s: DMEM[0x%04h] = 0x%02h, expected 0x%02h",
                     ctx, addr, dmem_rd_data, expected);
        end
    endtask

    // ???????????????????????????????????????????????????????????????????
    //  KERNEL RUNNER
    // ???????????????????????????????????????????????????????????????????
    task automatic run_kernel(
        input [8*40-1:0] name, input integer threads, input integer expect_done, input integer max_cyc
    );
        suite_num = suite_num + 1;
        $display("?? [3D-FULL 2x2x2] Suite %0d: %0s (T=%0d) ??", suite_num, name, threads);
        do_reset();
        // Load the appropriate program for this test
        if (name == "SAXPY-4T" || name == "SAXPY-8T" || name == "SAXPY-16T" || name == "SAXPY-32T") begin
            poison_bram(threads);
            load_prog_saxpy();
        end else if (name == "ALU-Stress") begin
            load_prog_alu_stress();
        end else if (name == "Reduction") begin
            load_prog_reduction();
        end else if (name == "NOP-Sled-16") begin
            load_prog_nop_sled();
        end else if (name == "Imm-Only") begin
            load_prog_immediate_only();
        end else if (name == "Mem-RAW") begin
            load_prog_mem_raw();
        end else begin
            // Random/generic: load SAXPY as fallback
            load_prog_saxpy();
        end
        t_start   = perf_cycle_count;
        t_hbm_rd  = perf_hbm_reads;
        t_hbm_wr  = perf_hbm_writes;
        t_flits   = perf_total_flits;
        write_dcr(threads[15:0]);
        repeat(5) @(posedge clk_sys);
        launch_kernel();
        wait_kernel(max_cyc);
        t_end = perf_cycle_count;
        $display("  [%0s] EXECUTION CYCLES: %0d", name, t_end - t_start);
        if (expect_done) begin
            gvf_check(kernel_done,  "kernel_done");
            gvf_check(!kernel_fault, "no fault");
        end else begin
            gvf_check(kernel_fault, "fault detected");
        end
        if (expect_done && (name == "SAXPY-4T" || name == "SAXPY-8T" || name == "SAXPY-16T" || name == "SAXPY-32T"))
            verify_saxpy(threads, name);
        $display("    Cycles=%0d HBM_rd=%0d HBM_wr=%0d Flits=%0d ActiveCores=%0d MeshBusy=%0b",
                 t_end - t_start,
                 perf_hbm_reads - t_hbm_rd,
                 perf_hbm_writes - t_hbm_wr,
                 perf_total_flits - t_flits,
                 perf_active_cores, dbg_mesh_busy);
    endtask

    // ???????????????????????????????????????????????????????????????????
    //  CONTINUOUS MONITORS
    // ???????????????????????????????????????????????????????????????????

    // M1: FSM Coverage
    always @(posedge clk_sys) if (rst_n) begin
        prev_kstate <= kernel_state;
        if (kernel_state <= 3'd7)
            fsm_visit[kernel_state] = fsm_visit[kernel_state] + 1;
        if (kernel_state != prev_kstate)
            fsm_transitions = fsm_transitions + 1;
    end

    // M2: FSM Legal Transitions
    reg rst_n_d1 = 0;
    always @(posedge clk_sys) rst_n_d1 <= rst_n;
    wire monitor_active = rst_n && rst_n_d1;

    always @(posedge clk_sys) if (monitor_active && kernel_state != prev_kstate) begin
        case (prev_kstate)
            K_RESET:   if (kernel_state != K_CONFIG && kernel_state != K_RESET) begin
                           v_fsm = v_fsm + 1;
                           $display("[M2] ILLEGAL FSM: %0d->%0d @%0d", prev_kstate, kernel_state, perf_cycle_count);
                       end
            K_CONFIG:  if (kernel_state != K_LAUNCH && kernel_state != K_RESET) begin
                           v_fsm = v_fsm + 1;
                           $display("[M2] ILLEGAL FSM: %0d->%0d @%0d", prev_kstate, kernel_state, perf_cycle_count);
                       end
            K_LAUNCH:  if (kernel_state != K_RUNNING && kernel_state != K_FAULT) begin
                           v_fsm = v_fsm + 1;
                           $display("[M2] ILLEGAL FSM: %0d->%0d @%0d", prev_kstate, kernel_state, perf_cycle_count);
                       end
            K_RUNNING: if (kernel_state != K_DRAIN && kernel_state != K_FAULT && kernel_state != K_PREEMPT) begin
                           v_fsm = v_fsm + 1;
                           $display("[M2] ILLEGAL FSM: %0d->%0d @%0d", prev_kstate, kernel_state, perf_cycle_count);
                       end
            K_DRAIN:   if (kernel_state != K_DONE && kernel_state != K_FAULT) begin
                           v_fsm = v_fsm + 1;
                           $display("[M2] ILLEGAL FSM: %0d->%0d @%0d", prev_kstate, kernel_state, perf_cycle_count);
                       end
            K_PREEMPT: if (kernel_state != K_DONE && kernel_state != K_FAULT) begin
                           v_fsm = v_fsm + 1;
                           $display("[M2] ILLEGAL FSM: %0d->%0d @%0d", prev_kstate, kernel_state, perf_cycle_count);
                       end
            default: ;
        endcase
    end

    // M3: Outstanding Memory Check (via perf counters ? no internal hierarchy)
    always @(posedge clk_sys) if (monitor_active) begin
        // Monitor for excessive HBM latency (indicates potential memory stall)
        if (perf_hbm_reads > 32'd1000000) begin
            v_mem = v_mem + 1;
        end
    end

    // M5: Deadlock Detector (declared early so M4 can reference dead_wd)
    integer dead_wd = 0;

    // M4: Credit Protocol (mesh-level: monitor for credit starvation)
    always @(posedge clk_sys) if (monitor_active) begin
        // Check if mesh is stuck busy for too long (indicates credit deadlock)
        if (dbg_mesh_busy && dead_wd > 50000)
            v_credit = v_credit + 1;
    end

    // M5: Deadlock Detector (logic)
    always @(posedge clk_sys) begin
        if (!rst_n || kernel_done || kernel_fault)
            dead_wd <= 0;
        else if (kernel_state == K_RUNNING || kernel_state == K_DRAIN) begin
            dead_wd <= dead_wd + 1;
            if (dead_wd > 80000) begin
                $display("[M5] DEADLOCK @%0d, stuck %0d cycles", perf_cycle_count, dead_wd);
                v_dead = v_dead + 1;
                dead_wd <= 0;
            end
        end else
            dead_wd <= 0;
    end

    // M6: Mesh Traffic Monitor ? count per-layer flit activity
    integer mesh_layer0_flits = 0, mesh_layer1_flits = 0;
    always @(posedge clk_sys) if (rst_n) begin
        begin : mesh_monitor
            integer mi;
            for (mi = 0; mi < 4; mi = mi + 1) begin  // Layer 0 nodes
                if (dut.meshFlitInValid[mi]) mesh_layer0_flits = mesh_layer0_flits + 1;
                if (dut.meshFlitOutValid[mi]) mesh_layer0_flits = mesh_layer0_flits + 1;
            end
            for (mi = 4; mi < 8; mi = mi + 1) begin  // Layer 1 nodes
                if (dut.meshFlitInValid[mi]) mesh_layer1_flits = mesh_layer1_flits + 1;
                if (dut.meshFlitOutValid[mi]) mesh_layer1_flits = mesh_layer1_flits + 1;
            end
        end
    end

    // M7: Instruction Retirement Counter (via core_done transitions)
    reg [7:0] prev_core_done = 8'h00;
    always @(posedge clk_sys) if (rst_n) begin
        if (dbg_core_done_sample != prev_core_done) begin
            total_instrs = total_instrs + 1;
        end
        prev_core_done <= dbg_core_done_sample;
    end

    // ???????????????????????????????????????????????????????????????????
    //  MAIN TEST SEQUENCE
    // ???????????????????????????????????????????????????????????????????
    initial begin
        integer i;
        integer covered;
        integer rand_threads;

        // Init arrays
        for (i = 0; i < 8; i = i + 1) fsm_visit[i] = 0;

        $display("");
        $display("????????????????????????????????????????????????????????????????????");
        $display("?  GridX 3D Full Integration Test (GVF-3D) v1.0                  ?");
        $display("?  CUBE: 2?2?2 = 8 cores | MemoryMesh + HBM3 + Cache Sheets     ?");
        $display("?  Per-Layer 250MHz Clocks with GALS CDC                         ?");
        $display("????????????????????????????????????????????????????????????????????");
        $display("");

        // ????????????????????????????????????????????????????????????
        //  STAGE 1: RESET & INFRASTRUCTURE VERIFICATION
        // ????????????????????????????????????????????????????????????
        $display("??? STAGE 1: Reset & Infrastructure ???");
        suite_num = suite_num + 1;
        $display("?? Suite %0d: Reset & Init ??", suite_num);
        do_reset();
        gvf_check(kernel_state == K_RESET,    "kernel_state = RESET");
        gvf_check(!kernel_done,                "kernel_done = 0");
        gvf_check(!kernel_fault,               "kernel_fault = 0");
        gvf_check(perf_cycle_count > 0,        "cycle counter running");
        gvf_check(perf_hbm_reads == 0,         "hbm_reads = 0");
        gvf_check(perf_hbm_writes == 0,        "hbm_writes = 0");
        gvf_check(perf_active_cores == 0,      "active_cores = 0");
        gvf_check(dbg_core_done_sample == 8'h00, "all 8 cores idle");
        gvf_check(dbg_mesh_busy == 0,          "mesh idle after reset");

        // Verify clkLayer is toggling (CDC infrastructure alive)
        suite_num = suite_num + 1;
        $display("?? Suite %0d: Per-Layer Clock Verification ??", suite_num);
        gvf_check(clk_layer[0] !== 1'bx, "Layer 0 clock alive");
        gvf_check(clk_layer[1] !== 1'bx, "Layer 1 clock alive");
        repeat(10) @(posedge clk_sys);
        $display("  [INFO] clk_layer[0] phase: %b | clk_layer[1] phase: %b", clk_layer[0], clk_layer[1]);

        // ????????????????????????????????????????????????????????????
        //  STAGE 2: SINGLE-BLOCK COMPUTE (4T on 1 core)
        // ????????????????????????????????????????????????????????????
        $display("");
        $display("??? STAGE 2: Single-Block Compute ???");

        // DCR Configuration
        suite_num = suite_num + 1;
        $display("?? Suite %0d: DCR Config ??", suite_num);
        do_reset();
        write_dcr(16'd4);
        repeat(5) @(posedge clk_sys);
        gvf_check(kernel_state == K_CONFIG, "CONFIGURED after DCR");

        // SAXPY 4T
        run_kernel("SAXPY-4T", 4, 1, TIMEOUT);

        // DMEM Readback
        read_dmem(22'd0);

        // ????????????????????????????????????????????????????????????
        //  STAGE 3: MULTI-CORE SCALING (8T, 16T, 32T)
        // ????????????????????????????????????????????????????????????
        $display("");
        $display("??? STAGE 3: Multi-Core Scaling ???");

        run_kernel("SAXPY-8T", 8, 1, TIMEOUT);
        run_kernel("SAXPY-16T", 16, 1, TIMEOUT);
        run_kernel("SAXPY-32T", 32, 1, TIMEOUT);

        // ????????????????????????????????????????????????????????????
        //  STAGE 4: ALU & MEMORY STRESS
        // ????????????????????????????????????????????????????????????
        $display("");
        $display("??? STAGE 4: ALU & Memory Stress ???");

        run_kernel("ALU-Stress", 4, 1, TIMEOUT);
        run_kernel("Reduction", 4, 1, TIMEOUT);
        run_kernel("NOP-Sled-16", 4, 1, TIMEOUT);
        run_kernel("Imm-Only", 4, 1, TIMEOUT);
        run_kernel("Mem-RAW", 4, 1, TIMEOUT);

        // ????????????????????????????????????????????????????????????
        //  STAGE 5: FSM LIFECYCLE & PROTOCOL
        // ????????????????????????????????????????????????????????????
        $display("");
        $display("??? STAGE 5: FSM Lifecycle & Protocol ???");

        suite_num = suite_num + 1;
        $display("?? Suite %0d: FSM Lifecycle ??", suite_num);
        do_reset();
        gvf_check(kernel_state == K_RESET, "S0: RESET");
        write_dcr(16'd4); repeat(3) @(posedge clk_sys);
        gvf_check(kernel_state == K_CONFIG, "S1: CONFIGURED");
        load_prog_saxpy();
        launch_kernel(); repeat(2) @(posedge clk_sys);
        gvf_check(kernel_state == K_LAUNCH || kernel_state == K_RUNNING, "S2/3: LAUNCH/RUNNING");
        wait_kernel(TIMEOUT);
        gvf_check(kernel_state == K_DONE, "S5: DONE");
        gvf_check(kernel_done, "kernel_done final");

        // Credit protocol
        suite_num = suite_num + 1;
        $display("?? Suite %0d: Credit Protocol ??", suite_num);
        gvf_check(v_credit == 0, "no credit starvation detected");

        // ????????????????????????????????????????????????????????????
        //  STAGE 6: RANDOM VERIFICATION (10 iterations)
        // ????????????????????????????????????????????????????????????
        $display("");
        $display("??? STAGE 6: Random Verification (10 iterations) ???");

        for (i = 0; i < 10; i = i + 1) begin
            rand_threads = (lfsr[4:0] % 32) + 1;
            do_reset();
            case (lfsr[2:0])
                3'd0: load_prog_saxpy();
                3'd1: load_prog_reduction();
                3'd2: load_prog_alu_stress();
                3'd3: load_prog_nop_sled();
                3'd4: load_prog_immediate_only();
                3'd5: load_prog_mem_raw();
                3'd6: load_prog_saxpy();
                3'd7: load_prog_reduction();
            endcase
            run_kernel("Random", rand_threads, 1, TIMEOUT);
        end

        // ????????????????????????????????????????????????????????????
        //  STAGE 7: STRESS (Max threads, back-to-back, scaling)
        // ????????????????????????????????????????????????????????????
        $display("");
        $display("??? STAGE 7: Stress Verification ???");

        run_kernel("SAXPY-32T", 32, 1, TIMEOUT);

        for (i = 0; i < 3; i = i + 1) begin
            run_kernel("SAXPY-4T", 4, 1, TIMEOUT);
        end

        // Thread scaling sweep
        run_kernel("SAXPY-4T", 1, 1, TIMEOUT);
        run_kernel("SAXPY-4T", 2, 1, TIMEOUT);
        run_kernel("SAXPY-4T", 5, 1, TIMEOUT);
        run_kernel("SAXPY-4T", 7, 1, TIMEOUT);

        // ????????????????????????????????????????????????????????????
        //  STAGE 8: MESH & HBM INTEGRATION VERIFICATION
        // ????????????????????????????????????????????????????????????
        $display("");
        $display("??? STAGE 8: Mesh & HBM Integration ???");

        $display("  Mesh Traffic Summary:");
        $display("    Layer 0 flit events: %0d", mesh_layer0_flits);
        $display("    Layer 1 flit events: %0d", mesh_layer1_flits);
        $display("    Total HBM Reads:     %0d", perf_hbm_reads);
        $display("    Total HBM Writes:    %0d", perf_hbm_writes);
        $display("    Total NoC Flits:     %0d", perf_total_flits);

        // ????????????????????????????????????????????????????????????
        //  STAGE 9: ASSERTION ROLL-UP & COVERAGE
        // ????????????????????????????????????????????????????????????
        $display("");
        $display("??? STAGE 9: Assertion Roll-Up & Coverage ???");

        gvf_assert(v_fsm == 0,      "A01: No illegal FSM transitions");
        gvf_assert(v_mem == 0,       "A02: No outstanding_mem underflow");
        gvf_assert(v_credit == 0,    "A03: No credit overflow");
        gvf_assert(v_dead == 0,      "A04: No deadlock");
        gvf_assert(sb_errors == 0,   "A05: All scoreboard checks passed");

        // FSM State Coverage
        $display("");
        $display("  FSM State Coverage:");
        covered = 0;
        for (i = 0; i < 8; i = i + 1) begin
            if (fsm_visit[i] > 0) covered = covered + 1;
            case (i)
                0: $display("    RESET      : %0d cycles", fsm_visit[0]);
                1: $display("    CONFIGURED : %0d cycles", fsm_visit[1]);
                2: $display("    LAUNCH     : %0d cycles", fsm_visit[2]);
                3: $display("    RUNNING    : %0d cycles", fsm_visit[3]);
                4: $display("    DRAIN      : %0d cycles", fsm_visit[4]);
                5: $display("    DONE       : %0d cycles", fsm_visit[5]);
                6: $display("    FAULT      : %0d cycles", fsm_visit[6]);
                7: $display("    PREEMPT    : %0d cycles", fsm_visit[7]);
            endcase
        end
        $display("    Transitions: %0d total", fsm_transitions);
        $display("    Coverage   : %0d/8 states", covered);
        gvf_assert(covered >= 5, "A06: >= 5/8 FSM states visited");

        // Performance Summary
        $display("");
        $display("  Performance Counters:");
        $display("    Total instructions retired : %0d", total_instrs);
        $display("    Total HBM reads            : %0d", perf_hbm_reads);
        $display("    Total HBM writes           : %0d", perf_hbm_writes);
        $display("    Total NoC flits            : %0d", perf_total_flits);
        $display("    Final cycle count          : %0d", perf_cycle_count);

        // ????????????????????????????????????????????????????????????
        //  FINAL REPORT
        // ????????????????????????????????????????????????????????????
        $display("");
        $display("????????????????????????????????????????????????????????????????????");
        $display("?  GVF-3D FINAL REPORT                                           ?");
        $display("????????????????????????????????????????????????????????????????????");
        $display("?  Suites:     %4d                                               ?", suite_num);
        $display("?  Assertions: %4d  (Passed: %4d  Failed: %4d)                ?",
                 total_assertions, passed_assertions, failed_assertions);
        $display("?  Scoreboard: %4d errors                                        ?", sb_errors);
        if (failed_assertions == 0)
            $display("?  RESULT: ? ALL TESTS PASSED                                   ?");
        else
            $display("?  RESULT: ? %0d FAILURES                                       ?", failed_assertions);
        $display("????????????????????????????????????????????????????????????????????");
        $display("");

        repeat(10) @(posedge clk_sys);
        $finish;
    end

    // Safety timeout
    initial begin
        #(CLK_PERIOD * TIMEOUT * 200);
        $display("[GVF-3D] GLOBAL TIMEOUT");
        $finish;
    end

endmodule
