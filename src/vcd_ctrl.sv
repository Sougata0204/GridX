
`default_nettype none
`timescale 1ns/1ns

// VCD waveform dump controller enabling selective signal tracing with configurable start/stop windows for simulation.
module vcdCtrl #(
    parameter string VCD_FILENAME  = "gridxTrace.vcd",
    parameter int    DUMP_START    = 0,
    parameter int    DUMP_END      = 100_000,
    parameter int    DUMP_LEVEL    = 2,
    parameter int    SNAPSHOT_INTERVAL = 10_000
) (
    input wire clk,
    input wire reset,
    input wire enable,
    input wire forceDumpOn,
    input wire forceDumpOff,
    output reg dumping
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

            if (enable && !dumpInitialized && (cycleCount >= DUMP_START) && (DUMP_LEVEL > 0)) begin
                $dumpfile(VCD_FILENAME);
                case (DUMP_LEVEL)
                    1: $dumpvars(1);
                    2: $dumpvars(2);
                    3: $dumpvars(0);
                    default: $dumpvars(1);
                endcase
                dumpInitialized <= 1'b1;
                dumpActive      <= 1'b1;
                dumping          <= 1'b1;
                $display("[vcdCtrl] Dump started at cycle %0d, level=%0d, file=%s",
                         cycleCount, DUMP_LEVEL, VCD_FILENAME);
            end

            if (dumpActive && (cycleCount >= DUMP_END)) begin
                $dumpoff;
                dumpActive <= 1'b0;
                dumping     <= 1'b0;
                $display("[vcdCtrl] Dump stopped at cycle %0d", cycleCount);
            end

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

            if (dumpActive && (cycleCount % SNAPSHOT_INTERVAL == 0) && (cycleCount > 0)) begin
                $dumpflush;
            end
        end
    end

endmodule
