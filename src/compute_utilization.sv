
`default_nettype none
`timescale 1ns/1ns

module compute_utilization #(
    parameter COUNTER_WIDTH = 32
) (
    input wire clk,
    input wire reset,
    input wire core_active,
    input wire alu_enable,
    input wire alu_executing,
    input wire tensor_busy,
    input wire tensor_executing,
    output reg [COUNTER_WIDTH-1:0] alu_active_cycles,
    output reg [COUNTER_WIDTH-1:0] alu_idle_cycles,
    output reg [COUNTER_WIDTH-1:0] tensor_active_cycles,
    output reg [COUNTER_WIDTH-1:0] tensor_idle_cycles,
    output wire alu_active_pulse,
    output wire alu_idle_pulse,
    output wire tensor_active_pulse,
    output wire tensor_idle_pulse
);
    assign alu_active_pulse = core_active && alu_executing;
    assign alu_idle_pulse = core_active && alu_enable && !alu_executing;
    assign tensor_active_pulse = core_active && tensor_executing;
    assign tensor_idle_pulse = core_active && !tensor_busy && !tensor_executing;
    always @(posedge clk) begin
        if (reset) begin
            alu_active_cycles <= 0;
            alu_idle_cycles <= 0;
            tensor_active_cycles <= 0;
            tensor_idle_cycles <= 0;
        end else if (core_active) begin
            if (alu_executing) begin
                alu_active_cycles <= alu_active_cycles + 1;
            end else if (alu_enable) begin
                alu_idle_cycles <= alu_idle_cycles + 1;
            end
            if (tensor_executing) begin
                tensor_active_cycles <= tensor_active_cycles + 1;
            end else if (!tensor_busy) begin
                tensor_idle_cycles <= tensor_idle_cycles + 1;
            end
        end
    end
endmodule
