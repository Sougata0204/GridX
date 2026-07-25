
`default_nettype none
`timescale 1ns/1ns
import gridx_pkg::*;

module channel_scheduler #(
    parameter NUM_CHANNELS        = CH_COUNT,
    parameter DEFAULT_TIMESLICE_P0 = 256,
    parameter DEFAULT_TIMESLICE_P1 = 512,
    parameter DEFAULT_TIMESLICE_P2 = 1024,
    parameter DEFAULT_TIMESLICE_P3 = 2048,
    parameter DEFAULT_AGING_THRESH = 4096
) (
    input  wire                          clk,
    input  wire                          rst_n,

    input  wire [NUM_CHANNELS-1:0]       ch_runnable_i,

    input  wire [NUM_CHANNELS*2-1:0]     ch_priority_i,

    input  wire [NUM_CHANNELS-1:0]       ch_block_done_i,

    input  wire [31:0]                   dcr_timeslice_p0_i,
    input  wire [31:0]                   dcr_timeslice_p1_i,
    input  wire [31:0]                   dcr_timeslice_p2_i,
    input  wire [31:0]                   dcr_timeslice_p3_i,
    input  wire [31:0]                   dcr_aging_thresh_i,

    output reg  [NUM_CHANNELS-1:0]       ch_running_o,
    output reg  [NUM_CHANNELS*2-1:0]     ch_state_o,
    output reg  [NUM_CHANNELS-1:0]       ch_preempt_o,
    output reg  [NUM_CHANNELS-1:0]       ch_aged_promotion_o,
    output reg                           all_channels_idle_o,
    output reg  [$clog2(NUM_CHANNELS)-1:0] active_channel_o
);
    localparam CH_BITS = $clog2(NUM_CHANNELS);

    reg [1:0]  ch_state_reg    [NUM_CHANNELS-1:0];
    reg [31:0] timeslice_ctr   [NUM_CHANNELS-1:0];
    reg [31:0] aging_ctr       [NUM_CHANNELS-1:0];
    reg [1:0]  effective_pri   [NUM_CHANNELS-1:0];
    reg [CH_BITS-1:0] current_ch;

    function automatic [31:0] get_timeslice(input [1:0] pri);
        case (pri)
            2'h0: get_timeslice = (dcr_timeslice_p0_i != 0) ? dcr_timeslice_p0_i : DEFAULT_TIMESLICE_P0;
            2'h1: get_timeslice = (dcr_timeslice_p1_i != 0) ? dcr_timeslice_p1_i : DEFAULT_TIMESLICE_P1;
            2'h2: get_timeslice = (dcr_timeslice_p2_i != 0) ? dcr_timeslice_p2_i : DEFAULT_TIMESLICE_P2;
            2'h3: get_timeslice = (dcr_timeslice_p3_i != 0) ? dcr_timeslice_p3_i : DEFAULT_TIMESLICE_P3;
            default: get_timeslice = DEFAULT_TIMESLICE_P2;
        endcase
    endfunction

    function automatic [1:0] ch_pri(input [CH_BITS-1:0] c);
        ch_pri = ch_priority_i[c*2 +: 2];
    endfunction

    reg [CH_BITS-1:0] best_ch;
    reg [1:0]         best_pri;
    reg               best_valid;
    integer s;
    always @(*) begin
        best_valid = 1'b0;
        best_ch    = 0;
        best_pri   = 2'h3;
        for (s = 0; s < NUM_CHANNELS; s = s + 1) begin
            if (ch_runnable_i[s] && ch_state_reg[s] != CH_PREEMPTED) begin
                if (!best_valid || effective_pri[s] < best_pri ||
                    (effective_pri[s] == best_pri && s[CH_BITS-1:0] == current_ch)) begin
                    best_valid = 1'b1;
                    best_ch    = s[CH_BITS-1:0];
                    best_pri   = effective_pri[s];
                end
            end
        end
    end

    integer p;
    always @(*) begin
        for (p = 0; p < NUM_CHANNELS; p = p + 1)
            ch_state_o[p*2 +: 2] = ch_state_reg[p];
    end

    always @(*) begin
        all_channels_idle_o = 1'b1;
        for (p = 0; p < NUM_CHANNELS; p = p + 1)
            if (ch_runnable_i[p]) all_channels_idle_o = 1'b0;
    end
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_ch          <= 0;
            active_channel_o    <= 0;
            ch_running_o        <= 0;
            ch_preempt_o        <= 0;
            ch_aged_promotion_o <= 0;
            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                ch_state_reg[i]  <= CH_IDLE;
                timeslice_ctr[i] <= 0;
                aging_ctr[i]     <= 0;
                effective_pri[i] <= 0;
            end
        end else begin
            ch_preempt_o        <= 0;
            ch_aged_promotion_o <= 0;

            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                effective_pri[i] <= ch_pri(i[CH_BITS-1:0]);

                if (!ch_runnable_i[i]) begin
                    ch_state_reg[i] <= CH_IDLE;
                    aging_ctr[i]    <= 0;
                end else if (ch_state_reg[i] == CH_IDLE && ch_runnable_i[i]) begin
                    ch_state_reg[i] <= CH_RUNNABLE;
                end

                if (ch_runnable_i[i] && ch_state_reg[i] == CH_RUNNABLE &&
                    i[CH_BITS-1:0] != current_ch) begin
                    aging_ctr[i] <= aging_ctr[i] + 1;
                    if (aging_ctr[i] >= ((dcr_aging_thresh_i != 0) ? dcr_aging_thresh_i : DEFAULT_AGING_THRESH)) begin
                        if (effective_pri[i] > 0)
                            effective_pri[i] <= effective_pri[i] - 1;
                        ch_aged_promotion_o[i] <= 1'b1;
                        aging_ctr[i] <= 0;
                    end
                end else begin
                    aging_ctr[i] <= 0;
                end
            end

            if (ch_running_o[current_ch]) begin
                timeslice_ctr[current_ch] <= timeslice_ctr[current_ch] + 1;
            end

            if (ch_running_o[current_ch]) begin

                if (best_valid && best_pri < effective_pri[current_ch] &&
                    best_ch != current_ch) begin
                    ch_preempt_o[current_ch]  <= 1'b1;
                    ch_state_reg[current_ch]  <= CH_PREEMPTED;
                    ch_running_o[current_ch]  <= 1'b0;

                    current_ch                <= best_ch;
                    active_channel_o          <= best_ch;
                    ch_state_reg[best_ch]     <= CH_RUNNING;
                    ch_running_o[best_ch]     <= 1'b1;
                    timeslice_ctr[best_ch]    <= 0;
                end

                else if (timeslice_ctr[current_ch] >= get_timeslice(effective_pri[current_ch])) begin
                    ch_state_reg[current_ch]  <= CH_RUNNABLE;
                    ch_running_o[current_ch]  <= 1'b0;
                    timeslice_ctr[current_ch] <= 0;

                    if (best_valid) begin
                        current_ch             <= best_ch;
                        active_channel_o       <= best_ch;
                        ch_state_reg[best_ch]  <= CH_RUNNING;
                        ch_running_o[best_ch]  <= 1'b1;
                        timeslice_ctr[best_ch] <= 0;
                    end
                end
            end else begin

                if (best_valid) begin
                    current_ch                <= best_ch;
                    active_channel_o          <= best_ch;
                    ch_state_reg[best_ch]     <= CH_RUNNING;
                    ch_running_o[best_ch]     <= 1'b1;
                    timeslice_ctr[best_ch]    <= 0;
                end
            end

            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                if (ch_state_reg[i] == CH_PREEMPTED && ch_runnable_i[i])
                    ch_state_reg[i] <= CH_RUNNABLE;
            end
        end
    end
`ifdef VERILATOR
    always @(posedge clk) begin
        if (rst_n && |ch_preempt_o)
            $display("[CH_SCHED] Preemption: ch%d preempted, ch%d now running", current_ch, best_ch);
    end
`endif
endmodule
