
`default_nettype none
`timescale 1ns/1ns
import gridx_pkg::*;

module perf_boost_controller #(
    parameter DEFAULT_UP_THRESH   = 75,
    parameter DEFAULT_DOWN_THRESH = 25,
    parameter DEFAULT_SAMPLE_WIN  = 1024,
    parameter COUNTER_WIDTH       = 32
) (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    alu_active_pulse_i,
    input  wire                    tensor_active_pulse_i,
    input  wire                    kernel_active_i,

    input  wire [1:0]             dcr_force_level_i,
    input  wire                   dcr_force_en_i,
    input  wire [7:0]            dcr_up_thresh_i,
    input  wire [7:0]            dcr_down_thresh_i,
    input  wire [31:0]           dcr_sample_win_i,

    output reg  [1:0]            perf_level_o,
    output reg                   clock_enable_o,
    output reg  [COUNTER_WIDTH-1:0] total_active_cycles_o,
    output reg  [COUNTER_WIDTH-1:0] total_sample_cycles_o
);
    reg [31:0] sample_counter;
    reg [31:0] active_counter;
    reg [1:0]  duty_phase;
    wire [7:0] up_thresh   = (dcr_up_thresh_i != 0) ? dcr_up_thresh_i : DEFAULT_UP_THRESH;
    wire [7:0] down_thresh = (dcr_down_thresh_i != 0) ? dcr_down_thresh_i : DEFAULT_DOWN_THRESH;
    wire [31:0] sample_win = (dcr_sample_win_i != 0) ? dcr_sample_win_i : DEFAULT_SAMPLE_WIN;

    wire [7:0] utilization_pct;
    assign utilization_pct = (sample_counter > 0) ?
                             (active_counter * 100) / sample_counter : 8'd0;

    wire [1:0] duty_num = perf_duty_num(perf_level_t'(perf_level_o));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            perf_level_o          <= PERF_P0;
            clock_enable_o        <= 1'b1;
            sample_counter        <= 0;
            active_counter        <= 0;
            duty_phase            <= 0;
            total_active_cycles_o <= 0;
            total_sample_cycles_o <= 0;
        end else begin

            duty_phase <= duty_phase + 1;

            if (dcr_force_en_i) begin
                perf_level_o <= dcr_force_level_i;
            end else if (kernel_active_i) begin

                sample_counter <= sample_counter + 1;
                if (alu_active_pulse_i || tensor_active_pulse_i)
                    active_counter <= active_counter + 1;

                if (sample_counter >= sample_win) begin
                    total_active_cycles_o <= total_active_cycles_o + active_counter;
                    total_sample_cycles_o <= total_sample_cycles_o + sample_counter;
                    if (utilization_pct >= up_thresh) begin

                        if (perf_level_o > PERF_P0)
                            perf_level_o <= perf_level_o - 1;
                    end else if (utilization_pct <= down_thresh) begin

                        if (perf_level_o < PERF_P8)
                            perf_level_o <= perf_level_o + 1;
                    end
                    sample_counter <= 0;
                    active_counter <= 0;
                end
            end else begin

                perf_level_o   <= PERF_P8;
                sample_counter <= 0;
                active_counter <= 0;
            end

            clock_enable_o <= (duty_phase <= duty_num);
        end
    end
`ifdef VERILATOR
    reg [1:0] prev_level;
    always @(posedge clk) begin
        prev_level <= perf_level_o;
        if (rst_n && perf_level_o != prev_level)
            $display("[PERF] P-state transition: P%0d -> P%0d (util=%0d%%)", prev_level, perf_level_o, utilization_pct);
    end
`endif
endmodule
