
`default_nettype none
`timescale 1ns/1ns

module dualIssue #(
    parameter WARP_ID_WIDTH = 2,
    parameter INSTR_WIDTH = 16
) (
    input wire clk,
    input wire reset,
    input wire computeQueueValid,
    input wire [INSTR_WIDTH-1:0] computeQueueInstr,
    input wire [WARP_ID_WIDTH-1:0] computeQueueWarp,
    output wire computeQueueReady,
    input wire memoryQueueValid,
    input wire [INSTR_WIDTH-1:0] memoryQueueInstr,
    input wire [WARP_ID_WIDTH-1:0] memoryQueueWarp,
    output wire memoryQueueReady,
    output wire sbQueryValid,
    output wire [WARP_ID_WIDTH-1:0] sbQueryWarp,
    output wire [3:0] sbQueryRs,
    output wire [3:0] sbQueryRt,
    output wire [3:0] sbQueryRd,
    input wire sbHazard,
    output reg computeDispatchValid,
    output reg [INSTR_WIDTH-1:0] computeDispatchInstr,
    output reg [WARP_ID_WIDTH-1:0] computeDispatchWarp,
    input wire computeDispatchReady,
    output reg memoryDispatchValid,
    output reg [INSTR_WIDTH-1:0] memoryDispatchInstr,
    output reg [WARP_ID_WIDTH-1:0] memoryDispatchWarp,
    input wire memoryDispatchReady,
    input wire computeUnitBusy,
    input wire memoryUnitBusy,
    output reg [31:0] perfDualIssueCycles,
    output reg [31:0] perfSingleComputeCycles,
    output reg [31:0] perfSingleMemoryCycles,
    output reg [31:0] perfNoIssueCycles
);
    wire [3:0] computeRd = computeQueueInstr[11:8];
    wire [3:0] computeRs = computeQueueInstr[7:4];
    wire [3:0] computeRt = computeQueueInstr[3:0];
    wire [3:0] memoryRd = memoryQueueInstr[11:8];
    wire [3:0] memoryRs = memoryQueueInstr[7:4];
    wire [3:0] memoryRt = memoryQueueInstr[3:0];
    wire computeCanIssue = computeQueueValid && !computeUnitBusy && !sbHazard;
    wire memoryCanIssue = memoryQueueValid && !memoryUnitBusy;
    wire sameWarp = (computeQueueWarp == memoryQueueWarp);
    wire dualPossible = computeCanIssue && memoryCanIssue && sameWarp;
    wire structuralHazard = sameWarp && (computeRd == memoryRd) && (computeRd != 4'd0);
    wire doDualIssue = dualPossible && !structuralHazard;
    wire doComputeOnly = computeCanIssue && !doDualIssue;
    wire doMemoryOnly = memoryCanIssue && !computeCanIssue;
    assign sbQueryValid = computeQueueValid;
    assign sbQueryWarp = computeQueueWarp;
    assign sbQueryRs = computeRs;
    assign sbQueryRt = computeRt;
    assign sbQueryRd = computeRd;
    assign computeQueueReady = (doDualIssue || doComputeOnly) && computeDispatchReady;
    assign memoryQueueReady = (doDualIssue || doMemoryOnly) && memoryDispatchReady;
    always @(posedge clk) begin
        if (reset) begin
            computeDispatchValid <= 0;
            memoryDispatchValid <= 0;
            computeDispatchInstr <= 0;
            memoryDispatchInstr <= 0;
            computeDispatchWarp <= 0;
            memoryDispatchWarp <= 0;
            perfDualIssueCycles <= 0;
            perfSingleComputeCycles <= 0;
            perfSingleMemoryCycles <= 0;
            perfNoIssueCycles <= 0;
        end else begin
            computeDispatchValid <= 0;
            memoryDispatchValid <= 0;
            if (doDualIssue) begin
                computeDispatchValid <= 1;
                computeDispatchInstr <= computeQueueInstr;
                computeDispatchWarp <= computeQueueWarp;
                memoryDispatchValid <= 1;
                memoryDispatchInstr <= memoryQueueInstr;
                memoryDispatchWarp <= memoryQueueWarp;
                perfDualIssueCycles <= perfDualIssueCycles + 1;
            end else if (doComputeOnly) begin
                computeDispatchValid <= 1;
                computeDispatchInstr <= computeQueueInstr;
                computeDispatchWarp <= computeQueueWarp;
                perfSingleComputeCycles <= perfSingleComputeCycles + 1;
            end else if (doMemoryOnly) begin
                memoryDispatchValid <= 1;
                memoryDispatchInstr <= memoryQueueInstr;
                memoryDispatchWarp <= memoryQueueWarp;
                perfSingleMemoryCycles <= perfSingleMemoryCycles + 1;
            end else begin
                perfNoIssueCycles <= perfNoIssueCycles + 1;
            end
        end
    end
endmodule
