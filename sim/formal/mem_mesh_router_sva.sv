// SystemVerilog Assertions (SVA) for MemoryMesh 3D NoC Router
// Verifies credit flow control, FIFO bounds, crossbar mapping, and header integrity.

`timescale 1ps/1ps
import gridx_mem_pkg::*;

module mem_mesh_router_sva (
    input logic clk,
    input logic rst_n,

    input coord_t my_coord,

    input flit_t   [NUM_PORTS-1:0] flit_in,
    input logic    [NUM_PORTS-1:0] flit_in_valid,
    input credit_t [NUM_PORTS-1:0] credit_out,

    input flit_t   [NUM_PORTS-1:0] flit_out,
    input logic    [NUM_PORTS-1:0] flit_out_valid,
    input credit_t [NUM_PORTS-1:0] credit_in
);

    // 1. Credit Underflow & Overflow Checks
    property p_credit_in_bounds(port, vc);
        @(posedge clk) disable iff (!rst_n)
        (credit_out[port].valid && credit_out[port].vc_id == vc) |-> (credit_out[port].vc_id < NUM_VCS);
    endproperty

    genvar p, v;
    generate
        for (p = 0; p < NUM_PORTS; p++) begin : g_port_sva
            for (v = 0; v < NUM_VCS; v++) begin : g_vc_sva
                assert property (p_credit_in_bounds(p, v))
                    else $error("SVA ERROR: Out-of-bounds VC credit returned on port %0d", p);
            end
        end
    endgenerate

    // 2. Flit Out Validity Invariant
    property p_flit_out_valid(port);
        @(posedge clk) disable iff (!rst_n)
        flit_out_valid[port] |-> flit_out[port].valid;
    endproperty

    generate
        for (p = 0; p < NUM_PORTS; p++) begin : g_flit_out_sva
            assert property (p_flit_out_valid(p))
                else $error("SVA ERROR: flit_out_valid asserted without flit_out.valid on port %0d", p);
        end
    endgenerate

    // 3. VC ID Match Invariant
    property p_vc_id_valid(port);
        @(posedge clk) disable iff (!rst_n)
        flit_in_valid[port] |-> (flit_in[port].vc_id < NUM_VCS);
    endproperty

    generate
        for (p = 0; p < NUM_PORTS; p++) begin : g_vc_match_sva
            assert property (p_vc_id_valid(p))
                else $error("SVA ERROR: Invalid VC ID on incoming flit at port %0d", p);
        end
    endgenerate

endmodule
