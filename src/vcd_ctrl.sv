
// GridX3 - VCD Dump Control Module
// Provides targeted, cycle-range-limited VCD dumping to keep file sizes
// manageable on memory-constrained systems.
// Usage: Instantiate in testbench. Control via parameters or runtime signals.

`default_nettype none
`timescale 1ns/1ns

module vcdCtrl #(
    parameter string VCD_FILENAME  = "gridxTrace.vcd",
    parameter int    DUMP_START    = 0,          // Cycle to begin dumping
    parameter int    DUMP_END      = 100_000,    // Cycle to stop dumping
    parameter int    DUMP_LEVEL    = 2,          // Hierarchy depth (0=off)
    parameter int    SNAPSHOT_INTERVAL = 10_000  // Cycles between $dumpflush
) (
    input wire clk,
    input wire reset,
    input wire enable,           // Runtime enable/disable
    input wire forceDumpOn,    // Force dump start (debug trigger)
    input wire forceDumpOff,   // Force dump stop
    output reg dumping           // Status: currently dumping
);

    reg [31:0] cycleCount;
    reg        dumpActive;
    reg        dumpInitialized;

    always @(posedge clk) begin
        if (reset) begin
            cycleCount      <= 32'd0;
            dumpActive      <= 1'b0;
            dumpInitialized <= 1'b0;
            dumping          <= 1'b0;
        end else begin
            cycleCount <= cycleCount + 32'd1;

            // Start VCD dump at DUMP_START
            // synthesis translateOff
            if (enable && !dumpInitialized && (cycleCount >= DUMP_START) && (DUMP_LEVEL > 0)) begin
                $dumpfile(VCD_FILENAME);
                case (DUMP_LEVEL)
                    1: $dumpvars(1);    // Top-level signals only
                    2: $dumpvars(2);    // Top + first sub-level
                    3: $dumpvars(0);    // Full hierarchy (WARNING: large)
                    default: $dumpvars(1);
                endcase
                dumpInitialized <= 1'b1;
                dumpActive      <= 1'b1;
                dumping          <= 1'b1;
                $display("[vcdCtrl] Dump started at cycle %0d, level=%0d, file=%s",
                         cycleCount, DUMP_LEVEL, VCD_FILENAME);
            end

            // Stop VCD dump at DUMP_END
            if (dumpActive && (cycleCount >= DUMP_END)) begin
                $dumpoff;
                dumpActive <= 1'b0;
                dumping     <= 1'b0;
                $display("[vcdCtrl] Dump stopped at cycle %0d", cycleCount);
            end

            // Force controls
            if (forceDumpOn && !dumpActive && dumpInitialized) begin
                $dumpon;
                dumpActive <= 1'b1;
                dumping     <= 1'b1;
            end
            if (forceDumpOff && dumpActive) begin
                $dumpoff;
                dumpActive <= 1'b0;
                dumping     <= 1'b0;
            end

            // Periodic flush to prevent data loss
            if (dumpActive && (cycleCount % SNAPSHOT_INTERVAL == 0) && (cycleCount > 0)) begin
                $dumpflush;
            end
            // synthesis translateOn
        end
    end

endmodule
