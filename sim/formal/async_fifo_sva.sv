`default_nettype none
`timescale 1ns/1ns

module async_fifo_sva #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 8,
    parameter PTR_WIDTH  = $clog2(DEPTH)
) (
    input  wire                  wr_clk,
    input  wire                  wr_rst,
    input  wire                  wr_en,
    input  wire                  wr_full,

    input  wire                  rd_clk,
    input  wire                  rd_rst,
    input  wire                  rd_en,
    input  wire                  rd_empty
);

    // 1. Write on Full Check (No Overflow)
    property p_no_write_on_full;
        @(posedge wr_clk) disable iff (wr_rst)
        wr_full |-> !wr_en;
    endproperty
    sva_no_write_on_full: assert property(p_no_write_on_full)
        else $error("SVA CDC ERROR: Async FIFO write while full!");

    // 2. Read on Empty Check (No Underflow)
    property p_no_read_on_empty;
        @(posedge rd_clk) disable iff (rd_rst)
        rd_empty |-> !rd_en;
    endproperty
    sva_no_read_on_empty: assert property(p_no_read_on_empty)
        else $error("SVA CDC ERROR: Async FIFO read while empty!");

    // 3. FIFO Liveness (Assuming eventual read)
    // If FIFO is not empty, it should eventually be read.
    property p_eventual_read;
        @(posedge rd_clk) disable iff (rd_rst)
        !rd_empty |-> s_eventually(rd_en);
    endproperty
    sva_eventual_read: assert property(p_eventual_read)
        else $error("SVA CDC LIVENESS ERROR: Flit stuck in async FIFO and never read!");

endmodule

// Bind statement to attach SVA module to the RTL
bind async_fifo async_fifo_sva #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(DEPTH),
    .PTR_WIDTH(PTR_WIDTH)
) sva_bind (
    .wr_clk(wr_clk),
    .wr_rst(wr_rst),
    .wr_en(wr_en),
    .wr_full(wr_full),
    .rd_clk(rd_clk),
    .rd_rst(rd_rst),
    .rd_en(rd_en),
    .rd_empty(rd_empty)
);
