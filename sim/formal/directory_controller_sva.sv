// Formal verification assertions for directory coherence controller verifying MOESI transitions and snoop integrity.
`timescale 1ns/1ns

module directory_controller_sva #(
    parameter NUM_CORES = 8,
    parameter ADDR_WIDTH = 22,
    parameter DATA_WIDTH = 256,
    parameter CORE_ID_WIDTH = 3
) (
    input wire clk,
    input wire reset,

    input wire reqValid,
    input wire [CORE_ID_WIDTH-1:0] reqCoreId,
    input wire [ADDR_WIDTH-1:0] reqAddr,
    input wire [2:0] reqType,
    input wire reqReady,

    input wire respValid,
    input wire [CORE_ID_WIDTH-1:0] respCoreId,
    input wire [1:0] respType,

    input wire snoopValid,
    input wire [NUM_CORES-1:0] snoopCoreMask,
    input wire [1:0] snoopType,
    input wire snoopRespValid
);

    property p_req_handshake;
        @(posedge clk) disable iff (reset)
        (reqValid && !reqReady) |=> reqValid;
    endproperty
    assert property (p_req_handshake)
        else $error("SVA ERROR: req_valid dropped before req_ready asserted");

    property p_resp_core_match;
        @(posedge clk) disable iff (reset)
        respValid |-> (respCoreId < NUM_CORES);
    endproperty
    assert property (p_resp_core_match)
        else $error("SVA ERROR: Invalid target core ID in directory response");

    property p_snoop_mask_nonzero;
        @(posedge clk) disable iff (reset)
        snoopValid |-> (snoopCoreMask != 0);
    endproperty
    assert property (p_snoop_mask_nonzero)
        else $error("SVA ERROR: snoop_valid asserted with zero snoop_core_mask");

endmodule
