// UVM top-level testbench module instantiating 3D SoC DUT, virtual interfaces, and launching test suites.
`default_nettype none
`timescale 1ns/1ps

`include "gridx_if.sv"

module tb_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import gridx_uvm_pkg::*;

    localparam CUBE_X = 2;
    localparam CUBE_Y = 2;
    localparam CUBE_Z = 2;
    localparam NUM_CORES = CUBE_X * CUBE_Y * CUBE_Z;
    localparam NUM_HBM_NODES = 2;
    localparam NUM_ACTIVE_CORES = 8;
    localparam HBM_NODE_BASE = NUM_CORES - NUM_HBM_NODES;

    localparam PROG_ADDR_BITS = 12;
    localparam PROG_DATA_BITS = 16;
    localparam DATA_ADDR_BITS = 22;
    localparam DATA_DATA_BITS = 8;
    localparam DMEM_DEPTH     = 8192;
    localparam PMEM_DEPTH     = 4096;
    localparam THREADS_PER_BLOCK = 4;
    localparam WARPS_PER_CORE = 1;

    logic clk;
    logic [CUBE_Z-1:0] clk_layer;
    logic rst_n;

    initial clk = 0;
    always #0.5 clk = ~clk;

    initial begin
        clk_layer = '0;
        fork
            begin #($urandom_range(0, 900) / 1000.0); forever #0.5 clk_layer[0] = ~clk_layer[0]; end
            begin #($urandom_range(0, 900) / 1000.0); forever #0.5 clk_layer[1] = ~clk_layer[1]; end
        join
    end

    initial begin
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
    end

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

    gridxKernelTop #(
        .NUM_CORES(NUM_CORES),
        .CUBE_X(CUBE_X),
        .CUBE_Y(CUBE_Y),
        .CUBE_Z(CUBE_Z),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .WARPS_PER_CORE(WARPS_PER_CORE),
        .PMEM_DEPTH(PMEM_DEPTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .SIM_TIMEOUT_CYCLES(500_000),
        .LOCAL_MEM_RANGE(22'h008FFF)
    ) dut (
        .clkSys         (clk),
        .clkLayer       (clk_layer),
        .rstN           (rst_n),

        .hostWrEn       (host_if.host_wr_en),
        .hostWrData     (host_if.host_wr_data),
        .hostStart      (host_if.host_start),

        .kernelDone     (kernel_status_if.kernel_done),
        .kernelFault    (kernel_status_if.kernel_fault),
        .kernelStateO   (kernel_status_if.kernel_state),

        .perfHbmReads      (kernel_status_if.perf_hbm_reads),
        .perfHbmWrites     (kernel_status_if.perf_hbm_writes),
        .perfTotalFlits    (kernel_status_if.perf_total_flits),
        .perfCycleCount    (kernel_status_if.perf_cycle_count),
        .perfActiveCores   (kernel_status_if.perf_active_cores),
        .perfNoCStallCycles(),

        .dbgCoreDoneSample (kernel_status_if.dbg_core_done_sample),
        .dbgMeshBusy       (kernel_status_if.dbg_mesh_busy),

        .pmemWrEn       (host_if.pmem_wr_en),
        .pmemWrAddr     (host_if.pmem_wr_addr),
        .pmemWrData     (host_if.pmem_wr_data),

        .dmemWrEn       (host_if.dmem_wr_en),
        .dmemWrAddr     (host_if.dmem_wr_addr),
        .dmemWrData     (host_if.dmem_wr_data),
        .dmemRdEn       (host_if.dmem_rd_en),
        .dmemRdAddr     (host_if.dmem_rd_addr),
        .dmemRdData     (host_if.dmem_rd_data)
    );

    initial begin
        forever begin
            @(posedge clk);
            if (dut.dmemWrEn && dut.dmemWrAddr == 22'h8010) begin
                $display("[DEBUG_TB] dataMem[0x8010] written with %0d at time %0t", dut.dmemWrData, $time);
            end
            if (dut.localRdValid[0]) begin
                $display("[DEBUG_TB_RD] time %0t: localRdAddr[0]=%0h, localRdData[0]=%0d, localRdReady[0]=%b, dmemRdData(to core)=%0d",
                         $time, dut.localRdAddr[0], dut.localRdData[0], dut.localRdReady[0], dut.dmRdData[0]);
            end
        end
    end

    initial begin
        uvm_config_db#(virtual gridx_host_if)::set(
            null, "*", "host_vif", host_if);
        uvm_config_db#(virtual gridx_kernel_status_if)::set(
            null, "*", "kernel_status_vif", kernel_status_if);

        run_test();
    end

    initial begin
        #5000000;
        `uvm_fatal("TIMEOUT", "Global simulation timeout reached (5 ms)")
    end

    integer hbm_trace_lsu_req = 0;
    integer hbm_trace_mesh_wr = 0;
    integer hbm_trace_mesh_rd = 0;
    integer hbm_trace_local_wr = 0;
    integer hbm_trace_bridge_tx = 0;
    integer hbm_trace_noc_hbm = 0;
    integer hbm_trace_z_plus = 0;
    integer hbm_trace_z_minus = 0;

    assign kernel_status_if.trace_z_plus = hbm_trace_z_plus;
    assign kernel_status_if.trace_z_minus = hbm_trace_z_minus;
    assign kernel_status_if.trace_lsu_req = hbm_trace_lsu_req;
    assign kernel_status_if.trace_mesh_wr = hbm_trace_mesh_wr;
    assign kernel_status_if.trace_local_wr = hbm_trace_local_wr;

    initial begin
        @(posedge rst_n);
        repeat(100) @(posedge clk);

        forever begin
            @(posedge clk);

            for (int c = 0; c < NUM_ACTIVE_CORES; c++) begin
                if (dut.uGpu.coreMemWriteValid[c]) begin
                    hbm_trace_lsu_req = hbm_trace_lsu_req + 1;
                    if (hbm_trace_lsu_req <= 20)
                        $display("[HBM_TRACE] t=%0t [0-LSU] Core[%0d] LSU_STORE_VALID addr=0x%06h data=0x%02h",
                            $time, c, dut.uGpu.coreMemWriteAddress[c], dut.uGpu.coreMemWriteData[c]);
                end
            end

            for (int c = 0; c < NUM_ACTIVE_CORES; c++) begin
                if (dut.meshBrWrValid[c]) begin
                    hbm_trace_mesh_wr = hbm_trace_mesh_wr + 1;
                    if (hbm_trace_mesh_wr <= 20)
                        $display("[HBM_TRACE] t=%0t [1-ADDR_DECODE] Core[%0d] STORE addr=0x%06h mesh=1 local=0",
                            $time, c, dut.meshBrWrAddr[c]);
                end
                if (dut.localWrValid[c]) begin
                    hbm_trace_local_wr = hbm_trace_local_wr + 1;
                    if (hbm_trace_local_wr <= 20)
                        $display("[HBM_TRACE] t=%0t [1-ADDR_DECODE] Core[%0d] STORE addr=0x%06h mesh=0 local=1",
                            $time, c, dut.localWrAddr[c]);
                end
                if (dut.meshBrRdValid[c]) begin
                    hbm_trace_mesh_rd = hbm_trace_mesh_rd + 1;
                    if (hbm_trace_mesh_rd <= 10)
                        $display("[HBM_TRACE] t=%0t [1-ADDR_DECODE] Core[%0d] READ->MESH addr=0x%06h",
                            $time, c, dut.meshBrRdAddr[c]);
                end
            end

            for (int c = 0; c < NUM_ACTIVE_CORES; c++) begin
                if (dut.coreBrTxValid[c]) begin
                    automatic logic [21:0] br_addr = dut.coreBrTxFlit[c].data[21:0];
                    automatic logic [1:0] br_dz = dut.coreBrTxFlit[c].data[112:111];
                    automatic logic [1:0] br_dy = dut.coreBrTxFlit[c].data[114:113];
                    automatic logic [1:0] br_dx = dut.coreBrTxFlit[c].data[116:115];
                    automatic int br_dnode = br_dx + br_dy * CUBE_X + br_dz * CUBE_X * CUBE_Y;
                    $display("[HBM_TRACE] t=%0t [2-BRIDGE_TX] Core[%0d] Bridge flit out -> CDC, type=%0d addr=0x%06h dest_node=%0d coords=(%0d,%0d,%0d)",
                        $time, c, dut.coreBrTxFlit[c].flit_type, br_addr, br_dnode, br_dx, br_dy, br_dz);
                end

                if (dut.meshFlitInValid[c]) begin
                    hbm_trace_bridge_tx = hbm_trace_bridge_tx + 1;
                    if (hbm_trace_bridge_tx <= 20) begin
                        automatic logic [21:0] flit_addr = dut.meshFlitIn[c].data[21:0];
                        automatic logic [1:0] dest_z = dut.meshFlitIn[c].data[112:111];
                        automatic logic [1:0] dest_y = dut.meshFlitIn[c].data[114:113];
                        automatic logic [1:0] dest_x = dut.meshFlitIn[c].data[116:115];
                        automatic int dest_node = dest_x + dest_y * CUBE_X + dest_z * CUBE_X * CUBE_Y;
                        $display("[HBM_TRACE] t=%0t [2-NOC_INJECT] Node[%0d] flit injected into NoC, type=%0d addr=0x%06h dest_node=%0d coords=(%0d,%0d,%0d)",
                            $time, c, dut.meshFlitIn[c].flit_type, flit_addr, dest_node, dest_x, dest_y, dest_z);
                    end
                end
            end

            for (int h = 0; h < NUM_HBM_NODES; h++) begin
                if (dut.meshFlitOutValid[HBM_NODE_BASE+h]) begin
                    hbm_trace_noc_hbm = hbm_trace_noc_hbm + 1;
                    if (hbm_trace_noc_hbm <= 20)
                        $display("[HBM_TRACE] t=%0t [3-NOC_HBM] Node[%0d] flit reached HBM edge router",
                            $time, HBM_NODE_BASE+h);
                end
            end

            for (int z = 0; z < CUBE_Z; z++) begin
                for (int y = 0; y < CUBE_Y; y++) begin
                    for (int x = 0; x < CUBE_X; x++) begin
                        if (z < CUBE_Z - 1) begin
                            if (dut.uMesh.node_flit_tx_valid[z][y][x][gridx_mem_pkg::PORT_Z_POS]) begin
                                hbm_trace_z_plus = hbm_trace_z_plus + 1;
                                $display("[Z_TRACE] t=%0t Z+ PRESENTED from Node[%0d,%0d,%0d] flit_type=%0d data=%06h",
                                    $time, x, y, z,
                                    dut.uMesh.node_flit_tx[z][y][x][gridx_mem_pkg::PORT_Z_POS].flit_type,
                                    dut.uMesh.node_flit_tx[z][y][x][gridx_mem_pkg::PORT_Z_POS].data[21:0]);
                            end
                            if (dut.uMesh.node_flit_rx_valid[z+1][y][x][gridx_mem_pkg::PORT_Z_NEG]) begin
                                $display("[Z_TRACE] t=%0t Z+ RECEIVED at Node[%0d,%0d,%0d] flit_type=%0d data=%06h",
                                    $time, x, y, z+1,
                                    dut.uMesh.node_flit_rx[z+1][y][x][gridx_mem_pkg::PORT_Z_NEG].flit_type,
                                    dut.uMesh.node_flit_rx[z+1][y][x][gridx_mem_pkg::PORT_Z_NEG].data[21:0]);
                            end
                        end
                        if (z > 0) begin
                            if (dut.uMesh.node_flit_tx_valid[z][y][x][gridx_mem_pkg::PORT_Z_NEG]) begin
                                hbm_trace_z_minus = hbm_trace_z_minus + 1;
                                $display("[Z_TRACE] t=%0t Z- PRESENTED from Node[%0d,%0d,%0d] flit_type=%0d",
                                    $time, x, y, z,
                                    dut.uMesh.node_flit_tx[z][y][x][gridx_mem_pkg::PORT_Z_NEG].flit_type);
                            end
                            if (dut.uMesh.node_flit_rx_valid[z-1][y][x][gridx_mem_pkg::PORT_Z_POS]) begin
                                $display("[Z_TRACE] t=%0t Z- RECEIVED at Node[%0d,%0d,%0d] flit_type=%0d",
                                    $time, x, y, z-1,
                                    dut.uMesh.node_flit_rx[z-1][y][x][gridx_mem_pkg::PORT_Z_POS].flit_type);
                            end
                        end
                    end
                end
            end
        end
    end

    final begin
        $display("");
        $display("  GRIDX3 UVM MULTICORE + 3D MEMORYMESH VERIFICATION SUMMARY");
        $display("  Topology:                  3D Mesh %0dx%0dx%0d (%0d Nodes)", CUBE_X, CUBE_Y, CUBE_Z, NUM_CORES);
        $display("  Active Compute Cores:      %0d", NUM_ACTIVE_CORES);
        $display("  HBM Endpoint Nodes:        %0d", NUM_HBM_NODES);
        $display("  Threads Per Block:         %0d", THREADS_PER_BLOCK);
        $display("  HBM PATH INSTRUMENTATION");
        $display("  [0] LSU Store Valid:         %0d events", hbm_trace_lsu_req);
        $display("  [1] Addr Decode -> Local WR: %0d events", hbm_trace_local_wr);
        $display("  [1] Addr Decode -> Mesh WR:  %0d events", hbm_trace_mesh_wr);
        $display("  [1] Addr Decode -> Mesh RD:  %0d events", hbm_trace_mesh_rd);
        $display("  [2] Bridge -> NoC TX flits:  %0d events", hbm_trace_bridge_tx);
        $display("  [3] NoC -> HBM node flits:   %0d events", hbm_trace_noc_hbm);
        $display("  [4] Z+ Physical link flits:  %0d events", hbm_trace_z_plus);
        $display("  [4] Z- Physical link flits:  %0d events", hbm_trace_z_minus);
        if (hbm_trace_lsu_req == 0)
            $display("  DIAGNOSIS: LSU never issued external store! Check kernel logic.");
        else if (hbm_trace_mesh_wr == 0)
            $display("  DIAGNOSIS: Address decode NEVER routed to mesh!");
        else if (hbm_trace_bridge_tx == 0)
            $display("  DIAGNOSIS: Decode fired but bridge never TX'd. Check bridge FSM.");
        else if (hbm_trace_noc_hbm == 0)
            $display("  DIAGNOSIS: Bridge sent flits but never reached HBM. Check NoC routing.");
        else
            $display("  DIAGNOSIS: PASS - Full HBM path exercised!");
    end

endmodule

`default_nettype wire
