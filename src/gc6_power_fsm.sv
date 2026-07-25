
`default_nettype none
`timescale 1ns/1ns
import gridx_pkg::*;

module gc6_power_fsm #(
    parameter DRAIN_TIMEOUT   = 2048,
    parameter WAKE_TIMEOUT    = 1024,
    parameter RESTORE_TIMEOUT = 512
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        dcr_enter_req_i,
    input  wire        dcr_exit_req_i,
    input  wire        dcr_retention_i,
    input  wire [31:0] dcr_watchdog_thresh_i,

    input  wire        all_pipelines_empty_i,
    input  wire [6:0]  outstanding_mem_i,
    input  wire [3:0]  tensor_inflight_i,

    output reg         context_save_req_o,
    input  wire        context_save_ack_i,
    output reg         context_restore_req_o,
    input  wire        context_restore_ack_i,

    input  wire        pll_lock_i,

    output reg         power_gate_enable_o,
    output reg         clock_gate_enable_o,
    output reg         retention_enable_o,

    output reg  [2:0]  gc6_state_o,
    output reg         gc6_watchdog_fault_o,
    output wire        gc6_active_o,
    output wire        gc6_powered_off_o
);
    reg [31:0] drain_counter;
    reg [31:0] wake_counter;
    reg [31:0] restore_counter;
    reg        enter_req_latch;
    reg        exit_req_latch;
    wire [31:0] effective_wake_thresh = (dcr_watchdog_thresh_i != 0) ?
                                         dcr_watchdog_thresh_i :
                                         GC6_WAKE_WATCHDOG_DEF;
    assign gc6_active_o      = (gc6_state_o == GC6_ACTIVE);
    assign gc6_powered_off_o = (gc6_state_o == GC6_POWERED_OFF);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gc6_state_o          <= GC6_ACTIVE;
            gc6_watchdog_fault_o <= 1'b0;
            power_gate_enable_o  <= 1'b0;
            clock_gate_enable_o  <= 1'b0;
            retention_enable_o   <= 1'b0;
            context_save_req_o   <= 1'b0;
            context_restore_req_o<= 1'b0;
            drain_counter        <= 0;
            wake_counter         <= 0;
            restore_counter      <= 0;
            enter_req_latch      <= 1'b0;
            exit_req_latch       <= 1'b0;
        end else begin

            if (dcr_enter_req_i && gc6_state_o == GC6_ACTIVE)
                enter_req_latch <= 1'b1;
            if (dcr_exit_req_i && gc6_state_o == GC6_POWERED_OFF)
                exit_req_latch <= 1'b1;
            case (gc6_state_o)
                GC6_ACTIVE: begin
                    power_gate_enable_o  <= 1'b0;
                    clock_gate_enable_o  <= 1'b0;
                    context_save_req_o   <= 1'b0;
                    context_restore_req_o<= 1'b0;
                    gc6_watchdog_fault_o <= 1'b0;
                    if (enter_req_latch) begin
                        gc6_state_o     <= GC6_PRE_SLEEP;
                        enter_req_latch <= 1'b0;
                        context_save_req_o <= 1'b1;
                        retention_enable_o <= dcr_retention_i;
                    end
                end
                GC6_PRE_SLEEP: begin

                    if (context_save_ack_i) begin
                        context_save_req_o <= 1'b0;
                        gc6_state_o        <= GC6_DRAIN;
                        drain_counter      <= 0;
                    end
                end
                GC6_DRAIN: begin

                    drain_counter <= drain_counter + 1;
                    if (outstanding_mem_i == 0 && tensor_inflight_i == 0) begin
                        gc6_state_o         <= GC6_POWERED_OFF;
                        power_gate_enable_o <= 1'b1;
                        clock_gate_enable_o <= 1'b1;
                    end else if (drain_counter >= DRAIN_TIMEOUT) begin
                        gc6_state_o          <= GC6_POWERED_OFF;
                        power_gate_enable_o  <= 1'b1;
                        clock_gate_enable_o  <= 1'b1;
                        gc6_watchdog_fault_o <= 1'b1;
                    end
                end
                GC6_POWERED_OFF: begin

                    power_gate_enable_o <= 1'b1;
                    clock_gate_enable_o <= 1'b1;
                    if (exit_req_latch) begin
                        gc6_state_o         <= GC6_WAKING;
                        exit_req_latch      <= 1'b0;
                        power_gate_enable_o <= 1'b0;
                        wake_counter        <= 0;
                    end
                end
                GC6_WAKING: begin

                    wake_counter <= wake_counter + 1;
                    if (pll_lock_i) begin
                        gc6_state_o          <= GC6_RESTORING;
                        clock_gate_enable_o  <= 1'b0;
                        context_restore_req_o<= 1'b1;
                        restore_counter      <= 0;
                    end else if (wake_counter >= effective_wake_thresh) begin
                        gc6_watchdog_fault_o <= 1'b1;
                    end
                end
                GC6_RESTORING: begin

                    restore_counter <= restore_counter + 1;
                    if (context_restore_ack_i) begin
                        context_restore_req_o <= 1'b0;
                        gc6_state_o           <= GC6_ACTIVE;
                        retention_enable_o    <= 1'b0;
                    end else if (restore_counter >= RESTORE_TIMEOUT) begin
                        gc6_watchdog_fault_o <= 1'b1;
                    end
                end
                default: gc6_state_o <= GC6_ACTIVE;
            endcase
        end
    end
`ifdef VERILATOR
    always @(posedge clk) begin
        if (rst_n && gc6_watchdog_fault_o)
            $display("[GC6] WATCHDOG FAULT in state %d", gc6_state_o);
    end
`endif
endmodule
