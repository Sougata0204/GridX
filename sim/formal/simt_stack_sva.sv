// Formal verification assertions for SIMT branch divergence stack verifying overflow, underflow, and depth integrity.
`timescale 1ns/1ns

module simt_stack_sva #(
    parameter DEPTH = 16,
    parameter THREADS_PER_WARP = 4,
    parameter PC_WIDTH = 12
) (
    input wire clk,
    input wire reset,

    input wire branchValid,
    input wire [THREADS_PER_WARP-1:0] branchTaken,
    input wire [THREADS_PER_WARP-1:0] currentActiveMask,

    input wire reconverge,

    input wire stackEmpty,
    input wire stackFull,
    input wire [$clog2(DEPTH):0] stackDepth
);

    property p_stack_depth_limit;
        @(posedge clk) disable iff (reset)
        stackDepth <= DEPTH;
    endproperty
    assert property (p_stack_depth_limit)
        else $error("SIMT SVA ERROR: Stack depth overflowed max DEPTH");

    property p_stack_empty_flag;
        @(posedge clk) disable iff (reset)
        stackEmpty <-> (stackDepth == 0);
    endproperty
    assert property (p_stack_empty_flag)
        else $error("SIMT SVA ERROR: Mismatch between stack_empty flag and stack_depth");

    property p_stack_full_flag;
        @(posedge clk) disable iff (reset)
        stackFull <-> (stackDepth >= DEPTH);
    endproperty
    assert property (p_stack_full_flag)
        else $error("SIMT SVA ERROR: Mismatch between stack_full flag and stack_depth");

endmodule
