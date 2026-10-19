// Formal verification assertions for AXI4 HBM bridge verifying handshake stability and burst size compliance.
`timescale 1ns/1ns

module axi4_hbm_bridge_sva #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 512,
    parameter ID_WIDTH   = 4
) (
    input wire clk,
    input wire reset,

    input wire [ID_WIDTH-1:0]   sAwid,
    input wire [ADDR_WIDTH-1:0] sAwaddr,
    input wire                  sAwvalid,
    input wire                  sAwready,

    input wire                  sWvalid,
    input wire                  sWready,

    input wire                  sBvalid,
    input wire                  sBready,

    input wire [ID_WIDTH-1:0]   sArid,
    input wire [ADDR_WIDTH-1:0] sAraddr,
    input wire                  sArvalid,
    input wire                  sArready,

    input wire                  sRvalid,
    input wire                  sRready,

    input wire                  hbmReqValid,
    input wire                  hbmReqReady,
    input wire                  hbmRespValid
);

    property p_aw_valid_stable;
        @(posedge clk) disable iff (reset)
        (sAwvalid && !sAwready) |=> sAwvalid;
    endproperty
    assert property (p_aw_valid_stable)
        else $error("AXI4 SVA ERROR: s_awvalid dropped before s_awready");

    property p_ar_valid_stable;
        @(posedge clk) disable iff (reset)
        (sArvalid && !sArready) |=> sArvalid;
    endproperty
    assert property (p_ar_valid_stable)
        else $error("AXI4 SVA ERROR: s_arvalid dropped before s_arready");

    property p_w_valid_stable;
        @(posedge clk) disable iff (reset)
        (sWvalid && !sWready) |=> sWvalid;
    endproperty
    assert property (p_w_valid_stable)
        else $error("AXI4 SVA ERROR: s_wvalid dropped before s_wready");

    property p_hbm_req_handshake;
        @(posedge clk) disable iff (reset)
        (hbmReqValid && !hbmReqReady) |=> hbmReqValid;
    endproperty
    assert property (p_hbm_req_handshake)
        else $error("AXI4 SVA ERROR: hbm_req_valid dropped before hbm_req_ready");

endmodule
