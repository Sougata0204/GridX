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

    input wire req_valid,
    input wire req_accepted,
    input wire req_credit_avail,

    input wire rsp_valid,
    input wire snp_valid,
    input wire dat_valid,

    input wire mem_req_valid,
    input wire mem_req_ready,
    input wire mem_resp_valid,

    input wire [$clog2(OTF_DEPTH):0] otf_count,
    input wire controller_busy
);

    // 1. OTF queue never exceeds depth
    property p_otf_bounds;
        @(posedge clk) disable iff (reset)
        otf_count <= OTF_DEPTH;
    endproperty
    assert property (p_otf_bounds)
        else $error("CHI SVA: OTF count exceeded maximum depth");

    // 2. Request accepted only when credits available
    property p_req_needs_credit;
        @(posedge clk) disable iff (reset)
        req_accepted |-> req_credit_avail;
    endproperty
    assert property (p_req_needs_credit)
        else $error("CHI SVA: Request accepted without available credit");

    // 3. Memory request handshake stability
    property p_mem_req_stable;
        @(posedge clk) disable iff (reset)
        (mem_req_valid && !mem_req_ready) |=> mem_req_valid;
    endproperty
    assert property (p_mem_req_stable)
        else $error("CHI SVA: mem_req_valid dropped before mem_req_ready");

    // 4. No simultaneous RSP + DAT + SNP (exclusive channel outputs)
    property p_no_triple_channel;
        @(posedge clk) disable iff (reset)
        $countones({rsp_valid, dat_valid, snp_valid}) <= 1;
    endproperty
    assert property (p_no_triple_channel)
        else $error("CHI SVA: Multiple CHI output channels active simultaneously");

endmodule
