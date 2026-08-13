// Out-of-Order Warp Scheduler & Issue Logic
// Tracks warp execution states and issues instructions to active thread lanes.
// I updated the SIMT divergence stack handling to re-converge thread lanes accurately at branch targets.

`default_nettype none
`timescale 1ns/1ns
import gridxPkg::*;

module scheduler #(
    parameter THREADS_PER_BLOCK = 4,
    parameter WARPS_PER_CORE = 1,
    parameter MAX_OUTSTANDING_LOADS = 4,
    parameter NUM_REGS = 16,
    parameter THREADS_PER_WARP = THREADS_PER_BLOCK / WARPS_PER_CORE,
    parameter WARP_ID_W = (WARPS_PER_CORE > 1) ? $clog2(WARPS_PER_CORE) : 1,
    parameter PROGRAM_MEM_ADDR_BITS = 8
) (
    input wire clk,
    input wire reset,
    input wire start,
    input wire kernelRunning,
    input wire [WARPS_PER_CORE-1:0] tensorDone,
    input wire powerSleepReq,
    input wire [63:0] decodedPacket,
    input wire [63:0] latchedPacket,
    input wire [2:0] fetcherState,
    input wire [1:0] lsuState [THREADS_PER_BLOCK-1:0],
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] currentPc,
    input wire [PROGRAM_MEM_ADDR_BITS-1:0] nextPc [THREADS_PER_BLOCK-1:0],
    output reg [3:0] coreState,
    output reg [3:0] warpState [WARPS_PER_CORE-1:0],
    output reg [WARP_ID_W-1:0] activeWarpId,
    output reg [WARPS_PER_CORE-1:0] warpIssueEnable,
    output wire [WARPS_PER_CORE-1:0] warpStalledOnReg,
    output wire [WARPS_PER_CORE-1:0] warpStalledOnMem,
    output reg trackerEnqueueValid,
    output reg [3:0] trackerEnqueueDestReg,
    output reg [15:0] trackerEnqueueTag,
    input wire trackerDequeueValid,
    input wire [3:0] trackerDequeuedDestReg,
    input wire nocCreditsFull,
    input wire storeBufferEmpty,
    input wire trackerDequeueFound,
    input wire [WARPS_PER_CORE-1:0] trackerWarpHasPending,
    input wire [WARPS_PER_CORE-1:0] trackerWarpQueueFull,
    input wire sbHazard,
    input wire [1:0] sbHazardType,
    output wire perfStallMemPulse,
    output wire perfStallSharedPulse,
    output wire perfStallTensorPulse,
    output wire perfStallDepPulse,
    output wire perfStallReadyPulse,
    input wire [WARPS_PER_CORE-1:0] warpEarlyWakeup,
    output wire [THREADS_PER_WARP-1:0] activeMask,
    output reg done
);
    // THREADS_PER_WARP and WARP_ID_W are derived parameters (see parameter block above)
    reg [$clog2(MAX_OUTSTANDING_LOADS+1)-1:0] pendingMemCount [WARPS_PER_CORE-1:0];
    localparam LOAD_QUEUE_DEPTH = MAX_OUTSTANDING_LOADS;
    reg [22:0] loadQueue [WARPS_PER_CORE-1:0][LOAD_QUEUE_DEPTH-1:0];
    reg [$clog2(LOAD_QUEUE_DEPTH)-1:0] lqHead [WARPS_PER_CORE-1:0];
    reg [$clog2(LOAD_QUEUE_DEPTH)-1:0] lqTail [WARPS_PER_CORE-1:0];

    reg [THREADS_PER_WARP-1:0] simtStackMask [WARPS_PER_CORE-1:0][3:0];
    reg [PROGRAM_MEM_ADDR_BITS-1:0] simtStackPc [WARPS_PER_CORE-1:0][3:0];
    reg [2:0] simtStackPtr [WARPS_PER_CORE-1:0];
    localparam IDLE         = STATE_IDLE,
               FETCH        = STATE_FETCH,
               DECODE       = STATE_DECODE,
               ISSUE        = STATE_ISSUE,
               EXECUTE      = STATE_EXECUTE,
               UPDATE       = STATE_UPDATE,
               STALLED_MEM  = STATE_STALLED_MEM,
               tensorBusy  = STATE_TENSOR_BUSY,
               SLEEP        = STATE_SLEEP,
               WAIT_REG     = STATE_WAIT_REG,
               WAIT_MEM_Q   = STATE_WAIT_MEM_Q,
               WAIT_BAR     = STATE_WAIT_BAR,
               WAIT_FENCE   = STATE_WAIT_FENCE,
               DONE         = STATE_DONE;
    reg [WARPS_PER_CORE-1:0] justDecoded;
    reg [WARPS_PER_CORE-1:0] barrierMask;
    wire [63:0] workingPacket = justDecoded[activeWarpId] ? decodedPacket : latchedPacket;
    wire pktTensor = workingPacket[43];
    wire pktRet    = workingPacket[42];
    wire pktMemRead  = workingPacket[32];
    wire pktMemWrite = workingPacket[33];
    wire pktMem    = pktMemRead || pktMemWrite;
    wire pktRegWe = workingPacket[31];
    wire [3:0] pktRd = workingPacket[27:24];
    wire [3:0] pktRs = workingPacket[23:20];
    wire [3:0] pktRt = workingPacket[19:16];
    reg [PROGRAM_MEM_ADDR_BITS-1:0] warpPc [WARPS_PER_CORE-1:0];
    reg warpDoneFlag [WARPS_PER_CORE-1:0];
    reg [THREADS_PER_WARP-1:0] warpActiveMask [WARPS_PER_CORE-1:0];
    reg startLatched;
    wire memQueueFull = (pendingMemCount[activeWarpId] >= MAX_OUTSTANDING_LOADS);
    genvar sw;
    generate
        for (sw = 0; sw < WARPS_PER_CORE; sw = sw + 1) begin : stallGen
            assign warpStalledOnReg[sw] = (warpState[sw] == WAIT_REG);
            assign warpStalledOnMem[sw] = (warpState[sw] == WAIT_MEM_Q);
        end
    endgenerate
    always @(*) begin
        currentPc = warpPc[activeWarpId];
        coreState = warpState[activeWarpId];
    end
    assign activeMask = warpActiveMask[activeWarpId];
    always @(*) begin
        warpIssueEnable = 0;
        if (warpState[activeWarpId] == ISSUE) begin
            warpIssueEnable[activeWarpId] = 1'b1;
        end
        // core is done only when all warps finished AND store buffer is drained
        done = storeBufferEmpty;
        for (int i = 0; i < WARPS_PER_CORE; i++) begin
            if (!warpDoneFlag[i]) done = 0;
        end
    end
    wire [WARP_ID_W-1:0] gtoOldestWarp;
    wire gtoOldestValid;
    wire [WARP_ID_W-1:0] nextWarpId;
    generate
        if (WARPS_PER_CORE > 1) begin : genNextWarp
            assign nextWarpId = gtoOldestValid ? gtoOldestWarp : 
                                  ((activeWarpId == WARPS_PER_CORE - 1) ? {WARP_ID_W{1'b0}} : (activeWarpId + 1'b1));
        end else begin : genNextWarpSingle
            assign nextWarpId = 1'b0;
        end
    endgenerate
    always @(posedge clk) begin
        if (reset) begin
            activeWarpId <= 0;
            startLatched <= 0;
            trackerEnqueueValid <= 0;
            trackerEnqueueDestReg <= 0;
            trackerEnqueueTag <= 0;
            for (int w = 0; w < WARPS_PER_CORE; w = w + 1) begin
                warpPc[w] <= 0;
                warpState[w] <= IDLE;
                warpDoneFlag[w] <= 0;
                justDecoded[w] <= 0;
                simtStackPtr[w] <= 0;
                pendingMemCount[w] <= 0;
                lqHead[w] <= 0;
                lqTail[w] <= 0;
                for (int q = 0; q < LOAD_QUEUE_DEPTH; q = q + 1) begin
                    loadQueue[w][q] <= 23'b0;
                end
                warpActiveMask[w] <= {THREADS_PER_WARP{1'b1}};
                for (int s = 0; s < 4; s = s + 1) begin
                    simtStackPc[w][s] <= 8'h00;
                    simtStackMask[w][s] <= {THREADS_PER_WARP{1'b0}};
                end
            end
            barrierMask <= {WARPS_PER_CORE{1'b0}};
        end else if (kernelRunning) begin
            trackerEnqueueValid <= 1'b0;
            if (start) startLatched <= 1;
            case (warpState[activeWarpId])
                IDLE: begin
                    if (start || startLatched) begin
                        if (!warpDoneFlag[activeWarpId])
                            warpState[activeWarpId] <= FETCH;
                    end
                end
                FETCH: begin
                    if (fetcherState == 3'b010) begin
                        warpState[activeWarpId] <= DECODE;
                    end
                end
                DECODE: begin
                    warpState[activeWarpId] <= ISSUE;
                    justDecoded[activeWarpId] <= 1;
                end
                ISSUE: begin
                    if (sbHazard) begin
                        warpState[activeWarpId] <= WAIT_REG;
                    end else if (pktMemRead && memQueueFull) begin
                        warpState[activeWarpId] <= WAIT_MEM_Q;
                    end else begin
                        if (pktTensor) begin
                            warpState[activeWarpId] <= tensorBusy;
                        end else if (workingPacket[50]) begin
                            warpState[activeWarpId] <= STATE_WAIT_FENCE;
                        end else if (workingPacket[48]) begin
                             warpState[activeWarpId] <= STATE_WAIT_BAR;
                        end else if (pktMem) begin
                            if (pktMemRead && pktRegWe) begin
                                pendingMemCount[activeWarpId] <= pendingMemCount[activeWarpId] + 1;
                                trackerEnqueueValid <= 1'b1;
                                trackerEnqueueDestReg <= pktRd;
                                trackerEnqueueTag <= 16'h0001;
                            end
                            warpState[activeWarpId] <= STALLED_MEM;
                        end else begin
                            warpState[activeWarpId] <= EXECUTE;
                            trackerEnqueueValid <= 1'b0;
                        end
                        justDecoded[activeWarpId] <= 0;
                    end
                end
                STALLED_MEM: begin
                    logic allDone;
                    int startIdx;
                    int endIdx;
                    allDone = 1'b1;
                    startIdx = activeWarpId * THREADS_PER_WARP;
                    endIdx = startIdx + THREADS_PER_WARP;
                    for (int i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin
                        if (i >= startIdx && i < endIdx) begin
                            int laneId;
                            laneId = i - startIdx;
                            if (warpActiveMask[activeWarpId][laneId] && lsuState[i] != 2'b11) begin
                                allDone = 1'b0;
                            end
                        end
                    end
                    if (allDone || warpEarlyWakeup[activeWarpId]) begin
                        if (pktMemRead && pktRegWe) begin
                            if (pendingMemCount[activeWarpId] > 0) begin
                                pendingMemCount[activeWarpId] <= pendingMemCount[activeWarpId] - 1;
                            end
                        end
                        warpState[activeWarpId] <= UPDATE;
                    end else begin
                        activeWarpId <= nextWarpId;
                    end
                end
                tensorBusy: begin
                    if (tensorDone[activeWarpId]) begin
                        warpState[activeWarpId] <= EXECUTE;
                    end else begin
                        activeWarpId <= nextWarpId;
                    end
                end
                WAIT_REG: begin
                    if (!sbHazard) begin
                        warpState[activeWarpId] <= ISSUE;
                    end else begin
                        activeWarpId <= nextWarpId;
                    end
                end
                WAIT_MEM_Q: begin
                    if (!memQueueFull) begin
                        warpState[activeWarpId] <= ISSUE;
                    end else begin
                        activeWarpId <= nextWarpId;
                    end
                end
                EXECUTE: begin
                    warpState[activeWarpId] <= UPDATE;
                end
                UPDATE: begin
                    if (pktRet) begin
                         warpDoneFlag[activeWarpId] <= 1;
                         warpState[activeWarpId] <= DONE;
                         activeWarpId <= nextWarpId;
                    end else begin
                        logic [PROGRAM_MEM_ADDR_BITS-1:0] leaderNextPc;
                        logic foundLeader;
                        logic diverges;
                        logic [THREADS_PER_WARP-1:0] takenMask;
                        logic [THREADS_PER_WARP-1:0] fallthroughMask;
                        logic [PROGRAM_MEM_ADDR_BITS-1:0] fallthroughPc;

                        if (workingPacket[49]) begin
                            if (simtStackPtr[activeWarpId] > 0) begin
                                logic [2:0] ptrMinus1;
                                ptrMinus1 = simtStackPtr[activeWarpId] - 1;
                                simtStackPtr[activeWarpId] <= ptrMinus1;
                                warpPc[activeWarpId] <= simtStackPc[activeWarpId][ptrMinus1];
                                warpActiveMask[activeWarpId] <= simtStackMask[activeWarpId][ptrMinus1];
                            end else begin
                                warpPc[activeWarpId] <= warpPc[activeWarpId] + 1;
                            end
                            if (powerSleepReq) warpState[activeWarpId] <= SLEEP;
                            else warpState[activeWarpId] <= FETCH;
                        end else begin
                            leaderNextPc = warpPc[activeWarpId] + 1;
                            foundLeader = 0;
                            diverges = 0;
                            takenMask = 0;
                            fallthroughMask = 0;
                            fallthroughPc = warpPc[activeWarpId] + 1;

                            for (int laneId = 0; laneId < THREADS_PER_WARP; laneId = laneId + 1) begin
                                if (warpActiveMask[activeWarpId][laneId]) begin
                                    int tIdx;
                                    tIdx = (activeWarpId * THREADS_PER_WARP) + laneId;
                                    if (!foundLeader) begin
                                        leaderNextPc = nextPc[tIdx];
                                        foundLeader = 1;
                                        takenMask[laneId] = 1'b1;
                                    end else begin
                                        if (nextPc[tIdx] == leaderNextPc) begin
                                            takenMask[laneId] = 1'b1;
                                        end else begin
                                            diverges = 1;
                                            fallthroughMask[laneId] = 1'b1;
                                        end
                                    end
                                end
                            end



                            if (diverges) begin
                                simtStackPc[activeWarpId][simtStackPtr[activeWarpId]] <= fallthroughPc;
                                simtStackMask[activeWarpId][simtStackPtr[activeWarpId]] <= fallthroughMask;
                                simtStackPtr[activeWarpId] <= simtStackPtr[activeWarpId] + 1;
                            end

                            warpPc[activeWarpId] <= leaderNextPc;
                            warpActiveMask[activeWarpId] <= takenMask;

                            if (powerSleepReq) begin
                                warpState[activeWarpId] <= SLEEP;
                            end else begin
                                warpState[activeWarpId] <= FETCH;
                            end
                        end
                    end
                end
                SLEEP: begin
                    if (!powerSleepReq) begin
                        warpState[activeWarpId] <= FETCH;
                    end else begin
                         activeWarpId <= nextWarpId;
                    end
                end
                DONE: begin
                     activeWarpId <= nextWarpId;
                end
                STATE_WAIT_BAR: begin
                    reg [WARPS_PER_CORE-1:0] currentActiveWarps;
                    reg [WARPS_PER_CORE-1:0] barrierAfterThis;
                    barrierMask[activeWarpId] <= 1'b1;
                    for (int i=0; i<WARPS_PER_CORE; i++) begin
                         currentActiveWarps[i] = !warpDoneFlag[i];
                    end
                    barrierAfterThis = barrierMask | (1 << activeWarpId);
                    if (barrierAfterThis == currentActiveWarps) begin
                         barrierMask <= 0;
                         for (int i=0; i<WARPS_PER_CORE; i++) begin
                             if (warpState[i] == STATE_WAIT_BAR || i == activeWarpId) begin
                                  warpState[i] <= UPDATE;
                             end
                         end
                    end else begin
                         if (WARPS_PER_CORE > 1) begin
                             activeWarpId <= (activeWarpId == WARPS_PER_CORE - 1) ? {WARP_ID_W{1'b0}} : (activeWarpId + 1'b1);
                         end else begin
                             activeWarpId <= 1'b0;
                         end
                    end
                end
                STATE_WAIT_FENCE: begin
                    if (storeBufferEmpty && nocCreditsFull) begin
                        warpState[activeWarpId] <= UPDATE;
                    end else begin
                        if (WARPS_PER_CORE > 1) begin
                            activeWarpId <= (activeWarpId == WARPS_PER_CORE - 1) ? {WARP_ID_W{1'b0}} : (activeWarpId + 1'b1);
                        end else begin
                            activeWarpId <= 1'b0;
                        end
                    end
                end
                default: warpState[activeWarpId] <= IDLE;
            endcase
        end
    end
    // barrierMask declared above (before first use)
    wire [WARPS_PER_CORE-1:0] stWarpActive;
    wire [WARPS_PER_CORE-1:0] stWarpWaitingMem;
    wire [WARPS_PER_CORE-1:0] stWarpWaitingShared;
    wire [WARPS_PER_CORE-1:0] stWarpWaitingTensor;
    wire [WARPS_PER_CORE-1:0] stWarpWaitingDep;
    generate
        for (genvar sw = 0; sw < WARPS_PER_CORE; sw = sw + 1) begin : stallDecode
            assign stWarpActive[sw]         = !warpDoneFlag[sw] && (warpState[sw] != IDLE);
            assign stWarpWaitingMem[sw]    = (warpState[sw] == STALLED_MEM) || (warpState[sw] == WAIT_MEM_Q);
            assign stWarpWaitingShared[sw] = 1'b0;
            assign stWarpWaitingTensor[sw] = (warpState[sw] == tensorBusy);
            assign stWarpWaitingDep[sw]    = (warpState[sw] == WAIT_REG);
        end
    endgenerate
    wire issueEvent = (warpState[activeWarpId] == ISSUE);
    stallTracker #(
        .NUM_WARPS(WARPS_PER_CORE),
        .WARP_ID_WIDTH(WARP_ID_W)
    ) efficiencyTracker (
        .clk(clk),
        .reset(reset),
        .warpActive(stWarpActive),
        .warpWaitingMem(stWarpWaitingMem),
        .warpWaitingShared(stWarpWaitingShared),
        .warpWaitingTensor(stWarpWaitingTensor),
        .warpWaitingDep(stWarpWaitingDep),
        .issueValid(issueEvent),
        .issuedWarpId(activeWarpId),
        .stallReason(),
        .warpAge(),
        .oldestReadyWarp(gtoOldestWarp),
        .oldestReadyValid(gtoOldestValid),
        .perfStallCyclesMem(),
        .perfStallCyclesShared(),
        .perfStallCyclesTensor(),
        .perfStallCyclesDep()
    );
    // synthesis translateOff
    // Debug prints disabled to prevent log flooding
    // synthesis translateOn
endmodule
