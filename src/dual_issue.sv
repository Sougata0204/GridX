
`default_nettype none
`timescale 1ns/1ns

module dual_issue #(
    parameter WARP_ID_WIDTH = 2,
    parameter INSTR_WIDTH = 16
) (
    input wire clk,
    input wire reset,
    input wire compute_queue_valid,
    input wire [INSTR_WIDTH-1:0] compute_queue_instr,
    input wire [WARP_ID_WIDTH-1:0] compute_queue_warp,
    output wire compute_queue_ready,
    input wire memory_queue_valid,
    input wire [INSTR_WIDTH-1:0] memory_queue_instr,
    input wire [WARP_ID_WIDTH-1:0] memory_queue_warp,
    output wire memory_queue_ready,
    output wire sb_query_valid,
    output wire [WARP_ID_WIDTH-1:0] sb_query_warp,
    output wire [3:0] sb_query_rs,
    output wire [3:0] sb_query_rt,
    output wire [3:0] sb_query_rd,
    input wire sb_hazard,
    output reg compute_dispatch_valid,
    output reg [INSTR_WIDTH-1:0] compute_dispatch_instr,
    output reg [WARP_ID_WIDTH-1:0] compute_dispatch_warp,
    input wire compute_dispatch_ready,
    output reg memory_dispatch_valid,
    output reg [INSTR_WIDTH-1:0] memory_dispatch_instr,
    output reg [WARP_ID_WIDTH-1:0] memory_dispatch_warp,
    input wire memory_dispatch_ready,
    input wire compute_unit_busy,
    input wire memory_unit_busy,
    output reg [31:0] perf_dual_issue_cycles,
    output reg [31:0] perf_single_compute_cycles,
    output reg [31:0] perf_single_memory_cycles,
    output reg [31:0] perf_no_issue_cycles
);
    wire [3:0] compute_rd = compute_queue_instr[11:8];
    wire [3:0] compute_rs = compute_queue_instr[7:4];
    wire [3:0] compute_rt = compute_queue_instr[3:0];
    wire [3:0] memory_rd = memory_queue_instr[11:8];
    wire [3:0] memory_rs = memory_queue_instr[7:4];
    wire [3:0] memory_rt = memory_queue_instr[3:0];
    wire compute_can_issue = compute_queue_valid && !compute_unit_busy && !sb_hazard;
    wire memory_can_issue = memory_queue_valid && !memory_unit_busy;
    wire same_warp = (compute_queue_warp == memory_queue_warp);
    wire dual_possible = compute_can_issue && memory_can_issue && same_warp;
    wire structural_hazard = same_warp && (compute_rd == memory_rd) && (compute_rd != 4'd0);
    wire do_dual_issue = dual_possible && !structural_hazard;
    wire do_compute_only = compute_can_issue && !do_dual_issue;
    wire do_memory_only = memory_can_issue && !compute_can_issue;
    assign sb_query_valid = compute_queue_valid;
    assign sb_query_warp = compute_queue_warp;
    assign sb_query_rs = compute_rs;
    assign sb_query_rt = compute_rt;
    assign sb_query_rd = compute_rd;
    assign compute_queue_ready = (do_dual_issue || do_compute_only) && compute_dispatch_ready;
    assign memory_queue_ready = (do_dual_issue || do_memory_only) && memory_dispatch_ready;
    always @(posedge clk) begin
        if (reset) begin
            compute_dispatch_valid <= 0;
            memory_dispatch_valid <= 0;
            compute_dispatch_instr <= 0;
            memory_dispatch_instr <= 0;
            compute_dispatch_warp <= 0;
            memory_dispatch_warp <= 0;
            perf_dual_issue_cycles <= 0;
            perf_single_compute_cycles <= 0;
            perf_single_memory_cycles <= 0;
            perf_no_issue_cycles <= 0;
        end else begin
            compute_dispatch_valid <= 0;
            memory_dispatch_valid <= 0;
            if (do_dual_issue) begin
                compute_dispatch_valid <= 1;
                compute_dispatch_instr <= compute_queue_instr;
                compute_dispatch_warp <= compute_queue_warp;
                memory_dispatch_valid <= 1;
                memory_dispatch_instr <= memory_queue_instr;
                memory_dispatch_warp <= memory_queue_warp;
                perf_dual_issue_cycles <= perf_dual_issue_cycles + 1;
            end else if (do_compute_only) begin
                compute_dispatch_valid <= 1;
                compute_dispatch_instr <= compute_queue_instr;
                compute_dispatch_warp <= compute_queue_warp;
                perf_single_compute_cycles <= perf_single_compute_cycles + 1;
            end else if (do_memory_only) begin
                memory_dispatch_valid <= 1;
                memory_dispatch_instr <= memory_queue_instr;
                memory_dispatch_warp <= memory_queue_warp;
                perf_single_memory_cycles <= perf_single_memory_cycles + 1;
            end else begin
                perf_no_issue_cycles <= perf_no_issue_cycles + 1;
            end
        end
    end
endmodule
