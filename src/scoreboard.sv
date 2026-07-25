
`default_nettype none
`timescale 1ns/1ns

module scoreboard #(
    parameter NUM_WARPS = 1,
    parameter NUM_REGS = 16,
    parameter WARP_ID_WIDTH = 1
) (
    input wire clk,
    input wire reset,
    input wire query_valid,
    input wire [WARP_ID_WIDTH-1:0] query_warp_id,
    input wire [3:0] query_rs,
    input wire [3:0] query_rt,
    input wire [3:0] query_rd,
    output wire query_hazard,
    output wire [1:0] query_hazard_type,
    input wire write_pending_set,
    input wire [WARP_ID_WIDTH-1:0] write_pending_warp,
    input wire [3:0] write_pending_reg,
    input wire write_complete,
    input wire [WARP_ID_WIDTH-1:0] write_complete_warp,
    input wire [3:0] write_complete_reg,
    input wire mem_load_start,
    input wire [WARP_ID_WIDTH-1:0] mem_load_warp,
    input wire [3:0] mem_load_dest_reg,
    input wire mem_load_complete,
    input wire [WARP_ID_WIDTH-1:0] mem_load_complete_warp,
    input wire [3:0] mem_load_complete_reg,
    input wire tensor_op_start,
    input wire [WARP_ID_WIDTH-1:0] tensor_op_warp,
    input wire tensor_op_complete,
    input wire [WARP_ID_WIDTH-1:0] tensor_op_complete_warp,
    output reg [31:0] perf_false_stalls_avoided,
    output reg [31:0] perf_true_dependency_stalls
);
    reg [NUM_REGS-1:0] reg_pending [NUM_WARPS-1:0];
    reg [NUM_REGS-1:0] mem_pending [NUM_WARPS-1:0];
    reg [NUM_WARPS-1:0] tensor_in_flight;
    integer w, r;
    wire rs_hazard = reg_pending[query_warp_id][query_rs] || mem_pending[query_warp_id][query_rs];
    wire rt_hazard = reg_pending[query_warp_id][query_rt] || mem_pending[query_warp_id][query_rt];
    wire rd_hazard = reg_pending[query_warp_id][query_rd] || mem_pending[query_warp_id][query_rd];
    wire tensor_hazard = tensor_in_flight[query_warp_id];
    assign query_hazard = query_valid && (rs_hazard || rt_hazard || rd_hazard || tensor_hazard);
    assign query_hazard_type = (rs_hazard || rt_hazard) ? 2'b01 :
                               (rd_hazard) ? 2'b10 :
                               2'b00;
    always @(posedge clk) begin
        if (reset) begin
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                reg_pending[w] <= 0;
                mem_pending[w] <= 0;
            end
            tensor_in_flight <= 0;
            perf_false_stalls_avoided <= 0;
            perf_true_dependency_stalls <= 0;
        end else begin
            if (write_pending_set) begin
                reg_pending[write_pending_warp][write_pending_reg] <= 1;
            end
            if (write_complete) begin
                reg_pending[write_complete_warp][write_complete_reg] <= 0;
            end
            if (mem_load_start) begin
                mem_pending[mem_load_warp][mem_load_dest_reg] <= 1;
            end
            if (mem_load_complete) begin
                mem_pending[mem_load_complete_warp][mem_load_complete_reg] <= 0;
            end
            if (tensor_op_start) begin
                tensor_in_flight[tensor_op_warp] <= 1;
            end
            if (tensor_op_complete) begin
                tensor_in_flight[tensor_op_complete_warp] <= 0;
            end
            if (query_valid) begin
                if (query_hazard) begin
                    perf_true_dependency_stalls <= perf_true_dependency_stalls + 1;
                end else begin
                    perf_false_stalls_avoided <= perf_false_stalls_avoided + 1;
                end
            end
        end
    end
endmodule
