
`default_nettype none
`timescale 1ns/1ns

module sharedMemory #(
    parameter DATA_BITS = 16,
    parameter ADDR_BITS = 13,
    parameter NUM_WARPS = 1,
    parameter THREADS_PER_WARP = 4,
    parameter NUM_BANKS = 4
)(
    input wire clk,
    input wire reset,
    input wire [NUM_WARPS*THREADS_PER_WARP-1:0] reqValid,
    input wire [NUM_WARPS*THREADS_PER_WARP-1:0] reqWrite,
    input wire [ADDR_BITS-1:0] reqAddr [NUM_WARPS*THREADS_PER_WARP-1:0],
    input wire [DATA_BITS-1:0] reqWdata [NUM_WARPS*THREADS_PER_WARP-1:0],
    output reg [NUM_WARPS*THREADS_PER_WARP-1:0] reqReady,
    output reg [DATA_BITS-1:0] reqRdata [NUM_WARPS*THREADS_PER_WARP-1:0],
    output wire sharedMemAccessPulse,
    output wire sharedMemConflictPulse
);
    localparam TOTAL_THREADS = NUM_WARPS * THREADS_PER_WARP;
    localparam BANK_SEL_BITS = $clog2(NUM_BANKS);
    localparam BANK_SEL_HIGH = BANK_SEL_BITS;
    localparam BANK_SEL_LOW  = 1;
    reg [DATA_BITS-1:0] banks [NUM_BANKS-1:0][511:0];
    integer b, t;
    wire [BANK_SEL_BITS-1:0] threadBankSel [TOTAL_THREADS-1:0];
    wire [ADDR_BITS - BANK_SEL_BITS - 1:0] threadBankAddr [TOTAL_THREADS-1:0];
    generate
        for (genvar i = 0; i < TOTAL_THREADS; i = i + 1) begin : decode
            assign threadBankSel[i]  = reqAddr[i][BANK_SEL_HIGH:BANK_SEL_LOW];
            assign threadBankAddr[i] = {reqAddr[i][ADDR_BITS-1:BANK_SEL_HIGH+1], reqAddr[i][BANK_SEL_LOW-1:0]};
        end
    endgenerate
    localparam THREAD_ID_W = (TOTAL_THREADS > 1) ? $clog2(TOTAL_THREADS) : 1;
    reg [THREAD_ID_W-1:0] bankWinner [NUM_BANKS-1:0];
    reg [NUM_BANKS-1:0] bankActive;
    always @(*) begin
        for (b = 0; b < NUM_BANKS; b = b + 1) begin
            bankWinner[b] = 0;
            bankActive[b] = 0;
            for (t = TOTAL_THREADS-1; t >= 0; t = t - 1) begin
                if (reqValid[t] && (threadBankSel[t] == b)) begin
                    bankWinner[b] = t[THREAD_ID_W-1:0];
                    bankActive[b] = 1;
                end
            end
        end
    end
    always @(*) begin
        for (t = 0; t < TOTAL_THREADS; t = t + 1) begin
            reqReady[t] = 0;
            if (reqValid[t]) begin
                if (bankWinner[threadBankSel[t]] == t[THREAD_ID_W-1:0]) begin
                    reqReady[t] = 1;
                end
            end
        end
    end
    assign sharedMemAccessPulse = |bankActive;
    reg conflictDetected;
    always @(*) begin
        conflictDetected = 0;
        for (t = 0; t < TOTAL_THREADS; t = t + 1) begin
            if (reqValid[t] && !reqReady[t]) begin
                conflictDetected = 1;
            end
        end
    end
    assign sharedMemConflictPulse = conflictDetected;
    always @(posedge clk) begin
        if (!reset) begin
            for (b = 0; b < NUM_BANKS; b = b + 1) begin
                if (bankActive[b]) begin
                    if (reqWrite[bankWinner[b]]) begin
                        banks[b][threadBankAddr[bankWinner[b]]] <= reqWdata[bankWinner[b]];
                    end else begin
                        reqRdata[bankWinner[b]] <= banks[b][threadBankAddr[bankWinner[b]]];
                    end
                end
            end
        end
    end
endmodule
