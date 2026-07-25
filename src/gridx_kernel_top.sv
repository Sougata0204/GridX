`default_nettype none
`timescale 1ns/1ns

import gridx_pkg::*;
import gridx_mem_pkg::*;

module gridx_kernel_top #(
    // 3D Cube Geometry
    parameter CUBE_X               = 2,
    parameter CUBE_Y               = 2,
    parameter CUBE_Z               = 2,    // Z = number of stacked dies
    parameter NUM_CORES            = CUBE_X * CUBE_Y * CUBE_Z,

    // Memory Widths
    parameter DATA_MEM_ADDR_BITS   = 22,
    parameter DATA_MEM_DATA_BITS   = 8,
    parameter PROG_MEM_ADDR_BITS   = 12,
    parameter PROG_MEM_DATA_BITS   = 16,
    parameter PROG_MEM_CHANNELS    = NUM_CORES,

    // Core Config (scale these)
    parameter THREADS_PER_BLOCK    = 4,
    parameter WARPS_PER_CORE       = 1,

    // HBM Endpoints on Mesh
    parameter NUM_HBM_NODES        = 2,

    // On-Chip Memory
    parameter PMEM_DEPTH           = 4096,
    parameter DMEM_DEPTH           = 4096,

    // Simulation
    parameter SIM_TIMEOUT_CYCLES   = 500_000
) (
    // Clock / Reset
    input  wire        clk_sys,
    input  wire        rst_n,

    // Host Interface
    input  wire        host_wr_en,
    input  wire [15:0] host_wr_data,
    input  wire        host_start,

    // Kernel Status
    output wire        kernel_done,
    output wire        kernel_fault,
    output wire [2:0]  kernel_state_o,

    // Performance Counters
    output wire [31:0] perf_hbm_reads,
    output wire [31:0] perf_hbm_writes,
    output wire [31:0] perf_total_flits,
    output wire [31:0] perf_cycle_count,
    output wire [31:0] perf_active_cores,

    // Debug
    output wire [7:0]  dbg_core_done_sample,
    output wire        dbg_mesh_busy,

    // Program Memory Load
    input  wire                          pmem_wr_en,
    input  wire [PROG_MEM_ADDR_BITS-1:0] pmem_wr_addr,
    input  wire [PROG_MEM_DATA_BITS-1:0] pmem_wr_data,

    // Data Memory Access
    input  wire                           dmem_wr_en,
    input  wire [DATA_MEM_ADDR_BITS-1:0]  dmem_wr_addr,
    input  wire [DATA_MEM_DATA_BITS-1:0]  dmem_wr_data,
    input  wire                           dmem_rd_en,
    input  wire [DATA_MEM_ADDR_BITS-1:0]  dmem_rd_addr,
    output reg  [DATA_MEM_DATA_BITS-1:0]  dmem_rd_data
);

    // CLOCK / RESET
    wire clk   = clk_sys;
    wire reset  = ~rst_n;

    // GPU <-> MEMORY WIRES
    wire [PROG_MEM_CHANNELS-1:0]      pm_rd_valid;
    wire [PROG_MEM_ADDR_BITS-1:0]     pm_rd_addr [PROG_MEM_CHANNELS-1:0];
    reg  [PROG_MEM_CHANNELS-1:0]      pm_rd_ready;
    reg  [PROG_MEM_DATA_BITS-1:0]     pm_rd_data [PROG_MEM_CHANNELS-1:0];

    wire [NUM_CORES-1:0]              dm_rd_valid;
    wire [DATA_MEM_ADDR_BITS-1:0]     dm_rd_addr  [NUM_CORES-1:0];
    reg  [NUM_CORES-1:0]              dm_rd_ready;
    reg  [DATA_MEM_DATA_BITS-1:0]     dm_rd_data  [NUM_CORES-1:0];
    wire [NUM_CORES-1:0]              dm_wr_valid;
    wire [DATA_MEM_ADDR_BITS-1:0]     dm_wr_addr  [NUM_CORES-1:0];
    wire [DATA_MEM_DATA_BITS-1:0]     dm_wr_data  [NUM_CORES-1:0];
    reg  [NUM_CORES-1:0]              dm_wr_ready;

    // 1. ON-CHIP PROGRAM MEMORY (BRAM) - Die 0
    (* ram_style = "block" *) reg [PROG_MEM_DATA_BITS-1:0] prog_mem [0:PMEM_DEPTH-1] = '{default: 16'h0000};

    always @(posedge clk)
        if (pmem_wr_en) prog_mem[pmem_wr_addr] <= pmem_wr_data;

    integer pi;
    always @(posedge clk) begin
        pm_rd_ready <= {PROG_MEM_CHANNELS{1'b0}};
        for (pi = 0; pi < PROG_MEM_CHANNELS; pi = pi + 1) begin
            if (pm_rd_valid[pi]) begin
                pm_rd_ready[pi] <= 1'b1;
                pm_rd_data[pi]  <= prog_mem[pm_rd_addr[pi]];
            end
        end
    end

    // 2. ON-CHIP DATA MEMORY (BRAM) - Die 0
    // Direct BRAM path for cores (bypasses mesh for on-chip data)
    (* ram_style = "block" *) reg [DATA_MEM_DATA_BITS-1:0] data_mem [0:DMEM_DEPTH-1] = '{default: 8'h00};

    // Host write port
    always @(posedge clk)
        if (dmem_wr_en) data_mem[dmem_wr_addr[$clog2(DMEM_DEPTH)-1:0]] <= dmem_wr_data;

    // Host read port (with reset)
    always @(posedge clk) begin
        if (reset)
            dmem_rd_data <= {DATA_MEM_DATA_BITS{1'b0}};
        else if (dmem_rd_en)
            dmem_rd_data <= data_mem[dmem_rd_addr[$clog2(DMEM_DEPTH)-1:0]];
    end

    // Core BRAM Arbiter (round-robin, 1 core/cycle)
    // Services core read/write requests directly from on-chip BRAM.
    // This is the low-latency path; mesh bridge path is for off-chip HBM.
    localparam CORE_IDX_W = (NUM_CORES > 1) ? $clog2(NUM_CORES) : 1;
    reg [CORE_IDX_W-1:0] dmem_arb_ptr;

    always @(posedge clk) begin
        if (reset) begin
            dmem_arb_ptr <= 0;
            dm_rd_ready  <= {NUM_CORES{1'b0}};
            dm_wr_ready  <= {NUM_CORES{1'b0}};
        end else begin
            // Default: de-assert all ready signals
            dm_rd_ready <= {NUM_CORES{1'b0}};
            dm_wr_ready <= {NUM_CORES{1'b0}};

            // Round-robin scan: find next active requester
            begin : arb_scan
                integer c;
                for (c = 0; c < NUM_CORES; c = c + 1) begin
                    automatic integer idx = (dmem_arb_ptr + c) % NUM_CORES;
                    if (dm_wr_valid[idx]) begin
                        // Write: store to BRAM, acknowledge
                        data_mem[dm_wr_addr[idx][$clog2(DMEM_DEPTH)-1:0]] <= dm_wr_data[idx];
                        dm_wr_ready[idx] <= 1'b1;
                        dmem_arb_ptr <= idx[CORE_IDX_W-1:0] + 1;
                        disable arb_scan;
                    end else if (dm_rd_valid[idx]) begin
                        // Read: fetch from BRAM, provide data
                        dm_rd_data[idx]  <= data_mem[dm_rd_addr[idx][$clog2(DMEM_DEPTH)-1:0]];
                        dm_rd_ready[idx] <= 1'b1;
                        dmem_arb_ptr <= idx[CORE_IDX_W-1:0] + 1;
                        disable arb_scan;
                    end
                end
            end
        end
    end

    // 3. VOLUMETRIC MEMORY FABRIC (Memory Sheets)
    wire [NUM_CORES-1:0][5:0] core_face_req_valid;
    wire [NUM_CORES-1:0][5:0] core_face_req_write;
    wire [NUM_CORES-1:0][5:0][DATA_MEM_ADDR_BITS-1:0] core_face_req_addr;
    wire [NUM_CORES-1:0][5:0][DATA_MEM_DATA_BITS-1:0] core_face_req_wdata;
    wire [NUM_CORES-1:0][5:0] core_face_req_ready;

    wire [NUM_CORES-1:0][5:0] core_face_resp_valid;
    wire [NUM_CORES-1:0][5:0][DATA_MEM_DATA_BITS-1:0] core_face_resp_rdata;
    wire [NUM_CORES-1:0][5:0] core_face_resp_ready;

    // Helper macro to calculate linear core ID from 3D coordinates
    `define CORE_ID(x,y,z) ((z) * CUBE_Y * CUBE_X + (y) * CUBE_X + (x))

    genvar gx, gy, gz;
    generate
        // X-Direction Memory Sheets (Between X faces)
        for (gz = 0; gz < CUBE_Z; gz = gz + 1) begin : gen_z_x
            for (gy = 0; gy < CUBE_Y; gy = gy + 1) begin : gen_y_x
                for (gx = 0; gx < CUBE_X - 1; gx = gx + 1) begin : gen_x_sheets
                    localparam CORE_A = `CORE_ID(gx, gy, gz);
                    localparam CORE_B = `CORE_ID(gx+1, gy, gz);
                    
                    memory_sheet #(
                        .ADDR_WIDTH(DATA_MEM_ADDR_BITS),
                        .DATA_WIDTH(DATA_MEM_DATA_BITS)
                    ) ms_x (
                        .clk(clk),
                        .reset(reset),
                        
                        // Side A connects to Core A's +X face (Face 0)
                        .side_a_req_valid(core_face_req_valid[CORE_A][0]),
                        .side_a_req_write(core_face_req_write[CORE_A][0]),
                        .side_a_req_addr(core_face_req_addr[CORE_A][0]),
                        .side_a_req_wdata(core_face_req_wdata[CORE_A][0]),
                        .side_a_req_ready(core_face_req_ready[CORE_A][0]),
                        .side_a_resp_valid(core_face_resp_valid[CORE_A][0]),
                        .side_a_resp_rdata(core_face_resp_rdata[CORE_A][0]),
                        .side_a_resp_ready(core_face_resp_ready[CORE_A][0]),
                        
                        // Side B connects to Core B's -X face (Face 1)
                        .side_b_req_valid(core_face_req_valid[CORE_B][1]),
                        .side_b_req_write(core_face_req_write[CORE_B][1]),
                        .side_b_req_addr(core_face_req_addr[CORE_B][1]),
                        .side_b_req_wdata(core_face_req_wdata[CORE_B][1]),
                        .side_b_req_ready(core_face_req_ready[CORE_B][1]),
                        .side_b_resp_valid(core_face_resp_valid[CORE_B][1]),
                        .side_b_resp_rdata(core_face_resp_rdata[CORE_B][1]),
                        .side_b_resp_ready(core_face_resp_ready[CORE_B][1]),
                        
                        // NoC Local Interface (tied off for now until mesh integration)
                        .noc_req_valid(1'b0),
                        .noc_req_write(1'b0),
                        .noc_req_addr('0),
                        .noc_req_wdata('0),
                        .noc_req_ready(),
                        .noc_resp_valid(),
                        .noc_resp_rdata(),
                        .noc_resp_ready(1'b1),
                        
                        .perf_reads(), .perf_writes(), .perf_bank_conflicts(),
                        .perf_side_a_accesses(), .perf_side_b_accesses(), .perf_noc_accesses(), .perf_merges()
                    );
                end
            end
        end
    endgenerate

    // Edge/Boundary tie-offs for un-instantiated boundary sheets (to avoid floating inputs)
    generate
        for (gz = 0; gz < CUBE_Z; gz = gz + 1) begin : tie_z
            for (gy = 0; gy < CUBE_Y; gy = gy + 1) begin : tie_y
                for (gx = 0; gx < CUBE_X; gx = gx + 1) begin : tie_x
                    localparam CID = `CORE_ID(gx, gy, gz);
                    // If at +X boundary, tie off +X face
                    if (gx == CUBE_X - 1) begin
                        assign core_face_req_ready[CID][0] = 1'b0;
                        assign core_face_resp_valid[CID][0] = 1'b0;
                        assign core_face_resp_rdata[CID][0] = '0;
                    end
                    // If at -X boundary, tie off -X face
                    if (gx == 0) begin
                        assign core_face_req_ready[CID][1] = 1'b0;
                        assign core_face_resp_valid[CID][1] = 1'b0;
                        assign core_face_resp_rdata[CID][1] = '0;
                    end
                    
                    // Tie off Y and Z faces entirely for this stage (until full 3D is wired)
                    assign core_face_req_ready[CID][2] = 1'b0;
                    assign core_face_resp_valid[CID][2] = 1'b0;
                    assign core_face_resp_rdata[CID][2] = '0;
                    
                    assign core_face_req_ready[CID][3] = 1'b0;
                    assign core_face_resp_valid[CID][3] = 1'b0;
                    assign core_face_resp_rdata[CID][3] = '0;
                    
                    assign core_face_req_ready[CID][4] = 1'b0;
                    assign core_face_resp_valid[CID][4] = 1'b0;
                    assign core_face_resp_rdata[CID][4] = '0;
                    
                    assign core_face_req_ready[CID][5] = 1'b0;
                    assign core_face_resp_valid[CID][5] = 1'b0;
                    assign core_face_resp_rdata[CID][5] = '0;
                end
            end
        end
    endgenerate

    // 4. GPU COMPUTE FABRIC - Dies 1..Z (Compute Dies)
    wire gpu_done;
    wire [2:0] kernel_state;

    gpu #(
        .NUM_CORES             (NUM_CORES),
        .CUBE_X                (CUBE_X),
        .CUBE_Y                (CUBE_Y),
        .CUBE_Z                (CUBE_Z),
        .DATA_MEM_ADDR_BITS    (DATA_MEM_ADDR_BITS),
        .DATA_MEM_DATA_BITS    (DATA_MEM_DATA_BITS),
        .PROGRAM_MEM_ADDR_BITS (PROG_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS (PROG_MEM_DATA_BITS),
        .PROGRAM_MEM_NUM_CHANNELS(PROG_MEM_CHANNELS),
        .THREADS_PER_BLOCK     (THREADS_PER_BLOCK),
        .WARPS_PER_CORE        (WARPS_PER_CORE)
    ) u_gpu (
        .clk                        (clk),
        .reset                      (reset),
        .start                      (host_start),
        .done                       (gpu_done),
        .device_control_write_enable(host_wr_en),
        .device_control_data        (host_wr_data),
        .program_mem_read_valid     (pm_rd_valid),
        .program_mem_read_address   (pm_rd_addr),
        .program_mem_read_ready     (pm_rd_ready),
        .program_mem_read_data      (pm_rd_data),
        .core_mem_read_valid        (dm_rd_valid),
        .core_mem_read_address      (dm_rd_addr),
        .core_mem_read_ready        (dm_rd_ready),
        .core_mem_read_data         (dm_rd_data),
        .core_mem_write_valid       (dm_wr_valid),
        .core_mem_write_address     (dm_wr_addr),
        .core_mem_write_data        (dm_wr_data),
        .core_mem_write_ready       (dm_wr_ready),
        .kernel_state_o             (kernel_state),
        
        .core_face_req_valid        (core_face_req_valid),
        .core_face_req_write        (core_face_req_write),
        .core_face_req_addr         (core_face_req_addr),
        .core_face_req_wdata        (core_face_req_wdata),
        .core_face_req_ready        (core_face_req_ready),
        .core_face_resp_valid       (core_face_resp_valid),
        .core_face_resp_rdata       (core_face_resp_rdata),
        .core_face_resp_ready       (core_face_resp_ready)
    );


    assign kernel_done     = gpu_done;
    assign kernel_state_o  = kernel_state;
    assign kernel_fault    = u_gpu.kernel_fault;

    // 4. MEMORYMESH 3D NOC - TSV-Connected Mesh (Inter-Die)
    localparam HBM_NODE_BASE = NUM_CORES - NUM_HBM_NODES;

    flit_t   [gridx_mem_pkg::NUM_NODES-1:0] mesh_flit_in;
    logic    [gridx_mem_pkg::NUM_NODES-1:0] mesh_flit_in_valid;
    credit_t [gridx_mem_pkg::NUM_NODES-1:0] mesh_credit_out;
    flit_t   [gridx_mem_pkg::NUM_NODES-1:0] mesh_flit_out;
    logic    [gridx_mem_pkg::NUM_NODES-1:0] mesh_flit_out_valid;
    credit_t [gridx_mem_pkg::NUM_NODES-1:0] mesh_credit_in;

    mem_mesh_top u_mesh (
        .clk              (clk),
        .rst_n            (rst_n),
        .local_flit_in       (mesh_flit_in),
        .local_flit_in_valid (mesh_flit_in_valid),
        .local_credit_out    (mesh_credit_out),
        .local_flit_out      (mesh_flit_out),
        .local_flit_out_valid(mesh_flit_out_valid),
        .local_credit_in     (mesh_credit_in)
    );

    // Core <-> Mesh Bridges (TSV path for off-chip memory)
    genvar n;
    generate
        for (n = 0; n < HBM_NODE_BASE; n = n + 1) begin : core_bridges
            wire        br_tx_valid;
            wire [511:0] br_tx_data;
            wire [1:0]  br_tx_flit_type;
            wire [1:0]  br_tx_vc_id;
            wire        br_rx_valid;
            wire [511:0] br_rx_data;
            wire [1:0]  br_rx_flit_type;
            wire [1:0]  br_rx_vc_id;
            wire        br_rx_credit_valid;
            wire [1:0]  br_rx_credit_vc_id;

            localparam [$clog2(CUBE_X+1)-1:0] MY_X = n % CUBE_X;
            localparam [$clog2(CUBE_Y+1)-1:0] MY_Y = (n / CUBE_X) % CUBE_Y;
            localparam [$clog2(CUBE_Z+1)-1:0] MY_Z = n / (CUBE_X * CUBE_Y);

            mem_mesh_bridge #(
                .NUM_GPU_CHANNELS(1),
                .ADDR_BITS       (DATA_MEM_ADDR_BITS),
                .DATA_BITS       (DATA_MEM_DATA_BITS),
                .MESH_COORD_W    (4)
            ) u_bridge (
                .clk(clk), .reset(reset),
                .gpu_read_valid   (1'b0),       // BRAM path handles local reads
                .gpu_read_address ('{22'd0}),
                .gpu_read_ready   (),
                .gpu_read_data    (),
                .gpu_write_valid  (1'b0),       // BRAM path handles local writes
                .gpu_write_address('{22'd0}),
                .gpu_write_data   ('{8'd0}),
                .gpu_write_ready  (),
                .mesh_tx_valid        (br_tx_valid),
                .mesh_tx_data         (br_tx_data),
                .mesh_tx_flit_type    (br_tx_flit_type),
                .mesh_tx_vc_id        (br_tx_vc_id),
                .mesh_tx_credit_valid (mesh_credit_out[n].valid),
                .mesh_tx_credit_vc_id (mesh_credit_out[n].vc_id),
                .mesh_rx_valid        (br_rx_valid),
                .mesh_rx_data         (br_rx_data),
                .mesh_rx_flit_type    (br_rx_flit_type),
                .mesh_rx_vc_id        (br_rx_vc_id),
                .mesh_rx_credit_valid (br_rx_credit_valid),
                .mesh_rx_credit_vc_id (br_rx_credit_vc_id),
                .my_x(MY_X), .my_y(MY_Y), .my_z(MY_Z),
                .outstanding_count(), .bridge_busy()
            );

            assign mesh_flit_in_valid[n]   = br_tx_valid;
            assign mesh_flit_in[n].data      = br_tx_data;
            assign mesh_flit_in[n].flit_type = flit_type_e'(br_tx_flit_type);
            assign mesh_flit_in[n].vc_id     = br_tx_vc_id;

            assign br_rx_valid     = mesh_flit_out_valid[n];
            assign br_rx_data      = mesh_flit_out[n].data;
            assign br_rx_flit_type = mesh_flit_out[n].flit_type;
            assign br_rx_vc_id     = mesh_flit_out[n].vc_id;

            assign mesh_credit_in[n].valid = br_rx_credit_valid;
            assign mesh_credit_in[n].vc_id = br_rx_credit_vc_id;
        end
    endgenerate

    // 5. HBM3 MEMORY ENDPOINTS - Die 0 (Base Die)
    wire [31:0] hbm_rd_cnt [NUM_HBM_NODES-1:0];
    wire [31:0] hbm_wr_cnt [NUM_HBM_NODES-1:0];

    genvar h;
    generate
        for (h = 0; h < NUM_HBM_NODES; h = h + 1) begin : hbm_nodes
            localparam HN = HBM_NODE_BASE + h;

            wire [511:0] hbm_resp_data;
            wire [31:0]  hbm_resp_addr;
            wire         hbm_resp_valid;
            wire         hbm_ready;

            wire [31:0]  hbm_req_addr  = mesh_flit_out[HN].data[31:0];
            wire [511:0] hbm_req_wdata = mesh_flit_out[HN].data;
            wire         hbm_req_write = (mesh_flit_out[HN].vc_id == gridx_mem_pkg::VC_WRITE_REQ);

            hbm3_ctrl u_hbm (
                .clk(clk), .reset(reset),
                .req_valid    (mesh_flit_out_valid[HN]),
                .req_addr     (hbm_req_addr),
                .req_wdata    (hbm_req_wdata),
                .req_write    (hbm_req_write),
                .req_ready    (hbm_ready),
                .resp_valid   (hbm_resp_valid),
                .resp_data    (hbm_resp_data),
                .resp_addr    (hbm_resp_addr),
                .total_reads  (hbm_rd_cnt[h]),
                .total_writes (hbm_wr_cnt[h]),
                .phy_read_valid(~hbm_req_write & mesh_flit_out_valid[HN]),
                .phy_read_data ({512{1'b1}}),
                .phy_stack_sel(),
                .phy_channel_sel(),
                .phy_row_addr(),
                .phy_col_addr(),
                .phy_bank_addr(),
                .phy_activate(),
                .phy_read(),
                .phy_write_cmd(),
                .phy_precharge(),
                .phy_write_data(),
                .row_hits(),
                .row_misses(),
                .controller_busy()
            );

            assign mesh_credit_in[HN].valid = hbm_ready;
            assign mesh_credit_in[HN].vc_id = 2'd0;

            always @(posedge clk) begin
                if (hbm_resp_valid) begin
                    mesh_flit_in_valid[HN]    <= 1'b1;
                    mesh_flit_in[HN].data      <= hbm_resp_data;
                    mesh_flit_in[HN].flit_type <= gridx_mem_pkg::FLIT_TAIL;
                    mesh_flit_in[HN].vc_id     <= gridx_mem_pkg::VC_MEM_RESP;
                end else begin
                    mesh_flit_in_valid[HN]    <= 1'b0;
                end
            end
        end
    endgenerate

    // 6. VERTICAL MEMORY CONTROLLER (TSV Interface - Die-to-Die)
    // Provides L2-like cache for vertical memory access across dies.
    // Routes local addresses to on-die L2 SRAM, global to off-die.
    wire [NUM_CORES-1:0] vmc_req_grant;
    wire [DATA_MEM_DATA_BITS-1:0] vmc_req_rdata [NUM_CORES-1:0];
    wire [NUM_CORES-1:0] vmc_req_ready;
    wire vmc_global_req_valid, vmc_global_req_write;
    wire [DATA_MEM_ADDR_BITS-1:0] vmc_global_req_addr;
    wire [DATA_MEM_DATA_BITS-1:0] vmc_global_req_data;

    // Core request arrays for VMC (currently tied off - BRAM arbiter serves local)
    wire [DATA_MEM_ADDR_BITS-1:0] vmc_core_addr [NUM_CORES-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] vmc_core_data [NUM_CORES-1:0];
    genvar vi;
    generate
        for (vi = 0; vi < NUM_CORES; vi = vi + 1) begin : vmc_tieoff
            assign vmc_core_addr[vi] = {DATA_MEM_ADDR_BITS{1'b0}};
            assign vmc_core_data[vi] = {DATA_MEM_DATA_BITS{1'b0}};
        end
    endgenerate

    vertical_memory_controller #(
        .NUM_CORES      (NUM_CORES),
        .ADDR_WIDTH     (DATA_MEM_ADDR_BITS),
        .DATA_WIDTH     (DATA_MEM_DATA_BITS)
    ) u_tsv_ctrl (
        .clk               (clk),
        .reset              (reset),
        .core_req_valid     ({NUM_CORES{1'b0}}),
        .core_req_write     ({NUM_CORES{1'b0}}),
        .core_req_addr      (vmc_core_addr),
        .core_req_data      (vmc_core_data),
        .core_req_grant     (vmc_req_grant),
        .core_req_rdata     (vmc_req_rdata),
        .core_req_ready     (vmc_req_ready),
        .global_req_valid   (vmc_global_req_valid),
        .global_req_write   (vmc_global_req_write),
        .global_req_addr    (vmc_global_req_addr),
        .global_req_data    (vmc_global_req_data),
        .global_req_ready   (1'b1),
        .global_req_rdata   ({DATA_MEM_DATA_BITS{1'b0}})
    );

    // 7. DMA ENGINE - Bulk Host<->Device Transfers (Die 0)
    dma_engine #(
        .ADDR_BITS       (DATA_MEM_ADDR_BITS),
        .DATA_WIDTH      (64),
        .BURST_SIZE      (8),
        .SRAM_ADDR_BITS  (11)
    ) u_dma (
        .clk               (clk),
        .reset              (reset),
        .cmd_valid          (1'b0),
        .cmd_direction      (1'b0),
        .cmd_ext_addr       ({DATA_MEM_ADDR_BITS{1'b0}}),
        .cmd_sram_addr      (11'd0),
        .cmd_length         (8'd0),
        .cmd_ready          (),
        .cmd_done           (),
        .cmd_error          (),
        .ext_read_valid     (),
        .ext_read_address   (),
        .ext_read_ready     (1'b1),
        .ext_read_data      (64'd0),
        .ext_write_valid    (),
        .ext_write_address  (),
        .ext_write_data     (),
        .ext_write_ready    (1'b1),
        .sram_read_valid    (),
        .sram_read_address  (),
        .sram_read_ready    (1'b1),
        .sram_read_data     (64'd0),
        .sram_write_valid   (),
        .sram_write_address (),
        .sram_write_data    (),
        .sram_write_ready   (1'b1),
        .busy               (),
        .words_transferred  ()
    );

    // 8. POWER & CLOCK MANAGEMENT - Per-Die Power Gating + DVFS

    // Power controller (bank-level power gating for cores)
    localparam PWR_BANKS = NUM_CORES;
    wire [PWR_BANKS-1:0] pwr_bank_enable;

    power_controller #(
        .NUM_BANKS      (PWR_BANKS),
        .IDLE_CYCLES    (16),
        .SLEEP_CYCLES   (256)
    ) u_pwr (
        .clk               (clk),
        .reset              (reset),
        .bank_active        (~u_gpu.core_done & u_gpu.core_start),
        .force_enable       ({PWR_BANKS{1'b0}}),
        .force_sleep        ({PWR_BANKS{1'b0}}),
        .bank_power_enable  (pwr_bank_enable),
        .bank_power_state   (),
        .bank_needs_reload  (),
        .total_active_cycles(),
        .total_idle_cycles  (),
        .total_sleep_cycles (),
        .state_transitions  (),
        .bank_was_active    ()
    );

    // Clock domain controller (cluster-level DVFS)
    localparam NUM_CLK_CLUSTERS = (NUM_CORES > 1) ? NUM_CORES : 2;
    wire [6:0] cluster_temp_arr [NUM_CLK_CLUSTERS-1:0];
    genvar ci;
    generate
        for (ci = 0; ci < NUM_CLK_CLUSTERS; ci = ci + 1) begin : clk_temp
            assign cluster_temp_arr[ci] = 7'd40;  // Default 40°C
        end
    endgenerate

    clk_domain_ctrl #(
        .NUM_CLUSTERS      (NUM_CLK_CLUSTERS),
        .CORES_PER_CLUSTER (1),
        .SAMPLE_WINDOW     (1024)
    ) u_clk_ctrl (
        .clk                   (clk),
        .reset                 (reset),
        .cluster_alu_active    (u_gpu.core_perf_alu_active[NUM_CLK_CLUSTERS-1:0]),
        .cluster_tensor_active (u_gpu.core_perf_tensor_active[NUM_CLK_CLUSTERS-1:0]),
        .cluster_stall_mem     (u_gpu.core_perf_stall_mem[NUM_CLK_CLUSTERS-1:0]),
        .cluster_temp          (cluster_temp_arr),
        .thermal_limit         (7'd95),
        .cluster_perf_level    (),
        .cluster_clock_enable  (),
        .cluster_power_gate    (),
        .cluster_throttled     (),
        .total_gated_cycles    ()
    );

    // 9. COMPUTE UTILIZATION MONITOR
    compute_utilization u_util (
        .clk               (clk),
        .reset              (reset),
        .core_active        (u_gpu.kernel_running),
        .alu_enable         (1'b1),
        .alu_executing      (|u_gpu.core_perf_alu_active),
        .tensor_busy        (|u_gpu.core_perf_tensor_active),
        .tensor_executing   (|u_gpu.core_perf_tensor_active),
        .alu_active_cycles  (),
        .alu_idle_cycles    (),
        .tensor_active_cycles(),
        .tensor_idle_cycles (),
        .alu_active_pulse   (),
        .alu_idle_pulse     (),
        .tensor_active_pulse(),
        .tensor_idle_pulse  ()
    );

    // 10. 3D INTERCONNECT INFRASTRUCTURE

    // Express link - long-distance mesh shortcut (core 0 ↔ core N-1)
    express_link #(
        .DATA_WIDTH  (DATA_MEM_DATA_BITS),
        .ADDR_WIDTH  (DATA_MEM_ADDR_BITS),
        .LINK_LATENCY(2)
    ) u_express (
        .clk        (clk),
        .reset      (reset),
        .a_tx_valid (1'b0),
        .a_tx_data  ({DATA_MEM_DATA_BITS{1'b0}}),
        .a_tx_addr  ({DATA_MEM_ADDR_BITS{1'b0}}),
        .a_tx_write (1'b0),
        .a_tx_ready (),
        .a_rx_valid (),
        .a_rx_data  (),
        .a_rx_addr  (),
        .a_rx_write (),
        .a_rx_ready (1'b1),
        .b_tx_valid (1'b0),
        .b_tx_data  ({DATA_MEM_DATA_BITS{1'b0}}),
        .b_tx_addr  ({DATA_MEM_ADDR_BITS{1'b0}}),
        .b_tx_write (1'b0),
        .b_tx_ready (),
        .b_rx_valid (),
        .b_rx_data  (),
        .b_rx_addr  (),
        .b_rx_write (),
        .b_rx_ready (1'b1)
    );

    // Multicast tree - broadcast/multicast distribution for barrier sync
    multicast_tree #(
        .NUM_GROUPS  (4),
        .MAX_TARGETS (NUM_CORES),
        .FLIT_WIDTH  (32)
    ) u_mcast (
        .clk               (clk),
        .reset             (reset),
        .cfg_valid         (1'b0),
        .cfg_group_id      (2'd0),
        .cfg_target_mask   ({NUM_CORES{1'b0}}),
        .cfg_enable        (1'b0),
        .flit_in_valid     (1'b0),
        .flit_in_data      (32'd0),
        .flit_in_group_id  (2'd0),
        .flit_in_is_multicast(1'b0),
        .flit_out_valid    (),
        .flit_out_data     (),
        .flit_out_target_id(),
        .flit_out_ready    (1'b1),
        .busy              ()
    );

    // Credit manager - NoC flow control for mesh traffic
    credit_manager #(
        .MAX_CREDITS  (16),
        .CREDIT_WIDTH (5)
    ) u_credits (
        .clk                (clk),
        .reset              (reset),
        .consume            (|mesh_flit_in_valid),
        .release_credit     (|mesh_flit_out_valid),
        .available          (),
        .can_issue          (),
        .nearly_empty       (),
        .empty              (),
        .total_consumed     (),
        .total_released     (),
        .min_credits_seen   (),
        .max_outstanding_seen()
    );

    // Mem shell controller - L3 shell memory on die surface
    mem_shell_controller #(
        .NUM_FACES   (6),
        .ADDR_WIDTH  (DATA_MEM_ADDR_BITS),
        .DATA_WIDTH  (DATA_MEM_DATA_BITS),
        .SHELL_SIZE_BYTES (256 * 1024)
    ) u_shell (
        .clk               (clk),
        .reset             (reset),
        .face_req_valid    (6'd0),
        .face_req_write    (6'd0),
        .face_req_addr     ('{default: '0}),
        .face_req_wdata    ('{default: '0}),
        .face_req_ready    (),
        .face_req_rdata    (),
        .face_credit_available(),
        .sram_req_valid    (),
        .sram_req_write    (),
        .sram_req_addr     (),
        .sram_req_wdata    (),
        .sram_req_ready    (1'b1),
        .sram_req_rdata    ({DATA_MEM_DATA_BITS{1'b0}})
    );

    // Prefetch engine - hardware stride-based prefetcher
    prefetch_engine #(
        .ADDR_WIDTH (DATA_MEM_ADDR_BITS),
        .DATA_WIDTH (DATA_MEM_DATA_BITS),
        .NUM_ENTRIES(8),
        .PREFETCH_DIST (4)
    ) u_prefetch (
        .clk            (clk),
        .reset          (reset),
        .lsu_load_valid (1'b0),
        .lsu_load_addr  ({DATA_MEM_ADDR_BITS{1'b0}}),
        .pf_req_valid   (),
        .pf_req_addr    (),
        .pf_req_ready   (1'b1),
        .active_streams (),
        .pf_issued_count(),
        .pf_hit_count   ()
    );

    // 11. PERFORMANCE COUNTERS
    reg [31:0] cycle_counter;
    always @(posedge clk)
        if (reset) cycle_counter <= 32'd0;
        else       cycle_counter <= cycle_counter + 32'd1;

    assign perf_cycle_count = cycle_counter;

    // HBM aggregated counters
    reg [31:0] hbm_reads_sum, hbm_writes_sum;
    integer si;
    always @(*) begin
        hbm_reads_sum  = 32'd0;
        hbm_writes_sum = 32'd0;
        for (si = 0; si < NUM_HBM_NODES; si = si + 1) begin
            hbm_reads_sum  = hbm_reads_sum  + hbm_rd_cnt[si];
            hbm_writes_sum = hbm_writes_sum + hbm_wr_cnt[si];
        end
    end
    assign perf_hbm_reads   = hbm_reads_sum;
    assign perf_hbm_writes  = hbm_writes_sum;
    assign perf_total_flits = hbm_reads_sum + hbm_writes_sum;

    // Active core count
    localparam DBG_SAMPLE_W = (NUM_CORES < 8) ? NUM_CORES : 8;
    assign dbg_core_done_sample = u_gpu.core_done[DBG_SAMPLE_W-1:0];
    reg [31:0] active_count;
    integer ai;
    always @(*) begin
        active_count = 32'd0;
        for (ai = 0; ai < NUM_CORES; ai = ai + 1)
            active_count = active_count + {31'd0, ~u_gpu.core_done[ai] & u_gpu.core_start[ai]};
    end
    assign perf_active_cores = active_count;
    assign dbg_mesh_busy = |mesh_flit_in_valid | |mesh_flit_out_valid;

    // 12. SIMULATION WATCHDOG
    // synthesis translate_off
    reg [31:0] sim_wd;
    always @(posedge clk) begin
        if (reset) sim_wd <= 0;
        else begin
            sim_wd <= sim_wd + 1;
            if (kernel_done) begin
                $display("[KERNEL_TOP] COMPLETE — cycles=%0d hbm_rd=%0d hbm_wr=%0d",
                         cycle_counter, perf_hbm_reads, perf_hbm_writes);
            end
            if (sim_wd >= SIM_TIMEOUT_CYCLES) begin
                $display("[KERNEL_TOP] TIMEOUT at %0d cycles", SIM_TIMEOUT_CYCLES);
                $finish;
            end
        end
    end
    // synthesis translate_on

endmodule
