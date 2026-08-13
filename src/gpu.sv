// GPU Core Array & Subsystem Top
// This module instantiates the core array, block dispatcher, and kernel state machine.
// I wired the core active gating and coreResetW signals to ensure cores get properly reset
// between recycled thread blocks without breaking execution flow.
`default_nettype none
`timescale 1ns/1ns

module gpu #(
    parameter DATA_MEM_ADDR_BITS = 22,
    parameter DATA_MEM_DATA_BITS = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 12,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter PROGRAM_MEM_NUM_CHANNELS = 8,
    parameter NUM_CORES = 8,
    parameter THREADS_PER_BLOCK = 4,
    parameter WARPS_PER_CORE = 1,
    parameter CUBE_X = 2,
    parameter CUBE_Y = 2,
    parameter CUBE_Z = 2
) (
    input wire clk,
    input wire reset,
    input wire start,
    output wire done,
    input wire deviceControlWriteEnable,
    input wire [15:0] deviceControlData,

    output wire [PROGRAM_MEM_NUM_CHANNELS-1:0] programMemReadValid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] programMemReadAddress [PROGRAM_MEM_NUM_CHANNELS-1:0],
    input wire [PROGRAM_MEM_NUM_CHANNELS-1:0] programMemReadReady,
    input wire [PROGRAM_MEM_DATA_BITS-1:0] programMemReadData [PROGRAM_MEM_NUM_CHANNELS-1:0],

    output wire [NUM_CORES-1:0] coreMemReadValid,
    output wire [DATA_MEM_ADDR_BITS-1:0] coreMemReadAddress [NUM_CORES-1:0],
    input  wire [NUM_CORES-1:0] coreMemReadReady,
    input  wire [DATA_MEM_DATA_BITS-1:0] coreMemReadData [NUM_CORES-1:0],

    output wire [NUM_CORES-1:0] coreMemWriteValid,
    output wire [DATA_MEM_ADDR_BITS-1:0] coreMemWriteAddress [NUM_CORES-1:0],
    output wire [DATA_MEM_DATA_BITS-1:0] coreMemWriteData [NUM_CORES-1:0],
    input  wire [NUM_CORES-1:0] coreMemWriteReady,
    input  wire [NUM_CORES-1:0] coreCreditsFull,
    output wire [2:0] kernelStateO,

    // Face Controller Interfaces per Core
    output wire [NUM_CORES-1:0][5:0] coreFaceReqValid,
    output wire [NUM_CORES-1:0][5:0] coreFaceReqWrite,
    output wire [NUM_CORES-1:0][5:0][DATA_MEM_ADDR_BITS-1:0] coreFaceReqAddr,
    output wire [NUM_CORES-1:0][5:0][DATA_MEM_DATA_BITS-1:0] coreFaceReqWdata,
    input  wire [NUM_CORES-1:0][5:0] coreFaceReqReady,

    input  wire [NUM_CORES-1:0][5:0] coreFaceRespValid,
    input  wire [NUM_CORES-1:0][5:0][DATA_MEM_DATA_BITS-1:0] coreFaceRespRdata,
    output wire [NUM_CORES-1:0][5:0] coreFaceRespReady
);

    wire [15:0] threadCount;
    wire dcrValid;
    wire [2:0] kernelState;
    wire kernelRunning;
    wire kernelDraining;
    wire kernelFault;
    wire kernelPreempting;
    wire allowDispatchGate;
    wire [15:0] blocksDispatched;
    wire [15:0] blocksDoneCount;
    wire [15:0] totalBlocks;
    wire allBlocksDispatched;
    wire allBlocksDone;
    wire [6:0] outstandingMem;
    wire [4:0] outstandingPmem;
    wire [3:0] tensorInflight = 4'b0000;  // No tensor pipeline tracking - default to idle (4-bit clean)
    wire instrRetired;
    wire memResponse;
    wire tensorComplete;
    wire [NUM_CORES-1:0] coreStart;
    wire [NUM_CORES-1:0] coreResetW;
    wire [NUM_CORES-1:0] coreDone;
    wire [7:0] coreBlockId [NUM_CORES-1:0];
    wire [$clog2(THREADS_PER_BLOCK):0] coreThreadCount [NUM_CORES-1:0];
    wire [NUM_CORES-1:0] coreInstrRetired;
    wire [NUM_CORES-1:0] corePerfSmemAccess;
    wire [NUM_CORES-1:0] corePerfSmemConflict;
    wire [NUM_CORES-1:0] corePerfExtAccess;
    wire [NUM_CORES-1:0] corePerfAluActive;
    wire [NUM_CORES-1:0] corePerfAluIdle;
    wire [NUM_CORES-1:0] corePerfTensorActive;
    wire [NUM_CORES-1:0] corePerfTensorIdle;
    wire [NUM_CORES-1:0] corePerfStallMem;
    wire [NUM_CORES-1:0] corePerfStallShared;
    wire [NUM_CORES-1:0] corePerfStallTensor;
    wire [NUM_CORES-1:0] corePerfStallDep;
    wire [NUM_CORES-1:0] corePerfStallReady;
    wire [NUM_CORES-1:0] corePerfStoreCombined;
    wire [NUM_CORES-1:0] corePerfEarlyWakeup;
    wire [NUM_CORES-1:0] corePerfDualIssueAttempt;
    wire [NUM_CORES-1:0] corePerfDualIssueSuccess;
    assign instrRetired = |coreInstrRetired;
    assign memResponse = |coreMemReadReady | |coreMemWriteReady;
    assign kernelStateO = kernelState;

    wire gc6ContextSaveReq;
    wire gc6ContextRestoreReq;
    wire gc6PowerGate;
    wire gc6ClockGate;
    wire [2:0] gc6State;
    wire gc6WatchdogFault;
    wire gc6Active;
    wire gc6PoweredOff;
    wire kernelContextSaveTrigger;

    wire faultInterrupt;
    wire faultKillKernel;
    wire chAllIdle;
    wire perfClockEnable;
    wire [1:0] perfLevel;

    localparam NUM_FETCHERS = NUM_CORES;
    wire [NUM_FETCHERS-1:0] fetcherReadValid;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] fetcherReadAddress [NUM_FETCHERS-1:0];
    wire [NUM_FETCHERS-1:0] fetcherReadReady;
    wire [PROGRAM_MEM_DATA_BITS-1:0] fetcherReadData [NUM_FETCHERS-1:0];

    dcr dcrInstance (
        .clk(clk),
        .reset(reset),
        .deviceControlWriteEnable(deviceControlWriteEnable),
        .deviceControlData(deviceControlData),
        .threadCount(threadCount),
        .dcrValid(dcrValid)
    );

    reg [6:0] outstandingMemReg;
    always @(posedge clk or posedge reset) begin
        if (reset) outstandingMemReg <= 7'd0;
        else begin
            outstandingMemReg <= outstandingMemReg
                + (|coreMemReadValid  ? 1'd1 : 1'd0)
                - (|coreMemReadReady  ? 1'd1 : 1'd0)
                + (|coreMemWriteValid ? 1'd1 : 1'd0)
                - (|coreMemWriteReady ? 1'd1 : 1'd0);
        end
    end
    assign outstandingMem = outstandingMemReg;

    controller #(
        .ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .NUM_CONSUMERS(NUM_FETCHERS),
        .NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS),
        .WRITE_ENABLE(0)
    ) programMemoryController (
        .clk(clk),
        .reset(reset),
        .consumerReadValid(fetcherReadValid),
        .consumerReadAddress(fetcherReadAddress),
        .consumerReadReady(fetcherReadReady),
        .consumerReadData(fetcherReadData),
        .memReadValid(programMemReadValid),
        .memReadAddress(programMemReadAddress),
        .memReadReady(programMemReadReady),
        .memReadData(programMemReadData),
        .pendingTransactions(outstandingPmem)
    );

    kernelFsm #(
        .NUM_CORES(NUM_CORES),
        .WARPS_PER_CORE(WARPS_PER_CORE),
        .WATCHDOG_THRESHOLD(200000),
        .MAX_DRAIN_CYCLES(4096)
    ) kernelControl (
        .clk(clk),
        .reset(reset),
        .start(start),
        .dcrValid(dcrValid),
        .threadCount(threadCount),
        .allBlocksDispatched(allBlocksDispatched),
        .allBlocksDone(allBlocksDone),
        .blocksDispatched(blocksDispatched),
        .totalBlocks(totalBlocks),
        .coreDone(coreDone),
        .outstandingMem(outstandingMem),
        .tensorInflight(tensorInflight),
        .instrRetired(instrRetired),
        .memResponse(memResponse),
        .tensorComplete(1'b0),
        .forcePreempt(1'b0),
        .gc6SleepReq(gc6ContextSaveReq),
        .contextSaveTrigger(kernelContextSaveTrigger),
        .faultKill(faultKillKernel),
        .dcrWatchdogThresh(32'd0),
        .kernelState(kernelState),
        .kernelDone(done),
        .kernelRunning(kernelRunning),
        .kernelDraining(kernelDraining),
        .kernelFault(kernelFault),
        .kernelPreempting(kernelPreempting),
        .allowDispatch(allowDispatchGate),
        .allowFetch(),
        .allowIssue(),
        .allowMemory(),
        .allowTensor(),
        .allowWriteback()
    );

    gc6PowerFsm #(
        .drainTimeout(2048),
        .WAKE_TIMEOUT(1024),
        .RESTORE_TIMEOUT(512)
    ) gc6Ctrl (
        .clk(clk),
        .rstN(!reset),
        .dcrEnterReqI(1'b0),
        .dcrExitReqI(1'b0),
        .dcrRetentionI(1'b1),
        .dcrWatchdogThreshI(32'd0),
        .allPipelinesEmptyI(1'b1),
        .outstandingMemI(outstandingMem),
        .tensorInflightI(tensorInflight),
        .contextSaveReqO(gc6ContextSaveReq),
        .contextSaveAckI(kernelContextSaveTrigger),
        .contextRestoreReqO(gc6ContextRestoreReq),
        .contextRestoreAckI(1'b0),
        .pllLockI(1'b1),
        .powerGateEnableO(gc6PowerGate),
        .clockGateEnableO(gc6ClockGate),
        .retentionEnableO(),
        .gc6StateO(gc6State),
        .gc6WatchdogFaultO(gc6WatchdogFault),
        .gc6ActiveO(gc6Active),
        .gc6PoweredOffO(gc6PoweredOff)
    );

    faultHandler #(
        .FIFO_DEPTH(16),
        .ADDR_WIDTH(32)
    ) faultCtrl (
        .clk(clk),
        .rstN(!reset),
        .faultValidI(1'b0),
        .faultAddrI(32'h0),
        .faultTypeI(2'h0),
        .faultWarpIdI(5'h0),
        .faultCoreIdI(4'h0),
        .faultThreadMaskI(6'h0),
        .dcrFaultModeI(2'h0),
        .dcrFaultClearI(1'b0),
        .faultInterruptO(faultInterrupt),
        .faultKillKernelO(faultKillKernel),
        .faultMaskThreadO(),
        .dcrFaultHeadO(),
        .dcrFaultHeadMetaO(),
        .dcrFaultDropCountO(),
        .dcrFaultFifoDepthO(),
        .fifoEmptyO(),
        .fifoFullO()
    );

    channelScheduler #(
        .NUM_CHANNELS(8)
    ) chSched (
        .clk(clk),
        .rstN(!reset),
        .chRunnableI(8'h01),
        .chPriorityI(16'h0),
        .chBlockDoneI(8'h0),
        .dcrTimesliceP0I(32'd256),
        .dcrTimesliceP1I(32'd512),
        .dcrTimesliceP2I(32'd1024),
        .dcrTimesliceP3I(32'd2048),
        .dcrAgingThreshI(32'd4096),
        .chRunningO(),
        .chStateO(),
        .chPreemptO(),
        .chAgedPromotionO(),
        .allChannelsIdleO(chAllIdle),
        .activeChannelO()
    );

    perfBoostController perfCtrl (
        .clk(clk),
        .rstN(!reset),
        .aluActivePulseI(|corePerfAluActive),
        .tensorActivePulseI(|corePerfTensorActive),
        .kernelActiveI(kernelRunning),
        .dcrForceLevelI(2'd0),
        .dcrForceEnI(1'b0),
        .dcrUpThreshI(8'd75),
        .dcrDownThreshI(8'd25),
        .dcrSampleWinI(32'd1024),
        .perfLevelO(perfLevel),
        .clockEnableO(perfClockEnable),
        .totalActiveCyclesO(),
        .totalSampleCyclesO()
    );

    dispatch #(
        .NUM_CORES(NUM_CORES),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK)
    ) dispatchInstance (
        .clk(clk),
        .reset(reset),
        .start(start),
        .kernelRunning(allowDispatchGate),
        .threadCount(threadCount),
        .coreDone(coreDone),
        .coreStart(coreStart),
        .coreReset(coreResetW),
        .coreBlockId(coreBlockId),
        .coreThreadCount(coreThreadCount),
        .blocksDispatchedOut(blocksDispatched),
        .blocksDoneOut(blocksDoneCount),
        .totalBlocksOut(totalBlocks),
        .allBlocksDispatched(allBlocksDispatched),
        .allBlocksDone      (allBlocksDone)
    );

    genvar i;
    generate
        for (i = 0; i < NUM_CORES; i = i + 1) begin : cores
            core #(
                .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
                .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
                .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
                .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
                .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
                .WARPS_PER_CORE(WARPS_PER_CORE)
            ) coreInstance (
                .clk(clk),
                .reset(coreResetW[i]),
                .start(coreStart[i]),
                .kernelRunning(kernelRunning),
                .done(coreDone[i]),
                .instrRetired(coreInstrRetired[i]),
                .blockId(coreBlockId[i]),
                .threadCount(coreThreadCount[i]),
                .programMemReadValid(fetcherReadValid[i]),
                .programMemReadAddress(fetcherReadAddress[i]),
                .programMemReadReady(fetcherReadReady[i]),
                .programMemReadData(fetcherReadData[i]),
                .memReadValid(coreMemReadValid[i]),
                .memReadAddress(coreMemReadAddress[i]),
                .memReadReady(coreMemReadReady[i]),
                .memReadData(coreMemReadData[i]),
                .memWriteValid(coreMemWriteValid[i]),
                .memWriteAddress(coreMemWriteAddress[i]),
                .memWriteData(coreMemWriteData[i]),
                .memWriteReady(coreMemWriteReady[i]),
                .nocCreditsFull(coreCreditsFull[i]),
                .perfSharedMemAccess(corePerfSmemAccess[i]),
                .perfSharedMemConflict(corePerfSmemConflict[i]),
                .perfExternalMemAccess(corePerfExtAccess[i]),
                .perfAluActive(corePerfAluActive[i]),
                .perfAluIdle(corePerfAluIdle[i]),
                .perfTensorActive(corePerfTensorActive[i]),
                .perfTensorIdle(corePerfTensorIdle[i]),
                .perfStallMem(corePerfStallMem[i]),
                .perfStallShared(corePerfStallShared[i]),
                .perfStallTensor(corePerfStallTensor[i]),
                .perfStallDep(corePerfStallDep[i]),
                .perfStallReady(corePerfStallReady[i]),
                .perfStoreCombined(corePerfStoreCombined[i]),
                .perfEarlyWakeup(corePerfEarlyWakeup[i]),
                .perfDualIssueAttempt(corePerfDualIssueAttempt[i]),
                .perfDualIssueSuccess(corePerfDualIssueSuccess[i]),
                
                // Face Controller Interfaces
                .faceReqValid(coreFaceReqValid[i]),
                .faceReqWrite(coreFaceReqWrite[i]),
                .faceReqAddr(coreFaceReqAddr[i]),
                .faceReqWdata(coreFaceReqWdata[i]),
                .faceReqReady(coreFaceReqReady[i]),
                .faceRespValid(coreFaceRespValid[i]),
                .faceRespRdata(coreFaceRespRdata[i]),
                .faceRespReady(coreFaceRespReady[i])
            );
        end
    endgenerate

    kernelPerfModel perfModel (
        .clk(clk),
        .reset(reset),
        .kernelActive(kernelRunning),
        .aluActivePulse(|corePerfAluActive),
        .aluIdlePulse(|corePerfAluIdle),
        .tensorActivePulse(|corePerfTensorActive),
        .tensorIdlePulse(|corePerfTensorIdle),
        .dualIssueAttemptPulse(|corePerfDualIssueAttempt),
        .dualIssueSuccessPulse(|corePerfDualIssueSuccess),
        .stallMemPulse(|corePerfStallMem),
        .stallSharedPulse(|corePerfStallShared),
        .stallTensorPulse(|corePerfStallTensor),
        .stallDepPulse(|corePerfStallDep),
        .stallReadyPulse(|corePerfStallReady),
        .storeCombinedPulse(|corePerfStoreCombined),
        .storeFlushPulse(1'b0),
        .earlyWakeupPulse(|corePerfEarlyWakeup)
    );

    performanceCounters #(
        .NUM_CORES(NUM_CORES),
        .WARPS_PER_CORE(WARPS_PER_CORE)
    ) globalPerf (
        .clk(clk),
        .reset(reset),
        .enable(1'b1),
        .clear(1'b0),
        .coreActive({NUM_CORES{kernelRunning}}),
        .coreStalled(corePerfStallMem | corePerfStallTensor),
        .instrIssued(coreInstrRetired),
        .instrRetired(coreInstrRetired),
        .l1ReadHit({NUM_CORES{1'b0}}),
        .l1WriteHit({NUM_CORES{1'b0}}),
        .l2ReadHit({NUM_CORES{1'b0}}),
        .l2WriteHit({NUM_CORES{1'b0}}),
        .sharedMemHit(corePerfSmemAccess),
        .sharedMemConflict(corePerfSmemConflict),
        .externalMemAccess(corePerfExtAccess),
        .l3Access({NUM_CORES{1'b0}}),
        .stallMem(corePerfStallMem),
        .stallTensor(corePerfStallTensor),
        .stallRegHazard(corePerfStallDep),
        .stallStructural({NUM_CORES{1'b0}}),
        .tensorOpStart(corePerfTensorActive),
        .tensorOpComplete(corePerfTensorIdle),
        .coreClockGated({NUM_CORES{1'b0}}),
        .corePowerGated({NUM_CORES{1'b0}})
    );
endmodule
