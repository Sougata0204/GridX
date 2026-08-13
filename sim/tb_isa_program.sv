// GridX3 - Tiny ISA Program Verification Testbench
// Performs closed-loop run through the entire SoC stack:
// Scheduler (warp execution & control)
// Core (register files, instruction buffer, FSM)
// Memory (on-chip BRAM, shared memories)
// NoC (MemoryMesh NoC routing memory requests)
// Tensor Unit (Matrix multiplication)

`default_nettype none
`timescale 1ns/1ns

module tb_isa_program;

    // Configurable parameters
    localparam CLK_PERIOD    = 5.0;       // 200 MHz
    localparam TIMEOUT       = 200_000;
    localparam PMEM_DEPTH    = 1024;
    localparam DMEM_DEPTH    = 8192;

    // Clock & Reset
    reg clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    reg rst_n = 0;

    // DUT Signals
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

    // Instantiation of the top-level GPU kernel top
    gridxKernelTop #(
        .CUBE_X            (2),
        .CUBE_Y            (2),
        .CUBE_Z            (1),
        .THREADS_PER_BLOCK (4),
        .WARPS_PER_CORE    (1),
        .NUM_HBM_NODES     (1),
        .PMEM_DEPTH        (PMEM_DEPTH),
        .DMEM_DEPTH        (DMEM_DEPTH),
        .SIM_TIMEOUT_CYCLES(TIMEOUT)
    ) dut (
        .clkSys       (clk),
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

    // Helpers
    task automatic do_reset;
        begin
            rst_n = 0;
            host_wr_en = 0; host_start = 0; host_wr_data = 0;
            pmem_wr_en = 0; pmem_wr_addr = 0; pmem_wr_data = 0;
            dmem_wr_en = 0; dmem_wr_addr = 0; dmem_wr_data = 0;
            dmem_rd_en = 0; dmem_rd_addr = 0;
            repeat (20) @(posedge clk);
            rst_n = 1;
            repeat (5) @(posedge clk);
        end
    endtask

    task automatic write_pmem_word(input [11:0] addr, input [15:0] data);
        begin
            @(posedge clk);
            pmem_wr_en <= 1; pmem_wr_addr <= addr; pmem_wr_data <= data;
            @(posedge clk);
            pmem_wr_en <= 0;
        end
    endtask

    task automatic write_dcr_word(input [15:0] data);
        begin
            @(posedge clk);
            host_wr_en <= 1; host_wr_data <= data;
            @(posedge clk);
            host_wr_en <= 0;
        end
    endtask

    task automatic write_dmem_byte(input [21:0] addr, input [7:0] data);
        begin
            @(posedge clk);
            dmem_wr_en <= 1; dmem_wr_addr <= addr; dmem_wr_data <= data;
            @(posedge clk);
            dmem_wr_en <= 0;
        end
    endtask

    task automatic read_dmem_byte(input [21:0] addr);
        begin
            @(posedge clk);
            dmem_rd_en <= 1; dmem_rd_addr <= addr;
            @(posedge clk);
            dmem_rd_en <= 0;
            @(posedge clk); // Allow register update
            @(posedge clk);
        end
    endtask

    task automatic load_isa_program;
        begin
            // 1. Construct global base 16'h8000 (32768)
            write_pmem_word(12'h000, 16'h9140);  // CONST R1, #64
            write_pmem_word(12'h001, 16'h5111);  // MUL R1, R1, R1 -> R1 = 4096
            write_pmem_word(12'h002, 16'h9208);  // CONST R2, #8
            write_pmem_word(12'h003, 16'h5112);  // MUL R1, R1, R2 -> R1 = 32768 (16'h8000)

            // 2. Set up offset constants
            write_pmem_word(12'h004, 16'h9210);  // CONST R2, #16
            write_pmem_word(12'h005, 16'h9320);  // CONST R3, #32
            write_pmem_word(12'h006, 16'h9430);  // CONST R4, #48
            write_pmem_word(12'h007, 16'h9B40);  // CONST R11, #64

            // 3. Set up thread-local local SMEM addresses
            write_pmem_word(12'h008, 16'h352F);  // ADD R5, R2, R15 -> local A = 16 + thread_id
            write_pmem_word(12'h009, 16'h363F);  // ADD R6, R3, R15 -> local B = 32 + thread_id
            write_pmem_word(12'h00A, 16'h3CBF);  // ADD R11, R11, R15 -> local Red = 64 + thread_id

            // 4. Construct global addresses (16'h8010, 16'h8020, 16'h8030)
            write_pmem_word(12'h00B, 16'h3212);  // ADD R2, R1, R2 -> 16'h8010
            write_pmem_word(12'h00C, 16'h3313);  // ADD R3, R1, R3 -> 16'h8020
            write_pmem_word(12'h00D, 16'h3414);  // ADD R4, R1, R4 -> 16'h8030

            // 5. Offset global addresses with Thread ID
            write_pmem_word(12'h00E, 16'h322F);  // ADD R2, R2, R15 -> 16'h8010 + thread_id
            write_pmem_word(12'h00F, 16'h333F);  // ADD R3, R3, R15 -> 16'h8020 + thread_id
            write_pmem_word(12'h010, 16'h344F);  // ADD R4, R4, R15 -> 16'h8030 + thread_id

            // 6. Vector Add
            write_pmem_word(12'h011, 16'h7720);  // LDR R7, [R2] -> Load A[thread_id]
            write_pmem_word(12'h012, 16'h7830);  // LDR R8, [R3] -> Load B[thread_id]
            write_pmem_word(12'h013, 16'h3978);  // ADD R9, R7, R8 -> R9 = A[i] + B[i]
            write_pmem_word(12'h014, 16'h8049);  // STR R4, R9 -> Store C[i] to global memory

            // 7. Matrix Multiply
            write_pmem_word(12'h015, 16'hEA78);  // OP_TENSOR_MMA R10, R7, R8 -> R10 = A[0] * B[thread_id]
            write_pmem_word(12'h016, 16'h80BA);  // STR R11, R10 -> Store MMA result to SMEM scratchpad

            // 8. Thread 0 branch logic for Reduction
            write_pmem_word(12'h017, 16'h20F0);  // CMP R15, R0 -> Compare thread ID to 0
            write_pmem_word(12'h018, 16'h141A);  // BRz #26 (PC 12'h01A)
            write_pmem_word(12'h019, 16'h1E29);  // BRnzp #41 (PC 12'h029)

            // 9. Thread 0 Reduction
            write_pmem_word(12'h01A, 16'h9B40);  // CONST R11, #64
            write_pmem_word(12'h01B, 16'h72B0);  // LDR R2, [R11] -> Load scratchpad[0]
            write_pmem_word(12'h01C, 16'h9301);  // CONST R3, #1
            write_pmem_word(12'h01D, 16'h3BB3);  // ADD R11, R11, R3 -> R11 = 65
            write_pmem_word(12'h01E, 16'h74B0);  // LDR R4, [R11] -> Load scratchpad[1]
            write_pmem_word(12'h01F, 16'h3BB3);  // ADD R11, R11, R3 -> R11 = 66
            write_pmem_word(12'h020, 16'h75B0);  // LDR R5, [R11] -> Load scratchpad[2]
            write_pmem_word(12'h021, 16'h3BB3);  // ADD R11, R11, R3 -> R11 = 67
            write_pmem_word(12'h022, 16'h76B0);  // LDR R6, [R11] -> Load scratchpad[3]
            write_pmem_word(12'h023, 16'h3C24);  // ADD R12, R2, R4
            write_pmem_word(12'h024, 16'h3CC5);  // ADD R12, R12, R5
            write_pmem_word(12'h025, 16'h3CC6);  // ADD R12, R12, R6 -> R12 = Sum
            write_pmem_word(12'h026, 16'h9850);  // CONST R8, #80
            write_pmem_word(12'h027, 16'h3818);  // ADD R8, R1, R8 -> R8 = 16'h8050
            write_pmem_word(12'h028, 16'h808C);  // STR R8, R12 -> Store Reduction result to BRAM

            // 10. Exit
            write_pmem_word(12'h029, 16'hF000);  // RET
            repeat (5) @(posedge clk);
        end
    endtask

    // Sim variables
    reg [7:0] C0, C1, C2, C3;
    reg [7:0] Reduction_Sum;
    integer cycle_cnt = 0;
    integer file_handle;

    initial begin
        $display("[TB] GridX3 ISA Program Testbench (Closed-Loop Run)");

        // Reset
        do_reset();

        // Populate Input Vectors:
        // A = [2, 3, 5, 7]
        // B = [11, 13, 17, 19]
        $display("[TB] Loading input vectors A and B to global data memory...");
        write_dmem_byte(22'h8010, 8'd2);
        write_dmem_byte(22'h8011, 8'd3);
        write_dmem_byte(22'h8012, 8'd5);
        write_dmem_byte(22'h8013, 8'd7);

        write_dmem_byte(22'h8020, 8'd11);
        write_dmem_byte(22'h8021, 8'd13);
        write_dmem_byte(22'h8022, 8'd17);
        write_dmem_byte(22'h8023, 8'd19);

        // Configure GPU with 4 threads (1 block of 4)
        $display("[TB] Configuring DCR registers (4 threads)...");
        write_dcr_word(16'd4);
        repeat (5) @(posedge clk);

        // Load Program
        $display("[TB] Loading ISA micro-program to program memory...");
        load_isa_program();

        // Start GPU kernel execution
        $display("[TB] Launching kernel...");
        @(posedge clk);
        host_start <= 1;
        @(posedge clk);
        host_start <= 0;

        // Wait for kernel completion
        cycle_cnt = 0;
        while (!kernel_done && !kernel_fault && cycle_cnt < TIMEOUT) begin
            @(posedge clk);
            cycle_cnt = cycle_cnt + 1;
        end

        if (kernel_fault) begin
            $display("[TB] ERROR: Kernel execution faulted!");
            $finish;
        end
        if (cycle_cnt >= TIMEOUT) begin
            $display("[TB] ERROR: Kernel execution timed out!");
            $finish;
        end

        $display("[TB] Kernel completed in %0d cycles.", cycle_cnt);

        // Readback results
        $display("[TB] Reading back results from data memory...");
        read_dmem_byte(22'h8030); C0 = dmem_rd_data;
        read_dmem_byte(22'h8031); C1 = dmem_rd_data;
        read_dmem_byte(22'h8032); C2 = dmem_rd_data;
        read_dmem_byte(22'h8033); C3 = dmem_rd_data;
        read_dmem_byte(22'h8050); Reduction_Sum = dmem_rd_data;

        $display("[TB] Results retrieved:");
        $display("  Vector Add C = [%0d, %0d, %0d, %0d]", C0, C1, C2, C3);
        $display("  Reduction Sum = %0d", Reduction_Sum);

        // Write outputs to text file for Python model verification
        $display("[TB] Saving simulation results to sim_results.txt...");
        file_handle = $fopen("sim_results.txt", "w");
        $fdisplay(file_handle, "%0d", C0);
        $fdisplay(file_handle, "%0d", C1);
        $fdisplay(file_handle, "%0d", C2);
        $fdisplay(file_handle, "%0d", C3);
        $fdisplay(file_handle, "%0d", Reduction_Sum);
        $fclose(file_handle);

        $display("[TB] Simulation Complete. Ready for golden comparison.");
        $finish;
    end

endmodule
