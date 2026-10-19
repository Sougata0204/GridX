
`default_nettype none
`timescale 1ns/1ps

// SIMT convergence stack managing thread divergence and reconvergence for conditional branch handling across warp lanes.
module simtStack #(
    parameter DEPTH            = 16,
    parameter THREADS_PER_WARP = 4,
    parameter PC_WIDTH         = 12
) (
    input  wire                           clk,
    input  wire                           reset,

    input  wire                           branchValid,
    input  wire [THREADS_PER_WARP-1:0]    branchTaken,
    input  wire [THREADS_PER_WARP-1:0]    currentActiveMask,
    input  wire [PC_WIDTH-1:0]            branchTargetPc,
    input  wire [PC_WIDTH-1:0]            fallThroughPc,

    input  wire                           reconverge,

    output wire [THREADS_PER_WARP-1:0]    activeMask,
    output wire [PC_WIDTH-1:0]            nextPc,
    output wire                           diverged,
    output wire                           stackEmpty,
    output wire                           stackFull,
    output wire [$clog2(DEPTH):0]         stackDepth
);

    reg [THREADS_PER_WARP-1:0] maskStack [DEPTH-1:0];
    reg [PC_WIDTH-1:0]         pcStack   [DEPTH-1:0];
    reg [THREADS_PER_WARP-1:0] reconvergeMaskStack [DEPTH-1:0];
    reg [$clog2(DEPTH):0]      sp;

    reg [THREADS_PER_WARP-1:0] curActiveMask;
    reg [PC_WIDTH-1:0]         curPc;
    reg                        isDiverged;

    assign activeMask = curActiveMask;
    assign nextPc     = curPc;
    assign diverged   = isDiverged;
    assign stackEmpty = (sp == 0);
    assign stackFull  = (sp >= DEPTH);
    assign stackDepth = sp;

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            sp            <= '0;
            curActiveMask <= {THREADS_PER_WARP{1'b1}};
            curPc         <= '0;
            isDiverged    <= 1'b0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                maskStack[i]           <= '0;
                pcStack[i]             <= '0;
                reconvergeMaskStack[i] <= '0;
            end
        end else begin
            if (reconverge && !stackEmpty) begin
                sp    <= sp - 1'b1;
                curPc <= pcStack[sp - 1];

                if (sp == 1) begin
                    curActiveMask <= reconvergeMaskStack[0];
                    isDiverged    <= 1'b0;
                end else begin
                    curActiveMask <= maskStack[sp - 1];
                end
            end else if (branchValid && !stackFull) begin
                if ((branchTaken & currentActiveMask) != 0 &&
                    (~branchTaken & currentActiveMask) != 0) begin
                    maskStack[sp]           <= ~branchTaken & currentActiveMask;
                    pcStack[sp]             <= fallThroughPc;
                    reconvergeMaskStack[sp] <= currentActiveMask;
                    sp                      <= sp + 1'b1;

                    curActiveMask <= branchTaken & currentActiveMask;
                    curPc         <= branchTargetPc;
                    isDiverged    <= 1'b1;
                end else if ((branchTaken & currentActiveMask) != 0) begin
                    curPc <= branchTargetPc;
                end else begin
                    curPc <= fallThroughPc;
                end
            end
        end
    end

endmodule
