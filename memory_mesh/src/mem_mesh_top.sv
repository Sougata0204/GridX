// `default_nettype none  -- removed: module uses `logic` typed ports
`timescale 1ps/1ps

import gridx_mem_pkg::*;

module mem_mesh_top (
    input logic clk,
    input logic rst_n,

    input  flit_t   [NUM_NODES-1:0] local_flit_in,
    input  logic    [NUM_NODES-1:0] local_flit_in_valid,
    output credit_t [NUM_NODES-1:0] local_credit_out,

    output flit_t   [NUM_NODES-1:0] local_flit_out,
    output logic    [NUM_NODES-1:0] local_flit_out_valid,
    input  credit_t [NUM_NODES-1:0] local_credit_in
);

    flit_t   [MESH_Z-1:0][MESH_Y-1:0][MESH_X-1:0][NUM_PORTS-1:0] node_flit_tx;
    logic    [MESH_Z-1:0][MESH_Y-1:0][MESH_X-1:0][NUM_PORTS-1:0] node_flit_tx_valid;
    credit_t [MESH_Z-1:0][MESH_Y-1:0][MESH_X-1:0][NUM_PORTS-1:0] node_credit_tx;

    flit_t   [MESH_Z-1:0][MESH_Y-1:0][MESH_X-1:0][NUM_PORTS-1:0] node_flit_rx;
    logic    [MESH_Z-1:0][MESH_Y-1:0][MESH_X-1:0][NUM_PORTS-1:0] node_flit_rx_valid;
    credit_t [MESH_Z-1:0][MESH_Y-1:0][MESH_X-1:0][NUM_PORTS-1:0] node_credit_rx;

    genvar x, y, z;
    generate
        for (z = 0; z < MESH_Z; z++) begin : gen_z
            for (y = 0; y < MESH_Y; y++) begin : gen_y
                for (x = 0; x < MESH_X; x++) begin : gen_x

                    localparam int NODE_ID = (z * MESH_Y * MESH_X) + (y * MESH_X) + x;

                    coord_t my_coord;
                    assign my_coord.x = x[COORD_X_W-1:0];
                    assign my_coord.y = y[COORD_Y_W-1:0];
                    assign my_coord.z = z[COORD_Z_W-1:0];

                    mem_mesh_router u_router (
                        .clk            (clk),
                        .rst_n          (rst_n),
                        .my_coord       (my_coord),
                        .flit_in        (node_flit_rx[z][y][x]),
                        .flit_in_valid  (node_flit_rx_valid[z][y][x]),
                        .credit_out     (node_credit_tx[z][y][x]),
                        .flit_out       (node_flit_tx[z][y][x]),
                        .flit_out_valid (node_flit_tx_valid[z][y][x]),
                        .credit_in      (node_credit_rx[z][y][x])
                    );

                    assign node_flit_rx[z][y][x][PORT_LOCAL]       = local_flit_in[NODE_ID];
                    assign node_flit_rx_valid[z][y][x][PORT_LOCAL] = local_flit_in_valid[NODE_ID];
                    assign local_credit_out[NODE_ID]               = node_credit_tx[z][y][x][PORT_LOCAL];
                    assign local_flit_out[NODE_ID]                 = node_flit_tx[z][y][x][PORT_LOCAL];
                    assign local_flit_out_valid[NODE_ID]           = node_flit_tx_valid[z][y][x][PORT_LOCAL];
                    assign node_credit_rx[z][y][x][PORT_LOCAL]     = local_credit_in[NODE_ID];

                    if (x < MESH_X - 1) begin : link_xp
                        always_ff @(posedge clk or negedge rst_n) begin
                            if (!rst_n) begin
                                node_flit_rx_valid[z][y][x][PORT_X_POS] <= 1'b0;
                                node_credit_rx[z][y][x][PORT_X_POS]     <= '0;
                            end else begin
                                node_flit_rx[z][y][x][PORT_X_POS]       <= node_flit_tx[z][y][x+1][PORT_X_NEG];
                                node_flit_rx_valid[z][y][x][PORT_X_POS] <= node_flit_tx_valid[z][y][x+1][PORT_X_NEG];
                                node_credit_rx[z][y][x][PORT_X_POS]     <= node_credit_tx[z][y][x+1][PORT_X_NEG];
                            end
                        end
                    end else begin : link_xp_tie
                        assign node_flit_rx_valid[z][y][x][PORT_X_POS] = 1'b0;
                        assign node_credit_rx[z][y][x][PORT_X_POS]     = '0;
                    end

                    if (x > 0) begin : link_xn
                        always_ff @(posedge clk or negedge rst_n) begin
                            if (!rst_n) begin
                                node_flit_rx_valid[z][y][x][PORT_X_NEG] <= 1'b0;
                                node_credit_rx[z][y][x][PORT_X_NEG]     <= '0;
                            end else begin
                                node_flit_rx[z][y][x][PORT_X_NEG]       <= node_flit_tx[z][y][x-1][PORT_X_POS];
                                node_flit_rx_valid[z][y][x][PORT_X_NEG] <= node_flit_tx_valid[z][y][x-1][PORT_X_POS];
                                node_credit_rx[z][y][x][PORT_X_NEG]     <= node_credit_tx[z][y][x-1][PORT_X_POS];
                            end
                        end
                    end else begin : link_xn_tie
                        assign node_flit_rx_valid[z][y][x][PORT_X_NEG] = 1'b0;
                        assign node_credit_rx[z][y][x][PORT_X_NEG]     = '0;
                    end

                    if (y < MESH_Y - 1) begin : link_yp
                        always_ff @(posedge clk or negedge rst_n) begin
                            if (!rst_n) begin
                                node_flit_rx_valid[z][y][x][PORT_Y_POS] <= 1'b0;
                                node_credit_rx[z][y][x][PORT_Y_POS]     <= '0;
                            end else begin
                                node_flit_rx[z][y][x][PORT_Y_POS]       <= node_flit_tx[z][y+1][x][PORT_Y_NEG];
                                node_flit_rx_valid[z][y][x][PORT_Y_POS] <= node_flit_tx_valid[z][y+1][x][PORT_Y_NEG];
                                node_credit_rx[z][y][x][PORT_Y_POS]     <= node_credit_tx[z][y+1][x][PORT_Y_NEG];
                            end
                        end
                    end else begin : link_yp_tie
                        assign node_flit_rx_valid[z][y][x][PORT_Y_POS] = 1'b0;
                        assign node_credit_rx[z][y][x][PORT_Y_POS]     = '0;
                    end

                    if (y > 0) begin : link_yn
                        always_ff @(posedge clk or negedge rst_n) begin
                            if (!rst_n) begin
                                node_flit_rx_valid[z][y][x][PORT_Y_NEG] <= 1'b0;
                                node_credit_rx[z][y][x][PORT_Y_NEG]     <= '0;
                            end else begin
                                node_flit_rx[z][y][x][PORT_Y_NEG]       <= node_flit_tx[z][y-1][x][PORT_Y_POS];
                                node_flit_rx_valid[z][y][x][PORT_Y_NEG] <= node_flit_tx_valid[z][y-1][x][PORT_Y_POS];
                                node_credit_rx[z][y][x][PORT_Y_NEG]     <= node_credit_tx[z][y-1][x][PORT_Y_POS];
                            end
                        end
                    end else begin : link_yn_tie
                        assign node_flit_rx_valid[z][y][x][PORT_Y_NEG] = 1'b0;
                        assign node_credit_rx[z][y][x][PORT_Y_NEG]     = '0;
                    end

                    if (z < MESH_Z - 1) begin : link_zp
                        always_ff @(posedge clk or negedge rst_n) begin
                            if (!rst_n) begin
                                node_flit_rx_valid[z][y][x][PORT_Z_POS] <= 1'b0;
                                node_credit_rx[z][y][x][PORT_Z_POS]     <= '0;
                            end else begin
                                node_flit_rx[z][y][x][PORT_Z_POS]       <= node_flit_tx[z+1][y][x][PORT_Z_NEG];
                                node_flit_rx_valid[z][y][x][PORT_Z_POS] <= node_flit_tx_valid[z+1][y][x][PORT_Z_NEG];
                                node_credit_rx[z][y][x][PORT_Z_POS]     <= node_credit_tx[z+1][y][x][PORT_Z_NEG];
                            end
                        end
                    end else begin : link_zp_tie
                        assign node_flit_rx_valid[z][y][x][PORT_Z_POS] = 1'b0;
                        assign node_credit_rx[z][y][x][PORT_Z_POS]     = '0;
                    end

                    if (z > 0) begin : link_zn
                        always_ff @(posedge clk or negedge rst_n) begin
                            if (!rst_n) begin
                                node_flit_rx_valid[z][y][x][PORT_Z_NEG] <= 1'b0;
                                node_credit_rx[z][y][x][PORT_Z_NEG]     <= '0;
                            end else begin
                                node_flit_rx[z][y][x][PORT_Z_NEG]       <= node_flit_tx[z-1][y][x][PORT_Z_POS];
                                node_flit_rx_valid[z][y][x][PORT_Z_NEG] <= node_flit_tx_valid[z-1][y][x][PORT_Z_POS];
                                node_credit_rx[z][y][x][PORT_Z_NEG]     <= node_credit_tx[z-1][y][x][PORT_Z_POS];
                            end
                        end
                    end else begin : link_zn_tie
                        assign node_flit_rx_valid[z][y][x][PORT_Z_NEG] = 1'b0;
                        assign node_credit_rx[z][y][x][PORT_Z_NEG]     = '0;
                    end

                end
            end
        end
    endgenerate

endmodule
