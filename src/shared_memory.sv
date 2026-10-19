
`default_nettype none
`timescale 1ns/1ps

// Shared memory bank providing fast intra-thread-block communication with configurable size and bank conflict detection.
module sharedMemory #(
    parameter DATA_BITS        = 16,
    parameter ADDR_BITS        = 13,
    parameter NUM_WARPS        = 1,
    parameter THREADS_PER_WARP = 4,
    parameter NUM_BANKS        = 4
)(
    input  wire                                     clk,
    input  wire                                     reset,

    input  wire [NUM_WARPS*THREADS_PER_WARP-1:0]    reqValid,
    input  wire [NUM_WARPS*THREADS_PER_WARP-1:0]    reqWrite,
    input  wire [ADDR_BITS-1:0]                     reqAddr [NUM_WARPS*THREADS_PER_WARP-1:0],
    input  wire [DATA_BITS-1:0]                     reqWdata [NUM_WARPS*THREADS_PER_WARP-1:0],
    output reg  [NUM_WARPS*THREADS_PER_WARP-1:0]    reqReady,
    output reg  [DATA_BITS-1:0]                     reqRdata [NUM_WARPS*THREADS_PER_WARP-1:0],

    output wire                                     sharedMemAccessPulse,
    output wire                                     sharedMemConflictPulse
);

    localparam TOTAL_THREADS  = NUM_WARPS * THREADS_PER_WARP;
    localparam BANK_SEL_BITS  = $clog2(NUM_BANKS);
    localparam BANK_SEL_HIGH  = BANK_SEL_BITS;
    localparam BANK_SEL_LOW   = 1;
    localparam THREAD_ID_W    = (TOTAL_THREADS > 1) ? $clog2(TOTAL_THREADS) : 1;
    localparam BANK_DEPTH     = 512;
    localparam BANK_ADDR_W    = ADDR_BITS - BANK_SEL_BITS;

    reg [DATA_BITS-1:0] banks [NUM_BANKS-1:0][BANK_DEPTH-1:0];

    wire [BANK_SEL_BITS-1:0] threadBankSel [TOTAL_THREADS-1:0];
    wire [BANK_ADDR_W-1:0]   threadBankAddr [TOTAL_THREADS-1:0];

    genvar gi;
    generate
        for (gi = 0; gi < TOTAL_THREADS; gi = gi + 1) begin : gen_bank_decode
            assign threadBankSel[gi]  = reqAddr[gi][BANK_SEL_HIGH:BANK_SEL_LOW];
            assign threadBankAddr[gi] = {reqAddr[gi][ADDR_BITS-1:BANK_SEL_HIGH+1], reqAddr[gi][BANK_SEL_LOW-1:0]};
        end
    endgenerate

    reg [THREAD_ID_W-1:0] bankWinner [NUM_BANKS-1:0];
    reg [NUM_BANKS-1:0]   bankActive;
    reg [THREAD_ID_W-1:0] rrBankPtr  [NUM_BANKS-1:0];

    always_comb begin
        for (int b = 0; b < NUM_BANKS; b = b + 1) begin
            bankWinner[b] = '0;
            bankActive[b] = 1'b0;

            for (int offset = 0; offset < TOTAL_THREADS; offset = offset + 1) begin
                automatic int tid = (rrBankPtr[b] + offset >= TOTAL_THREADS) ?
                                    (rrBankPtr[b] + offset - TOTAL_THREADS) :
                                    (rrBankPtr[b] + offset);
                if (!bankActive[b] && reqValid[tid] && (threadBankSel[tid] == b[BANK_SEL_BITS-1:0])) begin
                    bankWinner[b] = tid[THREAD_ID_W-1:0];
                    bankActive[b] = 1'b1;
                end
            end
        end
    end

    always_comb begin
        for (int t = 0; t < TOTAL_THREADS; t = t + 1) begin
            reqReady[t] = 1'b0;
            if (reqValid[t]) begin
                if (bankActive[threadBankSel[t]] && (bankWinner[threadBankSel[t]] == t[THREAD_ID_W-1:0])) begin
                    reqReady[t] = 1'b1;
                end
            end
        end
    end

    reg conflictDetected;
    always_comb begin
        conflictDetected = 1'b0;
        for (int t = 0; t < TOTAL_THREADS; t = t + 1) begin
            if (reqValid[t] && !reqReady[t])
                conflictDetected = 1'b1;
        end
    end

    assign sharedMemAccessPulse   = |bankActive;
    assign sharedMemConflictPulse = conflictDetected;

    integer b_idx, t_idx;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (t_idx = 0; t_idx < TOTAL_THREADS; t_idx = t_idx + 1)
                reqRdata[t_idx] <= '0;
            for (b_idx = 0; b_idx < NUM_BANKS; b_idx = b_idx + 1)
                rrBankPtr[b_idx] <= '0;
        end else begin
            for (b_idx = 0; b_idx < NUM_BANKS; b_idx = b_idx + 1) begin
                if (bankActive[b_idx]) begin
                    automatic int winTid = bankWinner[b_idx];

                    rrBankPtr[b_idx] <= (winTid == TOTAL_THREADS - 1) ? '0 : winTid[THREAD_ID_W-1:0] + 1'b1;

                    if (reqWrite[winTid]) begin
                        banks[b_idx][threadBankAddr[winTid]] <= reqWdata[winTid];
                    end else begin
                        reqRdata[winTid] <= banks[b_idx][threadBankAddr[winTid]];
                    end
                end
            end
        end
    end

endmodule
