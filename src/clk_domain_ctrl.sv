
`default_nettype none
`timescale 1ns/1ns

module clkDomainCtrl #(
    parameter NUM_CLUSTERS      = 8,
    parameter CORES_PER_CLUSTER = 4,
    parameter SAMPLE_WINDOW     = 1024,
    parameter UP_THRESHOLD      = 75,
    parameter DOWN_THRESHOLD    = 25,
    parameter HYSTERESIS        = 8
) (
    input  wire clk,
    input  wire reset,

    input  wire [NUM_CLUSTERS-1:0] clusterAluActive,
    input  wire [NUM_CLUSTERS-1:0] clusterTensorActive,
    input  wire [NUM_CLUSTERS-1:0] clusterStallMem,

    input  wire [6:0]              clusterTemp [NUM_CLUSTERS-1:0],
    input  wire [6:0]              thermalLimit,

    output reg  [1:0]              clusterPerfLevel [NUM_CLUSTERS-1:0],
    output reg  [NUM_CLUSTERS-1:0] clusterClockEnable,
    output reg  [NUM_CLUSTERS-1:0] clusterPowerGate,

    output reg  [NUM_CLUSTERS-1:0] clusterThrottled,
    output wire [31:0]             totalGatedCycles
);

    localparam [1:0] PERF_IDLE = 2'b00;
    localparam [1:0] PERF_LOW  = 2'b01;
    localparam [1:0] PERF_MED  = 2'b10;
    localparam [1:0] PERF_HIGH = 2'b11;

    reg [15:0] activeCycles  [NUM_CLUSTERS-1:0];
    reg [15:0] sampleCounter;
    reg [31:0] gatedCycles;
    assign totalGatedCycles = gatedCycles;

    integer c;

    always @(posedge clk) begin
        if (reset) begin
            sampleCounter <= 0;
            gatedCycles   <= 0;
            for (c = 0; c < NUM_CLUSTERS; c = c + 1) begin
                activeCycles[c]      <= 0;
                clusterPerfLevel[c] <= PERF_MED;
                clusterClockEnable[c] <= 1;
                clusterPowerGate[c]   <= 0;
                clusterThrottled[c]    <= 0;
            end
        end else begin
            sampleCounter <= sampleCounter + 1;

            for (c = 0; c < NUM_CLUSTERS; c = c + 1) begin
                if (clusterAluActive[c] || clusterTensorActive[c])
                    activeCycles[c] <= activeCycles[c] + 1;

                if (!clusterClockEnable[c])
                    gatedCycles <= gatedCycles + 1;
            end

            if (sampleCounter >= SAMPLE_WINDOW) begin
                sampleCounter <= 0;

                for (c = 0; c < NUM_CLUSTERS; c = c + 1) begin

                    if (clusterTemp[c] >= thermalLimit) begin

                        clusterPerfLevel[c] <= PERF_LOW;
                        clusterThrottled[c]  <= 1;
                    end else begin
                        clusterThrottled[c] <= 0;

                        if (activeCycles[c] > ((UP_THRESHOLD * SAMPLE_WINDOW) / 100)) begin

                            if (clusterPerfLevel[c] < PERF_HIGH)
                                clusterPerfLevel[c] <= clusterPerfLevel[c] + 1;
                        end else if (activeCycles[c] < ((DOWN_THRESHOLD * SAMPLE_WINDOW) / 100)) begin

                            if (clusterPerfLevel[c] > PERF_IDLE)
                                clusterPerfLevel[c] <= clusterPerfLevel[c] - 1;
                        end

                    end

                    clusterClockEnable[c] <= (clusterPerfLevel[c] != PERF_IDLE);

                    clusterPowerGate[c] <= (clusterPerfLevel[c] == PERF_IDLE) &&
                                              (activeCycles[c] == 0);

                    activeCycles[c] <= 0;
                end
            end
        end
    end

endmodule
