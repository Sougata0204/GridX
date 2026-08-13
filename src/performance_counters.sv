
`default_nettype none
`timescale 1ns/1ns

module performanceCounters #(
    parameter NUM_CORES = 8,
    parameter WARPS_PER_CORE = 1,
    parameter COUNTER_WIDTH = 48
) (
    input wire clk,
    input wire reset,
    input wire enable,
    input wire clear,
    input wire [NUM_CORES-1:0] coreActive,
    input wire [NUM_CORES-1:0] coreStalled,
    input wire [NUM_CORES-1:0] instrIssued,
    input wire [NUM_CORES-1:0] instrRetired,
    input wire [NUM_CORES-1:0] l1ReadHit,
    input wire [NUM_CORES-1:0] l1WriteHit,
    input wire [NUM_CORES-1:0] l2ReadHit,
    input wire [NUM_CORES-1:0] l2WriteHit,
    input wire [NUM_CORES-1:0] sharedMemHit,
    input wire [NUM_CORES-1:0] sharedMemConflict,
    input wire [NUM_CORES-1:0] externalMemAccess,
    input wire [NUM_CORES-1:0] l3Access,
    input wire [NUM_CORES-1:0] stallMem,
    input wire [NUM_CORES-1:0] stallTensor,
    input wire [NUM_CORES-1:0] stallRegHazard,
    input wire [NUM_CORES-1:0] stallStructural,
    input wire [NUM_CORES-1:0] tensorOpStart,
    input wire [NUM_CORES-1:0] tensorOpComplete,
    input wire [NUM_CORES-1:0] coreClockGated,
    input wire [NUM_CORES-1:0] corePowerGated,
    output reg [COUNTER_WIDTH-1:0] cycleCount,
    output reg [COUNTER_WIDTH-1:0] totalIssued,
    output reg [COUNTER_WIDTH-1:0] totalRetired,
    output reg [COUNTER_WIDTH-1:0] l1ReadHits,
    output reg [COUNTER_WIDTH-1:0] l1WriteHits,
    output reg [COUNTER_WIDTH-1:0] l2ReadHits,
    output reg [COUNTER_WIDTH-1:0] l2WriteHits,
    output reg [COUNTER_WIDTH-1:0] sharedMemHits,
    output reg [COUNTER_WIDTH-1:0] sharedMemConflicts,
    output reg [COUNTER_WIDTH-1:0] externalMemAccesses,
    output reg [COUNTER_WIDTH-1:0] l3Accesses,
    output reg [COUNTER_WIDTH-1:0] stallCyclesMem,
    output reg [COUNTER_WIDTH-1:0] stallCyclesTensor,
    output reg [COUNTER_WIDTH-1:0] stallCyclesReg,
    output reg [COUNTER_WIDTH-1:0] stallCyclesStructural,
    output reg [COUNTER_WIDTH-1:0] tensorOpsStarted,
    output reg [COUNTER_WIDTH-1:0] tensorOpsCompleted,
    output reg [COUNTER_WIDTH-1:0] clockGatedCycles,
    output reg [COUNTER_WIDTH-1:0] powerGatedCycles,
    output reg [15:0] coreUtilization,
    output reg [15:0] ipc
);
    reg [COUNTER_WIDTH-1:0] activeCoreCycles;

    function automatic int countOnes;
        input [NUM_CORES-1:0] vec;
        int cnt;
        begin
            cnt = 0;
            for (int i = 0; i < NUM_CORES; i++) begin
                if (vec[i]) cnt = cnt + 1;
            end
            countOnes = cnt;
        end
    endfunction
    always @(posedge clk) begin
        if (reset || clear) begin
            cycleCount <= 0;
            totalIssued <= 0;
            totalRetired <= 0;
            l1ReadHits <= 0;
            l1WriteHits <= 0;
            l2ReadHits <= 0;
            l2WriteHits <= 0;
            sharedMemHits <= 0;
            sharedMemConflicts <= 0;
            externalMemAccesses <= 0;
            l3Accesses <= 0;
            stallCyclesMem <= 0;
            stallCyclesTensor <= 0;
            stallCyclesReg <= 0;
            stallCyclesStructural <= 0;
            tensorOpsStarted <= 0;
            tensorOpsCompleted <= 0;
            clockGatedCycles <= 0;
            powerGatedCycles <= 0;
            activeCoreCycles <= 0;
            coreUtilization <= 0;
            ipc <= 0;
        end else if (enable) begin
            cycleCount <= cycleCount + 1;
            totalIssued <= totalIssued + countOnes(instrIssued);
            totalRetired <= totalRetired + countOnes(instrRetired);
            l1ReadHits <= l1ReadHits + countOnes(l1ReadHit);
            l1WriteHits <= l1WriteHits + countOnes(l1WriteHit);
            l2ReadHits <= l2ReadHits + countOnes(l2ReadHit);
            l2WriteHits <= l2WriteHits + countOnes(l2WriteHit);
            sharedMemHits <= sharedMemHits + countOnes(sharedMemHit);
            sharedMemConflicts <= sharedMemConflicts + countOnes(sharedMemConflict);
            externalMemAccesses <= externalMemAccesses + countOnes(externalMemAccess);
            l3Accesses <= l3Accesses + countOnes(l3Access);
            stallCyclesMem <= stallCyclesMem + countOnes(stallMem);
            stallCyclesTensor <= stallCyclesTensor + countOnes(stallTensor);
            stallCyclesReg <= stallCyclesReg + countOnes(stallRegHazard);
            stallCyclesStructural <= stallCyclesStructural + countOnes(stallStructural);
            tensorOpsStarted <= tensorOpsStarted + countOnes(tensorOpStart);
            tensorOpsCompleted <= tensorOpsCompleted + countOnes(tensorOpComplete);
            clockGatedCycles <= clockGatedCycles + countOnes(coreClockGated);
            powerGatedCycles <= powerGatedCycles + countOnes(corePowerGated);
            activeCoreCycles <= activeCoreCycles + countOnes(coreActive);
            if (cycleCount[7:0] == 8'hFF && cycleCount > 0) begin
                coreUtilization <= (activeCoreCycles << 8) / (cycleCount * NUM_CORES);
                ipc <= (totalRetired << 8) / cycleCount;
            end
        end
    end
endmodule
