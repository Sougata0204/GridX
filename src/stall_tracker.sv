
`default_nettype none
`timescale 1ns/1ns

module stall_tracker #(
    parameter NUM_WARPS = 1,
    parameter WARP_ID_WIDTH = 2,
    parameter AGE_WIDTH = 16
) (
    input wire clk,
    input wire reset,
    input wire [NUM_WARPS-1:0] warp_active,
    input wire [NUM_WARPS-1:0] warp_waiting_mem,
    input wire [NUM_WARPS-1:0] warp_waiting_shared,
    input wire [NUM_WARPS-1:0] warp_waiting_tensor,
    input wire [NUM_WARPS-1:0] warp_waiting_dep,
    input wire issue_valid,
    input wire [WARP_ID_WIDTH-1:0] issued_warp_id,
    output reg [2:0] stall_reason [NUM_WARPS-1:0],
    output reg [AGE_WIDTH-1:0] warp_age [NUM_WARPS-1:0],
    output wire [WARP_ID_WIDTH-1:0] oldest_ready_warp,
    output wire oldest_ready_valid,
    output reg [31:0] perf_stall_cycles_mem,
    output reg [31:0] perf_stall_cycles_shared,
    output reg [31:0] perf_stall_cycles_tensor,
    output reg [31:0] perf_stall_cycles_dep
);
    localparam READY        = 3'd0;
    localparam WAIT_MEM     = 3'd1;
    localparam WAIT_SHARED  = 3'd2;
    localparam WAIT_TENSOR  = 3'd3;
    localparam WAIT_DEP     = 3'd4;
    integer w;
    always @(posedge clk) begin
        if (reset) begin
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                stall_reason[w] <= READY;
                warp_age[w] <= 0;
            end
            perf_stall_cycles_mem <= 0;
            perf_stall_cycles_shared <= 0;
            perf_stall_cycles_tensor <= 0;
            perf_stall_cycles_dep <= 0;
        end else begin
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                if (!warp_active[w]) begin
                    stall_reason[w] <= READY;
                end else if (warp_waiting_mem[w]) begin
                    stall_reason[w] <= WAIT_MEM;
                    perf_stall_cycles_mem <= perf_stall_cycles_mem + 1;
                end else if (warp_waiting_shared[w]) begin
                    stall_reason[w] <= WAIT_SHARED;
                    perf_stall_cycles_shared <= perf_stall_cycles_shared + 1;
                end else if (warp_waiting_tensor[w]) begin
                    stall_reason[w] <= WAIT_TENSOR;
                    perf_stall_cycles_tensor <= perf_stall_cycles_tensor + 1;
                end else if (warp_waiting_dep[w]) begin
                    stall_reason[w] <= WAIT_DEP;
                    perf_stall_cycles_dep <= perf_stall_cycles_dep + 1;
                end else begin
                    stall_reason[w] <= READY;
                end
                if (issue_valid && issued_warp_id == w[WARP_ID_WIDTH-1:0]) begin
                    warp_age[w] <= 0;
                end else if (stall_reason[w] == READY && warp_active[w]) begin
                    warp_age[w] <= warp_age[w] + 1;
                end
            end
        end
    end
    reg [WARP_ID_WIDTH-1:0] oldest_id;
    reg [AGE_WIDTH-1:0] oldest_age;
    reg found_ready;
    always @(*) begin
        oldest_id = 0;
        oldest_age = 0;
        found_ready = 0;
        for (w = 0; w < NUM_WARPS; w = w + 1) begin
            if (warp_active[w] && stall_reason[w] == READY) begin
                if (!found_ready || warp_age[w] > oldest_age) begin
                    oldest_id = w[WARP_ID_WIDTH-1:0];
                    oldest_age = warp_age[w];
                    found_ready = 1;
                end
            end
        end
    end
    assign oldest_ready_warp = oldest_id;
    assign oldest_ready_valid = found_ready;
endmodule
