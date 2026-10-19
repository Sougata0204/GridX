// Formal verification bind module attaching SVA property checkers to GridX RTL targets.
`timescale 1ns/1ns

module gridx_formal_bind;

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

bind directoryController directory_controller_sva #(
    .NUM_CORES(NUM_CORES),
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .CORE_ID_WIDTH(CORE_ID_WIDTH)
) u_directory_controller_sva (
    .clk(clk),
    .reset(reset),
    .reqValid(reqValid),
    .reqCoreId(reqCoreId),
    .reqAddr(reqAddr),
    .reqType(reqType),
    .reqReady(reqReady),
    .respValid(respValid),
    .respCoreId(respCoreId),
    .respType(respType),
    .snoopValid(snoopValid),
    .snoopCoreMask(snoopCoreMask),
    .snoopType(snoopType),
    .snoopRespValid(snoopRespValid)
);

bind axi4HbmBridge axi4_hbm_bridge_sva #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .ID_WIDTH(ID_WIDTH)
) u_axi4_hbm_bridge_sva (
    .clk(clk),
    .reset(reset),
    .sAwid(sAwid),
    .sAwaddr(sAwaddr),
    .sAwvalid(sAwvalid),
    .sAwready(sAwready),
    .sWvalid(sWvalid),
    .sWready(sWready),
    .sBvalid(sBvalid),
    .sBready(sBready),
    .sArid(sArid),
    .sAraddr(sAraddr),
    .sArvalid(sArvalid),
    .sArready(sArready),
    .sRvalid(sRvalid),
    .sRready(sRready),
    .hbmReqValid(hbmReqValid),
    .hbmReqReady(hbmReqReady),
    .hbmRespValid(hbmRespValid)
);

bind simtStack simt_stack_sva #(
    .DEPTH(DEPTH),
    .THREADS_PER_WARP(THREADS_PER_WARP),
    .PC_WIDTH(PC_WIDTH)
) u_simt_stack_sva (
    .clk(clk),
    .reset(reset),
    .branchValid(branchValid),
    .branchTaken(branchTaken),
    .currentActiveMask(currentActiveMask),
    .reconverge(reconverge),
    .stackEmpty(stackEmpty),
    .stackFull(stackFull),
    .stackDepth(stackDepth)
);

bind creditManager credit_manager_sva u_credit_manager_sva (
    .clk(clk),
    .reset(reset),
    .allocValid(allocValid),
    .allocReady(allocReady),
    .freeValid(freeValid),
    .creditsAvailable(creditsAvailable)
);

bind asyncFifo async_fifo_sva u_async_fifo_sva (
    .wrClk(wrClk),
    .wrRst(wrRst),
    .wrEn(wrEn),
    .wrFull(wrFull),
    .rdClk(rdClk),
    .rdRst(rdRst),
    .rdEn(rdEn),
    .rdEmpty(rdEmpty)
);

bind chiChannelController chi_channel_controller_sva u_chi_channel_controller_sva (
    .clk(clk),
    .reset(reset),
    .reqValid(reqValid),
    .reqAccepted(reqAccepted),
    .reqCreditAvail(reqCreditAvail),
    .rspValid(rspValid),
    .snpValid(snpValid),
    .datValid(datValid),
    .memReqValid(memReqValid),
    .memReqReady(memReqReady),
    .memRespValid(memRespValid),
    .otfCount(otfCount),
    .controllerBusy(controllerBusy)
);

endmodule
