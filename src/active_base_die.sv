
`default_nettype none
`timescale 1ns/1ns

import gridx_config_pkg::*;

module active_base_die #(
    parameter NUM_COMPUTE_DIES = CFG_CUBE_Z,
    parameter CORES_PER_DIE    = CFG_CUBE_X * CFG_CUBE_Y,
    parameter TOTAL_CORES      = CFG_NUM_CORES,
    parameter ADDR_WIDTH       = CFG_DATA_MEM_ADDR_BITS,
    parameter DATA_WIDTH       = CFG_DATA_MEM_DATA_BITS,
    parameter TSV_DATA_WIDTH   = CFG_TSV_DATA_WIDTH,
    parameter NUM_HBM_NODES    = CFG_NUM_HBM_NODES,
    parameter NUM_NMC_ENGINES  = NUM_HBM_NODES
) (
    input  wire        clk,
    input  wire        reset,

    // TSV Interface (to/from compute dies above)
    input  wire [TOTAL_CORES-1:0]              tsv_rx_valid,
    input  wire [TSV_DATA_WIDTH-1:0]           tsv_rx_data  [TOTAL_CORES-1:0],
    output wire [TOTAL_CORES-1:0]              tsv_tx_valid,
    output wire [TSV_DATA_WIDTH-1:0]           tsv_tx_data  [TOTAL_CORES-1:0],

    // Host Interface
    input  wire                                host_cmd_valid,
    input  wire [127:0]                        host_cmd_data,
    output wire                                host_cmd_ready,

    // MMU Translation Interface
    input  wire                                translate_valid,
    input  wire [CFG_VIRTUAL_ADDR_BITS-1:0]    translate_vaddr,
    input  wire [7:0]                          translate_asid,
    input  wire                                translate_write,
    output wire                                translate_ready,
    output wire [CFG_PHYSICAL_ADDR_BITS-1:0]   translate_paddr,
    output wire                                translate_fault,
    input  wire [CFG_PHYSICAL_ADDR_BITS-1:0]   page_table_base,
    input  wire                                tlb_invalidate_all,

    // NMC Command & Status Interfaces
    input  wire [NUM_NMC_ENGINES-1:0]          nmc_cmd_valid,
    input  wire [3:0]                          nmc_cmd_opcode [NUM_NMC_ENGINES-1:0],
    input  wire [31:0]                         nmc_cmd_addr   [NUM_NMC_ENGINES-1:0],
    input  wire [15:0]                         nmc_cmd_length [NUM_NMC_ENGINES-1:0],
    output wire [NUM_NMC_ENGINES-1:0]          nmc_cmd_ready,
    output wire [NUM_NMC_ENGINES-1:0]          nmc_result_valid,
    output wire [255:0]                        nmc_result_data [NUM_NMC_ENGINES-1:0],
    output wire [NUM_NMC_ENGINES-1:0]          nmc_busy,

    // NMC Memory Access Ports (to HBM stacks)
    output wire [NUM_NMC_ENGINES-1:0]          nmc_mem_read_valid,
    output wire [31:0]                         nmc_mem_read_addr  [NUM_NMC_ENGINES-1:0],
    input  wire [NUM_NMC_ENGINES-1:0]          nmc_mem_read_ready,
    input  wire [255:0]                        nmc_mem_read_data  [NUM_NMC_ENGINES-1:0],
    output wire [NUM_NMC_ENGINES-1:0]          nmc_mem_write_valid,
    output wire [31:0]                         nmc_mem_write_addr [NUM_NMC_ENGINES-1:0],
    output wire [255:0]                        nmc_mem_write_data [NUM_NMC_ENGINES-1:0],
    input  wire [NUM_NMC_ENGINES-1:0]          nmc_mem_write_ready,

    // HCP Launch / Complete Interface
    output wire                                hcp_launch_valid,
    output wire [4:0]                          hcp_launch_task_id,
    output wire [CFG_HCP_CMD_WIDTH-1:0]        hcp_launch_cmd,
    input  wire                                hcp_launch_ack,
    input  wire                                hcp_complete_valid,
    input  wire [4:0]                          hcp_complete_task_id,

    // HBM PHY Interface (to package)
    output wire [NUM_HBM_NODES-1:0]            hbm_phy_active,
    output wire [31:0]                         hbm_total_reads,
    output wire [31:0]                         hbm_total_writes,

    // External DRAM Interface
    output wire                                dram_req_valid,
    output wire [39:0]                         dram_req_addr,
    output wire [255:0]                        dram_req_wdata,
    output wire [2:0]                          dram_req_cmd,
    input  wire                                dram_req_ready,
    input  wire                                dram_resp_valid,
    input  wire [255:0]                        dram_resp_data,

    // Status
    output wire                                base_die_ready,
    output wire [31:0]                         nmc_ops_completed,
    output wire                                hcp_busy,
    output wire                                hcp_graph_done
);

    // TSV BRIDGE ARRAY
    genvar t;
    generate
        for (t = 0; t < TOTAL_CORES; t = t + 1) begin : tsv_bridges
            tsv_bridge #(
                .DATA_WIDTH     (TSV_DATA_WIDTH),
                .LATENCY_CYCLES (CFG_TSV_LATENCY_CYCLES),
                .BUFFER_DEPTH   (4)
            ) u_tsv (
                .clk            (clk),
                .reset          (reset),
                // Transmit path (base -> compute)
                .tx_valid       (tsv_tx_valid[t]),
                .tx_data        (tsv_tx_data[t]),
                .tx_ready       (),
                // Receive path (compute -> base)
                .rx_valid       (),
                .rx_data        (),
                .rx_ready       (1'b1),
                // TSV physical pins
                .tsv_out_valid  (),
                .tsv_out_data   (),
                .tsv_in_valid   (tsv_rx_valid[t]),
                .tsv_in_data    (tsv_rx_data[t]),
                // Perf
                .perf_tx_count  (),
                .perf_rx_count  (),
                .perf_stall_cycles(),
                .link_up        ()
            );
        end
    endgenerate

    // MMU / TLB
    wire        ptw_mem_read_valid;
    wire [39:0] ptw_mem_read_addr;
    wire        ptw_mem_read_ready;
    wire [63:0] ptw_mem_read_data;

    mmu #(
        .VIRTUAL_ADDR_BITS  (CFG_VIRTUAL_ADDR_BITS),
        .PHYSICAL_ADDR_BITS (CFG_PHYSICAL_ADDR_BITS),
        .PAGE_OFFSET_BITS   (CFG_PAGE_OFFSET_BITS),
        .TLB_ENTRIES        (CFG_TLB_ENTRIES),
        .ASID_BITS          (8)
    ) u_mmu (
        .clk                (clk),
        .reset              (reset),
        .translate_valid    (translate_valid),
        .translate_vaddr    (translate_vaddr),
        .translate_asid     (translate_asid),
        .translate_write    (translate_write),
        .translate_ready    (translate_ready),
        .translate_paddr    (translate_paddr),
        .translate_fault    (translate_fault),
        .ptw_mem_read_valid (ptw_mem_read_valid),
        .ptw_mem_read_addr  (ptw_mem_read_addr),
        .ptw_mem_read_ready (ptw_mem_read_ready),
        .ptw_mem_read_data  (ptw_mem_read_data),
        .page_table_base    (page_table_base),
        .tlb_invalidate_all (tlb_invalidate_all),
        .perf_tlb_hits      (),
        .perf_tlb_misses    (),
        .perf_page_faults   ()
    );

    // NEAR-MEMORY COMPUTE ENGINES (one per HBM node)
    wire [31:0] nmc_ops [NUM_NMC_ENGINES-1:0];

    genvar nm;
    generate
        for (nm = 0; nm < NUM_NMC_ENGINES; nm = nm + 1) begin : nmc_engines
            nmc_engine #(
                .DATA_WIDTH      (256),
                .REDUCTION_WIDTH (32),
                .QUEUE_DEPTH     (CFG_NMC_QUEUE_DEPTH),
                .NUM_ALUS        (CFG_NMC_ALU_COUNT)
            ) u_nmc (
                .clk              (clk),
                .reset            (reset),
                .cmd_valid        (nmc_cmd_valid[nm]),
                .cmd_opcode       (nmc_cmd_opcode[nm]),
                .cmd_addr         (nmc_cmd_addr[nm]),
                .cmd_length       (nmc_cmd_length[nm]),
                .cmd_ready        (nmc_cmd_ready[nm]),
                .result_valid     (nmc_result_valid[nm]),
                .result_data      (nmc_result_data[nm]),
                .mem_read_valid   (nmc_mem_read_valid[nm]),
                .mem_read_addr    (nmc_mem_read_addr[nm]),
                .mem_read_ready   (nmc_mem_read_ready[nm]),
                .mem_read_data    (nmc_mem_read_data[nm]),
                .mem_write_valid  (nmc_mem_write_valid[nm]),
                .mem_write_addr   (nmc_mem_write_addr[nm]),
                .mem_write_data   (nmc_mem_write_data[nm]),
                .mem_write_ready  (nmc_mem_write_ready[nm]),
                .busy             (nmc_busy[nm]),
                .perf_ops_completed(nmc_ops[nm])
            );
        end
    endgenerate

    // Aggregate NMC ops
    reg [31:0] nmc_ops_sum;
    integer nmi;
    always @(*) begin
        nmc_ops_sum = 32'd0;
        for (nmi = 0; nmi < NUM_NMC_ENGINES; nmi = nmi + 1)
            nmc_ops_sum = nmc_ops_sum + nmc_ops[nmi];
    end
    assign nmc_ops_completed = nmc_ops_sum;

    // HARDWARE COMMAND PROCESSOR
    hw_command_processor #(
        .MAX_TASKS     (CFG_HCP_MAX_TASKS),
        .MAX_DEPS      (CFG_HCP_MAX_DEPS),
        .CMD_WIDTH     (CFG_HCP_CMD_WIDTH),
        .TASK_ID_WIDTH (5)
    ) u_hcp (
        .clk              (clk),
        .reset            (reset),
        .submit_valid     (host_cmd_valid),
        .submit_task_id   (host_cmd_data[4:0]),
        .submit_cmd       (host_cmd_data[127:0]),
        .submit_dep_count (host_cmd_data[7:5]),
        .submit_dep_ids   (host_cmd_data[27:8]),
        .submit_ready     (host_cmd_ready),
        .launch_valid     (hcp_launch_valid),
        .launch_task_id   (hcp_launch_task_id),
        .launch_cmd       (hcp_launch_cmd),
        .launch_ack       (hcp_launch_ack),
        .complete_valid   (hcp_complete_valid),
        .complete_task_id (hcp_complete_task_id),
        .busy             (hcp_busy),
        .tasks_pending    (),
        .tasks_completed  (),
        .graph_done       (hcp_graph_done)
    );

    // EXTERNAL DRAM CONTROLLER
    wire [255:0] dram_resp_data_256;
    assign ptw_mem_read_data = dram_resp_data_256[63:0];

    wire [2:0] dram_phy_cmd;
    assign dram_req_cmd = dram_phy_cmd;

    dram_ctrl #(
        .ADDR_WIDTH    (40),
        .DATA_WIDTH    (256),
        .BURST_LENGTH  (8),
        .NUM_RANKS     (2)
    ) u_dram (
        .clk            (clk),
        .reset          (reset),
        .req_valid      (ptw_mem_read_valid),
        .req_addr       (ptw_mem_read_addr),
        .req_wdata      (256'd0),
        .req_write      (1'b0),
        .req_ready      (),
        .resp_valid     (ptw_mem_read_ready),
        .resp_data      (dram_resp_data_256),
        .resp_addr      (),
        .phy_cmd_valid  (dram_req_valid),
        .phy_cmd        (dram_phy_cmd),
        .phy_addr       (dram_req_addr),
        .phy_wdata      (dram_req_wdata),
        .phy_rdata      (dram_resp_data),
        .phy_rdata_valid(dram_resp_valid),
        .busy           (),
        .total_reads    (),
        .total_writes   (),
        .row_hits       (),
        .row_misses     ()
    );

    // STATUS
    assign base_die_ready  = ~reset;
    assign hbm_phy_active  = {NUM_HBM_NODES{1'b1}};
    assign hbm_total_reads = 32'd0;
    assign hbm_total_writes = 32'd0;

endmodule
