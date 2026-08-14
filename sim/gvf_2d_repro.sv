`default_nettype none
`timescale 1ns/1ns

// Minimal repro: 32 threads on 4 cores (CUBE_Z=1) to trace the scheduler deadlock
module gvf_2d_repro;

    localparam CLK_PERIOD = 5.0;
    localparam TIMEOUT    = 500;  // Short timeout - just need to see the stall
    localparam PMEM_DEPTH = 256;
    localparam DMEM_DEPTH = 1024;
    localparam [3:0] OP_CONST = 4'h9, OP_MUL = 4'h5, OP_ADD = 4'h3, OP_STR = 4'h8, OP_RET = 4'hF;
    localparam PROG_ADDR_BITS = 12;
    localparam PROG_BITS      = 16;
    localparam DATA_ADDR_BITS  = 22;
    localparam DATA_BITS       = 8;

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

    gridxKernelTop #(
        .CUBE_X(2), .CUBE_Y(2), .CUBE_Z(1),  // 4 cores
        .PMEM_DEPTH(PMEM_DEPTH), .DMEM_DEPTH(DMEM_DEPTH), .SIM_TIMEOUT_CYCLES(TIMEOUT)
    ) dut (
        .clkSys(clk), .rstN(rst_n),
        .hostWrEn(host_wr_en), .hostWrData(host_wr_data), .hostStart(host_start),
        .kernelDone(kernel_done), .kernelFault(kernel_fault), .kernelStateO(kernel_state),
        .perfHbmReads(perf_hbm_reads), .perfHbmWrites(perf_hbm_writes),
        .perfTotalFlits(perf_total_flits), .perfCycleCount(perf_cycle_count),
        .perfActiveCores(perf_active_cores),
        .dbgCoreDoneSample(dbg_core_done_sample), .dbgMeshBusy(dbg_mesh_busy),
        .pmemWrEn(pmem_wr_en), .pmemWrAddr(pmem_wr_addr), .pmemWrData(pmem_wr_data),
        .dmemWrEn(dmem_wr_en), .dmemWrAddr(dmem_wr_addr), .dmemWrData(dmem_wr_data),
        .dmemRdEn(dmem_rd_en), .dmemRdAddr(dmem_rd_addr), .dmemRdData(dmem_rd_data)
    );

    function [15:0] enc_const(input [3:0] rd, input [7:0] imm);
        enc_const = {OP_CONST, rd, imm};
    endfunction
    function [15:0] enc_rrr(input [3:0] op, rd, rs, rt);
        enc_rrr = {op, rd, rs, rt};
    endfunction

    task automatic write_pmem(input [PROG_ADDR_BITS-1:0] addr, input [PROG_BITS-1:0] data);
        @(posedge clk); pmem_wr_en <= 1; pmem_wr_addr <= addr; pmem_wr_data <= data;
        @(posedge clk); pmem_wr_en <= 0;
    endtask

    initial begin
        integer cycle_cnt;
        // Reset
        rst_n = 0;
        repeat (20) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // Load SAXPY program
        write_pmem(0, enc_const(4'h0, 8'h02));
        write_pmem(1, enc_const(4'h1, 8'h00));
        write_pmem(2, enc_rrr(OP_MUL, 4'h2, 4'h0, 4'h1));
        write_pmem(3, enc_rrr(OP_ADD, 4'h3, 4'h2, 4'h1));
        write_pmem(4, {OP_STR, 4'h3, 4'h1, 4'h0});
        write_pmem(5, {OP_RET, 12'h000});
        repeat(2) @(posedge clk);

        // Configure: 32 threads = 8 blocks on 4 cores
        $display("[REPRO] Configuring 32 threads (8 blocks) on 4-core (CUBE_Z=1) config");
        @(posedge clk); host_wr_en <= 1; host_wr_data <= 16'd32;
        @(posedge clk); host_wr_en <= 0;
        repeat(5) @(posedge clk);

        // Launch
        $display("[REPRO] Launching kernel");
        @(posedge clk); host_start <= 1;
        @(posedge clk); host_start <= 0;

        // Wait and observe
        cycle_cnt = 0;
        while (!kernel_done && !kernel_fault && cycle_cnt < TIMEOUT) begin
            @(posedge clk);
            cycle_cnt = cycle_cnt + 1;
        end

        $display("[REPRO] Result: kernel_done=%0b kernel_fault=%0b kernel_state=%0d cycles=%0d",
                 kernel_done, kernel_fault, kernel_state, cycle_cnt);
        if (!kernel_done && !kernel_fault)
            $display("[REPRO] DEADLOCK CONFIRMED ? stuck after %0d cycles", cycle_cnt);

        repeat(5) @(posedge clk);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * TIMEOUT * 2);
        $display("[REPRO] GLOBAL TIMEOUT");
        $finish;
    end
endmodule
