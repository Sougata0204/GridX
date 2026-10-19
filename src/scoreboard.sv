
`default_nettype none
`timescale 1ns/1ps

// Register dependency scoreboard tracking in-flight writes to prevent read-after-write and write-after-write hazards.
module scoreboard #(
    parameter NUM_WARPS     = 1,
    parameter NUM_REGS      = 16,
    parameter WARP_ID_WIDTH = 1
) (
    input  wire                      clk,
    input  wire                      reset,

    input  wire                      queryValid,
    input  wire [WARP_ID_WIDTH-1:0]  queryWarpId,
    input  wire [3:0]                queryRs,
    input  wire [3:0]                queryRt,
    input  wire [3:0]                queryRd,
    output wire                      queryHazard,
    output wire [1:0]                queryHazardType,

    input  wire                      writePendingSet,
    input  wire [WARP_ID_WIDTH-1:0]  writePendingWarp,
    input  wire [3:0]                writePendingReg,
    input  wire                      writeComplete,
    input  wire [WARP_ID_WIDTH-1:0]  writeCompleteWarp,
    input  wire [3:0]                writeCompleteReg,

    input  wire                      memLoadStart,
    input  wire [WARP_ID_WIDTH-1:0]  memLoadWarp,
    input  wire [3:0]                memLoadDestReg,
    input  wire                      memLoadComplete,
    input  wire [WARP_ID_WIDTH-1:0]  memLoadCompleteWarp,
    input  wire [3:0]                memLoadCompleteReg,

    input  wire                      tensorOpStart,
    input  wire [WARP_ID_WIDTH-1:0]  tensorOpWarp,
    input  wire                      tensorOpComplete,
    input  wire [WARP_ID_WIDTH-1:0]  tensorOpCompleteWarp,

    output reg  [31:0]               perfFalseStallsAvoided,
    output reg  [31:0]               perfTrueDependencyStalls
);

    reg [NUM_REGS-1:0] regPending [NUM_WARPS-1:0];
    reg [NUM_REGS-1:0] memPending [NUM_WARPS-1:0];
    reg [NUM_WARPS-1:0] tensorInFlight;
    integer w;

    wire rsHazard = (queryRs != 4'b0000) && (regPending[queryWarpId][queryRs] || memPending[queryWarpId][queryRs]);
    wire rtHazard = (queryRt != 4'b0000) && (regPending[queryWarpId][queryRt] || memPending[queryWarpId][queryRt]);
    wire rdHazard = (queryRd != 4'b0000) && (regPending[queryWarpId][queryRd] || memPending[queryWarpId][queryRd]);
    wire tensorHazard = tensorInFlight[queryWarpId];

    assign queryHazard = queryValid && (rsHazard || rtHazard || rdHazard || tensorHazard);
    assign queryHazardType = (rsHazard || rtHazard) ? 2'b01 :
                             (rdHazard)             ? 2'b10 :
                             2'b00;

    always @(posedge clk) begin
        if (reset) begin
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                regPending[w] <= '0;
                memPending[w] <= '0;
            end
            tensorInFlight           <= '0;
            perfFalseStallsAvoided   <= 32'd0;
            perfTrueDependencyStalls <= 32'd0;
        end else begin
            if (writePendingSet && (writePendingReg != 4'b0000)) begin
                regPending[writePendingWarp][writePendingReg] <= 1'b1;
            end
            if (writeComplete && (writeCompleteReg != 4'b0000)) begin
                regPending[writeCompleteWarp][writeCompleteReg] <= 1'b0;
            end

            if (memLoadStart && (memLoadDestReg != 4'b0000)) begin
                memPending[memLoadWarp][memLoadDestReg] <= 1'b1;
            end
            if (memLoadComplete && (memLoadCompleteReg != 4'b0000)) begin
                memPending[memLoadCompleteWarp][memLoadCompleteReg] <= 1'b0;
            end

            if (tensorOpComplete) begin
                tensorInFlight[tensorOpCompleteWarp] <= 1'b0;
            end
            if (tensorOpStart) begin
                tensorInFlight[tensorOpWarp] <= 1'b1;
            end

            if (queryValid) begin
                if (queryHazard)
                    perfTrueDependencyStalls <= perfTrueDependencyStalls + 1;
                else
                    perfFalseStallsAvoided <= perfFalseStallsAvoided + 1;
            end
        end
    end

endmodule
