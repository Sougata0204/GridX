`default_nettype none
`timescale 1ps/1ps

import gridx_mem_pkg::*;

module z_link_adapter_uni (
    // Domain A (Sender of Flits, Receiver of Credits)
    input  wire  clk_a,
    input  wire  rst_a_n,
    input  flit_t flit_in,
    input  wire  flit_in_valid,
    output credit_t credit_out,

    // Domain B (Receiver of Flits, Sender of Credits)
    input  wire  clk_b,
    input  wire  rst_b_n,
    output flit_t flit_out,
    output wire  flit_out_valid,
    input  credit_t credit_in
);

    // 1. Flit CDC (A -> B)
    wire flit_empty;
    asyncFifo #(.DATA_WIDTH($bits(flit_t)), .DEPTH(FLITS_PER_BUFFER)) u_flit_fifo (
        .wrClk(clk_a),
        .wrRst(!rst_a_n),
        .wrEn(flit_in_valid),
        .wrData(flit_in),
        .wrFull(), // bounded by architectural credits
        
        .rdClk(clk_b),
        .rdRst(!rst_b_n),
        .rdEn(~flit_empty),
        .rdData(flit_out),
        .rdEmpty(flit_empty)
    );
    assign flit_out_valid = ~flit_empty;

    // 2. Credit CDC (B -> A)
    // We synchronize the pulse credit_in.valid using a fast-to-slow / slow-to-fast pulse synchronizer.
    
    wire [NUM_VCS-1:0] credit_pulses_a;
    genvar vc;
    generate
        for (vc = 0; vc < NUM_VCS; vc++) begin : gen_credit_sync
            pulse_sync u_pulse_sync (
                .clk_a(clk_b),
                .rst_a_n(rst_b_n),
                .pulse_a(credit_in.valid && (credit_in.vc_id == vc)),

                .clk_b(clk_a),
                .rst_b_n(rst_a_n),
                .pulse_b(credit_pulses_a[vc])
            );
        end
    endgenerate

    // 3. Credit Reassembly
    // If multiple pulse synchronizers emit a pulse simultaneously in Domain A,
    // we buffer them and feed them to the router sequentially.
    logic [NUM_VCS-1:0] pending_credits;
    logic [NUM_VCS-1:0] pending_credits_next;
    
    always_ff @(posedge clk_a or negedge rst_a_n) begin
        if (!rst_a_n)
            pending_credits <= '0;
        else
            pending_credits <= pending_credits_next;
    end
    
    always_comb begin
        pending_credits_next = pending_credits | credit_pulses_a;
        credit_out.valid = 1'b0;
        credit_out.vc_id = '0;
        
        for (int i = 0; i < NUM_VCS; i++) begin
            if (pending_credits_next[i]) begin
                credit_out.valid = 1'b1;
                credit_out.vc_id = i[VC_ID_W-1:0];
                pending_credits_next[i] = 1'b0;
                break;
            end
        end
    end

    // CDC Assertions (Formal & Simulation)
    // synthesis translate_off
    // coverage off
`ifndef SYNTHESIS
    property p_no_flit_overflow;
        @(posedge clk_a) disable iff (!rst_a_n)
        u_flit_fifo.wrFull |-> !flit_in_valid;
    endproperty
    assert property (p_no_flit_overflow) else $error("CDC Flit FIFO Overflow!");

    generate
        for (vc = 0; vc < NUM_VCS; vc++) begin : gen_credit_assert
            property p_credit_delivery;
                @(posedge clk_b) disable iff (!rst_b_n)
                (credit_in.valid && (credit_in.vc_id == vc)) |=> 
                s_eventually (@(posedge clk_a) credit_pulses_a[vc]);
            endproperty
            assert property (p_credit_delivery) else $error("Credit Pulse lost in CDC!");
        end
    endgenerate
`endif
    // coverage on
    // synthesis translate_on

endmodule
