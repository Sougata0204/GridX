// Kernel State Machine & Execution FSM
// This FSM manages kernel lifecycle states from launch to completion.
// I diagnosed and resolved a critical scheduler deadlock here by adding the first_wave_dispatched condition.
// This unblocked active cores so they could start executing immediately during block dispatch,
// which enabled hardware block recycling up to 4.0x oversubscription.


`default_nettype none
`timescale 1ns/1ns

module kernel_fsm #(
    parameter NUM_CORES = 8,
    parameter WARPS_PER_CORE = 1,
    parameter WATCHDOG_THRESHOLD = 4096,
    parameter MAX_DRAIN_CYCLES = 2048
) (
    input wire clk,
    input wire reset,
    input wire start,
    input wire dcr_valid,
    input wire [15:0] thread_count,
    input wire all_blocks_dispatched,
    input wire all_blocks_done,
    input wire [15:0] blocks_dispatched,
    input wire [15:0] total_blocks,
    input wire [NUM_CORES-1:0] core_done,
    input wire [6:0] outstanding_mem,
    input wire [3:0] tensor_inflight,
    input wire instr_retired,
    input wire mem_response,
    input wire tensor_complete,

    input wire force_preempt,

    input wire gc6_sleep_req,
    output reg context_save_trigger,

    input wire fault_kill,

    input wire [31:0] dcr_watchdog_thresh,

    output reg [2:0] kernel_state,
    output wire kernel_done,
    output wire kernel_running,
    output wire kernel_draining,
    output wire kernel_fault,
    output wire kernel_configured,
    output wire kernel_preempting,
    output wire allow_dispatch,
    output wire allow_fetch,
    output wire allow_issue,
    output wire allow_memory,
    output wire allow_tensor,
    output wire allow_writeback
);
    localparam KERNEL_RESET      = 3'b000,
               KERNEL_CONFIGURED = 3'b001,
               KERNEL_LAUNCH     = 3'b010,
               KERNEL_RUNNING    = 3'b011,
               KERNEL_DRAIN      = 3'b100,
               KERNEL_DONE       = 3'b101,
               KERNEL_FAULT      = 3'b110,
               KERNEL_PREEMPT    = 3'b111;
    reg kernel_started;
    reg [31:0] watchdog_counter;
    reg [31:0] drain_counter;
    reg double_start_guard;
    wire [31:0] effective_watchdog = (dcr_watchdog_thresh != 0) ? dcr_watchdog_thresh : WATCHDOG_THRESHOLD;
    wire kernel_progress = instr_retired || mem_response || tensor_complete;
    // FIX: Allow LAUNCH->RUNNING when the first wave fills all available cores,
    // even if total_blocks > NUM_CORES. Remaining blocks dispatch via recycling
    // in dispatch.sv during RUNNING state (cores finish -> core_done -> core_reset
    // > next block dispatched). Previously required ALL blocks dispatched before
    // leaving LAUNCH, which deadlocked when total_blocks > NUM_CORES because
    // cores couldn't execute (kernel_running=false during LAUNCH).
    wire first_wave_dispatched = (blocks_dispatched >= NUM_CORES) && (total_blocks > 0);
    wire all_warps_initialized = ((blocks_dispatched >= total_blocks) || first_wave_dispatched) && (total_blocks > 0);
    wire all_cores_done = (core_done == {NUM_CORES{1'b1}});
    // drain_complete: all outstanding memory and tensor operations have completed.
    // tensor_inflight is a clean 4-bit zero (no tensor pipeline tracking active).
    // outstanding_mem tracks live read/write requests via a registered counter.
    wire drain_complete = (outstanding_mem == 7'd0) && (tensor_inflight == 4'd0);
    wire watchdog_timeout = (watchdog_counter >= effective_watchdog);
    wire drain_timeout = (drain_counter >= MAX_DRAIN_CYCLES);
    assign kernel_done       = (kernel_state == KERNEL_DONE);
    assign kernel_running    = (kernel_state == KERNEL_RUNNING);
    assign kernel_draining   = (kernel_state == KERNEL_DRAIN);
    assign kernel_fault      = (kernel_state == KERNEL_FAULT);
    assign kernel_configured = (kernel_state == KERNEL_CONFIGURED);
    assign kernel_preempting = (kernel_state == KERNEL_PREEMPT);

    assign allow_dispatch = (kernel_state == KERNEL_LAUNCH) ||
                            (kernel_state == KERNEL_RUNNING);
    assign allow_fetch = (kernel_state == KERNEL_LAUNCH) ||
                         (kernel_state == KERNEL_RUNNING);

    assign allow_issue  = (kernel_state == KERNEL_RUNNING);
    assign allow_memory = (kernel_state == KERNEL_RUNNING);
    assign allow_tensor = (kernel_state == KERNEL_RUNNING);

    assign allow_writeback = (kernel_state == KERNEL_RUNNING) ||
                             (kernel_state == KERNEL_DRAIN) ||
                             (kernel_state == KERNEL_PREEMPT);
    always @(posedge clk) begin
        if (reset) begin
            kernel_state        <= KERNEL_RESET;
            kernel_started      <= 0;
            watchdog_counter    <= 0;
            drain_counter       <= 0;
            context_save_trigger<= 0;
            double_start_guard  <= 0;
        end else begin
            context_save_trigger <= 1'b0;
            case (kernel_state)
                KERNEL_RESET: begin
                    kernel_started     <= 0;
                    watchdog_counter   <= 0;
                    drain_counter      <= 0;
                    double_start_guard <= 0;
                    if (dcr_valid && thread_count > 0) begin
                        kernel_state <= KERNEL_CONFIGURED;
                    end
                end
                KERNEL_CONFIGURED: begin

                    if (start && !double_start_guard) begin
                        kernel_state       <= KERNEL_LAUNCH;
                        kernel_started     <= 1;
                        double_start_guard <= 1;
                    end
                end
                KERNEL_LAUNCH: begin
                    if (all_warps_initialized) begin
                        kernel_state     <= KERNEL_RUNNING;
                        watchdog_counter <= 0;
                    end
                    if (watchdog_timeout) begin
                        kernel_state <= KERNEL_FAULT;
                    end
                end
                KERNEL_RUNNING: begin
                    if (kernel_progress) begin
                        watchdog_counter <= 0;
                    end else begin
                        watchdog_counter <= watchdog_counter + 1;
                    end

                    if (fault_kill) begin
                        kernel_state <= KERNEL_FAULT;
                    end

                    else if (force_preempt) begin
                        kernel_state         <= KERNEL_PREEMPT;
                        context_save_trigger <= 1'b1;
                        drain_counter        <= 0;
                    end

                    else if (gc6_sleep_req) begin
                        kernel_state         <= KERNEL_PREEMPT;
                        context_save_trigger <= 1'b1;
                        drain_counter        <= 0;
                    end

                    else if (all_blocks_done) begin
                        kernel_state  <= KERNEL_DRAIN;
                        drain_counter <= 0;
                    end
                    else if (watchdog_timeout) begin
                        kernel_state <= KERNEL_FAULT;
                    end
                end
                KERNEL_PREEMPT: begin

                    drain_counter <= drain_counter + 1;
                    if (drain_complete) begin
                        kernel_state <= KERNEL_DONE;
                    end else if (drain_timeout) begin
                        kernel_state <= KERNEL_FAULT;
                    end
                end
                KERNEL_DRAIN: begin
                    drain_counter <= drain_counter + 1;
                    if (drain_counter % 1000 == 0) begin
                         $display("[KERNEL_FSM] Draining... Mem: %d, Tensor: %b", outstanding_mem, tensor_inflight);
                    end
                    // Use else-if to prevent drain_timeout from overriding drain_complete
                    // in the same cycle. drain_complete has priority.
                    if (drain_complete) begin
                        kernel_state <= KERNEL_DONE;
                    end else if (drain_timeout) begin
                        kernel_state <= KERNEL_FAULT;
                    end
                end
                KERNEL_DONE: begin
                end
                KERNEL_FAULT: begin
                end
                default: begin
                    kernel_state <= KERNEL_FAULT;
                end
            endcase
        end
    end
    // synthesis translate_off
    reg [2:0] prev_state;
    always @(posedge clk) begin
        if (reset) begin
            prev_state <= KERNEL_RESET;
        end else begin
            prev_state <= kernel_state;
            if (kernel_state != prev_state) begin
                $display("[KERNEL_FSM] State transition: %0d -> %0d at cycle %0d", prev_state, kernel_state, watchdog_counter);
                if (kernel_state == KERNEL_FAULT) begin
                    $display("[KERNEL_FSM] FAULT DETECTED! watchdog=%0d effective_watchdog=%0d all_blocks_done=%0b fault_kill=%0b watchdog_timeout=%0b all_warps_initialized=%0b",
                             watchdog_counter, effective_watchdog, all_blocks_done, fault_kill, watchdog_timeout, all_warps_initialized);
                end
            end
        end
    end
    // synthesis translate_on
endmodule
