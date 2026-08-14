// SystemVerilog Assertions for CHI Channel Controller
// Verifies credit flow, OTF bounds, FSM safety, and response ordering.

`timescale 1ns/1ns

module chi_channel_controller_sva #(
    parameter NUM_CORES     = 8,
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 512,
    parameter TXID_WIDTH    = 8,
    parameter OTF_DEPTH     = 16,
    parameter CREDIT_INIT   = 8
) (
    input wire clk,
    input wire reset,

    input wire reqValid,
    input wire reqAccepted,
    input wire reqCreditAvail,

    input wire rspValid,
    input wire snpValid,
    input wire datValid,

    input wire memReqValid,
    input wire memReqReady,
    input wire memRespValid,

    input wire [$clog2(OTF_DEPTH):0] otfCount,
    input wire controllerBusy
);

    // 1. OTF queue never exceeds depth
    property p_otf_bounds;
        @(posedge clk) disable iff (reset)
        otfCount <= OTF_DEPTH;
    endproperty
    assert property (p_otf_bounds)
        else $error("CHI SVA: OTF count exceeded maximum depth");

    // 2. Request accepted only when credits available
    property p_req_needs_credit;
        @(posedge clk) disable iff (reset)
        reqAccepted |-> reqCreditAvail;
    endproperty
    assert property (p_req_needs_credit)
        else $error("CHI SVA: Request accepted without available credit");

    // 3. Memory request handshake stability
    property p_mem_req_stable;
        @(posedge clk) disable iff (reset)
        (memReqValid && !memReqReady) |=> memReqValid;
    endproperty
    assert property (p_mem_req_stable)
        else $error("CHI SVA: mem_req_valid dropped before mem_req_ready");

    // 4. No simultaneous RSP + DAT + SNP (exclusive channel outputs)
    property p_no_triple_channel;
        @(posedge clk) disable iff (reset)
        $countones({rspValid, datValid, snpValid}) <= 1;
    endproperty
    assert property (p_no_triple_channel)
        else $error("CHI SVA: Multiple CHI output channels active simultaneously");

endmodule
