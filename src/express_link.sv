
`default_nettype none
`timescale 1ns/1ns

module express_link #(
    parameter DATA_WIDTH   = 512,
    parameter ADDR_WIDTH   = 22,
    parameter FIFO_DEPTH   = 4,
    parameter LINK_LATENCY = 2
) (
    input  wire clk,
    input  wire reset,

    input  wire                    a_tx_valid,
    input  wire [DATA_WIDTH-1:0]   a_tx_data,
    input  wire [ADDR_WIDTH-1:0]   a_tx_addr,
    input  wire                    a_tx_write,
    output wire                    a_tx_ready,

    output wire                    a_rx_valid,
    output wire [DATA_WIDTH-1:0]   a_rx_data,
    output wire [ADDR_WIDTH-1:0]   a_rx_addr,
    output wire                    a_rx_write,
    input  wire                    a_rx_ready,

    input  wire                    b_tx_valid,
    input  wire [DATA_WIDTH-1:0]   b_tx_data,
    input  wire [ADDR_WIDTH-1:0]   b_tx_addr,
    input  wire                    b_tx_write,
    output wire                    b_tx_ready,

    output wire                    b_rx_valid,
    output wire [DATA_WIDTH-1:0]   b_rx_data,
    output wire [ADDR_WIDTH-1:0]   b_rx_addr,
    output wire                    b_rx_write,
    input  wire                    b_rx_ready,

    output wire [3:0]              a_to_b_occupancy,
    output wire [3:0]              b_to_a_occupancy,
    output reg  [15:0]             total_flits_forwarded
);

    localparam PIPE_W = DATA_WIDTH + ADDR_WIDTH + 1;

    reg [PIPE_W-1:0] ab_pipe [LINK_LATENCY-1:0];
    reg [LINK_LATENCY-1:0] ab_pipe_valid;

    reg [PIPE_W-1:0] ba_pipe [LINK_LATENCY-1:0];
    reg [LINK_LATENCY-1:0] ba_pipe_valid;

    reg [PIPE_W-1:0] ab_fifo [FIFO_DEPTH-1:0];
    reg [$clog2(FIFO_DEPTH):0] ab_wr_ptr, ab_rd_ptr;
    wire [$clog2(FIFO_DEPTH):0] ab_count = ab_wr_ptr - ab_rd_ptr;
    wire ab_full  = (ab_count >= FIFO_DEPTH);
    wire ab_empty = (ab_count == 0);

    reg [PIPE_W-1:0] ba_fifo [FIFO_DEPTH-1:0];
    reg [$clog2(FIFO_DEPTH):0] ba_wr_ptr, ba_rd_ptr;
    wire [$clog2(FIFO_DEPTH):0] ba_count = ba_wr_ptr - ba_rd_ptr;
    wire ba_full  = (ba_count >= FIFO_DEPTH);
    wire ba_empty = (ba_count == 0);

    assign a_tx_ready = !ab_full;
    assign b_tx_ready = !ba_full;

    assign a_to_b_occupancy = ab_count;
    assign b_to_a_occupancy = ba_count;

    assign b_rx_valid = !ab_empty;
    assign {b_rx_write, b_rx_addr, b_rx_data} = ab_fifo[ab_rd_ptr[$clog2(FIFO_DEPTH)-1:0]];

    assign a_rx_valid = !ba_empty;
    assign {a_rx_write, a_rx_addr, a_rx_data} = ba_fifo[ba_rd_ptr[$clog2(FIFO_DEPTH)-1:0]];

    integer s;

    always @(posedge clk) begin
        if (reset) begin
            for (s = 0; s < LINK_LATENCY; s = s + 1) begin
                ab_pipe_valid[s] <= 0;
                ba_pipe_valid[s] <= 0;
            end
            ab_wr_ptr <= 0;
            ab_rd_ptr <= 0;
            ba_wr_ptr <= 0;
            ba_rd_ptr <= 0;
            total_flits_forwarded <= 0;
        end else begin

            if (a_tx_valid && !ab_full) begin
                ab_pipe[0] <= {a_tx_write, a_tx_addr, a_tx_data};
                ab_pipe_valid[0] <= 1;
            end else begin
                ab_pipe_valid[0] <= 0;
            end

            for (s = 1; s < LINK_LATENCY; s = s + 1) begin
                ab_pipe[s] <= ab_pipe[s-1];
                ab_pipe_valid[s] <= ab_pipe_valid[s-1];
            end

            if (ab_pipe_valid[LINK_LATENCY-1]) begin
                ab_fifo[ab_wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= ab_pipe[LINK_LATENCY-1];
                ab_wr_ptr <= ab_wr_ptr + 1;
                total_flits_forwarded <= total_flits_forwarded + 1;
            end

            if (!ab_empty && b_rx_ready) begin
                ab_rd_ptr <= ab_rd_ptr + 1;
            end

            if (b_tx_valid && !ba_full) begin
                ba_pipe[0] <= {b_tx_write, b_tx_addr, b_tx_data};
                ba_pipe_valid[0] <= 1;
            end else begin
                ba_pipe_valid[0] <= 0;
            end

            for (s = 1; s < LINK_LATENCY; s = s + 1) begin
                ba_pipe[s] <= ba_pipe[s-1];
                ba_pipe_valid[s] <= ba_pipe_valid[s-1];
            end

            if (ba_pipe_valid[LINK_LATENCY-1]) begin
                ba_fifo[ba_wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= ba_pipe[LINK_LATENCY-1];
                ba_wr_ptr <= ba_wr_ptr + 1;
                total_flits_forwarded <= total_flits_forwarded + 1;
            end

            if (!ba_empty && a_rx_ready) begin
                ba_rd_ptr <= ba_rd_ptr + 1;
            end
        end
    end

endmodule
