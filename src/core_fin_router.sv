
`default_nettype none
`timescale 1ns/1ns

module core_fin_router #(
    parameter DATA_W    = 8,
    parameter ADDR_W    = 22,
    parameter FIN_ADDR  = 10,
    parameter NUM_CH    = 4,
    parameter NUM_FACES = 6
) (
    input  wire clk,
    input  wire reset,

    input  wire              core_rd_valid,
    input  wire [ADDR_W-1:0] core_rd_addr,
    output wire              core_rd_ready,
    output wire [DATA_W-1:0] core_rd_data,

    input  wire              core_wr_valid,
    input  wire [ADDR_W-1:0] core_wr_addr,
    input  wire [DATA_W-1:0] core_wr_data,
    output wire              core_wr_ready,

    input  wire [5:0]        face_present,

    output reg  [NUM_CH-1:0] face_rd_valid [NUM_FACES-1:0],
    output reg  [FIN_ADDR-1:0] face_rd_addr [NUM_FACES-1:0][NUM_CH-1:0],
    input  wire [NUM_CH-1:0] face_rd_ready [NUM_FACES-1:0],
    input  wire [DATA_W-1:0] face_rd_data  [NUM_FACES-1:0][NUM_CH-1:0],

    output reg  [NUM_CH-1:0] face_wr_valid [NUM_FACES-1:0],
    output reg  [FIN_ADDR-1:0] face_wr_addr [NUM_FACES-1:0][NUM_CH-1:0],
    output reg  [DATA_W-1:0] face_wr_data  [NUM_FACES-1:0][NUM_CH-1:0],
    input  wire [NUM_CH-1:0] face_wr_ready [NUM_FACES-1:0]
);

    wire [2:0] face_sel  = core_rd_valid ? core_rd_addr[ADDR_W-1:ADDR_W-3] :
                           core_wr_valid ? core_wr_addr[ADDR_W-1:ADDR_W-3] : 3'd0;

    wire [1:0] ch_sel    = core_rd_valid ? core_rd_addr[FIN_ADDR+1:FIN_ADDR] :
                           core_wr_valid ? core_wr_addr[FIN_ADDR+1:FIN_ADDR] : 2'd0;

    wire [2:0] mapped_face = (face_sel < 3'd6) ? face_sel : 3'd0;

    reg rd_ack;
    reg [DATA_W-1:0] rd_val;
    reg wr_ack;

    integer f, c;
    always @(*) begin
        rd_ack = 0;
        rd_val = {DATA_W{1'b0}};
        wr_ack = 0;

        for (f = 0; f < NUM_FACES; f = f + 1) begin
            face_rd_valid[f] = {NUM_CH{1'b0}};
            face_wr_valid[f] = {NUM_CH{1'b0}};
            for (c = 0; c < NUM_CH; c = c + 1) begin
                face_rd_addr[f][c] = {FIN_ADDR{1'b0}};
                face_wr_addr[f][c] = {FIN_ADDR{1'b0}};
                face_wr_data[f][c] = {DATA_W{1'b0}};
            end
        end

        if (core_rd_valid && face_present[mapped_face]) begin
            face_rd_valid[mapped_face][ch_sel] = 1'b1;
            face_rd_addr[mapped_face][ch_sel]  = core_rd_addr[FIN_ADDR-1:0];
            rd_ack = face_rd_ready[mapped_face][ch_sel];
            rd_val = face_rd_data[mapped_face][ch_sel];
        end

        if (core_wr_valid && face_present[mapped_face]) begin
            face_wr_valid[mapped_face][ch_sel] = 1'b1;
            face_wr_addr[mapped_face][ch_sel]  = core_wr_addr[FIN_ADDR-1:0];
            face_wr_data[mapped_face][ch_sel]  = core_wr_data;
            wr_ack = face_wr_ready[mapped_face][ch_sel];
        end
    end

    assign core_rd_ready = rd_ack;
    assign core_rd_data  = rd_val;
    assign core_wr_ready = wr_ack;

endmodule
