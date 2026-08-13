// SystemVerilog Assertions (SVA) for SIMT Branch Divergence Stack
// Verifies stack overflow/underflow prevention and depth pointer integrity.

`timescale 1ns/1ns

module simt_stack_sva #(
    parameter DEPTH = 16,
    parameter THREADS_PER_WARP = 4,
    parameter PC_WIDTH = 12
) (
    input wire clk,
    input wire reset,

    input wire branch_valid,
    input wire [THREADS_PER_WARP-1:0] branch_taken,
    input wire [THREADS_PER_WARP-1:0] current_active_mask,

    input wire reconverge,

    input wire stack_empty,
    input wire stack_full,
    input wire [$clog2(DEPTH):0] stack_depth
);

    // 1. Stack Depth Never Exceeds Limit
    property p_stack_depth_limit;
        @(posedge clk) disable iff (reset)
        stack_depth <= DEPTH;
    endproperty
    assert property (p_stack_depth_limit)
        else $error("SIMT SVA ERROR: Stack depth overflowed max DEPTH");

    // 2. Stack Empty Flag Consistency
    property p_stack_empty_flag;
        @(posedge clk) disable iff (reset)
        stack_empty <-> (stack_depth == 0);
    endproperty
    assert property (p_stack_empty_flag)
        else $error("SIMT SVA ERROR: Mismatch between stack_empty flag and stack_depth");

    // 3. Stack Full Flag Consistency
    property p_stack_full_flag;
        @(posedge clk) disable iff (reset)
        stack_full <-> (stack_depth >= DEPTH);
    endproperty
    assert property (p_stack_full_flag)
        else $error("SIMT SVA ERROR: Mismatch between stack_full flag and stack_depth");

endmodule
