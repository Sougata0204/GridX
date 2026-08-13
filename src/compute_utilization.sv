
`default_nettype none
`timescale 1ns/1ns

module computeUtilization #(
    parameter COUNTER_WIDTH = 32
) (
    input wire clk,
    input wire reset,
    input wire coreActive,
    input wire aluEnable,
    input wire aluExecuting,
    input wire tensorBusy,
    input wire tensorExecuting,
    output reg [COUNTER_WIDTH-1:0] aluActiveCycles,
    output reg [COUNTER_WIDTH-1:0] aluIdleCycles,
    output reg [COUNTER_WIDTH-1:0] tensorActiveCycles,
    output reg [COUNTER_WIDTH-1:0] tensorIdleCycles,
    output wire aluActivePulse,
    output wire aluIdlePulse,
    output wire tensorActivePulse,
    output wire tensorIdlePulse
);
    assign aluActivePulse = coreActive && aluExecuting;
    assign aluIdlePulse = coreActive && aluEnable && !aluExecuting;
    assign tensorActivePulse = coreActive && tensorExecuting;
    assign tensorIdlePulse = coreActive && !tensorBusy && !tensorExecuting;
    always @(posedge clk) begin
        if (reset) begin
            aluActiveCycles <= 0;
            aluIdleCycles <= 0;
            tensorActiveCycles <= 0;
            tensorIdleCycles <= 0;
        end else if (coreActive) begin
            if (aluExecuting) begin
                aluActiveCycles <= aluActiveCycles + 1;
            end else if (aluEnable) begin
                aluIdleCycles <= aluIdleCycles + 1;
            end
            if (tensorExecuting) begin
                tensorActiveCycles <= tensorActiveCycles + 1;
            end else if (!tensorBusy) begin
                tensorIdleCycles <= tensorIdleCycles + 1;
            end
        end
    end
endmodule
