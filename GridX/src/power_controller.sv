`default_nettype none
`timescale 1ns/1ns

// POWER CONTROLLER
// > Bank-level power management for SRAM tile buffer
// > Implements clock gating and power gating states
// > Automatic idle detection with configurable timeouts
// > Research-grade: enables energy-per-operation studies
module power_controller #(
    parameter NUM_BANKS = 8,
    parameter IDLE_CYCLES = 16,         // Cycles before entering IDLE state
    parameter SLEEP_CYCLES = 256        // Cycles in IDLE before entering SLEEP
) (
    input wire clk,
    input wire reset,

    // Bank activity monitoring
    input wire [NUM_BANKS-1:0] bank_active,

    // Override controls (from software/CSR)
    input wire [NUM_BANKS-1:0] force_enable,    // Force bank to stay active
    input wire [NUM_BANKS-1:0] force_sleep,     // Force bank to sleep

    // Power state outputs
    output reg [NUM_BANKS-1:0] bank_power_enable,   // Clock enable
    output reg [1:0] bank_power_state [NUM_BANKS-1:0],  // 00=SLEEP, 01=IDLE, 10=ACTIVE
    
    // Status
    output reg [NUM_BANKS-1:0] bank_needs_reload    // Data lost, needs DMA reload
);
    // Power states
    localparam STATE_SLEEP  = 2'b00;
    localparam STATE_IDLE   = 2'b01;
    localparam STATE_ACTIVE = 2'b10;

    // Idle counters per bank
    reg [15:0] idle_counter [NUM_BANKS-1:0];
    reg [15:0] sleep_counter [NUM_BANKS-1:0];

    genvar b;
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            bank_power_enable <= {NUM_BANKS{1'b1}};  // Start all banks enabled
            bank_needs_reload <= {NUM_BANKS{1'b0}};
            
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                bank_power_state[i] <= STATE_ACTIVE;
                idle_counter[i] <= 0;
                sleep_counter[i] <= 0;
            end
        end else begin
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                // Handle forced states
                if (force_sleep[i]) begin
                    bank_power_state[i] <= STATE_SLEEP;
                    bank_power_enable[i] <= 1'b0;
                    bank_needs_reload[i] <= 1'b1;  // Data lost in sleep
                    idle_counter[i] <= 0;
                    sleep_counter[i] <= 0;
                end else if (force_enable[i]) begin
                    bank_power_state[i] <= STATE_ACTIVE;
                    bank_power_enable[i] <= 1'b1;
                    idle_counter[i] <= 0;
                    sleep_counter[i] <= 0;
                end else begin
                    // Automatic state machine
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
                            // Clock gated but data retained
                            bank_power_enable[i] <= 1'b0;
                            bank_needs_reload[i] <= 1'b0;
                            
                            if (bank_active[i]) begin
                                // Wake up on access
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
                            // Fully power gated, data lost
                            bank_power_enable[i] <= 1'b0;
                            bank_needs_reload[i] <= 1'b1;
                            
                            if (bank_active[i]) begin
                                // Wake up on access (data needs reload)
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
