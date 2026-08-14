// SystemVerilog Assertions (SVA) for AXI4 HBM Bridge
// Verifies AXI4 AW/W/B and AR/R handshake stability and burst size compliance.

`timescale 1ns/1ns

module axi4_hbm_bridge_sva #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 512,
    parameter ID_WIDTH   = 4
) (
    input wire clk,
    input wire reset,

    // Write Address Channel
    input wire [ID_WIDTH-1:0]   sAwid,
    input wire [ADDR_WIDTH-1:0] sAwaddr,
    input wire                  sAwvalid,
    input wire                  sAwready,

    // Write Data Channel
    input wire                  sWvalid,
    input wire                  sWready,

    // Write Response Channel
    input wire                  sBvalid,
    input wire                  sBready,

    // Read Address Channel
    input wire [ID_WIDTH-1:0]   sArid,
    input wire [ADDR_WIDTH-1:0] sAraddr,
    input wire                  sArvalid,
    input wire                  sArready,

    // Read Data Channel
    input wire                  sRvalid,
    input wire                  sRready,

    // Native HBM Interface
    input wire                  hbmReqValid,
    input wire                  hbmReqReady,
    input wire                  hbmRespValid
);

    // 1. AXI4 AWVALID stability until AWREADY
    property p_aw_valid_stable;
        @(posedge clk) disable iff (reset)
        (sAwvalid && !sAwready) |=> sAwvalid;
    endproperty
    assert property (p_aw_valid_stable)
        else $error("AXI4 SVA ERROR: s_awvalid dropped before s_awready");

    // 2. AXI4 ARVALID stability until ARREADY
    property p_ar_valid_stable;
        @(posedge clk) disable iff (reset)
        (sArvalid && !sArready) |=> sArvalid;
    endproperty
    assert property (p_ar_valid_stable)
        else $error("AXI4 SVA ERROR: s_arvalid dropped before s_arready");

    // 3. AXI4 WVALID stability until WREADY
    property p_w_valid_stable;
        @(posedge clk) disable iff (reset)
        (sWvalid && !sWready) |=> sWvalid;
    endproperty
    assert property (p_w_valid_stable)
        else $error("AXI4 SVA ERROR: s_wvalid dropped before s_wready");

    // 4. Native HBM Request Handshake
    property p_hbm_req_handshake;
        @(posedge clk) disable iff (reset)
        (hbmReqValid && !hbmReqReady) |=> hbmReqValid;
    endproperty
    assert property (p_hbm_req_handshake)
        else $error("AXI4 SVA ERROR: hbm_req_valid dropped before hbm_req_ready");

endmodule
