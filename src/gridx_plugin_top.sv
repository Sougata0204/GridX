
`default_nettype none
`timescale 1ns/1ns

import gridx_pkg::*;
import gridx_mem_pkg::*;

module gridx_plugin_top #(
    parameter CUBE_X = 2,
    parameter CUBE_Y = 2,
    parameter CUBE_Z = 2,
    parameter WARPS_PER_CORE = 1,
    parameter THREADS_PER_BLOCK = 4
) (
    input  wire clk,
    input  wire reset,
    input  wire start,
    output wire done,

    input  wire device_control_write_enable,
    input  wire [15:0] device_control_data,

    output wire [31:0] hbm_reads,
    output wire [31:0] hbm_writes,
    output wire [31:0] total_flits_forwarded
);

    localparam NUM_CORES = CUBE_X * CUBE_Y * CUBE_Z;
    localparam DATA_MEM_ADDR_BITS = 22;
    localparam DATA_MEM_DATA_BITS = 8;
    localparam PROGRAM_MEM_ADDR_BITS = 12;
    localparam PROGRAM_MEM_DATA_BITS = 16;
    localparam PROGRAM_MEM_NUM_CHANNELS = 16;

    wire [PROGRAM_MEM_NUM_CHANNELS-1:0] pm_read_valid;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] pm_read_address [PROGRAM_MEM_NUM_CHANNELS-1:0];
    reg  [PROGRAM_MEM_NUM_CHANNELS-1:0] pm_read_ready;
    reg  [PROGRAM_MEM_DATA_BITS-1:0] pm_read_data [PROGRAM_MEM_NUM_CHANNELS-1:0];

    wire [NUM_CORES-1:0] dm_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] dm_read_address [NUM_CORES-1:0];
    wire [NUM_CORES-1:0] dm_read_ready;
    wire [DATA_MEM_DATA_BITS-1:0] dm_read_data [NUM_CORES-1:0];

    wire [NUM_CORES-1:0] dm_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] dm_write_address [NUM_CORES-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] dm_write_data [NUM_CORES-1:0];
    wire [NUM_CORES-1:0] dm_write_ready;

    gpu #(
        .NUM_CORES(NUM_CORES),
        .CUBE_X(CUBE_X), .CUBE_Y(CUBE_Y), .CUBE_Z(CUBE_Z),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .WARPS_PER_CORE(WARPS_PER_CORE),
        .PROGRAM_MEM_NUM_CHANNELS(NUM_CORES)
    ) u_gpu (
        .clk(clk), .reset(reset), .start(start), .done(done),
        .device_control_write_enable(device_control_write_enable),
        .device_control_data(device_control_data),

        .program_mem_read_valid(pm_read_valid),
        .program_mem_read_address(pm_read_address),
        .program_mem_read_ready(pm_read_ready),
        .program_mem_read_data(pm_read_data),

        .core_mem_read_valid(dm_read_valid),
        .core_mem_read_address(dm_read_address),
        .core_mem_read_ready(dm_read_ready),
        .core_mem_read_data(dm_read_data),

        .core_mem_write_valid(dm_write_valid),
        .core_mem_write_address(dm_write_address),
        .core_mem_write_data(dm_write_data),
        .core_mem_write_ready(dm_write_ready)
    );

    integer pi;
    always @(posedge clk) begin
        pm_read_ready <= 0;
        for (pi = 0; pi < PROGRAM_MEM_NUM_CHANNELS; pi = pi + 1) begin
            if (pm_read_valid[pi]) begin
                pm_read_ready[pi] <= 1;
                if (pm_read_address[pi] == 12'h005) pm_read_data[pi] <= 16'hF000;
                else pm_read_data[pi] <= 16'h0000;
            end
        end
    end

    flit_t   [gridx_mem_pkg::NUM_NODES-1:0] local_flit_in;
    logic    [gridx_mem_pkg::NUM_NODES-1:0] local_flit_in_valid;
    credit_t [gridx_mem_pkg::NUM_NODES-1:0] local_credit_out;

    flit_t   [gridx_mem_pkg::NUM_NODES-1:0] local_flit_out;
    logic    [gridx_mem_pkg::NUM_NODES-1:0] local_flit_out_valid;
    credit_t [gridx_mem_pkg::NUM_NODES-1:0] local_credit_in;

    mem_mesh_top u_mesh (
        .clk(clk), .rst_n(~reset),
        .local_flit_in(local_flit_in), .local_flit_in_valid(local_flit_in_valid),
        .local_credit_out(local_credit_out),
        .local_flit_out(local_flit_out), .local_flit_out_valid(local_flit_out_valid),
        .local_credit_in(local_credit_in)
    );

    localparam NUM_HBM_NODES = 2;
    localparam HBM_NODE_BASE = NUM_CORES - NUM_HBM_NODES;

    wire [NUM_CORES-1:0] is_hbm_node;
    genvar hb;
    generate
        for (hb = 0; hb < NUM_CORES; hb = hb + 1) begin : hbm_flag
            assign is_hbm_node[hb] = (hb >= HBM_NODE_BASE);
        end
    endgenerate

    genvar n;
    generate
        for (n = 0; n < HBM_NODE_BASE; n = n + 1) begin : core_bridges
            wire bridge_tx_valid;
            wire [511:0] bridge_tx_data;
            wire [1:0] bridge_tx_flit_type;
            wire [1:0] bridge_tx_vc_id;

            wire bridge_rx_valid;
            wire [511:0] bridge_rx_data;
            wire [1:0] bridge_rx_flit_type;
            wire [1:0] bridge_rx_vc_id;
            wire bridge_rx_credit_valid;
            wire [1:0] bridge_rx_credit_vc_id;

            localparam [$clog2(CUBE_X+1)-1:0] MY_X = n % CUBE_X;
            localparam [$clog2(CUBE_Y+1)-1:0] MY_Y = (n / CUBE_X) % CUBE_Y;
            localparam [$clog2(CUBE_Z+1)-1:0] MY_Z = n / (CUBE_X * CUBE_Y);

            mem_mesh_bridge #(
                .NUM_GPU_CHANNELS(1),
                .ADDR_BITS(DATA_MEM_ADDR_BITS),
                .DATA_BITS(DATA_MEM_DATA_BITS),
                .MESH_COORD_W(4)
            ) u_bridge (
                .clk(clk), .reset(reset),
                .gpu_read_valid(dm_read_valid[n]),
                .gpu_read_address('{dm_read_address[n]}),
                .gpu_read_ready(dm_read_ready[n]),
                .gpu_read_data('{dm_read_data[n]}),
                .gpu_write_valid(dm_write_valid[n]),
                .gpu_write_address('{dm_write_address[n]}),
                .gpu_write_data('{dm_write_data[n]}),
                .gpu_write_ready(dm_write_ready[n]),
                .mesh_tx_valid(bridge_tx_valid),
                .mesh_tx_data(bridge_tx_data),
                .mesh_tx_flit_type(bridge_tx_flit_type),
                .mesh_tx_vc_id(bridge_tx_vc_id),
                .mesh_tx_credit_valid(local_credit_out[n].valid),
                .mesh_tx_credit_vc_id(local_credit_out[n].vc_id),
                .mesh_rx_valid(bridge_rx_valid),
                .mesh_rx_data(bridge_rx_data),
                .mesh_rx_flit_type(bridge_rx_flit_type),
                .mesh_rx_vc_id(bridge_rx_vc_id),
                .mesh_rx_credit_valid(bridge_rx_credit_valid),
                .mesh_rx_credit_vc_id(bridge_rx_credit_vc_id),
                .my_x(MY_X), .my_y(MY_Y), .my_z(MY_Z),
                .outstanding_count(),
                .bridge_busy()
            );

            assign local_flit_in_valid[n] = bridge_tx_valid;
            assign local_flit_in[n].data = bridge_tx_data;
            assign local_flit_in[n].flit_type = flit_type_e'(bridge_tx_flit_type);
            assign local_flit_in[n].vc_id = bridge_tx_vc_id;

            assign bridge_rx_valid = local_flit_out_valid[n];
            assign bridge_rx_data = local_flit_out[n].data;
            assign bridge_rx_flit_type = local_flit_out[n].flit_type;
            assign bridge_rx_vc_id = local_flit_out[n].vc_id;

            assign local_credit_in[n].valid = bridge_rx_credit_valid;
            assign local_credit_in[n].vc_id = bridge_rx_credit_vc_id;
        end
    endgenerate

    wire [31:0] hbm_total_reads [NUM_HBM_NODES-1:0];
    wire [31:0] hbm_total_writes [NUM_HBM_NODES-1:0];

    genvar h;
    generate
        for (h = 0; h < NUM_HBM_NODES; h = h + 1) begin : hbm_nodes
            localparam HN = HBM_NODE_BASE + h;

            wire [511:0] hbm_resp_data;
            wire [31:0] hbm_resp_addr;
            wire hbm_resp_valid;
            wire hbm_ready;

            wire [31:0] hbm_req_addr = local_flit_out[HN].data[31:0];
            wire [511:0] hbm_req_wdata = local_flit_out[HN].data;
            wire hbm_req_write = (local_flit_out[HN].vc_id == gridx_mem_pkg::VC_WRITE_REQ);

            hbm3_ctrl u_hbm (
                .clk(clk), .reset(reset),
                .req_valid(local_flit_out_valid[HN]),
                .req_addr(hbm_req_addr),
                .req_wdata(hbm_req_wdata),
                .req_write(hbm_req_write),
                .req_ready(hbm_ready),
                .resp_valid(hbm_resp_valid),
                .resp_data(hbm_resp_data),
                .resp_addr(hbm_resp_addr),
                .total_reads(hbm_total_reads[h]),
                .total_writes(hbm_total_writes[h]),
                .phy_read_valid(~hbm_req_write & local_flit_out_valid[HN]),
                .phy_read_data({512{1'b1}})
            );

            assign local_credit_in[HN].valid = hbm_ready;
            assign local_credit_in[HN].vc_id = 2'd0;

            always @(posedge clk) begin
                if (hbm_resp_valid) begin
                    local_flit_in_valid[HN] <= 1;
                    local_flit_in[HN].data <= hbm_resp_data;
                    local_flit_in[HN].flit_type <= gridx_mem_pkg::FLIT_TAIL;
                    local_flit_in[HN].vc_id <= gridx_mem_pkg::VC_MEM_RESP;
                end else begin
                    local_flit_in_valid[HN] <= 0;
                end
            end
        end
    endgenerate

    reg [31:0] hbm_reads_sum;
    reg [31:0] hbm_writes_sum;
    integer si;
    always @(*) begin
        hbm_reads_sum = 0;
        hbm_writes_sum = 0;
        for (si = 0; si < NUM_HBM_NODES; si = si + 1) begin
            hbm_reads_sum = hbm_reads_sum + hbm_total_reads[si];
            hbm_writes_sum = hbm_writes_sum + hbm_total_writes[si];
        end
    end
    assign hbm_reads = hbm_reads_sum;
    assign hbm_writes = hbm_writes_sum;
    assign total_flits_forwarded = hbm_reads + hbm_writes;

endmodule
