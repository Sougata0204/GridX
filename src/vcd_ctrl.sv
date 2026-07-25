
// GridX3 - VCD Dump Control Module
// Provides targeted, cycle-range-limited VCD dumping to keep file sizes
// manageable on memory-constrained systems.
// Usage: Instantiate in testbench. Control via parameters or runtime signals.

`default_nettype none
`timescale 1ns/1ns

module vcd_ctrl #(
    parameter string VCD_FILENAME  = "gridx_trace.vcd",
    parameter int    DUMP_START    = 0,          // Cycle to begin dumping
    parameter int    DUMP_END      = 100_000,    // Cycle to stop dumping
    parameter int    DUMP_LEVEL    = 2,          // Hierarchy depth (0=off)
    parameter int    SNAPSHOT_INTERVAL = 10_000  // Cycles between $dumpflush
) (
    input wire clk,
    input wire reset,
    input wire enable,           // Runtime enable/disable
    input wire force_dump_on,    // Force dump start (debug trigger)
    input wire force_dump_off,   // Force dump stop
    output reg dumping           // Status: currently dumping
);

    reg [31:0] cycle_count;
    reg        dump_active;
    reg        dump_initialized;

    always @(posedge clk) begin
        if (reset) begin
            cycle_count      <= 32'd0;
            dump_active      <= 1'b0;
            dump_initialized <= 1'b0;
            dumping          <= 1'b0;
        end else begin
            cycle_count <= cycle_count + 32'd1;

            // Start VCD dump at DUMP_START
            // synthesis translate_off
            if (enable && !dump_initialized && (cycle_count >= DUMP_START) && (DUMP_LEVEL > 0)) begin
                $dumpfile(VCD_FILENAME);
                case (DUMP_LEVEL)
                    1: $dumpvars(1);    // Top-level signals only
                    2: $dumpvars(2);    // Top + first sub-level
                    3: $dumpvars(0);    // Full hierarchy (WARNING: large)
                    default: $dumpvars(1);
                endcase
                dump_initialized <= 1'b1;
                dump_active      <= 1'b1;
                dumping          <= 1'b1;
                $display("[VCD_CTRL] Dump started at cycle %0d, level=%0d, file=%s",
                         cycle_count, DUMP_LEVEL, VCD_FILENAME);
            end

            // Stop VCD dump at DUMP_END
            if (dump_active && (cycle_count >= DUMP_END)) begin
                $dumpoff;
                dump_active <= 1'b0;
                dumping     <= 1'b0;
                $display("[VCD_CTRL] Dump stopped at cycle %0d", cycle_count);
            end

            // Force controls
            if (force_dump_on && !dump_active && dump_initialized) begin
                $dumpon;
                dump_active <= 1'b1;
                dumping     <= 1'b1;
            end
            if (force_dump_off && dump_active) begin
                $dumpoff;
                dump_active <= 1'b0;
                dumping     <= 1'b0;
            end

            // Periodic flush to prevent data loss
            if (dump_active && (cycle_count % SNAPSHOT_INTERVAL == 0) && (cycle_count > 0)) begin
                $dumpflush;
            end
            // synthesis translate_on
        end
    end

endmodule
