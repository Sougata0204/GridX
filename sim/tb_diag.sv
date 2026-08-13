`default_nettype none
`timescale 1ns/1ns

module tb_diag;
    localparam CLK_P = 5.0; // 200MHz
    reg clk = 0;
    always #(CLK_P/2) clk = ~clk;
    reg rst_n = 0;

    reg host_wr_en = 0;
    reg [15:0] host_wr_data = 0;
    reg host_start = 0;
    wire kernel_done, kernel_fault;
    wire [2:0] kernel_state;
    wire [31:0] perf_hbm_reads, perf_hbm_writes, perf_total_flits;
    wire [31:0] perf_cycle_count, perf_active_cores;
    wire [7:0] dbg_core_done_sample;
    wire dbg_mesh_busy;
    reg pmem_wr_en = 0;
    reg [11:0] pmem_wr_addr = 0;
    reg [15:0] pmem_wr_data = 0;
    reg dmem_wr_en = 0, dmem_rd_en = 0;
    reg [21:0] dmem_wr_addr = 0, dmem_rd_addr = 0;
    reg [7:0] dmem_wr_data = 0;
    wire [7:0] dmem_rd_data;

    gridxKernelTop #(
        .CUBE_X(2), .CUBE_Y(2), .CUBE_Z(2),
        .PMEM_DEPTH(256), .DMEM_DEPTH(1024),
        .SIM_TIMEOUT_CYCLES(50000),
        .THREADS_PER_BLOCK(4),
        .WARPS_PER_CORE(1),
        .NUM_HBM_NODES(2)
    ) dut (
        .clkSys(clk),
        .clkLayer({2{clk}}),
        .rstN(rst_n),
        .hostWrEn(host_wr_en),
        .hostWrData(host_wr_data),
        .hostStart(host_start),
        .kernelDone(kernel_done),
        .kernelFault(kernel_fault),
        .kernelStateO(kernel_state),
        .perfHbmReads(perf_hbm_reads),
        .perfHbmWrites(perf_hbm_writes),
        .perfTotalFlits(perf_total_flits),
        .perfCycleCount(perf_cycle_count),
        .perfActiveCores(perf_active_cores),
        .dbgCoreDoneSample(dbg_core_done_sample),
        .dbgMeshBusy(dbg_mesh_busy),
        .pmemWrEn(pmem_wr_en),
        .pmemWrAddr(pmem_wr_addr),
        .pmemWrData(pmem_wr_data),
        .dmemWrEn(dmem_wr_en),
        .dmemWrAddr(dmem_wr_addr),
        .dmemWrData(dmem_wr_data),
        .dmemRdEn(dmem_rd_en),
        .dmemRdAddr(dmem_rd_addr),
        .dmemRdData(dmem_rd_data)
    );

    // State tracking
    reg [2:0] prev_state = 0;
    integer cycle = 0;
    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (rst_n && kernel_state != prev_state) begin
            $display("[DIAG] Cycle %0d: kernelState %0d -> %0d  done=%b fault=%b coreDone=%b",
                     cycle, prev_state, kernel_state, kernel_done, kernel_fault, dbg_core_done_sample);
        end
        prev_state <= kernel_state;
    end

    task write_pmem(input [11:0] addr, input [15:0] data);
        @(posedge clk);
        pmem_wr_en <= 1; pmem_wr_addr <= addr; pmem_wr_data <= data;
        @(posedge clk);
        pmem_wr_en <= 0;
    endtask

    localparam [3:0] OP_NOP = 4'h0, OP_RET = 4'hF, OP_CONST = 4'h9, OP_ADD = 4'h3;

    initial begin
        
        // Reset
        rst_n = 0;
        repeat(20) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        
        $display("[DIAG] After reset: state=%0d done=%b fault=%b", kernel_state, kernel_done, kernel_fault);

        // TEST 1: Immediate RET
        $display("");
        write_pmem(0, {OP_RET, 12'h000});
        repeat(2) @(posedge clk);

        // Configure: 1 thread
        @(posedge clk); host_wr_en <= 1; host_wr_data <= 16'd1;
        @(posedge clk); host_wr_en <= 0;
        repeat(5) @(posedge clk);
        $display("[DIAG] After DCR: state=%0d", kernel_state);

        // Launch
        @(posedge clk); host_start <= 1;
        @(posedge clk); host_start <= 0;
        $display("[DIAG] Launched. Waiting...");
        
        fork
            begin
                wait(kernel_done || kernel_fault);
                $display("[DIAG] TEST1 DONE: done=%b fault=%b cycles=%0d coreDone=%b",
                         kernel_done, kernel_fault, cycle, dbg_core_done_sample);
            end
            begin
                repeat(10000) @(posedge clk);
                $display("[DIAG] TEST1 TIMEOUT after 10000 cycles. state=%0d coreDone=%b meshBusy=%b",
                         kernel_state, dbg_core_done_sample, dbg_mesh_busy);
            end
        join_any
        disable fork;

        // TEST 2: NOP + RET (4 threads)
        $display("");
        rst_n = 0; repeat(20) @(posedge clk); rst_n = 1; repeat(5) @(posedge clk);
        
        write_pmem(0, {OP_NOP, 12'h000});
        write_pmem(1, {OP_RET, 12'h000});
        repeat(2) @(posedge clk);
        
        @(posedge clk); host_wr_en <= 1; host_wr_data <= 16'd4;
        @(posedge clk); host_wr_en <= 0;
        repeat(5) @(posedge clk);
        
        @(posedge clk); host_start <= 1;
        @(posedge clk); host_start <= 0;
        
        fork
            begin
                wait(kernel_done || kernel_fault);
                $display("[DIAG] TEST2 DONE: done=%b fault=%b cycles=%0d", kernel_done, kernel_fault, cycle);
            end
            begin
                repeat(10000) @(posedge clk);
                $display("[DIAG] TEST2 TIMEOUT state=%0d coreDone=%b", kernel_state, dbg_core_done_sample);
            end
        join_any
        disable fork;

        // TEST 3: CONST + RET (4 threads)
        $display("");
        rst_n = 0; repeat(20) @(posedge clk); rst_n = 1; repeat(5) @(posedge clk);
        
        write_pmem(0, {OP_CONST, 4'h0, 8'h42});  // r0 = 0x42
        write_pmem(1, {OP_CONST, 4'h1, 8'h03});  // r1 = 3
        write_pmem(2, {OP_ADD, 4'h2, 4'h0, 4'h1}); // r2 = r0 + r1
        write_pmem(3, {OP_RET, 12'h000});
        repeat(2) @(posedge clk);
        
        @(posedge clk); host_wr_en <= 1; host_wr_data <= 16'd4;
        @(posedge clk); host_wr_en <= 0;
        repeat(5) @(posedge clk);
        
        @(posedge clk); host_start <= 1;
        @(posedge clk); host_start <= 0;
        
        fork
            begin
                wait(kernel_done || kernel_fault);
                $display("[DIAG] TEST3 DONE: done=%b fault=%b cycles=%0d", kernel_done, kernel_fault, cycle);
            end
            begin
                repeat(10000) @(posedge clk);
                $display("[DIAG] TEST3 TIMEOUT state=%0d coreDone=%b", kernel_state, dbg_core_done_sample);
            end
        join_any
        disable fork;

        $display("");
        repeat(5) @(posedge clk);
        $finish;
    end

    // Safety
    initial begin
        #(CLK_P * 100000);
        $display("[DIAG] GLOBAL TIMEOUT");
        $finish;
    end
endmodule
