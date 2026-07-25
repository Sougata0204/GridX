
`default_nettype none
`timescale 1ns/1ns

module power_controller #(
    parameter NUM_BANKS = 8,
    parameter IDLE_CYCLES = 16,
    parameter SLEEP_CYCLES = 256,
    parameter COUNTER_WIDTH = 32
) (
    input wire clk,
    input wire reset,
    input wire [NUM_BANKS-1:0] bank_active,
    input wire [NUM_BANKS-1:0] force_enable,
    input wire [NUM_BANKS-1:0] force_sleep,
    output reg [NUM_BANKS-1:0] bank_power_enable,
    output reg [1:0] bank_power_state [NUM_BANKS-1:0],
    output reg [NUM_BANKS-1:0] bank_needs_reload,
    output reg [COUNTER_WIDTH-1:0] total_active_cycles,
    output reg [COUNTER_WIDTH-1:0] total_idle_cycles,
    output reg [COUNTER_WIDTH-1:0] total_sleep_cycles,
    output reg [COUNTER_WIDTH-1:0] state_transitions,
    output reg [NUM_BANKS-1:0] bank_was_active
);
    localparam STATE_SLEEP  = 2'b00;
    localparam STATE_IDLE   = 2'b01;
    localparam STATE_ACTIVE = 2'b10;
    reg [15:0] idle_counter [NUM_BANKS-1:0];
    reg [15:0] sleep_counter [NUM_BANKS-1:0];
    reg [1:0] prev_bank_state [NUM_BANKS-1:0];
    genvar b;
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            bank_power_enable <= {NUM_BANKS{1'b1}};
            bank_needs_reload <= {NUM_BANKS{1'b0}};
            bank_was_active <= {NUM_BANKS{1'b0}};
            total_active_cycles <= 0;
            total_idle_cycles <= 0;
            total_sleep_cycles <= 0;
            state_transitions <= 0;
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                bank_power_state[i] <= STATE_ACTIVE;
                prev_bank_state[i] <= STATE_ACTIVE;
                idle_counter[i] <= 0;
                sleep_counter[i] <= 0;
            end
        end else begin
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                case (bank_power_state[i])
                    STATE_ACTIVE: total_active_cycles <= total_active_cycles + 1;
                    STATE_IDLE:   total_idle_cycles <= total_idle_cycles + 1;
                    STATE_SLEEP:  total_sleep_cycles <= total_sleep_cycles + 1;
                endcase
                if (bank_power_state[i] != prev_bank_state[i]) begin
                    state_transitions <= state_transitions + 1;
                end
                prev_bank_state[i] <= bank_power_state[i];
                bank_was_active[i] <= bank_active[i];
            end
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                if (force_sleep[i]) begin
                    bank_power_state[i] <= STATE_SLEEP;
                    bank_power_enable[i] <= 1'b0;
                    bank_needs_reload[i] <= 1'b1;
                    idle_counter[i] <= 0;
                    sleep_counter[i] <= 0;
                end else if (force_enable[i]) begin
                    bank_power_state[i] <= STATE_ACTIVE;
                    bank_power_enable[i] <= 1'b1;
                    idle_counter[i] <= 0;
                    sleep_counter[i] <= 0;
                end else begin
                    case (bank_power_state[i])
                        STATE_ACTIVE: begin
                            bank_power_enable[i] <= 1'b1;
                            bank_needs_reload[i] <= 1'b0;
                            if (bank_active[i]) begin
                                idle_counter[i] <= 0;
                            end else begin
                                idle_counter[i] <= idle_counter[i] + 1;
                                if (idle_counter[i] >= IDLE_CYCLES) begin
                                    bank_power_state[i] <= STATE_IDLE;
                                    idle_counter[i] <= 0;
                                end
                            end
                        end
                        STATE_IDLE: begin
                            bank_power_enable[i] <= 1'b0;
                            bank_needs_reload[i] <= 1'b0;
                            if (bank_active[i]) begin
                                bank_power_state[i] <= STATE_ACTIVE;
                                bank_power_enable[i] <= 1'b1;
                                sleep_counter[i] <= 0;
                            end else begin
                                sleep_counter[i] <= sleep_counter[i] + 1;
                                if (sleep_counter[i] >= SLEEP_CYCLES) begin
                                    bank_power_state[i] <= STATE_SLEEP;
                                    bank_needs_reload[i] <= 1'b1;
                                    sleep_counter[i] <= 0;
                                end
                            end
                        end
                        STATE_SLEEP: begin
                            bank_power_enable[i] <= 1'b0;
                            bank_needs_reload[i] <= 1'b1;
                            if (bank_active[i]) begin
                                bank_power_state[i] <= STATE_ACTIVE;
                                bank_power_enable[i] <= 1'b1;
                            end
                        end
                        default: begin
                            bank_power_state[i] <= STATE_ACTIVE;
                        end
                    endcase
                end
            end
        end
    end
endmodule
