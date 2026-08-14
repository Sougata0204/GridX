`default_nettype none
`timescale 1ns/1ns

// Minimal repro for lane-3 store failure.
// 4 threads, 1 block, ZERO branch instructions.
module gvf_lane3_repro;
    localparam CLK_PERIOD     = 5.0;
    localparam TIMEOUT        = 20_000;
    localparam PMEM_DEPTH     = 256;
    localparam DMEM_DEPTH     = 1024;
    localparam DATA_ADDR_BITS = 22;
    localparam DATA_BITS      = 8;
    localparam PROG_ADDR_BITS = 12;
    localparam PROG_BITS      = 16;
    localparam [15:0] BRAM_BASE = 16'hFF80;
    localparam [9:0]  BRAM_IDX  = BRAM_BASE[9:0]; // 0x380 = 896

    localparam [3:0] OP_ADD  = 4'h3, OP_MUL  = 4'h5,
                     OP_STR  = 4'h8, OP_CONST = 4'h9, OP_RET = 4'hF;

    reg clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    reg rst_n = 0;
    reg host_wr_en = 0; reg [15:0] host_wr_data = 0; reg host_start = 0;
    wire kernel_done, kernel_fault; wire [2:0] kernel_state;
    wire [31:0] perf_hbm_reads, perf_hbm_writes, perf_total_flits;
    wire [31:0] perf_cycle_count, perf_active_cores;
    wire [7:0] dbg_core_done_sample; wire dbg_mesh_busy;
    reg pmem_wr_en = 0; reg [PROG_ADDR_BITS-1:0] pmem_wr_addr = 0;
    reg [PROG_BITS-1:0] pmem_wr_data = 0;
    reg dmem_wr_en=0, dmem_rd_en=0;
    reg [DATA_ADDR_BITS-1:0] dmem_wr_addr=0, dmem_rd_addr=0;
    reg [DATA_BITS-1:0] dmem_wr_data=0;
    wire [DATA_BITS-1:0] dmem_rd_data;

    gridxKernelTop #(
        .CUBE_X(1), .CUBE_Y(1), .CUBE_Z(1), // 1 core only
        .PMEM_DEPTH(PMEM_DEPTH), .DMEM_DEPTH(DMEM_DEPTH),
        .SIM_TIMEOUT_CYCLES(TIMEOUT)
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

    task automatic write_pmem(input [PROG_ADDR_BITS-1:0] a, input [PROG_BITS-1:0] d);
        @(posedge clk); pmem_wr_en<=1; pmem_wr_addr<=a; pmem_wr_data<=d;
        @(posedge clk); pmem_wr_en<=0;
    endtask
    task automatic write_dcr(input [15:0] d);
        @(posedge clk); host_wr_en<=1; host_wr_data<=d;
        @(posedge clk); host_wr_en<=0;
    endtask
    task automatic write_dmem(input [DATA_ADDR_BITS-1:0] a, input [DATA_BITS-1:0] d);
        @(posedge clk); dmem_wr_en<=1; dmem_wr_addr<=a; dmem_wr_data<=d;
        @(posedge clk); dmem_wr_en<=0;
    endtask
    task automatic read_dmem(input [DATA_ADDR_BITS-1:0] a);
        @(posedge clk); dmem_rd_en<=1; dmem_rd_addr<=a;
        @(posedge clk); dmem_rd_en<=0;
        @(posedge clk);
    endtask

    initial begin
        $display("[GRIDX3_TEST] Lane-3 Repro Test: 4 threads, 1 block, 1 core");
        rst_n = 0; repeat(20) @(posedge clk); rst_n = 1; repeat(5) @(posedge clk);

        // Poison BRAM locations 896..899
        write_dmem({12'b0, BRAM_IDX} + 0, 8'hAA);
        write_dmem({12'b0, BRAM_IDX} + 1, 8'hAA);
        write_dmem({12'b0, BRAM_IDX} + 2, 8'hAA);
        write_dmem({12'b0, BRAM_IDX} + 3, 8'hAA);

        // Straight-line ADD-STORE: NO branches, NO conditions
        // r1 = 0xFF80 (base addr)
        // r2 = block_id * TPB = r13 * r14 (= 0 for block 0)
        // r3 = global_tid = r2 + r15
        // r4 = addr = r3 + r1
        // r5 = 5
        // r6 = value = r3 + r5
        // STR: DMEM[r4] = r6
        // RET
        write_pmem(0, enc_const(4'h1, 8'h80));
        write_pmem(1, enc_rrr(OP_MUL, 4'h2, 4'hD, 4'hE));
        write_pmem(2, enc_rrr(OP_ADD, 4'h3, 4'h2, 4'hF));
        write_pmem(3, enc_rrr(OP_ADD, 4'h4, 4'h3, 4'h1));
        write_pmem(4, enc_const(4'h5, 8'h05));
        write_pmem(5, enc_rrr(OP_ADD, 4'h6, 4'h3, 4'h5));
        write_pmem(6, {OP_STR, 4'h0, 4'h4, 4'h6});
        write_pmem(7, {OP_RET, 12'h000});

        write_dcr(16'd4); // 4 threads = 1 block
        repeat(5) @(posedge clk);
        @(posedge clk); host_start <= 1;
        @(posedge clk); host_start <= 0;

        // Wait for completion
        begin : wait_loop
            integer cnt;
            cnt = 0;
            while (!kernel_done && !kernel_fault && cnt < TIMEOUT) begin
                @(posedge clk); cnt = cnt + 1;
            end
            $display("kernel_done=%b kernel_fault=%b cycles=%0d", kernel_done, kernel_fault, cnt);
        end

        // Read back all 4 thread locations
        $display("[SCOREBOARD] Per-Thread Results:");
        begin : check
            integer tid;
            reg [7:0] expected, got;
            for (tid = 0; tid < 4; tid = tid + 1) begin
                read_dmem({12'b0, BRAM_IDX} + tid);
                got = dmem_rd_data;
                expected = (tid + 5) & 8'hFF;
                if (got == expected)
                    $display("  [PASS] thread %0d: DMEM[%0d] = 0x%02h (expected 0x%02h)", tid, BRAM_IDX+tid, got, expected);
                else
                    $display("  [FAIL] thread %0d: DMEM[%0d] = 0x%02h (expected 0x%02h)", tid, BRAM_IDX+tid, got, expected);
            end
        end
        repeat(10) @(posedge clk);
        $finish;
    end

    initial begin #(CLK_PERIOD * TIMEOUT * 2); $display("GLOBAL TIMEOUT"); $finish; end
endmodule
