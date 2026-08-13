
`default_nettype none
`timescale 1ns/1ns

module kernelPerfModel #(
    parameter NUM_CORES = 8,
    parameter WARPS_PER_CORE = 1,
    parameter COUNTER_WIDTH = 48
) (
    input wire clk,
    input wire reset,
    input wire kernelActive,
    input wire aluActivePulse,
    input wire aluIdlePulse,
    input wire tensorActivePulse,
    input wire tensorIdlePulse,
    input wire dualIssueAttemptPulse,
    input wire dualIssueSuccessPulse,
    input wire stallMemPulse,
    input wire stallSharedPulse,
    input wire stallTensorPulse,
    input wire stallDepPulse,
    input wire stallReadyPulse,
    input wire storeCombinedPulse,
    input wire storeFlushPulse,
    input wire earlyWakeupPulse,
    output reg [31:0] kernelCycles,
    output reg [31:0] aluUtilization,
    output reg [31:0] tensorUtilization,
    output reg [31:0] dualIssueRate,
    output reg [31:0] memoryStallFraction,
    output reg [31:0] storeCombineEfficiency,
    output reg [COUNTER_WIDTH-1:0] cntAluActive,
    output reg [COUNTER_WIDTH-1:0] cntAluIdle,
    output reg [COUNTER_WIDTH-1:0] cntTensorActive,
    output reg [COUNTER_WIDTH-1:0] cntTensorIdle,
    output reg [COUNTER_WIDTH-1:0] cntDualAttempts,
    output reg [COUNTER_WIDTH-1:0] cntDualSuccesses,
    output reg [COUNTER_WIDTH-1:0] cntStallMem,
    output reg [COUNTER_WIDTH-1:0] cntStallShared,
    output reg [COUNTER_WIDTH-1:0] cntStallTensor,
    output reg [COUNTER_WIDTH-1:0] cntStallDep,
    output reg [COUNTER_WIDTH-1:0] cntStallReady,
    output reg [COUNTER_WIDTH-1:0] cntStoreCombined,
    output reg [COUNTER_WIDTH-1:0] cntStoreFlush,
    output reg [COUNTER_WIDTH-1:0] cntEarlyWakeup
);
    reg [31:0] cycleCounter;
    reg wasActive;
    always @(posedge clk) begin
        if (reset) begin
            cycleCounter          <= 0;
            kernelCycles          <= 0;
            aluUtilization        <= 0;
            tensorUtilization     <= 0;
            dualIssueRate        <= 0;
            memoryStallFraction  <= 0;
            storeCombineEfficiency <= 0;
            wasActive             <= 0;
            cntAluActive     <= 0;
            cntAluIdle       <= 0;
            cntTensorActive  <= 0;
            cntTensorIdle    <= 0;
            cntDualAttempts  <= 0;
            cntDualSuccesses <= 0;
            cntStallMem      <= 0;
            cntStallShared   <= 0;
            cntStallTensor   <= 0;
            cntStallDep      <= 0;
            cntStallReady    <= 0;
            cntStoreCombined <= 0;
            cntStoreFlush    <= 0;
            cntEarlyWakeup   <= 0;
        end else begin
            wasActive <= kernelActive;
            if (kernelActive) begin
                cycleCounter <= cycleCounter + 1;
                if (aluActivePulse)         cntAluActive     <= cntAluActive + 1;
                if (aluIdlePulse)           cntAluIdle       <= cntAluIdle + 1;
                if (tensorActivePulse)      cntTensorActive  <= cntTensorActive + 1;
                if (tensorIdlePulse)        cntTensorIdle    <= cntTensorIdle + 1;
                if (dualIssueAttemptPulse) cntDualAttempts  <= cntDualAttempts + 1;
                if (dualIssueSuccessPulse) cntDualSuccesses <= cntDualSuccesses + 1;
                if (stallMemPulse)          cntStallMem      <= cntStallMem + 1;
                if (stallSharedPulse)       cntStallShared   <= cntStallShared + 1;
                if (stallTensorPulse)       cntStallTensor   <= cntStallTensor + 1;
                if (stallDepPulse)          cntStallDep      <= cntStallDep + 1;
                if (stallReadyPulse)        cntStallReady    <= cntStallReady + 1;
                if (storeCombinedPulse)     cntStoreCombined <= cntStoreCombined + 1;
                if (storeFlushPulse)        cntStoreFlush    <= cntStoreFlush + 1;
                if (earlyWakeupPulse)       cntEarlyWakeup   <= cntEarlyWakeup + 1;
            end
            if (wasActive && !kernelActive) begin
                kernelCycles <= cycleCounter;
                if ((cntAluActive + cntAluIdle) > 0) begin
                    aluUtilization <= (cntAluActive << 16) / (cntAluActive + cntAluIdle);
                end
                if ((cntTensorActive + cntTensorIdle) > 0) begin
                    tensorUtilization <= (cntTensorActive << 16) / (cntTensorActive + cntTensorIdle);
                end
                if (cntDualAttempts > 0) begin
                    dualIssueRate <= (cntDualSuccesses << 16) / cntDualAttempts;
                end
                if (cycleCounter > 0) begin
                    memoryStallFraction <= (cntStallMem << 16) / cycleCounter;
                end
                if ((cntStoreCombined + cntStoreFlush) > 0) begin
                    storeCombineEfficiency <= (cntStoreCombined << 16) / (cntStoreCombined + cntStoreFlush);
                end
                cycleCounter <= 0;
            end
        end
    end
endmodule
