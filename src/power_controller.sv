
`default_nettype none
`timescale 1ns/1ns

module powerController #(
    parameter NUM_BANKS = 8,
    parameter idleCycles = 16,
    parameter SLEEP_CYCLES = 256,
    parameter COUNTER_WIDTH = 32
) (
    input wire clk,
    input wire reset,
    input wire [NUM_BANKS-1:0] bankActive,
    input wire [NUM_BANKS-1:0] forceEnable,
    input wire [NUM_BANKS-1:0] forceSleep,
    output reg [NUM_BANKS-1:0] bankPowerEnable,
    output reg [1:0] bankPowerState [NUM_BANKS-1:0],
    output reg [NUM_BANKS-1:0] bankNeedsReload,
    output reg [COUNTER_WIDTH-1:0] totalActiveCycles,
    output reg [COUNTER_WIDTH-1:0] totalIdleCycles,
    output reg [COUNTER_WIDTH-1:0] totalSleepCycles,
    output reg [COUNTER_WIDTH-1:0] stateTransitions,
    output reg [NUM_BANKS-1:0] bankWasActive
);
    localparam STATE_SLEEP  = 2'b00;
    localparam STATE_IDLE   = 2'b01;
    localparam STATE_ACTIVE = 2'b10;
    reg [15:0] idleCounter [NUM_BANKS-1:0];
    reg [15:0] sleepCounter [NUM_BANKS-1:0];
    reg [1:0] prevBankState [NUM_BANKS-1:0];
    genvar b;
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            bankPowerEnable <= {NUM_BANKS{1'b1}};
            bankNeedsReload <= {NUM_BANKS{1'b0}};
            bankWasActive <= {NUM_BANKS{1'b0}};
            totalActiveCycles <= 0;
            totalIdleCycles <= 0;
            totalSleepCycles <= 0;
            stateTransitions <= 0;
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                bankPowerState[i] <= STATE_ACTIVE;
                prevBankState[i] <= STATE_ACTIVE;
                idleCounter[i] <= 0;
                sleepCounter[i] <= 0;
            end
        end else begin
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                case (bankPowerState[i])
                    STATE_ACTIVE: totalActiveCycles <= totalActiveCycles + 1;
                    STATE_IDLE:   totalIdleCycles <= totalIdleCycles + 1;
                    STATE_SLEEP:  totalSleepCycles <= totalSleepCycles + 1;
                endcase
                if (bankPowerState[i] != prevBankState[i]) begin
                    stateTransitions <= stateTransitions + 1;
                end
                prevBankState[i] <= bankPowerState[i];
                bankWasActive[i] <= bankActive[i];
            end
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                if (forceSleep[i]) begin
                    bankPowerState[i] <= STATE_SLEEP;
                    bankPowerEnable[i] <= 1'b0;
                    bankNeedsReload[i] <= 1'b1;
                    idleCounter[i] <= 0;
                    sleepCounter[i] <= 0;
                end else if (forceEnable[i]) begin
                    bankPowerState[i] <= STATE_ACTIVE;
                    bankPowerEnable[i] <= 1'b1;
                    idleCounter[i] <= 0;
                    sleepCounter[i] <= 0;
                end else begin
                    case (bankPowerState[i])
                        STATE_ACTIVE: begin
                            bankPowerEnable[i] <= 1'b1;
                            bankNeedsReload[i] <= 1'b0;
                            if (bankActive[i]) begin
                                idleCounter[i] <= 0;
                            end else begin
                                idleCounter[i] <= idleCounter[i] + 1;
                                if (idleCounter[i] >= idleCycles) begin
                                    bankPowerState[i] <= STATE_IDLE;
                                    idleCounter[i] <= 0;
                                end
                            end
                        end
                        STATE_IDLE: begin
                            bankPowerEnable[i] <= 1'b0;
                            bankNeedsReload[i] <= 1'b0;
                            if (bankActive[i]) begin
                                bankPowerState[i] <= STATE_ACTIVE;
                                bankPowerEnable[i] <= 1'b1;
                                sleepCounter[i] <= 0;
                            end else begin
                                sleepCounter[i] <= sleepCounter[i] + 1;
                                if (sleepCounter[i] >= SLEEP_CYCLES) begin
                                    bankPowerState[i] <= STATE_SLEEP;
                                    bankNeedsReload[i] <= 1'b1;
                                    sleepCounter[i] <= 0;
                                end
                            end
                        end
                        STATE_SLEEP: begin
                            bankPowerEnable[i] <= 1'b0;
                            bankNeedsReload[i] <= 1'b1;
                            if (bankActive[i]) begin
                                bankPowerState[i] <= STATE_ACTIVE;
                                bankPowerEnable[i] <= 1'b1;
                            end
                        end
                        default: begin
                            bankPowerState[i] <= STATE_ACTIVE;
                        end
                    endcase
                end
            end
        end
    end
endmodule
