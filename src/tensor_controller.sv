
`default_nettype none
`timescale 1ns/1ns

module tensorController #(
    parameter NUM_WARPS = 1,
    parameter NUM_UNITS = 4,
    parameter WARP_ID_WIDTH = (NUM_WARPS > 1) ? $clog2(NUM_WARPS) : 1
) (
    input wire clk,
    input wire reset,
    input wire requestValid,
    input wire [WARP_ID_WIDTH-1:0] warpId,
    input wire [3:0] destRegIdx,
    input wire signed [3:0][3:0][15:0] srcA,
    input wire signed [3:0][3:0][15:0] srcB,
    input wire signed [3:0][3:0][31:0] srcC,
    input wire [15:0] imm,
    output reg requestReady,
    output reg [NUM_WARPS-1:0] warpBusy,
    output reg [NUM_WARPS-1:0] warpDone,
    output reg writebackValid,
    output reg [WARP_ID_WIDTH-1:0] writebackWarpId,
    output reg signed [3:0][3:0][31:0] writebackData,
    output reg [3:0] writebackRegIdx,
    output wire [$clog2(NUM_WARPS+1)-1:0] activeTensorOps
);
    reg [NUM_UNITS-1:0] unitStart;
    wire [NUM_UNITS-1:0] unitDone;
    wire [NUM_UNITS-1:0] unitBusyStatus;
    wire signed [3:0][3:0][31:0] unitResult [NUM_UNITS-1:0];
    reg [WARP_ID_WIDTH-1:0] unitOwner [NUM_UNITS-1:0];
    reg [NUM_UNITS-1:0] unitActive;
    integer i;
    reg signed [3:0][3:0][15:0] unitSrcA [NUM_UNITS-1:0];
    reg signed [3:0][3:0][15:0] unitSrcB [NUM_UNITS-1:0];
    reg signed [3:0][3:0][31:0] unitSrcC [NUM_UNITS-1:0];
    wire [3:0] unitTagIn [NUM_UNITS-1:0];
    wire [3:0] unitTagOut [NUM_UNITS-1:0];
    wire [NUM_UNITS-1:0] unitOutValid;
    reg [15:0] unitImm [NUM_UNITS-1:0];
    wire [NUM_UNITS-1:0] tcDone, rtDone;
    wire signed [3:0][3:0][31:0] tcResult [NUM_UNITS-1:0];
    wire signed [3:0][3:0][31:0] rtResult [NUM_UNITS-1:0];
    wire [NUM_UNITS-1:0] tcBusyStatus, rtBusyStatus;

    genvar u;
    generate
        for (u = 0; u < NUM_UNITS; u = u + 1) begin : coProcessors
            assign unitTagIn[u] = u[3:0];

            tensorUnitPipelined tUnit (
                .clk(clk),
                .reset(reset),
                .start(unitStart[u] && unitImm[u] != 1),
                .tagIn(unitTagIn[u]),
                .busy(tcBusyStatus[u]),
                .done(tcDone[u]),
                .tagOut(),
                .matrixA(unitSrcA[u]),
                .matrixB(unitSrcB[u]),
                .matrixC(unitSrcC[u]),
                .matrixD(tcResult[u])
            );

            rtCore rtUnit (
                .clk(clk),
                .reset(reset),
                .start(unitStart[u] && unitImm[u] == 1),
                .tagIn(unitTagIn[u]),
                .busy(rtBusyStatus[u]),
                .done(rtDone[u]),
                .tagOut(),
                .matrixA(unitSrcA[u]),
                .matrixB(unitSrcB[u]),
                .matrixC(unitSrcC[u]),
                .matrixD(rtResult[u])
            );

            assign unitDone[u] = tcDone[u] | rtDone[u];
            assign unitResult[u] = (unitImm[u] == 1) ? rtResult[u] : tcResult[u];
            assign unitBusyStatus[u] = tcBusyStatus[u] | rtBusyStatus[u];
        end
    endgenerate
    reg [1:0] freeUnitIdx;
    reg foundFree;
    always @(*) begin
        foundFree = 0;
        freeUnitIdx = 0;
        for (i = 0; i < NUM_UNITS; i = i + 1) begin
            if (!unitActive[i] && !foundFree) begin
                freeUnitIdx = i[1:0];
                foundFree = 1;
            end
        end
    end
    assign requestReady = foundFree;
    reg [3:0] unitDestReg [NUM_UNITS-1:0];
    always @(posedge clk) begin
        if (reset) begin
            unitStart <= 0;
            unitActive <= 0;
            warpBusy <= 0;
            warpDone <= 0;
            writebackValid <= 0;
            for (i=0; i<NUM_UNITS; i=i+1) begin
                unitOwner[i] <= 0;
                unitDestReg[i] <= 0;
                unitSrcA[i] <= 0;
                unitSrcB[i] <= 0;
                unitSrcC[i] <= 0;
                unitImm[i] <= 0;
            end
        end else begin
            unitStart <= 0;
            warpDone <= 0;
            writebackValid <= 0;
            if (requestValid && foundFree) begin
                unitStart[freeUnitIdx] <= 1;
                unitActive[freeUnitIdx] <= 1;
                unitOwner[freeUnitIdx] <= warpId;
                unitDestReg[freeUnitIdx] <= destRegIdx;
                warpBusy[warpId] <= 1;
                unitSrcA[freeUnitIdx] <= srcA;
                unitSrcB[freeUnitIdx] <= srcB;
                unitSrcC[freeUnitIdx] <= srcC;
                unitImm[freeUnitIdx] <= imm;
            end
            for (i = 0; i < NUM_UNITS; i = i + 1) begin
                if (unitDone[i]) begin
                    writebackValid <= 1;
                    writebackWarpId <= unitOwner[i];
                    writebackData <= unitResult[i];
                    writebackRegIdx <= unitDestReg[i];
                    unitActive[i] <= 0;
                    warpBusy[unitOwner[i]] <= 0;
                    warpDone[unitOwner[i]] <= 1;
                end
            end
        end
    end
    assign activeTensorOps = $countones(warpBusy);
`ifdef DEBUG
    reg [31:0] debugCycle;
    always @(posedge clk) begin
        if (reset) debugCycle <= 0;
        else debugCycle <= debugCycle + 1;
    end
    always @(posedge clk) begin
        if (requestValid) begin
            $display("[tCtrl] Cycle %d Request: valid=%b foundFree=%b freeUnit=%d warpId=%d imm=%d dest=%d",
                     debugCycle, requestValid, foundFree, freeUnitIdx, warpId, imm, destRegIdx);
        end
        for (int u = 0; u < NUM_UNITS; u = u + 1) begin
            if (unitDone[u]) begin
                $display("[tCtrl] Cycle %d Unit %d DONE: tcDone=%b rtDone=%b data=%h",
                         debugCycle, u, tcDone[u], rtDone[u], unitResult[u][0][0]);
            end
        end
    end
`endif
endmodule
