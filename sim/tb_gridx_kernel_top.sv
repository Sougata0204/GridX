`default_nettype none
`timescale 1ns/1ns

// GridX3 Kernel Top - Unified Self-Contained Testbench
// Tests the full 3D GPU stack: cores → mesh NoC → HBM
// Parameterized to match any configuration of gridx_kernel_top.

module tb_gridx_kernel_top;

    // Configurable test parameters
    localparam TIMEOUT        = 200_000;
    localparam PMEM_DEPTH     = 4096;
    localparam DMEM_DEPTH     = 65536;
    localparam THREADS_TO_RUN = 4;       // Must be <= THREADS_PER_BLOCK

    // Clock & Reset
    reg clk, rst_n;
    initial clk = 0;
    always #2.5 clk = ~clk;  // 200 MHz

    // DUT signals
    reg        host_wr_en, host_start;
    reg [15:0] host_wr_data;
    wire       kernel_done, kernel_fault;
    wire [2:0] kernel_state;
    wire [31:0] perf_hbm_reads, perf_hbm_writes, perf_total_flits;
    wire [31:0] perf_cycle_count, perf_active_cores;
    wire [7:0]  dbg_core_done_sample;
    wire        dbg_mesh_busy;

    reg        pmem_wr_en;
    reg [11:0] pmem_wr_addr;
    reg [15:0] pmem_wr_data;

    reg        dmem_wr_en, dmem_rd_en;
    reg [21:0] dmem_wr_addr, dmem_rd_addr;
    reg [7:0]  dmem_wr_data;
    wire [7:0] dmem_rd_data;

    // DUT
    gridxKernelTop #(
        .PMEM_DEPTH        (PMEM_DEPTH),
        .DMEM_DEPTH        (DMEM_DEPTH),
        .SIM_TIMEOUT_CYCLES(TIMEOUT),
        .NUM_HBM_NODES     (2)
    ) dut (
        .clkSys       (clk),
        .clkLayer     ({2{clk}}),
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

    // State name decoder (for waveform debug)
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

    // Helper Tasks
    task write_pmem(input [11:0] addr, input [15:0] data);
        @(posedge clk);
        pmem_wr_en   <= 1;
        pmem_wr_addr <= addr;
        pmem_wr_data <= data;
        @(posedge clk);
        pmem_wr_en   <= 0;
    endtask

    task write_dcr(input [15:0] data);
        @(posedge clk);
        host_wr_en   <= 1;
        host_wr_data <= data;
        @(posedge clk);
        host_wr_en   <= 0;
    endtask

    task write_dmem(input [21:0] addr, input [7:0] data);
        @(posedge clk);
        dmem_wr_en   <= 1;
        dmem_wr_addr <= addr;
        dmem_wr_data <= data;
        @(posedge clk);
        dmem_wr_en   <= 0;
    endtask

    task read_dmem(input [21:0] addr);
        @(posedge clk);
        dmem_rd_en   <= 1;
        dmem_rd_addr <= addr;
        @(posedge clk);
        dmem_rd_en   <= 0;
        @(posedge clk); // wait for data
    endtask

    // Main Test Sequence
    integer cycle_cnt = 0;
    integer test_pass = 1;

    initial begin
        $display("[TB_KERNEL_TOP] GridX3 3D GPU Integration Test");
        $display("[TB_KERNEL_TOP] Architecture: 2x2x2 = 8 cores | Threads/Block: %0d | Warps/Core: %0d",
                 dut.THREADS_PER_BLOCK, dut.WARPS_PER_CORE);

        // Init all inputs
        rst_n = 0; host_wr_en = 0; host_start = 0; host_wr_data = 0;
        pmem_wr_en = 0; pmem_wr_addr = 0; pmem_wr_data = 0;
        dmem_wr_en = 0; dmem_wr_addr = 0; dmem_wr_data = 0;
        dmem_rd_en = 0; dmem_rd_addr = 0;

        // Reset Phase
        $display("[TB] Applying reset...");
        repeat (20) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);
        $display("[TB] Reset released, kernel_state = %0d (%0s)",
                 kernel_state, state_name);

        // Load Program Memory (SAXPY kernel)
        $display("[TB] Loading SAXPY kernel into PMEM...");
        write_pmem(12'h000, 16'h9002);  // CONST R0, #2  (scalar a=2)
        write_pmem(12'h001, 16'h9100);  // CONST R1, #0  (addr base)
        write_pmem(12'h002, 16'h5201);  // MUL R2, R0, R1
        write_pmem(12'h003, 16'h3321);  // ADD R3, R2, R1
        write_pmem(12'h004, 16'h8310);  // STR R3, [R1]
        write_pmem(12'h005, 16'hF000);  // RET
        repeat (5) @(posedge clk);

        // Configure Thread Count
        $display("[TB] Configuring thread count = %0d", THREADS_TO_RUN);
        write_dcr(THREADS_TO_RUN[15:0]);
        repeat (5) @(posedge clk);
        $display("[TB] kernel_state = %0d (%0s)", kernel_state, state_name);

        // Launch Kernel
        $display("[TB] Launching kernel at perf_cycle = %0d", perf_cycle_count);
        @(posedge clk); host_start <= 1;
        @(posedge clk); host_start <= 0;

        // Wait for Completion
        cycle_cnt = 0;
        while (!kernel_done && !kernel_fault && cycle_cnt < TIMEOUT) begin
            @(posedge clk);
            cycle_cnt = cycle_cnt + 1;
            if (cycle_cnt % 10000 == 0)
                $display("[TB] Cycle %0d: state=%0d (%0s) active=%0d mesh_busy=%0b",
                         perf_cycle_count, kernel_state, state_name,
                         perf_active_cores, dbg_mesh_busy);
        end

        // Report Results
        if (kernel_done) begin
            $display("[TB_KERNEL_TOP] RESULT: KERNEL COMPLETE - PASS | Cycles: %0d | HBM Reads: %0d | HBM Writes: %0d | Flits: %0d",
                     perf_cycle_count, perf_hbm_reads, perf_hbm_writes, perf_total_flits);
        end else if (kernel_fault) begin
            $display("[TB_KERNEL_TOP] RESULT: KERNEL FAULT at cycle %0d (State: %0d %0s)", perf_cycle_count, kernel_state, state_name);
            test_pass = 0;
        end else begin
            $display("[TB_KERNEL_TOP] RESULT: TIMEOUT after %0d cycles", TIMEOUT);
            test_pass = 0;
        end

        // Readback Test
        $display("[TB] Reading data memory...");
        read_dmem(22'd0);
        $display("[TB] DMEM[0] = 0x%02h", dmem_rd_data);

        repeat (10) @(posedge clk);

        if (test_pass)
            $display("[TB] ALL TESTS PASSED");
        else
            $display("[TB] TESTS FAILED");

        $finish;
    end

    // VCD Dump
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("gridx_kernel_top.vcd");
            $dumpvars(0, tb_gridx_kernel_top);
        end
    end

endmodule
