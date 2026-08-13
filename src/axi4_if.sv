`ifndef AXI4_IF_SV
`define AXI4_IF_SV

`default_nettype none
`timescale 1ns/1ns

// AXI4 Full Interface for GridX3 memory bus channels
interface axi4If #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 512,
    parameter ID_WIDTH   = 4,
    parameter LEN_WIDTH  = 8
) (
    input wire clk,
    input wire rstN
);


    // Write Address Channel (AW)
    logic [ID_WIDTH-1:0]    awid;
    logic [ADDR_WIDTH-1:0]  awaddr;
    logic [LEN_WIDTH-1:0]   awlen;
    logic [2:0]             awsize;
    logic [1:0]             awburst;
    logic                   awvalid;
    logic                   awready;

    // Write Data Channel (W)
    logic [DATA_WIDTH-1:0]  wdata;
    logic [DATA_WIDTH/8-1:0] wstrb;
    logic                   wlast;
    logic                   wvalid;
    logic                   wready;

    // Write Response Channel (B)
    logic [ID_WIDTH-1:0]    bid;
    logic [1:0]             bresp;
    logic                   bvalid;
    logic                   bready;

    // Read Address Channel (AR)
    logic [ID_WIDTH-1:0]    arid;
    logic [ADDR_WIDTH-1:0]  araddr;
    logic [LEN_WIDTH-1:0]   arlen;
    logic [2:0]             arsize;
    logic [1:0]             arburst;
    logic                   arvalid;
    logic                   arready;

    // Read Data Channel (R)
    logic [ID_WIDTH-1:0]    rid;
    logic [DATA_WIDTH-1:0]  rdata;
    logic [1:0]             rresp;
    logic                   rlast;
    logic                   rvalid;
    logic                   rready;

    // Master port (core/bridge drives AW/W/AR, receives B/R)
    modport master (
        output awid, awaddr, awlen, awsize, awburst, awvalid,
        input  awready,
        output wdata, wstrb, wlast, wvalid,
        input  wready,
        input  bid, bresp, bvalid,
        output bready,
        output arid, araddr, arlen, arsize, arburst, arvalid,
        input  arready,
        input  rid, rdata, rresp, rlast, rvalid,
        output rready
    );

    // Slave port (HBM controller receives AW/W/AR, drives B/R)
    modport slave (
        input  awid, awaddr, awlen, awsize, awburst, awvalid,
        output awready,
        input  wdata, wstrb, wlast, wvalid,
        output wready,
        output bid, bresp, bvalid,
        input  bready,
        input  arid, araddr, arlen, arsize, arburst, arvalid,
        output arready,
        output rid, rdata, rresp, rlast, rvalid,
        input  rready
    );

endinterface

`default_nettype wire

`endif // AXI4_IF_SV

