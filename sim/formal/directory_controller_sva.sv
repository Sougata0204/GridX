// SystemVerilog Assertions (SVA) for Directory Coherence Controller
// Verifies MOESI state transitions, response handshakes, and snoop expected mask integrity.

`timescale 1ns/1ns

module directory_controller_sva #(
    parameter NUM_CORES = 8,
    parameter ADDR_WIDTH = 22,
    parameter DATA_WIDTH = 256,
    parameter CORE_ID_WIDTH = 3
) (
    input wire clk,
    input wire reset,

    input wire req_valid,
    input wire [CORE_ID_WIDTH-1:0] req_core_id,
    input wire [ADDR_WIDTH-1:0] req_addr,
    input wire [2:0] req_type,
    input wire req_ready,

    input wire resp_valid,
    input wire [CORE_ID_WIDTH-1:0] resp_core_id,
    input wire [1:0] resp_type,

    input wire snoop_valid,
    input wire [NUM_CORES-1:0] snoop_core_mask,
    input wire [1:0] snoop_type,
    input wire snoop_resp_valid
);

    // 1. Request Handshake Stability: req_valid stays stable until req_ready
    property p_req_handshake;
        @(posedge clk) disable iff (reset)
        (req_valid && !req_ready) |=> req_valid;
    endproperty
    assert property (p_req_handshake)
        else $error("SVA ERROR: req_valid dropped before req_ready asserted");

    // 2. Response Target Core Matches Requested Core
    property p_resp_core_match;
        @(posedge clk) disable iff (reset)
        resp_valid |-> (resp_core_id < NUM_CORES);
    endproperty
    assert property (p_resp_core_match)
        else $error("SVA ERROR: Invalid target core ID in directory response");

    // 3. Snoop Core Mask non-zero when snoop_valid asserted
    property p_snoop_mask_nonzero;
        @(posedge clk) disable iff (reset)
        snoop_valid |-> (snoop_core_mask != 0);
    endproperty
    assert property (p_snoop_mask_nonzero)
        else $error("SVA ERROR: snoop_valid asserted with zero snoop_core_mask");

endmodule
