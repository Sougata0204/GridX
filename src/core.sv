// SIMT Execution Core
// This is the main SIMT compute core combining fetcher, decoder, ALU, registers, and LSU.
// I integrated the 4-thread execution pipeline and handled core-level reset signals
// so internal registers and state machines clear safely after a thread block completes.

`default_nettype none
`timescale 1ns/1ns
import gridxPkg::*;

module core #(
    parameter DATA_MEM_ADDR_BITS = 8,
    parameter DATA_MEM_DATA_BITS = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter THREADS_PER_BLOCK = 4,
    parameter WARPS_PER_CORE = 1,
    parameter REG_WIDTH = 16
) (
    input wire clk,
    input wire reset,
    input wire start,
    input wire kernelRunning,
    output wire done,
    input wire [7:0] blockId,
    input wire [$clog2(THREADS_PER_BLOCK):0] threadCount,
    output wire programMemReadValid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] programMemReadAddress,
    input wire programMemReadReady,
    input wire [PROGRAM_MEM_DATA_BITS-1:0] programMemReadData,
    output wire memReadValid,
    output wire [DATA_MEM_ADDR_BITS-1:0] memReadAddress,
    input wire memReadReady,
    input wire [DATA_MEM_DATA_BITS-1:0] memReadData,
    output wire memWriteValid,
    output wire [DATA_MEM_ADDR_BITS-1:0] memWriteAddress,
    output wire [DATA_MEM_DATA_BITS-1:0] memWriteData,
    input wire memWriteReady,
    input wire nocCreditsFull,
    input wire powerSleepReq,
    output wire instrRetired,
    output wire perfSharedMemAccess,
    output wire perfSharedMemConflict,
    output wire perfExternalMemAccess,
    output wire perfAluActive,
    output wire perfAluIdle,
    output wire perfTensorActive,
    output wire perfTensorIdle,
    output wire perfStallMem,
    output wire perfStallShared,
    output wire perfStallTensor,
    output wire perfStallDep,
    output wire perfStallReady,
    output wire perfStoreCombined,
    output wire perfEarlyWakeup,
    output wire perfDualIssueAttempt,
    output wire perfDualIssueSuccess,
    
    // Face Controller Interfaces (0:+X, 1:-X, 2:+Y, 3:-Y, 4:+Z, 5:-Z)
    output wire [5:0] faceReqValid,
    output wire [5:0] faceReqWrite,
    output wire [5:0][DATA_MEM_ADDR_BITS-1:0] faceReqAddr,
    output wire [5:0][DATA_MEM_DATA_BITS-1:0] faceReqWdata,
    input  wire [5:0] faceReqReady,
    input  wire [5:0] faceRespValid,
    input  wire [5:0][DATA_MEM_DATA_BITS-1:0] faceRespRdata,
    output wire [5:0] faceRespReady
);
    localparam THREADS_PER_WARP = THREADS_PER_BLOCK / WARPS_PER_CORE;
    localparam NUM_LANES = THREADS_PER_WARP;
    localparam WARP_ID_W = (WARPS_PER_CORE > 1) ? $clog2(WARPS_PER_CORE) : 1;

    wire [3:0] activeCoreState;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] currentPc;

    assign instrRetired = (activeCoreState == STATE_UPDATE);
    wire [3:0] warpStates [WARPS_PER_CORE-1:0];
    wire [WARP_ID_W-1:0] activeWarpId;
    wire [REG_WIDTH-1:0] rs [THREADS_PER_BLOCK-1:0];
    wire [REG_WIDTH-1:0] rt [THREADS_PER_BLOCK-1:0];
    wire [REG_WIDTH-1:0] rdVal [THREADS_PER_BLOCK-1:0];
    wire [1:0] lsuState [THREADS_PER_BLOCK-1:0];
    wire [REG_WIDTH-1:0] lsuOut [THREADS_PER_BLOCK-1:0];
    wire [WARPS_PER_CORE-1:0] tensorBusy;
    wire [WARPS_PER_CORE-1:0] tensorDone;
    wire [15:0] instruction;
    wire [2:0] fetcherState;
    wire [63:0] decodedPacket;
    wire [WARPS_PER_CORE-1:0] warpIssueEnable;
    reg [63:0] warpInstrLatch [WARPS_PER_CORE-1:0];
    wire sbHazard;
    wire [1:0] sbHazardType;
    wire sbQueryValid;
    wire [$clog2(WARPS_PER_CORE > 1 ? WARPS_PER_CORE : 2)-1:0] sbQueryWarp;
    wire [3:0] sbQueryRs, sbQueryRt, sbQueryRd;
    wire computeIssue, memoryIssue;
    wire perfAluActivePulse;
    wire perfAluIdlePulse;
    wire perfTensorActivePulse;
    wire perfTensorIdlePulse;
    wire coreHangDetected;
    wire perfStallMemPulse;
    wire perfStallSharedPulse;
    wire perfStallTensorPulse;
    wire perfStallDepPulse;
    wire perfStallReadyPulse;
    wire combinedWriteValid;
    wire [DATA_MEM_ADDR_BITS-1:0] combinedWriteAddr;
    wire [DATA_MEM_DATA_BITS-1:0] combinedWriteData;
    wire combinedWriteReady;
    wire combinerEmpty;
    // all stores flushed = combiner drained AND no per-thread store buffers pending
    wire allWritesDrained;
    wire storeBufferEmpty = combinerEmpty && allWritesDrained;
    wire [15:0] issueActiveMask;
    reg [15:0] warpMaskLatch [WARPS_PER_CORE-1:0];
    wire rbRespReady;
    wire rbOutValid;
    wire [DATA_MEM_ADDR_BITS-1:0] rbOutAddr;
    wire [DATA_MEM_DATA_BITS-1:0] rbOutData;
    wire [WARPS_PER_CORE-1:0] rbWarpCanResume;
    fetcher #(
        .ProgMemAddrBits(PROGRAM_MEM_ADDR_BITS),
        .ProgMemDataBits(PROGRAM_MEM_DATA_BITS)
    ) fetcherInstance (
        .clk(clk),
        .reset(reset),
        .coreState(activeCoreState[2:0]),
        .currentPc(currentPc),
        .memReadValid(programMemReadValid),
        .memReadAddress(programMemReadAddress),
        .memReadReady(programMemReadReady),
        .memReadData(programMemReadData),
        .fetcherState(fetcherState),
        .instruction(instruction)
    );
    decoder decoderInstance (
        .coreState(activeCoreState[2:0]),
        .instruction(instruction),
        .decodedPacket(decodedPacket)
    );
    wire [PROGRAM_MEM_ADDR_BITS-1:0] nextPc [THREADS_PER_BLOCK-1:0];
    wire trackerEnqueueValid;
    wire [15:0] warpRsVal = rs[activeWarpId * THREADS_PER_WARP];
    wire actualTrackerEnqueueValid = trackerEnqueueValid && (warpRsVal >= 16'h2000);
    wire [3:0] trackerEnqueueDestReg;
    wire [15:0] trackerEnqueueTag;
    wire trackerDequeueValid = rbOutValid;
    wire [3:0] trackerDequeuedDestReg;
    wire trackerDequeueFound;
    wire [WARPS_PER_CORE-1:0] trackerWarpHasPending;
    wire [WARPS_PER_CORE-1:0] trackerWarpQueueFull;
    wire perfDualIssueAttemptPulse;
    wire perfDualIssueSuccessPulse;
    wire [63:0] dualComputePacket, dualMemoryPacket;
    wire dualComputeValid, dualMemoryValid;
    dualIssue #(
        .WARP_ID_WIDTH(WARP_ID_W),
        .INSTR_WIDTH(16)
    ) issueEngine (
        .clk(clk),
        .reset(reset),
        .computeQueueValid(activeCoreState == STATE_ISSUE && !decodedPacket[32] && !decodedPacket[33]),
        .computeQueueInstr(instruction),
        .computeQueueWarp(activeWarpId),
        .memoryQueueValid(activeCoreState == STATE_ISSUE && (decodedPacket[32] || decodedPacket[33])),
        .memoryQueueInstr(instruction),
        .memoryQueueWarp(activeWarpId),
        .sbQueryValid(sbQueryValid),
        .sbQueryWarp(sbQueryWarp),
        .sbQueryRs(sbQueryRs),
        .sbQueryRt(sbQueryRt),
        .sbQueryRd(sbQueryRd),
        .sbHazard(sbHazard),
        .computeDispatchReady(1'b1),
        .memoryDispatchReady(1'b1),
        .computeUnitBusy(1'b0),
        .memoryUnitBusy(1'b0),
        .perfDualIssueCycles(perfDualIssueSuccessPulse),
        .perfSingleComputeCycles(),
        .perfSingleMemoryCycles(),
        .perfNoIssueCycles()
    );
    scoreboard #(
        .NUM_WARPS(WARPS_PER_CORE),
        .NUM_REGS(16)
    ) coreScoreboard (
        .clk(clk),
        .reset(reset),
        .queryValid(activeCoreState == STATE_DECODE || activeCoreState == STATE_ISSUE || activeCoreState == STATE_WAIT_REG),
        .queryWarpId(activeWarpId),
        .queryRs(decodedPacket[23:20]),
        .queryRt(decodedPacket[19:16]),
        .queryRd(decodedPacket[27:24]),
        .queryHazard(sbHazard),
        .queryHazardType(sbHazardType),
        .writePendingSet(activeCoreState == STATE_ISSUE && decodedPacket[31] && !decodedPacket[32] && !decodedPacket[43]),
        .writePendingWarp(activeWarpId),
        .writePendingReg(decodedPacket[27:24]),
        .writeComplete(activeCoreState == STATE_UPDATE && warpInstrLatch[activeWarpId][31]),
        .writeCompleteWarp(activeWarpId),
        .writeCompleteReg(warpInstrLatch[activeWarpId][27:24]),
        .memLoadStart(activeCoreState == STATE_ISSUE && decodedPacket[32] && (warpRsVal >= 16'h2000)),
        .memLoadWarp(activeWarpId),
        .memLoadDestReg(decodedPacket[27:24]),
        .memLoadComplete(trackerDequeueFound),
        .memLoadCompleteWarp(activeWarpId),
        .memLoadCompleteReg(trackerDequeuedDestReg),
        .tensorOpStart(activeCoreState == STATE_ISSUE && decodedPacket[43]),
        .tensorOpWarp(activeWarpId),
        .tensorOpComplete(|tensorDone),
        .tensorOpCompleteWarp(activeWarpId),
        .perfFalseStallsAvoided(),
        .perfTrueDependencyStalls()
    );
    asyncLoadTracker #(
        .WARPS_PER_CORE(WARPS_PER_CORE),
        .MAX_OUTSTANDING_PER_WARP(4),
        .REG_ADDR_BITS(4)
    ) loadTracker (
        .clk(clk),
        .reset(reset),
        .enqueueValid(actualTrackerEnqueueValid),
        .enqueueWarpId(activeWarpId),
        .enqueueDestReg(trackerEnqueueDestReg),
        .enqueueTag(trackerEnqueueTag),
        .dequeueValid(trackerDequeueValid),
        .dequeueWarpId(activeWarpId),
        .dequeueTag(16'h0001),
        .dequeuedDestReg(trackerDequeuedDestReg),
        .dequeueFound(trackerDequeueFound),
        .warpHasPending(trackerWarpHasPending),
        .warpQueueFull(trackerWarpQueueFull),
        .pendingCount()
    );
    scheduler #(
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .WARPS_PER_CORE(WARPS_PER_CORE),
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS)
    ) schedulerInstance (
        .clk(clk),
        .reset(reset),
        .start(start),
        .kernelRunning(kernelRunning),
        .tensorDone(tensorDone),
        .powerSleepReq(powerSleepReq),
        .decodedPacket(decodedPacket),
        .latchedPacket(warpInstrLatch[activeWarpId]),
        .fetcherState(fetcherState),
        .lsuState(lsuState),
        .currentPc(currentPc),
        .nextPc(nextPc),
        .coreState(activeCoreState),
        .warpState(warpStates),
        .activeWarpId(activeWarpId),
        .warpIssueEnable(warpIssueEnable),
        .trackerEnqueueValid(trackerEnqueueValid),
        .trackerEnqueueDestReg(trackerEnqueueDestReg),
        .trackerEnqueueTag(trackerEnqueueTag),
        .trackerDequeueValid(trackerDequeueFound),
        .trackerDequeuedDestReg(trackerDequeuedDestReg),
        .nocCreditsFull(nocCreditsFull),
        .storeBufferEmpty(storeBufferEmpty),
        .trackerDequeueFound(trackerDequeueFound),
        .trackerWarpHasPending(trackerWarpHasPending),
        .trackerWarpQueueFull(trackerWarpQueueFull),
        .sbHazard(sbHazard),
        .sbHazardType(sbHazardType),
        .perfStallMemPulse(perfStallMemPulse),
        .perfStallSharedPulse(perfStallSharedPulse),
        .perfStallTensorPulse(perfStallTensorPulse),
        .perfStallDepPulse(perfStallDepPulse),
        .perfStallReadyPulse(perfStallReadyPulse),
        .warpEarlyWakeup(rbWarpCanResume),
        .activeMask(issueActiveMask),
        .done(done)
    );
    integer w;
    always @(posedge clk) begin
        if (reset) begin
            for (w=0; w<WARPS_PER_CORE; w=w+1) warpInstrLatch[w] <= 0;
        end else begin
            for (w=0; w<WARPS_PER_CORE; w=w+1) begin
                if (warpIssueEnable[w]) begin
                    warpInstrLatch[w] <= decodedPacket;
                    warpMaskLatch[w] <= issueActiveMask;
                end
            end
        end
    end
    wire [63:0] activeWarpInstr = warpInstrLatch[activeWarpId];
    wire [3:0] aluArithMux = activeWarpInstr[40:37];
    wire aluOutMux = activeWarpInstr[39];
    genvar lane;
    wire [REG_WIDTH-1:0] laneAluOut [NUM_LANES-1:0];
    generate
        for (lane = 0; lane < NUM_LANES; lane = lane + 1) begin : lanes
            reg [REG_WIDTH-1:0] laneRs;
            reg [REG_WIDTH-1:0] laneRt;
            always @(*) begin
                laneRs = rs[activeWarpId * THREADS_PER_WARP + lane];
                laneRt = rt[activeWarpId * THREADS_PER_WARP + lane];
            end
            alu #(
                .DataBits(REG_WIDTH)
            ) aluUnit (
                .enable(activeCoreState == STATE_EXECUTE),
                .arithMux(aluArithMux),
                .rs(laneRs),
                .rt(laneRt),
                .aluOut(laneAluOut[lane]),
                .divByZero()
            );
        end
    endgenerate
    wire [THREADS_PER_BLOCK-1:0] respArbiterGrant;
    wire [THREADS_PER_BLOCK-1:0] lsuReqValid;
    wire [THREADS_PER_BLOCK-1:0] lsuPending;
    wire [THREADS_PER_BLOCK-1:0] lsuReqWrite;
    wire [DATA_MEM_ADDR_BITS-1:0] lsuReqAddr [THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] lsuReqData [THREADS_PER_BLOCK-1:0];
    wire [THREADS_PER_BLOCK-1:0] smemReqValid;
    wire [12:0] smemReqAddr [THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] smemReqWdata [THREADS_PER_BLOCK-1:0];
    wire [THREADS_PER_BLOCK-1:0] smemReqReady;
    wire [DATA_MEM_DATA_BITS-1:0] smemReqRdata [THREADS_PER_BLOCK-1:0];
    sharedMemory #(
        .DATA_BITS(DATA_MEM_DATA_BITS),
        .ADDR_BITS(13),
        .NUM_WARPS(WARPS_PER_CORE),
        .THREADS_PER_WARP(THREADS_PER_WARP)
    ) shMem (
        .clk(clk),
        .reset(reset),
        .reqValid(smemReqValid),
        .reqWrite(lsuReqWrite),
        .reqAddr(smemReqAddr),
        .reqWdata(lsuReqData),
        .reqReady(smemReqReady),
        .reqRdata(smemReqRdata),
        .sharedMemAccessPulse(perfSharedMemAccess),
        .sharedMemConflictPulse(perfSharedMemConflict)
    );
    assign perfExternalMemAccess = memReadValid || memWriteValid;
    wire [THREADS_PER_BLOCK-1:0] arbReqValid;
    wire [THREADS_PER_BLOCK-1:0] lsuActiveReq;
    wire [THREADS_PER_BLOCK-1:0] respArbReqValid;
    wire [THREADS_PER_BLOCK-1:0] reqArbiterGrant;
    wire [THREADS_PER_BLOCK-1:0] lsuWe;
    reg [THREADS_PER_BLOCK-1:0] lsuReqSent;

    genvar g;
    generate
        for (g = 0; g < THREADS_PER_BLOCK; g = g + 1) begin : arbFilter
            assign arbReqValid[g] = lsuReqValid[g] && (lsuReqAddr[g] >= 16'h2000);
            assign smemReqValid[g] = lsuReqValid[g] && (lsuReqAddr[g] < 16'h2000);
            assign smemReqAddr[g] = lsuReqAddr[g][12:0];
            assign lsuActiveReq[g] = lsuReqValid[g] && (lsuReqAddr[g] >= 16'h2000) && !lsuReqSent[g];
            assign respArbReqValid[g] = lsuPending[g] && (lsuReqAddr[g] >= 16'h2000);
        end
    endgenerate
    wire arbValid, arbWrite;
    wire [DATA_MEM_ADDR_BITS-1:0] arbAddr;
    wire [DATA_MEM_DATA_BITS-1:0] arbData;
    wire coalescedReqValid;
    wire [DATA_MEM_ADDR_BITS-1:0] coalescedReqAddr;
    wire [THREADS_PER_BLOCK-1:0] coalescerGrant;
    loadCoalescer #(
        .LANES(THREADS_PER_BLOCK),
        .ADDR_WIDTH(DATA_MEM_ADDR_BITS)
    ) coalescer (
        .clk(clk),
        .reset(reset),
        .laneValid(arbReqValid),
        .laneAddr(lsuReqAddr),
        .laneReadEnable(1'b0),
        .coalescedReqValid(coalescedReqValid),
        .coalescedReqAddr(coalescedReqAddr),
        .coalescedReqCount(),
        .coalescedLaneMask(),
        .coalescedReqReady(1'b1),
        .respValid(1'b0),
        .respData('0),
        .laneRespValid(),
        .laneRespData(),
        .perfCoalescedRequests(),
        .perfUncoalescedRequests(),
        .perfBytesSaved()
    );
    
    always @(posedge clk) begin
        if (reset) begin
            lsuReqSent <= 0;
        end else begin
            for (integer i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin
                if (!lsuReqValid[i]) begin
                    lsuReqSent[i] <= 1'b0;
                end else if (reqArbiterGrant[i] && lsuWe[i]) begin
                    // writes: clear immediately so store buffer can drain next entry
                    lsuReqSent[i] <= 1'b0;
                end else if (reqArbiterGrant[i]) begin
                    lsuReqSent[i] <= 1'b1;
                end
            end
        end
    end

    lsuArbiter #(
        .NUM_REQUESTERS(THREADS_PER_BLOCK),
        .ADDR_WIDTH(DATA_MEM_ADDR_BITS),
        .DATA_WIDTH(DATA_MEM_DATA_BITS)
    ) reqArbiter (
        .clk(clk),
        .reset(reset),
        .requestValid(lsuActiveReq),
        .requestWrite(lsuReqWrite),
        .requestAddr(lsuReqAddr),
        .requestData(lsuReqData),
        .memValid(arbValid),
        .memWrite(arbWrite),
        .memAddr(arbAddr),
        .memData(arbData),
        .memReady(1'b1),
        .grant(reqArbiterGrant)
    );
    
    lsuArbiter #(
        .NUM_REQUESTERS(THREADS_PER_BLOCK),
        .ADDR_WIDTH(DATA_MEM_ADDR_BITS),
        .DATA_WIDTH(DATA_MEM_DATA_BITS),
        .IS_RESP(1)
    ) respArbiter (
        .clk(clk),
        .reset(reset),
        .requestValid(respArbReqValid),
        .requestWrite(lsuReqWrite),
        .requestAddr(lsuReqAddr),
        .requestData(lsuReqData),
        .memValid(),
        .memWrite(),
        .memAddr(),
        .memData(),
        .memReady(rbOutValid || memWriteReady || l1ReadReady || l1WriteReady),
        .grant(respArbiterGrant)
    );
    wire l1Hit = (arbAddr >= 16'h2000 && arbAddr < 16'h8000);
    // Face hit: address bits [21:19] select face direction (1-6), 0 = normal BRAM path
    wire [2:0] arbFaceSel = arbAddr[21:19];
    wire faceHit = (arbFaceSel >= 3'd1) && (arbFaceSel <= 3'd6);
    wire l1ReadReady, l1WriteReady;
    wire [DATA_MEM_DATA_BITS-1:0] l1ReadData;
    coreLocalMemory #(
        .ADDR_WIDTH(15),
        .DATA_WIDTH(DATA_MEM_DATA_BITS)
    ) l1Memory (
        .clk(clk),
        .reset(reset),
        .readValid(arbValid && !arbWrite && l1Hit),
        .readAddress(arbAddr[14:0]),
        .writeValid(arbValid && arbWrite && l1Hit),
        .writeAddress(arbAddr[14:0]),
        .writeData(arbData),
        .readReady(l1ReadReady),
        .readData(l1ReadData),
        .writeReady(l1WriteReady)
    );
    assign memReadValid = arbValid && !arbWrite && !l1Hit && !faceHit;
    assign memReadAddress = arbAddr;
    storeCombiner #(
        .ADDR_WIDTH(DATA_MEM_ADDR_BITS),
        .DATA_WIDTH(DATA_MEM_DATA_BITS)
    ) externalStoreCombiner (
        .clk(clk),
        .reset(reset),
        .storeValid(arbValid && arbWrite && !l1Hit && !faceHit),
        .storeAddr(arbAddr),
        .storeData(arbData),
        .storeReady(),
        .combinedValid(memWriteValid),
        .combinedAddr(memWriteAddress),
        .combinedData(memWriteData),
        .combinedReady(memWriteReady),
        .storeWarpId(activeWarpId),
        .fenceInstruction(1'b0),
        .kernelEnd(done),
        .loadPending(1'b0),
        .combinedMask(),
        .combinedCount(),
        .perfStoresCombined(perfStoreCombinedPulse),
        .perfStoresReceived(),
        .perfFlushEvents(),
        .storeBufferEmpty(combinerEmpty)
    );
    responseBuffer #(
        .BUFFER_DEPTH(4),
        .NUM_WARPS(WARPS_PER_CORE)
    ) externalResponseBuffer (
        .clk(clk),
        .reset(reset),
        .respValid(memReadReady),
        .respAddr(memReadAddress),
        .respData(memReadData),
        .respWarpId(activeWarpId),
        .respReady(rbRespReady),
        .warpHasPendingLoad(trackerWarpHasPending),
        .warpPendingCount(),
        .outValid(rbOutValid),
        .outAddr(rbOutAddr),
        .outData(rbOutData),
        .outWarpId(),
        .outReady(1'b1),
        .warpCanResume(rbWarpCanResume),
        .perfEarlyWakeups(perfEarlyWakeupPulse),
        .perfTotalResponses(),
        .perfBufferFullStalls()
    );
    wire [DATA_MEM_DATA_BITS-1:0] memReadDataInternal;
    wire memReadReadyInternal;
    wire memWriteReadyInternal;
    assign memReadReadyInternal = l1Hit ? l1ReadReady : rbOutValid;
    assign memReadDataInternal = l1Hit ? l1ReadData : rbOutData;
    assign memWriteReadyInternal = l1Hit ? l1WriteReady : memWriteReady;
    wire signed [3:0][3:0][15:0] tensorSrcA;
    wire signed [3:0][3:0][15:0] tensorSrcB;
    wire [3:0][3:0][31:0] tensorWbData;
    wire tensorWbValid;
    wire [1:0] tensorWbWarp;
    wire [3:0] writebackRegIdx;
    genvar tr, tc;
    generate
        for (tr=0; tr<4; tr=tr+1) begin : rows
            for (tc=0; tc<4; tc=tc+1) begin : cols
                 localparam int TIDX = tr*4 + tc;
                 if (TIDX < THREADS_PER_WARP) begin : validLane
                     wire [7:0] rVal = rs[activeWarpId * THREADS_PER_WARP + TIDX][7:0];
                     wire [7:0] tVal = rt[activeWarpId * THREADS_PER_WARP + TIDX][7:0];
                     assign tensorSrcA[tr][tc] = {{8{rVal[7]}}, rVal};
                     assign tensorSrcB[tr][tc] = {{8{tVal[7]}}, tVal};
                 end else begin : zeroLane
                     assign tensorSrcA[tr][tc] = 16'd0;
                     assign tensorSrcB[tr][tc] = 16'd0;
                 end
            end
        end
    endgenerate
    
    tensorController #(
        .NUM_WARPS(WARPS_PER_CORE),
        .NUM_UNITS(4)
    ) tCtrl (
        .clk(clk),
        .reset(reset),
        .requestValid(activeCoreState == STATE_ISSUE && decodedPacket[43]),
        .warpId(activeWarpId),
        .destRegIdx(decodedPacket[27:24]),
        .srcA(tensorSrcA),
        .srcB(tensorSrcB),
        .srcC(512'd0),
        .imm(decodedPacket[15:0]),
        .requestReady(),
        .warpBusy(tensorBusy),
        .warpDone(tensorDone),
        .writebackValid(tensorWbValid),
        .writebackWarpId(tensorWbWarp),
        .writebackData(tensorWbData),
        .writebackRegIdx(writebackRegIdx)
    );
    computeUtilization utilizationTracker (
        .clk(clk),
        .reset(reset),
        .coreActive(kernelRunning),
        .aluEnable(activeCoreState == STATE_EXECUTE),
        .aluExecuting(activeCoreState == STATE_EXECUTE),
        .tensorBusy(|tensorBusy),
        .tensorExecuting(|tensorDone),
        .aluActivePulse(perfAluActivePulse),
        .aluIdlePulse(perfAluIdlePulse),
        .tensorActivePulse(perfTensorActivePulse),
        .tensorIdlePulse(perfTensorIdlePulse)
    );
    assign perfAluActive   = perfAluActivePulse;
    assign perfAluIdle     = perfAluIdlePulse;
    assign perfTensorActive = perfTensorActivePulse;
    assign perfTensorIdle   = perfTensorIdlePulse;
    assign perfStallMem    = perfStallMemPulse;
    assign perfStallShared = perfStallSharedPulse;
    assign perfStallTensor = perfStallTensorPulse;
    assign perfStallDep    = perfStallDepPulse;
    assign perfStallReady  = perfStallReadyPulse;
    wire perfStoreCombinedPulse;
    wire perfEarlyWakeupPulse;
    assign perfStoreCombined = perfStoreCombinedPulse;
    assign perfEarlyWakeup   = perfEarlyWakeupPulse;
    // Declared early so always_ff blocks below can use them
    assign perfDualIssueAttempt = (activeCoreState == STATE_ISSUE);
    assign perfDualIssueSuccess = perfDualIssueSuccessPulse;
    forwardProgress #(
        .WATCHDOG_CYCLES(32768)
    ) progressWatchdog (
        .clk(clk),
        .reset(reset),
        .warpActive(|warpIssueEnable),
        .warpMadeProgress(instrRetired),
        .assertWarpTimeout(coreHangDetected),
        .memReqIssued(1'b0),
        .memReqId('0),
        .memReqCompleted(1'b0),
        .memCompletedId('0),
        .timeoutDetected(),
        .timeoutWarpId(),
        .pendingMemRequests(),
        .dumpTrigger(),
        .stalledWarps(),
        .warpStallCycles(),
        .assertMemLeak()
    );
    genvar t;
    generate
        for (t = 0; t < THREADS_PER_BLOCK; t = t + 1) begin : threads
            localparam warpIdx = t / THREADS_PER_WARP;
            localparam laneIdx = t % THREADS_PER_WARP;
            wire useBypass = warpIssueEnable[warpIdx];
            wire [63:0] myInstr = useBypass ? decodedPacket : warpInstrLatch[warpIdx];
            wire [15:0] myMaskBits = useBypass ? issueActiveMask : warpMaskLatch[warpIdx];
            wire myThreadActive = myMaskBits[laneIdx];
            wire [15:0] myImm      = myInstr[15:0];
            wire [3:0]  myRtAddr  = myInstr[19:16];
            wire [3:0]  myRsAddr  = myInstr[23:20];
            wire [3:0]  myRdAddr  = myInstr[27:24];
            wire        myRegWe   = myInstr[31];
            wire        myMemRe   = myInstr[32];
            wire        myMemWe   = myInstr[33];
            assign lsuWe[t] = myMemWe && myThreadActive;
            wire [1:0]  myRegMux  = myInstr[36:35];
            wire [1:0] myRow = laneIdx / 4;
            wire [1:0] myCol = laneIdx % 4;
            wire myForceEn = tensorWbValid && (warpIdx == tensorWbWarp);
            wire [REG_WIDTH-1:0] myForceData = tensorWbData[myRow][myCol][REG_WIDTH-1:0];
            wire [2:0] mappedState =
                (warpStates[warpIdx] == STATE_EXECUTE)     ? 3'b100 :
                (warpStates[warpIdx] == STATE_UPDATE)      ? 3'b110 :
                (warpStates[warpIdx] == STATE_ISSUE)       ? 3'b011 :
                (warpStates[warpIdx] == STATE_STALLED_MEM) ? 3'b011 :
                3'b000;
            registers #(
                 .ThreadsPerBlock(THREADS_PER_BLOCK),
                 .ThreadId(t),
                 .DataBits(REG_WIDTH)
            ) regFile (
                .clk(clk),
                .reset(reset),
                .enable(1'b1),
                .blockId(blockId),
                .coreState(mappedState),
                .decodedRdAddress(myRdAddr),
                .decodedRsAddress(myRsAddr),
                .decodedRtAddress(myRtAddr),
                .decodedImmediate(myImm),
                .decodedRegWriteEnable(myRegWe && myThreadActive),
                .decodedRegInputMux(myRegMux),
                .forceRegWriteEnable(myForceEn),
                .forceRegWriteDest(writebackRegIdx),
                .forceRegWriteData(myForceData),
                .aluOut(laneAluOut[laneIdx]),
                .lsuOut(lsuOut[t]),
                .rs(rs[t]),
                .rt(rt[t]),
                .rdVal(rdVal[t])
            );
            wire [2:0]  myNzp       = myInstr[30:28];
            wire        myNzpWe    = myInstr[34];
            wire        myPcMux    = myInstr[41];
            pc #(
                .DataMemBits(DATA_MEM_DATA_BITS),
                .ProgMemBits(PROGRAM_MEM_ADDR_BITS)
            ) pcInst (
                .clk(clk),
                .reset(reset),
                .enable(t < threadCount),
                .coreState(mappedState),
                .decodedNzp(myNzp),
                .decodedImm(myImm[PROGRAM_MEM_ADDR_BITS-1:0]),
                .nzpWe(myNzpWe),
                .pcMux(myPcMux),
                .aluOut(laneAluOut[laneIdx]),
                .currentPc(currentPc),
                .nextPc(nextPc[t])
            );
            wire myGrant = respArbiterGrant[t];
            wire myReadReady = (myGrant && !lsuWe[t] && memReadReadyInternal);
            wire myWriteReady = (myGrant && lsuWe[t] && memWriteReadyInternal);
            wire myReadVal, myWriteVal;
            wire [DATA_MEM_ADDR_BITS-1:0] lsuReqRdAddr;
            wire [DATA_MEM_ADDR_BITS-1:0] lsuReqWrAddr;
            assign lsuReqAddr[t] = lsuReqWrite[t] ? lsuReqWrAddr : lsuReqRdAddr;
            assign lsuReqValid[t] = myReadVal || myWriteVal;
            assign lsuReqWrite[t] = myWriteVal;
            wire isSmem = (rs[t] < 16'h2000);
            wire isLocalAddr = (rs[t] < 16'h8000);
            wire thrReadReady  = isSmem ? smemReqReady[t]  : (myGrant && !lsuWe[t] && memReadReadyInternal);
            wire thrWriteReady = isSmem ? smemReqReady[t]  : reqArbiterGrant[t];
            wire [DATA_MEM_DATA_BITS-1:0] thrReadData = isSmem ? smemReqRdata[t] : memReadDataInternal;
            // synthesis translateOff
            reg [31:0] thrDebugCnt;
            always @(posedge clk) begin
                if (reset) thrDebugCnt <= 32'd0;
                else        thrDebugCnt <= thrDebugCnt + 32'd1;
                if (!reset && (thrDebugCnt < 350) && (t == 0)) begin
                    $display("[THREAD-0] Cycle %0d: thrReadReady=%b isSmem=%b lsuWe0=%b memReadReadyInternal=%b",
                             thrDebugCnt, thrReadReady, isSmem, lsuWe[t], memReadReadyInternal);
                end
            end
            // synthesis translateOn
            lsu #(
                .AddrBits(DATA_MEM_ADDR_BITS),
                .MemDataWidth(DATA_MEM_DATA_BITS),
                .RegWidth(REG_WIDTH)
            ) lsuInst (
                .clk(clk),
                .reset(reset),
                .enable(1'b1),
                .coreState(mappedState),
                .decodedMemReadEnable(myMemRe && myThreadActive),
                .decodedMemWriteEnable(myMemWe && myThreadActive),
                .isLocal(isLocalAddr),
                .memReadValid(myReadVal),
                .memReadAddress(lsuReqRdAddr),
                .memReadReady(thrReadReady),
                .memReadData(thrReadData),
                .memWriteValid(myWriteVal),
                .memWriteReady(thrWriteReady),
                .memWriteAddress(lsuReqWrAddr),
                .memWriteData(lsuReqData[t]),
                .rs(rs[t]),
                .rt(rt[t]),
                .lsuStateOut(lsuState[t]),
                .lsuOut(lsuOut[t]),
                .lsuPending(lsuPending[t])
            );
        end
    endgenerate
    // no thread has a pending store buffer entry
    assign allWritesDrained = ~|(lsuReqValid & lsuReqWrite);
`ifdef DEBUG
    reg [31:0] coreDebugCounter;
    always @(posedge clk) begin
        if (reset) coreDebugCounter <= 0;
        else coreDebugCounter <= coreDebugCounter + 1;
        if (!reset && (coreDebugCounter < 350)) begin
            if (activeCoreState == STATE_ISSUE) begin
                $display("[T_DEBUG] Cycle %d: PC=%x rs[0]=%h rt[0]=%h rd[0]=%h rsAddr=%d warpRsVal=%h enqueueValid=%b actualEnqueueValid=%b",
                         coreDebugCounter, currentPc, rs[0], rt[0], rdVal[0], decodedPacket[23:20], warpRsVal, trackerEnqueueValid, actualTrackerEnqueueValid);
            end
            $display("[CORE] Cycle %0d: ArbValid=%b LsuReqValid[0]=%b ArbAddr=%x L1Hit=%b MemReadValid=%b MemReadReady=%b LsuReqAddr0=%h LsuState0=%d lsuActiveReq0=%b lsuWe0=%b",
                     coreDebugCounter, arbValid, lsuReqValid[0], arbAddr, l1Hit, memReadValid, memReadReady, lsuReqAddr[0], lsuState[0], lsuActiveReq[0], lsuWe[0]);
            $display("[CORE] WarpState[0]=%d WarpIssueEn[0]=%b WarpLatch[0][32]=%b decodedPkt[32]=%b activeCoreSt=%d lsuState0=%d",
                     warpStates[0], warpIssueEnable[0], warpInstrLatch[0][32], decodedPacket[32], activeCoreState, lsuState[0]);
            if (actualTrackerEnqueueValid) begin
                $display("[CORE-LT] Cycle %d ENQUEUE: destReg=%d tag=%h",
                         coreDebugCounter, trackerEnqueueDestReg, trackerEnqueueTag);
            end
            if (trackerDequeueValid || trackerDequeueFound) begin
                $display("[CORE-LT] Cycle %d DEQUEUE: deqVal=%b deqFound=%b destReg=%d",
                         coreDebugCounter, trackerDequeueValid, trackerDequeueFound, trackerDequeuedDestReg);
            end
            if (memReadReady) begin
                $display("[CORE-MEM] Cycle %d memRdReady: data=%h", coreDebugCounter, memReadData);
            end
        end
    end
`endif
    // Volumetric Face Controllers & Routing
    // The core's external memory requests (which miss L1) are routed to the
    // appropriate 3D face based on the address map.
    // Address [21:19] selects the target:
    // 3'd0: Normal external BRAM path (memReadValid / memWriteValid)
    // 3'd1: +X face  (Face 0)
    // 3'd2: -X face  (Face 1)
    // 3'd3: +Y face  (Face 2)
    // 3'd4: -Y face  (Face 3)
    // 3'd5: +Z face  (Face 4)
    // 3'd6: -Z face  (Face 5)
    // 3'd7: Reserved

    wire faceArbValid = arbValid && !l1Hit && faceHit;
    wire faceArbWrite = arbWrite;
    wire [5:0] fcCoreReqValid;
    wire [5:0] fcCoreReqReady;
    wire [5:0] fcCoreRespValid;
    wire [5:0][DATA_MEM_DATA_BITS-1:0] fcCoreRespRdata;
    genvar f;
    generate
        for (f = 0; f < 6; f = f + 1) begin : genFaceControllers
            
            // Face f corresponds to arbFaceSel == (f+1)
            assign fcCoreReqValid[f] = faceArbValid && (arbFaceSel == (f + 1));
            
            faceController #(
                .ADDR_WIDTH(DATA_MEM_ADDR_BITS),
                .DATA_WIDTH(DATA_MEM_DATA_BITS),
                .BUFFER_DEPTH(4),
                .FACE_ID(f),
                .creditCount(4)
            ) faceCtrl (
                .clk(clk),
                .reset(reset),
                
                // Core-side - driven directly from arbiter, not from mem* ports
                .coreReqValid(fcCoreReqValid[f]),
                .coreReqWrite(faceArbWrite),
                .coreReqAddr(arbAddr),
                .coreReqWdata(arbData),
                .coreReqReady(fcCoreReqReady[f]),
                
                .coreRespValid(fcCoreRespValid[f]),
                .coreRespRdata(fcCoreRespRdata[f]),
                .coreRespReady(1'b1),
                
                // Sheet-side
                .sheetReqValid(faceReqValid[f]),
                .sheetReqWrite(faceReqWrite[f]),
                .sheetReqAddr(faceReqAddr[f]),
                .sheetReqWdata(faceReqWdata[f]),
                .sheetReqReady(faceReqReady[f]),
                
                .sheetRespValid(faceRespValid[f]),
                .sheetRespRdata(faceRespRdata[f]),
                .sheetRespReady(faceRespReady[f]),
                
                .creditsAvailable(),
                .fcBusy()
            );
        end
    endgenerate

endmodule
