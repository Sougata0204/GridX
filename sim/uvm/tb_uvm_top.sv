// GridX3 UVM Top-Level Testbench
// Instantiates DUT, creates virtual interfaces, sets uvm_config_db, and calls run_test().

`default_nettype none
`timescale 1ns/1ps

// Include virtual interfaces (before the module, not inside a package)
`include "gridx_if.sv"

module tb_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import gridx_uvm_pkg::*;

    // Parameters matching the DUT
    localparam PROG_ADDR_BITS = 12;
    localparam PROG_DATA_BITS = 16;
    localparam DATA_ADDR_BITS = 22;
    localparam DATA_DATA_BITS = 8;
    localparam DMEM_DEPTH     = 8192;
    localparam PMEM_DEPTH     = 4096;

    // Clock and reset
    logic clk;
    logic [3:0] clk_layer; // CUBE_Z = 4
    logic rst_n;

    // Base System Clock: 1 ns period (1 GHz sim clock)
    initial clk = 0;
    always #0.5 clk = ~clk;

    // Layer Clocks with Randomized Phase Offsets
    // This perfectly stresses the CDC Gray pointers by shifting the clock edges,
    // without altering the period (which would break the synchronous global dispatcher).
    initial begin
        clk_layer = 4'b0000;
        // Inject random phase delays (between 0 and 0.9 ns)
        fork
            begin #($urandom_range(0, 900) / 1000.0); forever #0.5 clk_layer[0] = ~clk_layer[0]; end
            begin #($urandom_range(0, 900) / 1000.0); forever #0.5 clk_layer[1] = ~clk_layer[1]; end
            begin #($urandom_range(0, 900) / 1000.0); forever #0.5 clk_layer[2] = ~clk_layer[2]; end
            begin #($urandom_range(0, 900) / 1000.0); forever #0.5 clk_layer[3] = ~clk_layer[3]; end
        join
    end

    // Reset sequence
    initial begin
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
    end

    // Virtual interface instances
    gridx_host_if #(
        .PROG_ADDR_BITS(PROG_ADDR_BITS),
        .PROG_DATA_BITS(PROG_DATA_BITS),
        .DATA_ADDR_BITS(DATA_ADDR_BITS),
        .DATA_DATA_BITS(DATA_DATA_BITS)
    ) host_if (
        .clk(clk),
        .rst_n(rst_n)
    );

    gridx_kernel_status_if kernel_status_if (
        .clk(clk),
        .rst_n(rst_n)
    );

    // DUT instantiation
    gridx_kernel_top #(
        .NUM_CORES(64),
        .CUBE_X(4),
        .CUBE_Y(4),
        .CUBE_Z(4),
        .THREADS_PER_BLOCK(32),
        .WARPS_PER_CORE(4),
        .PMEM_DEPTH(PMEM_DEPTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .SIM_TIMEOUT_CYCLES(500_000),
        .LOCAL_MEM_RANGE(22'h00009F)
    ) dut (
        .clk_sys        (clk),
        .clk_layer      (clk_layer),
        .rst_n          (rst_n),

        // Host interface — driven by UVM driver via virtual interface
        .host_wr_en     (host_if.host_wr_en),
        .host_wr_data   (host_if.host_wr_data),
        .host_start     (host_if.host_start),

        // Kernel status — observed by UVM monitor
        .kernel_done    (kernel_status_if.kernel_done),
        .kernel_fault   (kernel_status_if.kernel_fault),
        .kernel_state_o (kernel_status_if.kernel_state),

        // Performance counters
        .perf_hbm_reads    (kernel_status_if.perf_hbm_reads),
        .perf_hbm_writes   (kernel_status_if.perf_hbm_writes),
        .perf_total_flits  (kernel_status_if.perf_total_flits),
        .perf_cycle_count  (kernel_status_if.perf_cycle_count),
        .perf_active_cores (kernel_status_if.perf_active_cores),

        // Debug
        .dbg_core_done_sample (kernel_status_if.dbg_core_done_sample),
        .dbg_mesh_busy        (kernel_status_if.dbg_mesh_busy),

        // Program memory load — driven by UVM driver
        .pmem_wr_en     (host_if.pmem_wr_en),
        .pmem_wr_addr   (host_if.pmem_wr_addr),
        .pmem_wr_data   (host_if.pmem_wr_data),

        // Data memory — driven/read by UVM driver
        .dmem_wr_en     (host_if.dmem_wr_en),
        .dmem_wr_addr   (host_if.dmem_wr_addr),
        .dmem_wr_data   (host_if.dmem_wr_data),
        .dmem_rd_en     (host_if.dmem_rd_en),
        .dmem_rd_addr   (host_if.dmem_rd_addr),
        .dmem_rd_data   (host_if.dmem_rd_data)
    );

    // Set virtual interfaces into uvm_config_db for all UVM components
    initial begin
        uvm_config_db#(virtual gridx_host_if)::set(
            null, "uvm_test_top.m_env.m_host_agent.*", "host_vif", host_if);
        uvm_config_db#(virtual gridx_kernel_status_if)::set(
            null, "uvm_test_top.m_env.m_kernel_agent.*", "kernel_status_vif", kernel_status_if);

        // Run UVM test — memory stress test
        run_test("gridx_mem_stress_test");


    end


    // Global timeout
    initial begin
        #5000000;
        `uvm_fatal("TIMEOUT", "Global simulation timeout reached (5 ms)")
    end


    //  HBM PATH INSTRUMENTATION — traces the valid chain end-to-end
    //  [0] LSU Request
    //  [1] LSU addr_decode → mesh routing
    //  [2] Bridge TX → NoC flit injection
    //  [3] NoC delivery → HBM endpoint nodes
    integer hbm_trace_lsu_req = 0;
    integer hbm_trace_mesh_wr = 0;
    integer hbm_trace_mesh_rd = 0;
    integer hbm_trace_local_wr = 0;
    integer hbm_trace_bridge_tx = 0;
    integer hbm_trace_noc_hbm = 0;

    initial begin
        // Wait for reset deassert
        @(posedge rst_n);
        repeat(100) @(posedge clk);

        forever begin
            @(posedge clk);

            // Stage 0: LSU Request
            for (int c = 0; c < 64; c++) begin
                if (dut.u_gpu.core_mem_write_valid[c]) begin
                    hbm_trace_lsu_req = hbm_trace_lsu_req + 1;
                    if (hbm_trace_lsu_req <= 20)
                        $display("[HBM_TRACE] t=%0t [0-LSU] Core[%0d] LSU_STORE_VALID addr=0x%06h data=0x%02h range=0x%06h",
                            $time, c, dut.u_gpu.core_mem_write_address[c], dut.u_gpu.core_mem_write_data[c], dut.LOCAL_MEM_RANGE);
                end
            end

            // Stage 1: Address Decode → mesh routing (check all 64 cores)
            for (int c = 0; c < 64; c++) begin
                if (dut.mesh_br_wr_valid[c]) begin
                    hbm_trace_mesh_wr = hbm_trace_mesh_wr + 1;
                    if (hbm_trace_mesh_wr <= 20)
                        $display("[HBM_TRACE] t=%0t [1-ADDR_DECODE] Core[%0d] STORE addr=0x%06h range=0x%06h mesh=1 local=0",
                            $time, c, dut.mesh_br_wr_addr[c], dut.LOCAL_MEM_RANGE);
                end
                // Trace specifically for Q1 Waveform (Addr 0x1000A0)
                if (c == 0) begin
                    if (dut.mesh_br_wr_valid[0] && dut.mesh_br_wr_addr[0] == 22'h1000A0) begin
                        $display("[Q1_WAVE] t=%0t | Mesh Bridge 0 TX Write Data=0x%0x -> Addr 0x1000A0", $time, dut.mesh_br_wr_data[0]);
                    end
                    if (dut.mesh_br_rd_valid[0] && dut.mesh_br_rd_addr[0] == 22'h1000A0) begin
                        $display("[Q1_WAVE] t=%0t | Mesh Bridge 0 TX Read Request -> Addr 0x1000A0", $time);
                    end
                    if (dut.mesh_br_rd_ready[0]) begin
                        $display("[Q1_WAVE] t=%0t | Mesh Bridge 0 RX Read Response <- Data=0x%0x", $time, dut.mesh_br_rd_data[0]);
                    end
                end
                if (dut.local_wr_valid[c]) begin
                    hbm_trace_local_wr = hbm_trace_local_wr + 1;
                    if (hbm_trace_local_wr <= 20)
                        $display("[HBM_TRACE] t=%0t [1-ADDR_DECODE] Core[%0d] STORE addr=0x%06h range=0x%06h mesh=0 local=1",
                            $time, c, dut.local_wr_addr[c], dut.LOCAL_MEM_RANGE);
                end
                if (dut.mesh_br_rd_valid[c]) begin
                    hbm_trace_mesh_rd = hbm_trace_mesh_rd + 1;
                    if (hbm_trace_mesh_rd <= 10)
                        $display("[HBM_TRACE] t=%0t [1-ADDR_DECODE] Core[%0d] READ->MESH addr=0x%06h",
                            $time, c, dut.mesh_br_rd_addr[c]);
                end
            end

            // Stage 2: Bridge → NoC flit injection (check all 64 nodes)
            for (int c = 0; c < 64; c++) begin
                if (dut.mesh_flit_in_valid[c] && dut.mesh_br_wr_valid[c]) begin
                    hbm_trace_bridge_tx = hbm_trace_bridge_tx + 1;
                    if (hbm_trace_bridge_tx <= 20)
                        $display("[HBM_TRACE] t=%0t [2-BRIDGE_TX] Node[%0d] flit injected into NoC, addr=0x%06h",
                            $time, c, dut.mesh_br_wr_addr[c]);
                end
            end

            // Stage 3: NoC → HBM endpoint (nodes 60-63)
            for (int h = 0; h < 4; h++) begin
                if (dut.mesh_flit_out_valid[60+h]) begin
                    hbm_trace_noc_hbm = hbm_trace_noc_hbm + 1;
                    if (hbm_trace_noc_hbm <= 10)
                        $display("[HBM_TRACE] t=%0t [3-NOC_HBM] HBM node[%0d] received flit",
                            $time, 60+h);
                end
            end
        end
    end

    // Print summary at end of simulation
    final begin
        $display("");
        $display("  HBM PATH INSTRUMENTATION SUMMARY");
        $display("  [0] LSU Store Valid:         %0d events", hbm_trace_lsu_req);
        $display("  [1] Addr Decode -> Local WR: %0d events", hbm_trace_local_wr);
        $display("  [1] Addr Decode -> Mesh WR:  %0d events", hbm_trace_mesh_wr);
        $display("  [2] Bridge -> NoC TX flits:  %0d events", hbm_trace_bridge_tx);
        $display("  [3] NoC -> HBM node flits:   %0d events", hbm_trace_noc_hbm);
        if (hbm_trace_lsu_req == 0)
            $display("  DIAGNOSIS: LSU never issued external store! Check kernel logic.");
        else if (hbm_trace_mesh_wr == 0)
            $display("  DIAGNOSIS: Address decode NEVER routed to mesh!");
        else if (hbm_trace_bridge_tx == 0)
            $display("  DIAGNOSIS: Decode fired but bridge never TX'd. Check bridge FSM.");
        else if (hbm_trace_noc_hbm == 0)
            $display("  DIAGNOSIS: Bridge sent flits but never reached HBM. Check NoC routing.");
        else
            $display("  DIAGNOSIS: PASS — Full HBM path exercised!");
    end

endmodule

`default_nettype wire
