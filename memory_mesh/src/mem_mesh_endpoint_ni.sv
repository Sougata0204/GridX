// `default_nettype none  -- removed: module uses `logic` typed ports
`timescale 1ps/1ps

import gridx_mem_pkg::*;

typedef struct packed {
    logic [ADDR_WIDTH-1:0]  addr;
    logic [DATA_WIDTH-1:0]  data;
    logic [TX_ID_W-1:0]     tx_id;
    logic                   is_store;
} l2_req_t;

typedef struct packed {
    logic [DATA_WIDTH-1:0]  data;
    logic [TX_ID_W-1:0]     tx_id;
    logic                   error;
} l2_resp_t;

module mem_mesh_endpoint_ni (
    input  logic clk,
    input  logic rst_n,

    input  coord_t my_coord,

    input  l2_req_t  l2_req,
    input  logic     l2_req_valid,
    output logic     l2_req_ready,

    output l2_resp_t l2_resp,
    output logic     l2_resp_valid,
    input  logic     l2_resp_ready,

    output flit_t    mesh_tx_flit,
    output logic     mesh_tx_valid,
    input  credit_t  mesh_tx_credit,

    input  flit_t    mesh_rx_flit,
    input  logic     mesh_rx_valid,
    output credit_t  mesh_rx_credit
);

    logic [TX_TABLE_ENTRIES-1:0] tx_active;
    logic                       tx_table_full;

    assign tx_table_full = &tx_active;

    typedef enum logic [2:0] {
        TX_IDLE,
        TX_SEND_HEAD,
        TX_SEND_BODY,
        TX_SEND_TAIL
    } tx_state_e;

    tx_state_e           tx_state;
    l2_req_t             latched_req;
    logic [VC_ID_W-1:0]  target_vc;
    logic [2:0]          body_flit_cnt;

    always_comb begin
        target_vc = latched_req.is_store ? VC_WRITE_REQ : VC_READ_REQ;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state      <= TX_IDLE;
            mesh_tx_valid <= 1'b0;
            mesh_tx_flit  <= '0;
            l2_req_ready  <= 1'b0;
            tx_active     <= '0;
            body_flit_cnt <= '0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    mesh_tx_valid <= 1'b0;
                    l2_req_ready  <= !tx_table_full;

                    if (l2_req_valid && l2_req_ready && !tx_table_full) begin
                        latched_req           <= l2_req;
                        tx_active[l2_req.tx_id] <= 1'b1;
                        tx_state              <= TX_SEND_HEAD;
                        l2_req_ready          <= 1'b0;
                        body_flit_cnt         <= '0;
                    end
                end

                TX_SEND_HEAD: begin
                    mesh_tx_valid          <= 1'b1;
                    mesh_tx_flit.valid     <= 1'b1;
                    mesh_tx_flit.vc_id     <= target_vc;
                    mesh_tx_flit.flit_type <= FLIT_HEAD;

                    mesh_tx_flit.data <= {
                        latched_req.is_store ? PKT_WRITE_REQ : PKT_READ_REQ,
                        target_vc,
                        my_coord.x, my_coord.y, my_coord.z,
                        latched_req.addr[7:6], latched_req.addr[5:4], 2'd3,
                        latched_req.tx_id,
                        4'b0000,
                        latched_req.addr, 70'b0
                    };

                    if (latched_req.is_store)
                        tx_state <= TX_SEND_BODY;
                    else
                        tx_state <= TX_SEND_TAIL;
                end

                TX_SEND_BODY: begin
                    mesh_tx_valid          <= 1'b1;
                    mesh_tx_flit.valid     <= 1'b1;
                    mesh_tx_flit.vc_id     <= target_vc;
                    mesh_tx_flit.flit_type <= FLIT_BODY;
                    mesh_tx_flit.data      <= latched_req.data;

                    if (body_flit_cnt < 3'd5) begin
                        body_flit_cnt <= body_flit_cnt + 1'b1;
                    end else begin
                        tx_state <= TX_SEND_TAIL;
                    end
                end

                TX_SEND_TAIL: begin
                    mesh_tx_valid          <= 1'b1;
                    mesh_tx_flit.valid     <= 1'b1;
                    mesh_tx_flit.vc_id     <= target_vc;
                    mesh_tx_flit.flit_type <= FLIT_TAIL;
                    mesh_tx_flit.data      <= latched_req.data;

                    tx_state <= TX_IDLE;
                end

                default: begin
                    tx_state      <= TX_IDLE;
                    mesh_tx_valid <= 1'b0;
                end
            endcase
        end
    end

    logic [TX_ID_W-1:0] pending_resp_tx_id;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            l2_resp_valid        <= 1'b0;
            mesh_rx_credit.valid <= 1'b0;
            mesh_rx_credit.vc_id <= '0;
        end else begin
            mesh_rx_credit.valid <= 1'b0;
            l2_resp_valid        <= 1'b0;

            if (mesh_rx_valid && mesh_rx_flit.valid) begin

                mesh_rx_credit.valid <= 1'b1;
                mesh_rx_credit.vc_id <= mesh_rx_flit.vc_id;

                if (mesh_rx_flit.flit_type == FLIT_HEAD) begin

                    pending_resp_tx_id <= mesh_rx_flit.data[110:106];
                end
                else if (mesh_rx_flit.flit_type == FLIT_TAIL) begin
                    l2_resp_valid       <= 1'b1;
                    l2_resp.data        <= mesh_rx_flit.data;
                    l2_resp.tx_id       <= pending_resp_tx_id;
                    l2_resp.error       <= 1'b0;

                    tx_active[pending_resp_tx_id] <= 1'b0;
                end
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n) begin

            if (l2_req_valid && l2_req_ready)
                assert (!tx_active[l2_req.tx_id])
                    else $error("ASSERT FAIL: TX ID %0d reused while active", l2_req.tx_id);
        end
    end
`endif

endmodule
