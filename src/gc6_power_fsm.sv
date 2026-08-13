
`default_nettype none
`timescale 1ns/1ns
import gridxPkg::*;

module gc6PowerFsm #(
    parameter drainTimeout   = 2048,
    parameter WAKE_TIMEOUT    = 1024,
    parameter RESTORE_TIMEOUT = 512
) (
    input  wire        clk,
    input  wire        rstN,

    input  wire        dcrEnterReqI,
    input  wire        dcrExitReqI,
    input  wire        dcrRetentionI,
    input  wire [31:0] dcrWatchdogThreshI,

    input  wire        allPipelinesEmptyI,
    input  wire [6:0]  outstandingMemI,
    input  wire [3:0]  tensorInflightI,

    output reg         contextSaveReqO,
    input  wire        contextSaveAckI,
    output reg         contextRestoreReqO,
    input  wire        contextRestoreAckI,

    input  wire        pllLockI,

    output reg         powerGateEnableO,
    output reg         clockGateEnableO,
    output reg         retentionEnableO,

    output reg  [2:0]  gc6StateO,
    output reg         gc6WatchdogFaultO,
    output wire        gc6ActiveO,
    output wire        gc6PoweredOffO
);
    reg [31:0] drainCounter;
    reg [31:0] wakeCounter;
    reg [31:0] restoreCounter;
    reg        enterReqLatch;
    reg        exitReqLatch;
    wire [31:0] effectiveWakeThresh = (dcrWatchdogThreshI != 0) ?
                                         dcrWatchdogThreshI :
                                         GC6_WAKE_WATCHDOG_DEF;
    assign gc6ActiveO      = (gc6StateO == gc6Active);
    assign gc6PoweredOffO = (gc6StateO == gc6PoweredOff);
    always @(posedge clk or negedge rstN) begin
        if (!rstN) begin
            gc6StateO          <= gc6Active;
            gc6WatchdogFaultO <= 1'b0;
            powerGateEnableO  <= 1'b0;
            clockGateEnableO  <= 1'b0;
            retentionEnableO   <= 1'b0;
            contextSaveReqO   <= 1'b0;
            contextRestoreReqO<= 1'b0;
            drainCounter        <= 0;
            wakeCounter         <= 0;
            restoreCounter      <= 0;
            enterReqLatch      <= 1'b0;
            exitReqLatch       <= 1'b0;
        end else begin

            if (dcrEnterReqI && gc6StateO == gc6Active)
                enterReqLatch <= 1'b1;
            if (dcrExitReqI && gc6StateO == gc6PoweredOff)
                exitReqLatch <= 1'b1;
            case (gc6StateO)
                gc6Active: begin
                    powerGateEnableO  <= 1'b0;
                    clockGateEnableO  <= 1'b0;
                    contextSaveReqO   <= 1'b0;
                    contextRestoreReqO<= 1'b0;
                    gc6WatchdogFaultO <= 1'b0;
                    if (enterReqLatch) begin
                        gc6StateO     <= GC6_PRE_SLEEP;
                        enterReqLatch <= 1'b0;
                        contextSaveReqO <= 1'b1;
                        retentionEnableO <= dcrRetentionI;
                    end
                end
                GC6_PRE_SLEEP: begin

                    if (contextSaveAckI) begin
                        contextSaveReqO <= 1'b0;
                        gc6StateO        <= GC6_DRAIN;
                        drainCounter      <= 0;
                    end
                end
                GC6_DRAIN: begin

                    drainCounter <= drainCounter + 1;
                    if (outstandingMemI == 0 && tensorInflightI == 0) begin
                        gc6StateO         <= gc6PoweredOff;
                        powerGateEnableO <= 1'b1;
                        clockGateEnableO <= 1'b1;
                    end else if (drainCounter >= drainTimeout) begin
                        gc6StateO          <= gc6PoweredOff;
                        powerGateEnableO  <= 1'b1;
                        clockGateEnableO  <= 1'b1;
                        gc6WatchdogFaultO <= 1'b1;
                    end
                end
                gc6PoweredOff: begin

                    powerGateEnableO <= 1'b1;
                    clockGateEnableO <= 1'b1;
                    if (exitReqLatch) begin
                        gc6StateO         <= GC6_WAKING;
                        exitReqLatch      <= 1'b0;
                        powerGateEnableO <= 1'b0;
                        wakeCounter        <= 0;
                    end
                end
                GC6_WAKING: begin

                    wakeCounter <= wakeCounter + 1;
                    if (pllLockI) begin
                        gc6StateO          <= GC6_RESTORING;
                        clockGateEnableO  <= 1'b0;
                        contextRestoreReqO<= 1'b1;
                        restoreCounter      <= 0;
                    end else if (wakeCounter >= effectiveWakeThresh) begin
                        gc6WatchdogFaultO <= 1'b1;
                    end
                end
                GC6_RESTORING: begin

                    restoreCounter <= restoreCounter + 1;
                    if (contextRestoreAckI) begin
                        contextRestoreReqO <= 1'b0;
                        gc6StateO           <= gc6Active;
                        retentionEnableO    <= 1'b0;
                    end else if (restoreCounter >= RESTORE_TIMEOUT) begin
                        gc6WatchdogFaultO <= 1'b1;
                    end
                end
                default: gc6StateO <= gc6Active;
            endcase
        end
    end
`ifdef VERILATOR
    always @(posedge clk) begin
        if (rstN && gc6WatchdogFaultO)
            $display("[GC6] WATCHDOG FAULT in state %d", gc6StateO);
    end
`endif
endmodule
