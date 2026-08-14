`default_nettype none
`timescale 1ns/1ns

module async_fifo_sva #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 8,
    parameter PTR_WIDTH  = $clog2(DEPTH)
) (
    input  wire                  wrClk,
    input  wire                  wrRst,
    input  wire                  wrEn,
    input  wire                  wrFull,

    input  wire                  rdClk,
    input  wire                  rdRst,
    input  wire                  rdEn,
    input  wire                  rdEmpty
);

    // 1. Write on Full Check (No Overflow)
    property p_no_write_on_full;
        @(posedge wrClk) disable iff (wrRst)
        wrFull |-> !wrEn;
    endproperty
    sva_no_write_on_full: assert property(p_no_write_on_full)
        else $error("SVA CDC ERROR: Async FIFO write while full!");

    // 2. Read on Empty Check (No Underflow)
    property p_no_read_on_empty;
        @(posedge rdClk) disable iff (rdRst)
        rdEmpty |-> !rdEn;
    endproperty
    sva_no_read_on_empty: assert property(p_no_read_on_empty)
        else $error("SVA CDC ERROR: Async FIFO read while empty!");

    // 3. FIFO Liveness (Assuming eventual read)
    // If FIFO is not empty, it should eventually be read.
    property p_eventual_read;
        @(posedge rdClk) disable iff (rdRst)
        !rdEmpty |-> s_eventually(rdEn);
    endproperty
    sva_eventual_read: assert property(p_eventual_read)
        else $error("SVA CDC LIVENESS ERROR: Flit stuck in async FIFO and never read!");

endmodule


