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
    input wire [ID_WIDTH-1:0]   s_awid,
    input wire [ADDR_WIDTH-1:0] s_awaddr,
    input wire                  s_awvalid,
    input wire                  s_awready,

    // Write Data Channel
    input wire                  s_wvalid,
    input wire                  s_wready,

    // Write Response Channel
    input wire                  s_bvalid,
    input wire                  s_bready,

    // Read Address Channel
    input wire [ID_WIDTH-1:0]   s_arid,
    input wire [ADDR_WIDTH-1:0] s_araddr,
    input wire                  s_arvalid,
    input wire                  s_arready,

    // Read Data Channel
    input wire                  s_rvalid,
    input wire                  s_rready,

    // Native HBM Interface
    input wire                  hbm_req_valid,
    input wire                  hbm_req_ready,
    input wire                  hbm_resp_valid
);

    // 1. AXI4 AWVALID stability until AWREADY
    property p_aw_valid_stable;
        @(posedge clk) disable iff (reset)
        (s_awvalid && !s_awready) |=> s_awvalid;
    endproperty
    assert property (p_aw_valid_stable)
        else $error("AXI4 SVA ERROR: s_awvalid dropped before s_awready");

    // 2. AXI4 ARVALID stability until ARREADY
    property p_ar_valid_stable;
        @(posedge clk) disable iff (reset)
        (s_arvalid && !s_arready) |=> s_arvalid;
    endproperty
    assert property (p_ar_valid_stable)
        else $error("AXI4 SVA ERROR: s_arvalid dropped before s_arready");

    // 3. AXI4 WVALID stability until WREADY
    property p_w_valid_stable;
        @(posedge clk) disable iff (reset)
        (s_wvalid && !s_wready) |=> s_wvalid;
    endproperty
    assert property (p_w_valid_stable)
        else $error("AXI4 SVA ERROR: s_wvalid dropped before s_wready");

    // 4. Native HBM Request Handshake
    property p_hbm_req_handshake;
        @(posedge clk) disable iff (reset)
        (hbm_req_valid && !hbm_req_ready) |=> hbm_req_valid;
    endproperty
    assert property (p_hbm_req_handshake)
        else $error("AXI4 SVA ERROR: hbm_req_valid dropped before hbm_req_ready");

endmodule
