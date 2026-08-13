// SystemVerilog Formal Verification Bind File
// Binds SVA property modules to GridX RTL targets.

`timescale 1ns/1ns

// Bind SVA to mem_mesh_router
bind mem_mesh_router mem_mesh_router_sva u_mem_mesh_router_sva (
    .clk(clk),
    .rst_n(rst_n),
    .my_coord(my_coord),
    .flit_in(flit_in),
    .flit_in_valid(flit_in_valid),
    .credit_out(credit_out),
    .flit_out(flit_out),
    .flit_out_valid(flit_out_valid),
    .credit_in(credit_in)
);

// Bind SVA to directory_controller
bind directory_controller directory_controller_sva #(
    .NUM_CORES(NUM_CORES),
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .CORE_ID_WIDTH(CORE_ID_WIDTH)
) u_directory_controller_sva (
    .clk(clk),
    .reset(reset),
    .req_valid(req_valid),
    .req_core_id(req_core_id),
    .req_addr(req_addr),
    .req_type(req_type),
    .req_ready(req_ready),
    .resp_valid(resp_valid),
    .resp_core_id(resp_core_id),
    .resp_type(resp_type),
    .snoop_valid(snoop_valid),
    .snoop_core_mask(snoop_core_mask),
    .snoop_type(snoop_type),
    .snoop_resp_valid(snoop_resp_valid)
);

// Bind SVA to axi4_hbm_bridge
bind axi4_hbm_bridge axi4_hbm_bridge_sva #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .ID_WIDTH(ID_WIDTH)
) u_axi4_hbm_bridge_sva (
    .clk(clk),
    .reset(reset),
    .s_awid(s_awid),
    .s_awaddr(s_awaddr),
    .s_awvalid(s_awvalid),
    .s_awready(s_awready),
    .s_wvalid(s_wvalid),
    .s_wready(s_wready),
    .s_bvalid(s_bvalid),
    .s_bready(s_bready),
    .s_arid(s_arid),
    .s_araddr(s_araddr),
    .s_arvalid(s_arvalid),
    .s_arready(s_arready),
    .s_rvalid(s_rvalid),
    .s_rready(s_rready),
    .hbm_req_valid(hbm_req_valid),
    .hbm_req_ready(hbm_req_ready),
    .hbm_resp_valid(hbm_resp_valid)
);

// Bind SVA to simt_stack
bind simt_stack simt_stack_sva #(
    .DEPTH(DEPTH),
    .THREADS_PER_WARP(THREADS_PER_WARP),
    .PC_WIDTH(PC_WIDTH)
) u_simt_stack_sva (
    .clk(clk),
    .reset(reset),
    .branch_valid(branch_valid),
    .branch_taken(branch_taken),
    .current_active_mask(current_active_mask),
    .reconverge(reconverge),
    .stack_empty(stack_empty),
    .stack_full(stack_full),
    .stack_depth(stack_depth)
);
