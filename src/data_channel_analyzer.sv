// Data Channel Analyzer
// Real-time performance monitoring and analysis for AXI4/CHI data channels.
// Provides live bandwidth measurement, utilization tracking, congestion detection,
// and latency histogram binning for design space exploration.
//
// Connects passively to any valid/ready data channel and computes:
//   - Rolling bandwidth (bytes/window)
//   - Channel utilization percentage
//   - Congestion events (valid && !ready)
//   - Latency histogram (4 configurable bins)
//   - Peak/average throughput

`default_nettype none
`timescale 1ns/1ns

module dataChannelAnalyzer #(
    parameter DATA_WIDTH       = 512,
    parameter WINDOW_CYCLES    = 1024,  // Measurement window in clock cycles
    parameter LATENCY_BIN0_MAX = 4,     // Bin 0: [0, BIN0_MAX]
    parameter LATENCY_BIN1_MAX = 16,    // Bin 1: (BIN0_MAX, BIN1_MAX]
    parameter LATENCY_BIN2_MAX = 64     // Bin 2: (BIN1_MAX, BIN2_MAX], Bin 3: > BIN2_MAX
) (
    input  wire clk,
    input  wire reset,

    // Channel observation (passive)
    input  wire        chValid,
    input  wire        chReady,
    input  wire        chLast,       // Burst boundary marker (optional, tie to 1 if N/A)

    // Latency measurement input
    input  wire        latStart,     // Pulse: transaction issued
    input  wire        latEnd,       // Pulse: transaction completed
    input  wire [31:0] latValue,     // Measured latency in cycles (valid when latEnd)

    output reg  [31:0] bwBytesPerWindow,
    output reg  [31:0] bwPeakBytes,
    output reg  [31:0] utilizationPct,        // 0-100 (x100 for fixed-point)
    output reg  [31:0] totalTransfers,
    output reg  [31:0] totalBursts,
    output reg  [31:0] totalBytes,
    output reg  [31:0] congestionEvents,
    output reg  [31:0] idleCycles,
    output reg  [31:0] latencyBin0Count,     // [0, BIN0_MAX]
    output reg  [31:0] latencyBin1Count,     // (BIN0_MAX, BIN1_MAX]
    output reg  [31:0] latencyBin2Count,     // (BIN1_MAX, BIN2_MAX]
    output reg  [31:0] latencyBin3Count,     // > BIN2_MAX
    output reg  [31:0] latencyMin,
    output reg  [31:0] latencyMax,
    output reg  [31:0] latencySum,
    output reg  [31:0] latencyCount,
    output reg  [31:0] avgLatency
);

    localparam BYTES_PER_BEAT = DATA_WIDTH / 8;

    // Rolling window counters
    reg [31:0] windowCounter;
    reg [31:0] windowBytes;
    reg [31:0] windowActive;

    always @(posedge clk) begin
        if (reset) begin
            bwBytesPerWindow <= 0;
            bwPeakBytes       <= 0;
            utilizationPct     <= 0;
            totalTransfers     <= 0;
            totalBursts        <= 0;
            totalBytes         <= 0;
            congestionEvents   <= 0;
            idleCycles         <= 0;
            latencyBin0Count  <= 0;
            latencyBin1Count  <= 0;
            latencyBin2Count  <= 0;
            latencyBin3Count  <= 0;
            latencyMin         <= 32'hFFFFFFFF;
            latencyMax         <= 0;
            latencySum         <= 0;
            latencyCount       <= 0;
            avgLatency         <= 0;
            windowCounter      <= 0;
            windowBytes        <= 0;
            windowActive       <= 0;
        end else begin
            windowCounter <= windowCounter + 1;

            if (windowCounter >= WINDOW_CYCLES) begin
                // Snapshot and reset window
                bwBytesPerWindow <= windowBytes;
                if (windowBytes > bwPeakBytes)
                    bwPeakBytes <= windowBytes;
                // Utilization = (activeCycles * 100) / WINDOW_CYCLES
                if (WINDOW_CYCLES > 0)
                    utilizationPct <= (windowActive * 100) / WINDOW_CYCLES;
                windowCounter <= 0;
                windowBytes   <= 0;
                windowActive  <= 0;
            end

            if (chValid && chReady) begin
                totalTransfers <= totalTransfers + 1;
                totalBytes     <= totalBytes + BYTES_PER_BEAT;
                windowBytes    <= windowBytes + BYTES_PER_BEAT;
                windowActive   <= windowActive + 1;

                if (chLast)
                    totalBursts <= totalBursts + 1;
            end

            if (chValid && !chReady)
                congestionEvents <= congestionEvents + 1;

            if (!chValid && !chReady)
                idleCycles <= idleCycles + 1;

            if (latEnd) begin
                latencyCount <= latencyCount + 1;
                latencySum   <= latencySum + latValue;

                if (latValue < latencyMin)
                    latencyMin <= latValue;
                if (latValue > latencyMax)
                    latencyMax <= latValue;

                // Bin classification
                if (latValue <= LATENCY_BIN0_MAX)
                    latencyBin0Count <= latencyBin0Count + 1;
                else if (latValue <= LATENCY_BIN1_MAX)
                    latencyBin1Count <= latencyBin1Count + 1;
                else if (latValue <= LATENCY_BIN2_MAX)
                    latencyBin2Count <= latencyBin2Count + 1;
                else
                    latencyBin3Count <= latencyBin3Count + 1;

                // Running average
                if (latencyCount > 0)
                    avgLatency <= (latencySum + latValue) / (latencyCount + 1);
            end
        end
    end

endmodule

`default_nettype wire
