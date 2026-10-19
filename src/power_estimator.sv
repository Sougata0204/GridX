`default_nettype none
`timescale 1ns/1ns

// Real-time switching activity monitor computing dynamic power (P=alpha*Ceff*V^2*f), static leakage, peak tracking, and energy accumulation.
module power_estimator #(
    parameter NUM_CORES          = 4096,
    parameter SAMPLE_WINDOW      = 1024,
    parameter VDD_MV             = 800,
    parameter FREQ_MHZ           = 2000,
    parameter C_EFF_FF           = 100,
    parameter STATIC_PER_CORE_UW = 50
) (
    input wire clk,
    input wire reset,

    input wire [NUM_CORES-1:0] core_active,
    input wire [NUM_CORES-1:0] alu_switching,
    input wire [NUM_CORES-1:0] mem_switching,
    input wire [NUM_CORES-1:0] tensor_switching,

    output reg [63:0] dynamic_power_uw,
    output reg [31:0] static_power_uw,
    output reg [63:0] total_power_uw,
    output reg [63:0] total_switching_events,
    output reg [31:0] activity_factor_pct,
    output reg [63:0] peak_power_uw,
    output reg [63:0] energy_consumed_pj
);

    reg [31:0] window_counter;
    reg [63:0] window_alu_events;
    reg [63:0] window_mem_events;
    reg [63:0] window_tensor_events;
    reg [31:0] window_active_cores;

    integer ci;
    reg [31:0] active_count;
    reg [31:0] alu_count;
    reg [31:0] mem_count;
    reg [31:0] tensor_count;

    always @(*) begin
        active_count = 0;
        alu_count    = 0;
        mem_count    = 0;
        tensor_count = 0;
        for (ci = 0; ci < NUM_CORES; ci = ci + 1) begin
            active_count = active_count + {31'd0, core_active[ci]};
            alu_count    = alu_count    + {31'd0, alu_switching[ci]};
            mem_count    = mem_count    + {31'd0, mem_switching[ci]};
            tensor_count = tensor_count + {31'd0, tensor_switching[ci]};
        end
    end

    wire [31:0] computed_static = active_count * STATIC_PER_CORE_UW;

    always @(posedge clk) begin
        if (reset) begin
            window_counter         <= 0;
            window_alu_events      <= 0;
            window_mem_events      <= 0;
            window_tensor_events   <= 0;
            window_active_cores    <= 0;
            dynamic_power_uw       <= 0;
            static_power_uw        <= 0;
            total_power_uw         <= 0;
            total_switching_events <= 0;
            activity_factor_pct    <= 0;
            peak_power_uw          <= 0;
            energy_consumed_pj     <= 0;
        end else begin
            window_alu_events    <= window_alu_events + {32'd0, alu_count};
            window_mem_events    <= window_mem_events + {32'd0, mem_count};
            window_tensor_events <= window_tensor_events + {32'd0, tensor_count};
            window_active_cores  <= window_active_cores + active_count;
            window_counter       <= window_counter + 1;

            static_power_uw <= computed_static;

            energy_consumed_pj <= energy_consumed_pj + (total_power_uw * 1000) / FREQ_MHZ;

            if (window_counter >= SAMPLE_WINDOW) begin
                total_switching_events <= total_switching_events +
                    window_alu_events + window_mem_events + window_tensor_events;

                if (NUM_CORES > 0 && SAMPLE_WINDOW > 0) begin
                    activity_factor_pct <= ((window_alu_events + window_mem_events + window_tensor_events) * 100) /
                                          (NUM_CORES * SAMPLE_WINDOW * 3);
                end

                begin
                    reg [63:0] total_events;
                    reg [63:0] new_dynamic_uw;
                    reg [63:0] new_total_uw;

                    total_events   = window_alu_events + window_mem_events + window_tensor_events;
                    new_dynamic_uw = (total_events * C_EFF_FF / SAMPLE_WINDOW) *
                                     ((VDD_MV * VDD_MV) / 1000) * FREQ_MHZ / 1000000;
                    new_total_uw   = new_dynamic_uw + computed_static;

                    dynamic_power_uw <= new_dynamic_uw;
                    total_power_uw   <= new_total_uw;

                    if (new_total_uw > peak_power_uw)
                        peak_power_uw <= new_total_uw;
                end

                window_counter       <= 0;
                window_alu_events    <= 0;
                window_mem_events    <= 0;
                window_tensor_events <= 0;
                window_active_cores  <= 0;
            end
        end
    end

`ifndef SYNTHESIS
    task automatic print_power_report;
        begin
            $display("[POWER_REPORT] Cores: %0d | VDD: %0d mV | Freq: %0d MHz | C_eff: %0d fF",
                     NUM_CORES, VDD_MV, FREQ_MHZ, C_EFF_FF);
            $display("[POWER_REPORT] Dynamic: %0d uW | Static: %0d uW | Total: %0d uW | Peak: %0d uW | Activity: %0d%%",
                     dynamic_power_uw, static_power_uw, total_power_uw, peak_power_uw, activity_factor_pct);
            $display("[POWER_REPORT] Events: %0d | Energy: %0d pJ",
                     total_switching_events, energy_consumed_pj);
        end
    endtask
`endif

endmodule
