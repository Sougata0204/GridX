
`default_nettype none
`timescale 1ns/1ns

module shared_memory #(
    parameter DATA_BITS = 16,
    parameter ADDR_BITS = 13,
    parameter NUM_WARPS = 1,
    parameter THREADS_PER_WARP = 4,
    parameter NUM_BANKS = 4
)(
    input wire clk,
    input wire reset,
    input wire [NUM_WARPS*THREADS_PER_WARP-1:0] req_valid,
    input wire [NUM_WARPS*THREADS_PER_WARP-1:0] req_write,
    input wire [ADDR_BITS-1:0] req_addr [NUM_WARPS*THREADS_PER_WARP-1:0],
    input wire [DATA_BITS-1:0] req_wdata [NUM_WARPS*THREADS_PER_WARP-1:0],
    output reg [NUM_WARPS*THREADS_PER_WARP-1:0] req_ready,
    output reg [DATA_BITS-1:0] req_rdata [NUM_WARPS*THREADS_PER_WARP-1:0],
    output wire shared_mem_access_pulse,
    output wire shared_mem_conflict_pulse
);
    localparam TOTAL_THREADS = NUM_WARPS * THREADS_PER_WARP;
    localparam BANK_SEL_BITS = $clog2(NUM_BANKS);
    localparam BANK_SEL_HIGH = BANK_SEL_BITS;
    localparam BANK_SEL_LOW  = 1;
    reg [DATA_BITS-1:0] banks [NUM_BANKS-1:0][511:0];
    integer b, t;
    wire [BANK_SEL_BITS-1:0] thread_bank_sel [TOTAL_THREADS-1:0];
    wire [ADDR_BITS - BANK_SEL_BITS - 1:0] thread_bank_addr [TOTAL_THREADS-1:0];
    generate
        for (genvar i = 0; i < TOTAL_THREADS; i = i + 1) begin : decode
            assign thread_bank_sel[i]  = req_addr[i][BANK_SEL_HIGH:BANK_SEL_LOW];
            assign thread_bank_addr[i] = {req_addr[i][ADDR_BITS-1:BANK_SEL_HIGH+1], req_addr[i][BANK_SEL_LOW-1:0]};
        end
    endgenerate
    localparam THREAD_ID_W = (TOTAL_THREADS > 1) ? $clog2(TOTAL_THREADS) : 1;
    reg [THREAD_ID_W-1:0] bank_winner [NUM_BANKS-1:0];
    reg [NUM_BANKS-1:0] bank_active;
    always @(*) begin
        for (b = 0; b < NUM_BANKS; b = b + 1) begin
            bank_winner[b] = 0;
            bank_active[b] = 0;
            for (t = TOTAL_THREADS-1; t >= 0; t = t - 1) begin
                if (req_valid[t] && (thread_bank_sel[t] == b)) begin
                    bank_winner[b] = t[THREAD_ID_W-1:0];
                    bank_active[b] = 1;
                end
            end
        end
    end
    always @(*) begin
        for (t = 0; t < TOTAL_THREADS; t = t + 1) begin
            req_ready[t] = 0;
            if (req_valid[t]) begin
                if (bank_winner[thread_bank_sel[t]] == t[THREAD_ID_W-1:0]) begin
                    req_ready[t] = 1;
                end
            end
        end
    end
    assign shared_mem_access_pulse = |bank_active;
    reg conflict_detected;
    always @(*) begin
        conflict_detected = 0;
        for (t = 0; t < TOTAL_THREADS; t = t + 1) begin
            if (req_valid[t] && !req_ready[t]) begin
                conflict_detected = 1;
            end
        end
    end
    assign shared_mem_conflict_pulse = conflict_detected;
    always @(posedge clk) begin
        if (!reset) begin
            for (b = 0; b < NUM_BANKS; b = b + 1) begin
                if (bank_active[b]) begin
                    if (req_write[bank_winner[b]]) begin
                        banks[b][thread_bank_addr[bank_winner[b]]] <= req_wdata[bank_winner[b]];
                    end else begin
                        req_rdata[bank_winner[b]] <= banks[b][thread_bank_addr[bank_winner[b]]];
                    end
                end
            end
        end
    end
endmodule
