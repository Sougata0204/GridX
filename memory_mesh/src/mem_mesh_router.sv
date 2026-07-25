// `default_nettype none  -- removed: module uses `logic` typed ports
`timescale 1ps/1ps

import gridx_mem_pkg::*;

module mem_mesh_router (
    input  logic clk,
    input  logic rst_n,

    input  coord_t my_coord,

    input  flit_t   [NUM_PORTS-1:0] flit_in,
    input  logic    [NUM_PORTS-1:0] flit_in_valid,
    output credit_t [NUM_PORTS-1:0] credit_out,

    output flit_t   [NUM_PORTS-1:0] flit_out,
    output logic    [NUM_PORTS-1:0] flit_out_valid,
    input  credit_t [NUM_PORTS-1:0] credit_in
);

    flit_t [NUM_PORTS-1:0][NUM_VCS-1:0][FLITS_PER_BUFFER-1:0] buffer_data;
    logic  [NUM_PORTS-1:0][NUM_VCS-1:0][$clog2(FLITS_PER_BUFFER)-1:0] wr_ptr;
    logic  [NUM_PORTS-1:0][NUM_VCS-1:0][$clog2(FLITS_PER_BUFFER)-1:0] rd_ptr;
    logic  [NUM_PORTS-1:0][NUM_VCS-1:0][$clog2(FLITS_PER_BUFFER):0]   fifo_count;

    logic  [NUM_PORTS-1:0][NUM_VCS-1:0][CREDIT_WIDTH-1:0] downstream_credits;

    typedef enum logic {
        OVC_IDLE   = 1'b0,
        OVC_ACTIVE = 1'b1
    } ovc_state_e;

    ovc_state_e [NUM_PORTS-1:0][NUM_VCS-1:0] ovc_state;

    logic [NUM_PORTS-1:0][NUM_VCS-1:0][2:0]          ovc_lock_in_port;
    logic [NUM_PORTS-1:0][NUM_VCS-1:0][VC_ID_W-1:0]  ovc_lock_in_vc;

    logic [NUM_PORTS-1:0][NUM_VCS-1:0][2:0] rc_out_port;
    logic [NUM_PORTS-1:0][NUM_VCS-1:0]      rc_valid;

    logic [NUM_PORTS-1:0][NUM_VCS-1:0][2:0] s1_out_port;
    logic [NUM_PORTS-1:0][NUM_VCS-1:0]      s1_valid;
    logic [NUM_PORTS-1:0][NUM_VCS-1:0][2:0] latched_route;

    logic [1:0] bids_in_flight [NUM_PORTS][NUM_VCS];

    always_comb begin
        rc_valid    = '0;
        rc_out_port = '0;

        for (int p = 0; p < NUM_PORTS; p++) begin
            for (int v = 0; v < NUM_VCS; v++) begin
                if (fifo_count[p][v] > {1'b0, bids_in_flight[p][v]}) begin
                    automatic flit_t head_f;
                    automatic logic [COORD_X_W-1:0] dest_x;
                    automatic logic [COORD_Y_W-1:0] dest_y;
                    automatic logic [COORD_Z_W-1:0] dest_z;

                    head_f = buffer_data[p][v][rd_ptr[p][v]];
                    rc_valid[p][v] = 1'b1;

                    if (head_f.flit_type == FLIT_HEAD) begin
                        dest_x = head_f.data[116:115];
                        dest_y = head_f.data[114:113];
                        dest_z = head_f.data[112:111];

                        if      (dest_x > my_coord.x) rc_out_port[p][v] = PORT_X_POS;
                        else if (dest_x < my_coord.x) rc_out_port[p][v] = PORT_X_NEG;
                        else if (dest_y > my_coord.y) rc_out_port[p][v] = PORT_Y_POS;
                        else if (dest_y < my_coord.y) rc_out_port[p][v] = PORT_Y_NEG;
                        else if (dest_z > my_coord.z) rc_out_port[p][v] = PORT_Z_POS;
                        else if (dest_z < my_coord.z) rc_out_port[p][v] = PORT_Z_NEG;
                        else                          rc_out_port[p][v] = PORT_LOCAL;
                    end else begin
                        rc_out_port[p][v] = latched_route[p][v];
                    end
                end
            end
        end
    end

    // Forward declarations (needed before always_comb blocks)
    logic [NUM_PORTS-1:0][NUM_VCS-1:0] s2_va_grant;
    logic [NUM_PORTS-1:0][NUM_VCS-1:0][2:0] s2_out_port;
    logic [NUM_PORTS-1:0][NUM_VCS-1:0] va_grant_comb;
    logic [NUM_PORTS-1:0]              sa_grant_valid;
    logic [NUM_PORTS-1:0][2:0]         sa_win_in_port;
    logic [NUM_PORTS-1:0][VC_ID_W-1:0] sa_win_vc;

    logic s1_ready [NUM_PORTS][NUM_VCS];
    logic s2_ready [NUM_PORTS][NUM_VCS];
    logic bid_granted [NUM_PORTS][NUM_VCS];

    always_comb begin
        for (int p = 0; p < NUM_PORTS; p++) begin
            for (int v = 0; v < NUM_VCS; v++) begin
                bid_granted[p][v] = 1'b0;
                for (int out_p = 0; out_p < NUM_PORTS; out_p++) begin
                    if (sa_grant_valid[out_p] && (sa_win_in_port[out_p] == p) && (sa_win_vc[out_p] == v)) begin
                        bid_granted[p][v] = 1'b1;
                    end
                end

                s2_ready[p][v] = bid_granted[p][v] || !s2_va_grant[p][v];
                s1_ready[p][v] = s2_ready[p][v]   || !s1_valid[p][v];
            end
        end
    end

    always_comb begin
        va_grant_comb = '0;

        for (int p = 0; p < NUM_PORTS; p++) begin
            for (int v = 0; v < NUM_VCS; v++) begin
                if (s1_valid[p][v]) begin
                    if (buffer_data[p][v][rd_ptr[p][v]].flit_type == FLIT_HEAD) begin

                        if (ovc_state[s1_out_port[p][v]][v] == OVC_IDLE)
                            va_grant_comb[p][v] = 1'b1;
                    end else begin

                        if (ovc_state[s1_out_port[p][v]][v] == OVC_ACTIVE &&
                            ovc_lock_in_port[s1_out_port[p][v]][v] == p[2:0] &&
                            ovc_lock_in_vc[s1_out_port[p][v]][v]   == v[VC_ID_W-1:0])
                            va_grant_comb[p][v] = 1'b1;
                    end
                end
            end
        end
    end

    always_comb begin
        sa_grant_valid = '0;
        sa_win_in_port = '0;
        sa_win_vc      = '0;

        for (int out_p = 0; out_p < NUM_PORTS; out_p++) begin

            for (int pri_pass = 0; pri_pass < 4; pri_pass++) begin

                int v;
                if      (pri_pass == 0) v = 2;
                else if (pri_pass == 1) v = 0;
                else if (pri_pass == 2) v = 1;
                else                    v = 3;

                if (!sa_grant_valid[out_p]) begin
                    for (int in_p = 0; in_p < NUM_PORTS; in_p++) begin
                        if (!sa_grant_valid[out_p] &&
                            s2_va_grant[in_p][v] &&
                            (s2_out_port[in_p][v] == out_p[2:0]) &&
                            (downstream_credits[out_p][v] > '0)) begin

                            sa_grant_valid[out_p]  = 1'b1;
                            sa_win_in_port[out_p]  = in_p[2:0];
                            sa_win_vc[out_p]       = v[VC_ID_W-1:0];
                        end
                    end
                end
            end
        end
    end

    flit_t  [NUM_PORTS-1:0] xbar_flit_comb;
    logic   [NUM_PORTS-1:0] xbar_valid_comb;

    always_comb begin
        xbar_flit_comb  = '0;
        xbar_valid_comb = '0;

        for (int out_p = 0; out_p < NUM_PORTS; out_p++) begin
            if (sa_grant_valid[out_p]) begin
                automatic logic [2:0]         wp = sa_win_in_port[out_p];
                automatic logic [VC_ID_W-1:0] wv = sa_win_vc[out_p];
                automatic flit_t src_flit;
                src_flit = buffer_data[wp][wv][rd_ptr[wp][wv]];

                // Full-width crossbar data transfer (all FLIT_WIDTH bits)
                xbar_flit_comb[out_p].data      = src_flit.data;

                xbar_flit_comb[out_p].valid     = src_flit.valid;
                xbar_flit_comb[out_p].flit_type = src_flit.flit_type;
                xbar_flit_comb[out_p].vc_id     = src_flit.vc_id;
                xbar_valid_comb[out_p]          = 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin

            wr_ptr          <= '0;
            rd_ptr          <= '0;
            fifo_count      <= '0;
            credit_out      <= '0;
            latched_route   <= '0;
            ovc_state       <= '0;
            ovc_lock_in_port<= '0;
            ovc_lock_in_vc  <= '0;
            s1_valid        <= '0;
            s1_out_port     <= '0;
            s2_va_grant     <= '0;
            s2_out_port     <= '0;
            flit_out        <= '0;
            flit_out_valid  <= '0;
            for (int p = 0; p < NUM_PORTS; p++) begin
                for (int v = 0; v < NUM_VCS; v++) begin
                    bids_in_flight[p][v] <= '0;
                end
            end

            for (int p = 0; p < NUM_PORTS; p++) begin
                for (int v = 0; v < NUM_VCS; v++) begin
                    downstream_credits[p][v] <= CREDIT_WIDTH'(FLITS_PER_BUFFER);
                end
            end
        end else begin

            for (int p = 0; p < NUM_PORTS; p++)
                credit_out[p].valid <= 1'b0;

            for (int p = 0; p < NUM_PORTS; p++) begin
                if (credit_in[p].valid)
                    downstream_credits[p][credit_in[p].vc_id] <=
                        downstream_credits[p][credit_in[p].vc_id] + 1'b1;
            end

            for (int p = 0; p < NUM_PORTS; p++) begin
                if (flit_in_valid[p]) begin
                    automatic logic [VC_ID_W-1:0] vc_w;
                    vc_w = flit_in[p].vc_id;
                    if (fifo_count[p][vc_w] < ($clog2(FLITS_PER_BUFFER)+1)'(FLITS_PER_BUFFER)) begin
                        buffer_data[p][vc_w][wr_ptr[p][vc_w]] <= flit_in[p];
                        wr_ptr[p][vc_w]     <= wr_ptr[p][vc_w] + 1'b1;
                        fifo_count[p][vc_w] <= fifo_count[p][vc_w] + 1'b1;
                    end
                end
            end

            for (int p = 0; p < NUM_PORTS; p++) begin
                for (int v = 0; v < NUM_VCS; v++) begin
                    if (s1_ready[p][v]) begin
                        s1_valid[p][v]    <= rc_valid[p][v];
                        s1_out_port[p][v] <= rc_out_port[p][v];
                    end
                end
            end

            for (int p = 0; p < NUM_PORTS; p++) begin
                for (int v = 0; v < NUM_VCS; v++) begin
                    if (s2_ready[p][v]) begin
                        s2_va_grant[p][v] <= s1_valid[p][v];
                        s2_out_port[p][v] <= s1_out_port[p][v];
                    end
                end
            end

            for (int p = 0; p < NUM_PORTS; p++) begin
                for (int v = 0; v < NUM_VCS; v++) begin
                    automatic logic bid_launched = (rc_valid[p][v] && s1_ready[p][v]);
                    if (bid_launched && !bid_granted[p][v]) begin
                        bids_in_flight[p][v] <= bids_in_flight[p][v] + 1'b1;
                    end else if (!bid_launched && bid_granted[p][v]) begin
                        bids_in_flight[p][v] <= bids_in_flight[p][v] - 1'b1;
                    end
                end
            end

            flit_out       <= xbar_flit_comb;
            flit_out_valid <= xbar_valid_comb;

            for (int out_p = 0; out_p < NUM_PORTS; out_p++) begin
                if (sa_grant_valid[out_p]) begin
                    automatic logic [2:0]         wp = sa_win_in_port[out_p];
                    automatic logic [VC_ID_W-1:0] wv = sa_win_vc[out_p];

                    rd_ptr[wp][wv]     <= rd_ptr[wp][wv] + 1'b1;
                    fifo_count[wp][wv] <= fifo_count[wp][wv] - 1'b1;

                    downstream_credits[out_p][wv] <=
                        downstream_credits[out_p][wv] - 1'b1;

                    credit_out[wp].valid <= 1'b1;
                    credit_out[wp].vc_id <= wv;

                    if (buffer_data[wp][wv][rd_ptr[wp][wv]].flit_type == FLIT_HEAD) begin

                        latched_route[wp][wv]          <= s2_out_port[wp][wv];
                        ovc_state[out_p][wv]           <= OVC_ACTIVE;
                        ovc_lock_in_port[out_p][wv]    <= wp;
                        ovc_lock_in_vc[out_p][wv]      <= wv;
                    end
                    else if (buffer_data[wp][wv][rd_ptr[wp][wv]].flit_type == FLIT_TAIL) begin

                        ovc_state[out_p][wv] <= OVC_IDLE;
                    end
                end
            end

        end
    end

`ifndef SYNTHESIS

    logic [6:0] warmup_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) warmup_cnt <= '0;
        else if (warmup_cnt < 7'd127) warmup_cnt <= warmup_cnt + 1'b1;
    end

    generate
        for (genvar gp = 0; gp < NUM_PORTS; gp++) begin : assert_port
            for (genvar gv = 0; gv < NUM_VCS; gv++) begin : assert_vc
                always @(posedge clk) begin
                    if (rst_n && warmup_cnt == 7'd127) begin
                        assert (downstream_credits[gp][gv] <= CREDIT_WIDTH'(FLITS_PER_BUFFER));

                        assert (fifo_count[gp][gv] <= ($clog2(FLITS_PER_BUFFER)+1)'(FLITS_PER_BUFFER))
                            else $warning("ASSERT: FIFO overflow port=%0d vc=%0d count=%0d",
                                         gp, gv, fifo_count[gp][gv]);
                    end
                end
            end
        end
    endgenerate

    generate
        for (genvar gp = 0; gp < NUM_PORTS; gp++) begin : assert_onehot
            always @(posedge clk) begin
                if (rst_n && sa_grant_valid[gp]) begin

                end
            end
        end
    endgenerate
`endif

endmodule
