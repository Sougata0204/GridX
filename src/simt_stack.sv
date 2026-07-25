// SIMT Branch Divergence Stack
// Maintains per-warp PC and active mask stacks for nested conditional branching.
// Handles stack push on branch divergence and pop on SIMT barrier synchronization.

`default_nettype none
`timescale 1ns/1ns

module simt_stack #(
    parameter DEPTH = 16,
    parameter THREADS_PER_WARP = 4,
    parameter PC_WIDTH = 12
) (
    input  wire clk,
    input  wire reset,

    input  wire                           branch_valid,
    input  wire [THREADS_PER_WARP-1:0]    branch_taken,
    input  wire [THREADS_PER_WARP-1:0]    current_active_mask,
    input  wire [PC_WIDTH-1:0]            branch_target_pc,
    input  wire [PC_WIDTH-1:0]            fall_through_pc,

    input  wire                           reconverge,

    output wire [THREADS_PER_WARP-1:0]    active_mask,
    output wire [PC_WIDTH-1:0]            next_pc,
    output wire                           diverged,
    output wire                           stack_empty,
    output wire                           stack_full,
    output wire [$clog2(DEPTH):0]         stack_depth
);

    reg [THREADS_PER_WARP-1:0] mask_stack [DEPTH-1:0];
    reg [PC_WIDTH-1:0]         pc_stack   [DEPTH-1:0];
    reg [THREADS_PER_WARP-1:0] reconverge_mask_stack [DEPTH-1:0];
    reg [$clog2(DEPTH):0]      sp;

    reg [THREADS_PER_WARP-1:0] cur_active_mask;
    reg [PC_WIDTH-1:0]         cur_pc;
    reg                        is_diverged;

    assign active_mask = cur_active_mask;
    assign next_pc     = cur_pc;
    assign diverged    = is_diverged;
    assign stack_empty = (sp == 0);
    assign stack_full  = (sp >= DEPTH);
    assign stack_depth = sp;

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            sp <= 0;
            cur_active_mask <= {THREADS_PER_WARP{1'b1}};
            cur_pc <= 0;
            is_diverged <= 0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                mask_stack[i] <= 0;
                pc_stack[i]   <= 0;
                reconverge_mask_stack[i] <= 0;
            end
        end else begin
            if (branch_valid && !stack_full) begin

                if ((branch_taken & current_active_mask) != 0 &&
                    (~branch_taken & current_active_mask) != 0) begin

                    mask_stack[sp] <= ~branch_taken & current_active_mask;
                    pc_stack[sp]   <= fall_through_pc;
                    reconverge_mask_stack[sp] <= current_active_mask;
                    sp <= sp + 1;

                    cur_active_mask <= branch_taken & current_active_mask;
                    cur_pc <= branch_target_pc;
                    is_diverged <= 1;
                end else if ((branch_taken & current_active_mask) != 0) begin

                    cur_pc <= branch_target_pc;
                end else begin

                    cur_pc <= fall_through_pc;
                end
            end

            if (reconverge && !stack_empty) begin

                sp <= sp - 1;
                cur_active_mask <= mask_stack[sp - 1];
                cur_pc <= pc_stack[sp - 1];

                if (sp == 1) begin
                    cur_active_mask <= reconverge_mask_stack[0];
                    is_diverged <= 0;
                end
            end
        end
    end

endmodule
