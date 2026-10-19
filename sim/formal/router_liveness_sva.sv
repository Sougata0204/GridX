// Formal verification assertions for router liveness verifying flit drain and starvation freedom.
`default_nettype none
`timescale 1ns/1ns

import gridx_mem_pkg::*;

module router_liveness_sva (
    input wire clk,
    input wire rst_n,
    input wire flit_t   [NUM_PORTS-1:0] flit_in,
    input wire logic    [NUM_PORTS-1:0] flit_in_valid,
    input wire flit_t   [NUM_PORTS-1:0] flit_out,
    input wire logic    [NUM_PORTS-1:0] flit_out_valid,
    input wire logic  [NUM_PORTS-1:0][NUM_VCS-1:0][$clog2(FLITS_PER_BUFFER):0] fifo_count
);

    genvar p, v;
    generate
        for (p = 0; p < NUM_PORTS; p++) begin : liveness_p
            for (v = 0; v < NUM_VCS; v++) begin : liveness_v
                property p_fifo_drains;
                    @(posedge clk) disable iff (!rst_n)
                    (fifo_count[p][v] > 0) |-> ##[1:256] (fifo_count[p][v] == 0);
                endproperty
                sva_fifo_drains: assert property(p_fifo_drains)
                    else $error("SVA LIVENESS ERROR: Router buffer [%0d][%0d] did not drain within 256 cycles (Deadlock).", p, v);
            end
        end
    endgenerate

endmodule

bind mem_mesh_router router_liveness_sva sva_bind (
    .clk(clk),
    .rst_n(rst_n),
    .flit_in(flit_in),
    .flit_in_valid(flit_in_valid),
    .flit_out(flit_out),
    .flit_out_valid(flit_out_valid),
    .fifo_count(fifo_count)
);
