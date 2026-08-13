
`default_nettype none
`timescale 1ns/1ns
import gridxPkg::*;

module channelScheduler #(
    parameter NUM_CHANNELS        = CH_COUNT,
    parameter DEFAULT_TIMESLICE_P0 = 256,
    parameter DEFAULT_TIMESLICE_P1 = 512,
    parameter DEFAULT_TIMESLICE_P2 = 1024,
    parameter DEFAULT_TIMESLICE_P3 = 2048,
    parameter DEFAULT_AGING_THRESH = 4096
) (
    input  wire                          clk,
    input  wire                          rstN,

    input  wire [NUM_CHANNELS-1:0]       chRunnableI,

    input  wire [NUM_CHANNELS*2-1:0]     chPriorityI,

    input  wire [NUM_CHANNELS-1:0]       chBlockDoneI,

    input  wire [31:0]                   dcrTimesliceP0I,
    input  wire [31:0]                   dcrTimesliceP1I,
    input  wire [31:0]                   dcrTimesliceP2I,
    input  wire [31:0]                   dcrTimesliceP3I,
    input  wire [31:0]                   dcrAgingThreshI,

    output reg  [NUM_CHANNELS-1:0]       chRunningO,
    output reg  [NUM_CHANNELS*2-1:0]     chStateO,
    output reg  [NUM_CHANNELS-1:0]       chPreemptO,
    output reg  [NUM_CHANNELS-1:0]       chAgedPromotionO,
    output reg                           allChannelsIdleO,
    output reg  [$clog2(NUM_CHANNELS)-1:0] activeChannelO
);
    localparam CH_BITS = $clog2(NUM_CHANNELS);

    reg [1:0]  chStateReg    [NUM_CHANNELS-1:0];
    reg [31:0] timesliceCtr   [NUM_CHANNELS-1:0];
    reg [31:0] agingCtr       [NUM_CHANNELS-1:0];
    reg [1:0]  effectivePri   [NUM_CHANNELS-1:0];
    reg [CH_BITS-1:0] currentCh;

    function automatic [31:0] getTimeslice(input [1:0] pri);
        case (pri)
            2'h0: getTimeslice = (dcrTimesliceP0I != 0) ? dcrTimesliceP0I : DEFAULT_TIMESLICE_P0;
            2'h1: getTimeslice = (dcrTimesliceP1I != 0) ? dcrTimesliceP1I : DEFAULT_TIMESLICE_P1;
            2'h2: getTimeslice = (dcrTimesliceP2I != 0) ? dcrTimesliceP2I : DEFAULT_TIMESLICE_P2;
            2'h3: getTimeslice = (dcrTimesliceP3I != 0) ? dcrTimesliceP3I : DEFAULT_TIMESLICE_P3;
            default: getTimeslice = DEFAULT_TIMESLICE_P2;
        endcase
    endfunction

    function automatic [1:0] chPri(input [CH_BITS-1:0] c);
        chPri = chPriorityI[c*2 +: 2];
    endfunction

    reg [CH_BITS-1:0] bestCh;
    reg [1:0]         bestPri;
    reg               bestValid;
    integer s;
    always @(*) begin
        bestValid = 1'b0;
        bestCh    = 0;
        bestPri   = 2'h3;
        for (s = 0; s < NUM_CHANNELS; s = s + 1) begin
            if (chRunnableI[s] && chStateReg[s] != CH_PREEMPTED) begin
                if (!bestValid || effectivePri[s] < bestPri ||
                    (effectivePri[s] == bestPri && s[CH_BITS-1:0] == currentCh)) begin
                    bestValid = 1'b1;
                    bestCh    = s[CH_BITS-1:0];
                    bestPri   = effectivePri[s];
                end
            end
        end
    end

    integer p;
    always @(*) begin
        for (p = 0; p < NUM_CHANNELS; p = p + 1)
            chStateO[p*2 +: 2] = chStateReg[p];
    end

    always @(*) begin
        allChannelsIdleO = 1'b1;
        for (p = 0; p < NUM_CHANNELS; p = p + 1)
            if (chRunnableI[p]) allChannelsIdleO = 1'b0;
    end
    integer i;
    always @(posedge clk or negedge rstN) begin
        if (!rstN) begin
            currentCh          <= 0;
            activeChannelO    <= 0;
            chRunningO        <= 0;
            chPreemptO        <= 0;
            chAgedPromotionO <= 0;
            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                chStateReg[i]  <= CH_IDLE;
                timesliceCtr[i] <= 0;
                agingCtr[i]     <= 0;
                effectivePri[i] <= 0;
            end
        end else begin
            chPreemptO        <= 0;
            chAgedPromotionO <= 0;

            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                effectivePri[i] <= chPri(i[CH_BITS-1:0]);

                if (!chRunnableI[i]) begin
                    chStateReg[i] <= CH_IDLE;
                    agingCtr[i]    <= 0;
                end else if (chStateReg[i] == CH_IDLE && chRunnableI[i]) begin
                    chStateReg[i] <= CH_RUNNABLE;
                end

                if (chRunnableI[i] && chStateReg[i] == CH_RUNNABLE &&
                    i[CH_BITS-1:0] != currentCh) begin
                    agingCtr[i] <= agingCtr[i] + 1;
                    if (agingCtr[i] >= ((dcrAgingThreshI != 0) ? dcrAgingThreshI : DEFAULT_AGING_THRESH)) begin
                        if (effectivePri[i] > 0)
                            effectivePri[i] <= effectivePri[i] - 1;
                        chAgedPromotionO[i] <= 1'b1;
                        agingCtr[i] <= 0;
                    end
                end else begin
                    agingCtr[i] <= 0;
                end
            end

            if (chRunningO[currentCh]) begin
                timesliceCtr[currentCh] <= timesliceCtr[currentCh] + 1;
            end

            if (chRunningO[currentCh]) begin

                if (bestValid && bestPri < effectivePri[currentCh] &&
                    bestCh != currentCh) begin
                    chPreemptO[currentCh]  <= 1'b1;
                    chStateReg[currentCh]  <= CH_PREEMPTED;
                    chRunningO[currentCh]  <= 1'b0;

                    currentCh                <= bestCh;
                    activeChannelO          <= bestCh;
                    chStateReg[bestCh]     <= CH_RUNNING;
                    chRunningO[bestCh]     <= 1'b1;
                    timesliceCtr[bestCh]    <= 0;
                end

                else if (timesliceCtr[currentCh] >= getTimeslice(effectivePri[currentCh])) begin
                    chStateReg[currentCh]  <= CH_RUNNABLE;
                    chRunningO[currentCh]  <= 1'b0;
                    timesliceCtr[currentCh] <= 0;

                    if (bestValid) begin
                        currentCh             <= bestCh;
                        activeChannelO       <= bestCh;
                        chStateReg[bestCh]  <= CH_RUNNING;
                        chRunningO[bestCh]  <= 1'b1;
                        timesliceCtr[bestCh] <= 0;
                    end
                end
            end else begin

                if (bestValid) begin
                    currentCh                <= bestCh;
                    activeChannelO          <= bestCh;
                    chStateReg[bestCh]     <= CH_RUNNING;
                    chRunningO[bestCh]     <= 1'b1;
                    timesliceCtr[bestCh]    <= 0;
                end
            end

            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                if (chStateReg[i] == CH_PREEMPTED && chRunnableI[i])
                    chStateReg[i] <= CH_RUNNABLE;
            end
        end
    end
`ifdef VERILATOR
    always @(posedge clk) begin
        if (rstN && |chPreemptO)
            $display("[chSched] Preemption: ch%d preempted, ch%d now running", currentCh, bestCh);
    end
`endif
endmodule
