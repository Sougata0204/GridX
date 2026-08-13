
`default_nettype none
`timescale 1ns/1ns
import gridxPkg::*;

module perfBoostController #(
    parameter DEFAULT_UP_THRESH   = 75,
    parameter DEFAULT_DOWN_THRESH = 25,
    parameter DEFAULT_SAMPLE_WIN  = 1024,
    parameter COUNTER_WIDTH       = 32
) (
    input  wire                    clk,
    input  wire                    rstN,

    input  wire                    aluActivePulseI,
    input  wire                    tensorActivePulseI,
    input  wire                    kernelActiveI,

    input  wire [1:0]             dcrForceLevelI,
    input  wire                   dcrForceEnI,
    input  wire [7:0]            dcrUpThreshI,
    input  wire [7:0]            dcrDownThreshI,
    input  wire [31:0]           dcrSampleWinI,

    output reg  [1:0]            perfLevelO,
    output reg                   clockEnableO,
    output reg  [COUNTER_WIDTH-1:0] totalActiveCyclesO,
    output reg  [COUNTER_WIDTH-1:0] totalSampleCyclesO
);
    reg [31:0] sampleCounter;
    reg [31:0] activeCounter;
    reg [1:0]  dutyPhase;
    wire [7:0] upThresh   = (dcrUpThreshI != 0) ? dcrUpThreshI : DEFAULT_UP_THRESH;
    wire [7:0] downThresh = (dcrDownThreshI != 0) ? dcrDownThreshI : DEFAULT_DOWN_THRESH;
    wire [31:0] sampleWin = (dcrSampleWinI != 0) ? dcrSampleWinI : DEFAULT_SAMPLE_WIN;

    wire [7:0] utilizationPct;
    assign utilizationPct = (sampleCounter > 0) ?
                             (activeCounter * 100) / sampleCounter : 8'd0;

    wire [1:0] dutyNum = perfDutyNum(perfLevelT'(perfLevelO));
    always @(posedge clk or negedge rstN) begin
        if (!rstN) begin
            perfLevelO          <= PERF_P0;
            clockEnableO        <= 1'b1;
            sampleCounter        <= 0;
            activeCounter        <= 0;
            dutyPhase            <= 0;
            totalActiveCyclesO <= 0;
            totalSampleCyclesO <= 0;
        end else begin

            dutyPhase <= dutyPhase + 1;

            if (dcrForceEnI) begin
                perfLevelO <= dcrForceLevelI;
            end else if (kernelActiveI) begin

                sampleCounter <= sampleCounter + 1;
                if (aluActivePulseI || tensorActivePulseI)
                    activeCounter <= activeCounter + 1;

                if (sampleCounter >= sampleWin) begin
                    totalActiveCyclesO <= totalActiveCyclesO + activeCounter;
                    totalSampleCyclesO <= totalSampleCyclesO + sampleCounter;
                    if (utilizationPct >= upThresh) begin

                        if (perfLevelO > PERF_P0)
                            perfLevelO <= perfLevelO - 1;
                    end else if (utilizationPct <= downThresh) begin

                        if (perfLevelO < PERF_P8)
                            perfLevelO <= perfLevelO + 1;
                    end
                    sampleCounter <= 0;
                    activeCounter <= 0;
                end
            end else begin

                perfLevelO   <= PERF_P8;
                sampleCounter <= 0;
                activeCounter <= 0;
            end

            clockEnableO <= (dutyPhase <= dutyNum);
        end
    end
`ifdef VERILATOR
    reg [1:0] prevLevel;
    always @(posedge clk) begin
        prevLevel <= perfLevelO;
        if (rstN && perfLevelO != prevLevel)
            $display("[PERF] P-state transition: P%0d -> P%0d (util=%0d%%)", prevLevel, perfLevelO, utilizationPct);
    end
`endif
endmodule
