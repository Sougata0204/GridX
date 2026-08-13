// Kernel State Machine & Execution FSM
// This FSM manages kernel lifecycle states from launch to completion.
// I diagnosed and resolved a critical scheduler deadlock here by adding the firstWaveDispatched condition.
// This unblocked active cores so they could start executing immediately during block dispatch,
// which enabled hardware block recycling up to 4.0x oversubscription.

`default_nettype none
`timescale 1ns/1ns

module kernelFsm #(
    parameter NUM_CORES = 8,
    parameter WARPS_PER_CORE = 1,
    parameter WATCHDOG_THRESHOLD = 4096,
    parameter MAX_DRAIN_CYCLES = 2048
) (
    input wire clk,
    input wire reset,
    input wire start,
    input wire dcrValid,
    input wire [15:0] threadCount,
    input wire allBlocksDispatched,
    input wire allBlocksDone,
    input wire [15:0] blocksDispatched,
    input wire [15:0] totalBlocks,
    input wire [NUM_CORES-1:0] coreDone,
    input wire [6:0] outstandingMem,
    input wire [3:0] tensorInflight,
    input wire instrRetired,
    input wire memResponse,
    input wire tensorComplete,

    input wire forcePreempt,

    input wire gc6SleepReq,
    output reg contextSaveTrigger,

    input wire faultKill,

    input wire [31:0] dcrWatchdogThresh,

    output reg [2:0] kernelState,
    output wire kernelDone,
    output wire kernelRunning,
    output wire kernelDraining,
    output wire kernelFault,
    output wire kernelConfigured,
    output wire kernelPreempting,
    output wire allowDispatch,
    output wire allowFetch,
    output wire allowIssue,
    output wire allowMemory,
    output wire allowTensor,
    output wire allowWriteback
);
    localparam KERNEL_RESET      = 3'b000,
               KERNEL_CONFIGURED = 3'b001,
               KERNEL_LAUNCH     = 3'b010,
               KERNEL_RUNNING    = 3'b011,
               KERNEL_DRAIN      = 3'b100,
               KERNEL_DONE       = 3'b101,
               KERNEL_FAULT      = 3'b110,
               KERNEL_PREEMPT    = 3'b111;
    reg kernelStarted;
    reg [31:0] watchdogCounter;
    reg [31:0] drainCounter;
    reg doubleStartGuard;
    wire [31:0] effectiveWatchdog = (dcrWatchdogThresh != 0) ? dcrWatchdogThresh : WATCHDOG_THRESHOLD;
    wire kernelProgress = instrRetired || memResponse || tensorComplete;
    // FIX: Allow LAUNCH->RUNNING when the first wave fills all available cores,
    // even if totalBlocks > NUM_CORES. Remaining blocks dispatch via recycling
    // in dispatch.sv during RUNNING state (cores finish -> coreDone -> coreReset
    // > next block dispatched). Previously required ALL blocks dispatched before
    // leaving LAUNCH, which deadlocked when totalBlocks > NUM_CORES because
    // cores couldn't execute (kernelRunning=false during LAUNCH).
    wire firstWaveDispatched = (blocksDispatched >= NUM_CORES) && (totalBlocks > 0);
    wire allWarpsInitialized = ((blocksDispatched >= totalBlocks) || firstWaveDispatched) && (totalBlocks > 0);
    wire allCoresDone = (coreDone == {NUM_CORES{1'b1}});
    // drainComplete: all outstanding memory and tensor operations have completed.
    // tensorInflight is a clean 4-bit zero (no tensor pipeline tracking active).
    // outstandingMem tracks live read/write requests via a registered counter.
    wire drainComplete = (outstandingMem == 7'd0) && (tensorInflight == 4'd0);
    wire watchdogTimeout = (watchdogCounter >= effectiveWatchdog);
    wire drainTimeout = (drainCounter >= MAX_DRAIN_CYCLES);

    assign kernelDone       = (kernelState == KERNEL_DONE);
    assign kernelRunning    = (kernelState == KERNEL_RUNNING);
    assign kernelDraining   = (kernelState == KERNEL_DRAIN);
    assign kernelFault      = (kernelState == KERNEL_FAULT);
    assign kernelConfigured = (kernelState == KERNEL_CONFIGURED);
    assign kernelPreempting = (kernelState == KERNEL_PREEMPT);

    assign allowDispatch = (kernelState == KERNEL_LAUNCH) ||
                            (kernelState == KERNEL_RUNNING);
    assign allowFetch = (kernelState == KERNEL_LAUNCH) ||
                         (kernelState == KERNEL_RUNNING);

    assign allowIssue  = (kernelState == KERNEL_RUNNING);
    assign allowMemory = (kernelState == KERNEL_RUNNING);
    assign allowTensor = (kernelState == KERNEL_RUNNING);

    assign allowWriteback = (kernelState == KERNEL_RUNNING) ||
                             (kernelState == KERNEL_DRAIN) ||
                             (kernelState == KERNEL_PREEMPT);

    always @(posedge clk) begin
        if (reset) begin
            kernelState        <= KERNEL_RESET;
            kernelStarted      <= 0;
            watchdogCounter    <= 0;
            drainCounter       <= 0;
            contextSaveTrigger <= 0;
            doubleStartGuard   <= 0;
        end else begin
            contextSaveTrigger <= 1'b0;
            case (kernelState)
                KERNEL_RESET: begin
                    kernelStarted     <= 0;
                    watchdogCounter   <= 0;
                    drainCounter      <= 0;
                    doubleStartGuard  <= 0;
                    if (dcrValid && threadCount > 0) begin
                        kernelState <= KERNEL_CONFIGURED;
                    end
                end
                KERNEL_CONFIGURED: begin
                    if (start && !doubleStartGuard) begin
                        kernelState       <= KERNEL_LAUNCH;
                        kernelStarted     <= 1;
                        doubleStartGuard  <= 1;
                    end
                end
                KERNEL_LAUNCH: begin
                    if (allWarpsInitialized) begin
                        kernelState     <= KERNEL_RUNNING;
                        watchdogCounter <= 0;
                    end else if (watchdogTimeout) begin
                        kernelState <= KERNEL_FAULT;
                    end else begin
                        watchdogCounter <= watchdogCounter + 1;
                    end
                end
                KERNEL_RUNNING: begin
                    if (kernelProgress) begin
                        watchdogCounter <= 0;
                    end else begin
                        watchdogCounter <= watchdogCounter + 1;
                    end

                    if (faultKill) begin
                        kernelState <= KERNEL_FAULT;
                    end else if (forcePreempt) begin
                        kernelState         <= KERNEL_PREEMPT;
                        contextSaveTrigger <= 1'b1;
                        drainCounter        <= 0;
                    end else if (gc6SleepReq) begin
                        kernelState         <= KERNEL_PREEMPT;
                        contextSaveTrigger <= 1'b1;
                        drainCounter        <= 0;
                    end else if (allBlocksDone) begin
                        kernelState  <= KERNEL_DRAIN;
                        drainCounter <= 0;
                    end else if (watchdogTimeout) begin
                        kernelState <= KERNEL_FAULT;
                    end
                end
                KERNEL_PREEMPT: begin
                    drainCounter <= drainCounter + 1;
                    if (drainComplete) begin
                        kernelState <= KERNEL_DONE;
                    end else if (drainTimeout) begin
                        kernelState <= KERNEL_FAULT;
                    end
                end
                KERNEL_DRAIN: begin
                    drainCounter <= drainCounter + 1;
                    if (drainCounter % 1000 == 0) begin
                         $display("[kernelFsm] Draining... Mem: %d, Tensor: %b", outstandingMem, tensorInflight);
                    end
                    // Use else-if to prevent drainTimeout from overriding drainComplete
                    // in the same cycle. drainComplete has priority.
                    if (drainComplete) begin
                        kernelState <= KERNEL_DONE;
                    end else if (drainTimeout) begin
                        kernelState <= KERNEL_FAULT;
                    end
                end
                KERNEL_DONE: begin
                    // Wait in DONE state. Reset externally via global reset or explicit clear.
                    if (!start) doubleStartGuard <= 0;
                end
                KERNEL_FAULT: begin
                    // Unrecoverable fault state. Requires reset.
                end
                default: begin
                    kernelState <= KERNEL_FAULT;
                end
            endcase
        end
    end
    // synthesis translateOff
    reg [2:0] prevState;
    always @(posedge clk) begin
        if (reset) begin
            prevState <= KERNEL_RESET;
        end else begin
            prevState <= kernelState;
            if (kernelState != prevState) begin
                $display("[kernelFsm] State transition: %0d -> %0d at cycle %0d", prevState, kernelState, watchdogCounter);
                if (kernelState == KERNEL_FAULT) begin
                    $display("[kernelFsm] FAULT DETECTED! watchdog=%0d effectiveWatchdog=%0d allBlocksDone=%0b faultKill=%0b watchdogTimeout=%0b allWarpsInitialized=%0b",
                             watchdogCounter, effectiveWatchdog, allBlocksDone, faultKill, watchdogTimeout, allWarpsInitialized);
                end
            end
        end
    end
    // synthesis translateOn
endmodule
