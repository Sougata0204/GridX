
`default_nettype none
`timescale 1ns/1ns

// ISA program testbench running a comprehensive instruction set regression across all ALU and memory operations.
module tb_isa_program;

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
            @(posedge clk);
            @(posedge clk);
        end
    endtask

    task automatic load_isa_program;
        begin
            write_pmem_word(12'h000, 16'h9140);
            write_pmem_word(12'h001, 16'h5111);
            write_pmem_word(12'h002, 16'h9208);
            write_pmem_word(12'h003, 16'h5112);

            write_pmem_word(12'h004, 16'h9210);
            write_pmem_word(12'h005, 16'h9320);
            write_pmem_word(12'h006, 16'h9430);
            write_pmem_word(12'h007, 16'h9B40);

            write_pmem_word(12'h008, 16'h352F);
            write_pmem_word(12'h009, 16'h363F);
            write_pmem_word(12'h00A, 16'h3CBF);

            write_pmem_word(12'h00B, 16'h3212);
            write_pmem_word(12'h00C, 16'h3313);
            write_pmem_word(12'h00D, 16'h3414);

            write_pmem_word(12'h00E, 16'h322F);
            write_pmem_word(12'h00F, 16'h333F);
            write_pmem_word(12'h010, 16'h344F);

            write_pmem_word(12'h011, 16'h7720);
            write_pmem_word(12'h012, 16'h7830);
            write_pmem_word(12'h013, 16'h3978);
            write_pmem_word(12'h014, 16'h8049);

            write_pmem_word(12'h015, 16'hEA78);
            write_pmem_word(12'h016, 16'h80BA);

            write_pmem_word(12'h017, 16'h20F0);
            write_pmem_word(12'h018, 16'h141A);
            write_pmem_word(12'h019, 16'h1E29);

            write_pmem_word(12'h01A, 16'h9B40);
            write_pmem_word(12'h01B, 16'h72B0);
            write_pmem_word(12'h01C, 16'h9301);
            write_pmem_word(12'h01D, 16'h3BB3);
            write_pmem_word(12'h01E, 16'h74B0);
            write_pmem_word(12'h01F, 16'h3BB3);
            write_pmem_word(12'h020, 16'h75B0);
            write_pmem_word(12'h021, 16'h3BB3);
            write_pmem_word(12'h022, 16'h76B0);
            write_pmem_word(12'h023, 16'h3C24);
            write_pmem_word(12'h024, 16'h3CC5);
            write_pmem_word(12'h025, 16'h3CC6);
            write_pmem_word(12'h026, 16'h9850);
            write_pmem_word(12'h027, 16'h3818);
            write_pmem_word(12'h028, 16'h808C);

            write_pmem_word(12'h029, 16'hF000);
            repeat (5) @(posedge clk);
        end
    endtask

    reg [7:0] C0, C1, C2, C3;
    reg [7:0] Reduction_Sum;
    integer cycle_cnt = 0;
    integer file_handle;

    initial begin
        $display("[TB] GridX3 ISA Program Testbench (Closed-Loop Run)");

        do_reset();

        $display("[TB] Loading input vectors A and B to global data memory...");
        write_dmem_byte(22'h8010, 8'd2);
        write_dmem_byte(22'h8011, 8'd3);
        write_dmem_byte(22'h8012, 8'd5);
        write_dmem_byte(22'h8013, 8'd7);

        write_dmem_byte(22'h8020, 8'd11);
        write_dmem_byte(22'h8021, 8'd13);
        write_dmem_byte(22'h8022, 8'd17);
        write_dmem_byte(22'h8023, 8'd19);

        $display("[TB] Configuring DCR registers (4 threads)...");
        write_dcr_word(16'd4);
        repeat (5) @(posedge clk);

        $display("[TB] Loading ISA micro-program to program memory...");
        load_isa_program();

        $display("[TB] Launching kernel...");
        @(posedge clk);
        host_start <= 1;
        @(posedge clk);
        host_start <= 0;

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

        $display("[TB] Reading back results from data memory...");
        read_dmem_byte(22'h8030); C0 = dmem_rd_data;
        read_dmem_byte(22'h8031); C1 = dmem_rd_data;
        read_dmem_byte(22'h8032); C2 = dmem_rd_data;
        read_dmem_byte(22'h8033); C3 = dmem_rd_data;
        read_dmem_byte(22'h8050); Reduction_Sum = dmem_rd_data;

        $display("[TB] Results retrieved:");
        $display("  Vector Add C = [%0d, %0d, %0d, %0d]", C0, C1, C2, C3);
        $display("  Reduction Sum = %0d", Reduction_Sum);

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
