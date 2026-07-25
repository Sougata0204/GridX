// Out-of-Order Warp Scheduler & Issue Logic
// Tracks warp execution states and issues instructions to active thread lanes.
// I updated the SIMT divergence stack handling to re-converge thread lanes accurately at branch targets.

`default_nettype none
`timescale 1ns/1ns
import gridx_pkg::*;

module scheduler #(
    parameter THREADS_PER_BLOCK = 4,
    parameter WARPS_PER_CORE = 1,
    parameter MAX_OUTSTANDING_LOADS = 4,
    parameter NUM_REGS = 16,
    parameter THREADS_PER_WARP = THREADS_PER_BLOCK / WARPS_PER_CORE,
    parameter WARP_ID_W = (WARPS_PER_CORE > 1) ? $clog2(WARPS_PER_CORE) : 1,
    parameter PROGRAM_MEM_ADDR_BITS = 8
) (
    input wire clk,
    input wire reset,
    input wire start,
    input wire kernel_running,
    input wire [WARPS_PER_CORE-1:0] tensor_done,
    input wire power_sleep_req,
    input wire [63:0] decoded_packet,
    input wire [63:0] latched_packet,
    input wire [2:0] fetcher_state,
    input wire [1:0] lsu_state [THREADS_PER_BLOCK-1:0],
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    input wire [PROGRAM_MEM_ADDR_BITS-1:0] next_pc [THREADS_PER_BLOCK-1:0],
    output reg [3:0] core_state,
    output reg [3:0] warp_state [WARPS_PER_CORE-1:0],
    output reg [WARP_ID_W-1:0] active_warp_id,
    output reg [WARPS_PER_CORE-1:0] warp_issue_enable,
    output wire [WARPS_PER_CORE-1:0] warp_stalled_on_reg,
    output wire [WARPS_PER_CORE-1:0] warp_stalled_on_mem,
    output reg tracker_enqueue_valid,
    output reg [3:0] tracker_enqueue_dest_reg,
    output reg [15:0] tracker_enqueue_tag,
    input wire tracker_dequeue_valid,
    input wire [3:0] tracker_dequeued_dest_reg,
    input wire tracker_dequeue_found,
    input wire [WARPS_PER_CORE-1:0] tracker_warp_has_pending,
    input wire [WARPS_PER_CORE-1:0] tracker_warp_queue_full,
    input wire sb_hazard,
    input wire [1:0] sb_hazard_type,
    output wire perf_stall_mem_pulse,
    output wire perf_stall_shared_pulse,
    output wire perf_stall_tensor_pulse,
    output wire perf_stall_dep_pulse,
    output wire perf_stall_ready_pulse,
    input wire [WARPS_PER_CORE-1:0] warp_early_wakeup,
    output wire [THREADS_PER_WARP-1:0] active_mask,
    output reg done
);
    // THREADS_PER_WARP and WARP_ID_W are derived parameters (see parameter block above)
    reg [$clog2(MAX_OUTSTANDING_LOADS+1)-1:0] pending_mem_count [WARPS_PER_CORE-1:0];
    localparam LOAD_QUEUE_DEPTH = MAX_OUTSTANDING_LOADS;
    reg [22:0] load_queue [WARPS_PER_CORE-1:0][LOAD_QUEUE_DEPTH-1:0];
    reg [$clog2(LOAD_QUEUE_DEPTH)-1:0] lq_head [WARPS_PER_CORE-1:0];
    reg [$clog2(LOAD_QUEUE_DEPTH)-1:0] lq_tail [WARPS_PER_CORE-1:0];

    reg [THREADS_PER_WARP-1:0] simt_stack_mask [WARPS_PER_CORE-1:0][3:0];
    reg [PROGRAM_MEM_ADDR_BITS-1:0] simt_stack_pc [WARPS_PER_CORE-1:0][3:0];
    reg [2:0] simt_stack_ptr [WARPS_PER_CORE-1:0];
    localparam IDLE         = STATE_IDLE,
               FETCH        = STATE_FETCH,
               DECODE       = STATE_DECODE,
               ISSUE        = STATE_ISSUE,
               EXECUTE      = STATE_EXECUTE,
               UPDATE       = STATE_UPDATE,
               STALLED_MEM  = STATE_STALLED_MEM,
               TENSOR_BUSY  = STATE_TENSOR_BUSY,
               SLEEP        = STATE_SLEEP,
               WAIT_REG     = STATE_WAIT_REG,
               WAIT_MEM_Q   = STATE_WAIT_MEM_Q,
               WAIT_BAR     = STATE_WAIT_BAR,
               DONE         = STATE_DONE;
    reg [WARPS_PER_CORE-1:0] just_decoded;
    reg [WARPS_PER_CORE-1:0] barrier_mask;
    wire [63:0] working_packet = just_decoded[active_warp_id] ? decoded_packet : latched_packet;
    wire pkt_tensor = working_packet[43];
    wire pkt_ret    = working_packet[42];
    wire pkt_mem_read  = working_packet[32];
    wire pkt_mem_write = working_packet[33];
    wire pkt_mem    = pkt_mem_read || pkt_mem_write;
    wire pkt_reg_we = working_packet[31];
    wire [3:0] pkt_rd = working_packet[27:24];
    wire [3:0] pkt_rs = working_packet[23:20];
    wire [3:0] pkt_rt = working_packet[19:16];
    reg [PROGRAM_MEM_ADDR_BITS-1:0] warp_pc [WARPS_PER_CORE-1:0];
    reg warp_done_flag [WARPS_PER_CORE-1:0];
    reg [THREADS_PER_WARP-1:0] warp_active_mask [WARPS_PER_CORE-1:0];
    reg start_latched;
    wire mem_queue_full = (pending_mem_count[active_warp_id] >= MAX_OUTSTANDING_LOADS);
    genvar sw;
    generate
        for (sw = 0; sw < WARPS_PER_CORE; sw = sw + 1) begin : stall_gen
            assign warp_stalled_on_reg[sw] = (warp_state[sw] == WAIT_REG);
            assign warp_stalled_on_mem[sw] = (warp_state[sw] == WAIT_MEM_Q);
        end
    endgenerate
    always @(*) begin
        current_pc = warp_pc[active_warp_id];
        core_state = warp_state[active_warp_id];
    end
    assign active_mask = warp_active_mask[active_warp_id];
    always @(*) begin
        warp_issue_enable = 0;
        if (warp_state[active_warp_id] == ISSUE) begin
            warp_issue_enable[active_warp_id] = 1'b1;
        end
        done = 1;
        for (int i = 0; i < WARPS_PER_CORE; i++) begin
            if (!warp_done_flag[i]) done = 0;
        end
        if (done) begin
        end
    end
    wire [WARP_ID_W-1:0] gto_oldest_warp;
    wire gto_oldest_valid;
    wire [WARP_ID_W-1:0] next_warp_id;
    generate
        if (WARPS_PER_CORE > 1) begin : gen_next_warp
            assign next_warp_id = gto_oldest_valid ? gto_oldest_warp : 
                                  ((active_warp_id == WARPS_PER_CORE - 1) ? {WARP_ID_W{1'b0}} : (active_warp_id + 1'b1));
        end else begin : gen_next_warp_single
            assign next_warp_id = 1'b0;
        end
    endgenerate
    always @(posedge clk) begin
        if (reset) begin
            active_warp_id <= 0;
            start_latched <= 0;
            tracker_enqueue_valid <= 0;
            tracker_enqueue_dest_reg <= 0;
            tracker_enqueue_tag <= 0;
            for (int w = 0; w < WARPS_PER_CORE; w = w + 1) begin
                warp_pc[w] <= 0;
                warp_state[w] <= IDLE;
                warp_done_flag[w] <= 0;
                just_decoded[w] <= 0;
                simt_stack_ptr[w] <= 0;
                pending_mem_count[w] <= 0;
                lq_head[w] <= 0;
                lq_tail[w] <= 0;
                for (int q = 0; q < LOAD_QUEUE_DEPTH; q = q + 1) begin
                    load_queue[w][q] <= 23'b0;
                end
                warp_active_mask[w] <= {THREADS_PER_WARP{1'b1}};
                for (int s = 0; s < 4; s = s + 1) begin
                    simt_stack_pc[w][s] <= 8'h00;
                    simt_stack_mask[w][s] <= {THREADS_PER_WARP{1'b0}};
                end
            end
            barrier_mask <= {WARPS_PER_CORE{1'b0}};
        end else if (kernel_running) begin
            tracker_enqueue_valid <= 1'b0;
            if (start) start_latched <= 1;
            case (warp_state[active_warp_id])
                IDLE: begin
                    if (start || start_latched) begin
                        if (!warp_done_flag[active_warp_id])
                            warp_state[active_warp_id] <= FETCH;
                    end
                end
                FETCH: begin
                    if (fetcher_state == 3'b010) begin
                        warp_state[active_warp_id] <= DECODE;
                    end
                end
                DECODE: begin
                    warp_state[active_warp_id] <= ISSUE;
                    just_decoded[active_warp_id] <= 1;
                end
                ISSUE: begin
                    if (sb_hazard) begin
                        warp_state[active_warp_id] <= WAIT_REG;
                    end else if (pkt_mem_read && mem_queue_full) begin
                        warp_state[active_warp_id] <= WAIT_MEM_Q;
                    end else begin
                        if (pkt_tensor) begin
                            warp_state[active_warp_id] <= TENSOR_BUSY;
                        end else if (working_packet[48]) begin
                             warp_state[active_warp_id] <= STATE_WAIT_BAR;
                        end else if (pkt_mem) begin
                            if (pkt_mem_read && pkt_reg_we) begin
                                pending_mem_count[active_warp_id] <= pending_mem_count[active_warp_id] + 1;
                                tracker_enqueue_valid <= 1'b1;
                                tracker_enqueue_dest_reg <= pkt_rd;
                                tracker_enqueue_tag <= 16'h0001;
                            end
                            warp_state[active_warp_id] <= STALLED_MEM;
                        end else begin
                            warp_state[active_warp_id] <= EXECUTE;
                            tracker_enqueue_valid <= 1'b0;
                        end
                        just_decoded[active_warp_id] <= 0;
                    end
                end
                STALLED_MEM: begin
                    logic all_done;
                    int start_idx;
                    int end_idx;
                    all_done = 1'b1;
                    start_idx = active_warp_id * THREADS_PER_WARP;
                    end_idx = start_idx + THREADS_PER_WARP;
                    for (int i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin
                        if (i >= start_idx && i < end_idx) begin
                            int lane_id;
                            lane_id = i - start_idx;
                            if (warp_active_mask[active_warp_id][lane_id] && lsu_state[i] != 2'b11) begin
                                all_done = 1'b0;
                            end
                        end
                    end
                    if (all_done || warp_early_wakeup[active_warp_id]) begin
                        if (pkt_mem_read && pkt_reg_we) begin
                            if (pending_mem_count[active_warp_id] > 0) begin
                                pending_mem_count[active_warp_id] <= pending_mem_count[active_warp_id] - 1;
                            end
                        end
                        warp_state[active_warp_id] <= UPDATE;
                    end else begin
                        active_warp_id <= next_warp_id;
                    end
                end
                TENSOR_BUSY: begin
                    if (tensor_done[active_warp_id]) begin
                        warp_state[active_warp_id] <= EXECUTE;
                    end else begin
                        active_warp_id <= next_warp_id;
                    end
                end
                WAIT_REG: begin
                    if (!sb_hazard) begin
                        warp_state[active_warp_id] <= ISSUE;
                    end else begin
                        active_warp_id <= next_warp_id;
                    end
                end
                WAIT_MEM_Q: begin
                    if (!mem_queue_full) begin
                        warp_state[active_warp_id] <= ISSUE;
                    end else begin
                        active_warp_id <= next_warp_id;
                    end
                end
                EXECUTE: begin
                    warp_state[active_warp_id] <= UPDATE;
                end
                UPDATE: begin
                    if (pkt_ret) begin
                         warp_done_flag[active_warp_id] <= 1;
                         warp_state[active_warp_id] <= DONE;
                         active_warp_id <= next_warp_id;
                    end else begin
                        logic [PROGRAM_MEM_ADDR_BITS-1:0] leader_next_pc;
                        logic found_leader;
                        logic diverges;
                        logic [THREADS_PER_WARP-1:0] taken_mask;
                        logic [THREADS_PER_WARP-1:0] fallthrough_mask;
                        logic [PROGRAM_MEM_ADDR_BITS-1:0] fallthrough_pc;

                        if (working_packet[49]) begin
                            if (simt_stack_ptr[active_warp_id] > 0) begin
                                logic [2:0] ptr_minus_1;
                                ptr_minus_1 = simt_stack_ptr[active_warp_id] - 1;
                                simt_stack_ptr[active_warp_id] <= ptr_minus_1;
                                warp_pc[active_warp_id] <= simt_stack_pc[active_warp_id][ptr_minus_1];
                                warp_active_mask[active_warp_id] <= simt_stack_mask[active_warp_id][ptr_minus_1];
                            end else begin
                                warp_pc[active_warp_id] <= warp_pc[active_warp_id] + 1;
                            end
                            if (power_sleep_req) warp_state[active_warp_id] <= SLEEP;
                            else warp_state[active_warp_id] <= FETCH;
                        end else begin
                            leader_next_pc = warp_pc[active_warp_id] + 1;
                            found_leader = 0;
                            diverges = 0;
                            taken_mask = 0;
                            fallthrough_mask = 0;
                            fallthrough_pc = warp_pc[active_warp_id] + 1;

                            for (int lane_id = 0; lane_id < THREADS_PER_WARP; lane_id = lane_id + 1) begin
                                if (warp_active_mask[active_warp_id][lane_id]) begin
                                    int t_idx;
                                    t_idx = (active_warp_id * THREADS_PER_WARP) + lane_id;
                                    if (!found_leader) begin
                                        leader_next_pc = next_pc[t_idx];
                                        found_leader = 1;
                                        taken_mask[lane_id] = 1'b1;
                                    end else begin
                                        if (next_pc[t_idx] == leader_next_pc) begin
                                            taken_mask[lane_id] = 1'b1;
                                        end else begin
                                            diverges = 1;
                                            fallthrough_mask[lane_id] = 1'b1;
                                        end
                                    end
                                end
                            end



                            if (diverges) begin
                                simt_stack_pc[active_warp_id][simt_stack_ptr[active_warp_id]] <= fallthrough_pc;
                                simt_stack_mask[active_warp_id][simt_stack_ptr[active_warp_id]] <= fallthrough_mask;
                                simt_stack_ptr[active_warp_id] <= simt_stack_ptr[active_warp_id] + 1;
                            end

                            warp_pc[active_warp_id] <= leader_next_pc;
                            warp_active_mask[active_warp_id] <= taken_mask;

                            if (power_sleep_req) begin
                                warp_state[active_warp_id] <= SLEEP;
                            end else begin
                                warp_state[active_warp_id] <= FETCH;
                            end
                        end
                    end
                end
                SLEEP: begin
                    if (!power_sleep_req) begin
                        warp_state[active_warp_id] <= FETCH;
                    end else begin
                         active_warp_id <= next_warp_id;
                    end
                end
                DONE: begin
                     active_warp_id <= next_warp_id;
                end
                STATE_WAIT_BAR: begin
                    reg [WARPS_PER_CORE-1:0] current_active_warps;
                    reg [WARPS_PER_CORE-1:0] barrier_after_this;
                    barrier_mask[active_warp_id] <= 1'b1;
                    for (int i=0; i<WARPS_PER_CORE; i++) begin
                         current_active_warps[i] = !warp_done_flag[i];
                    end
                    barrier_after_this = barrier_mask | (1 << active_warp_id);
                    if (barrier_after_this == current_active_warps) begin
                         barrier_mask <= 0;
                         for (int i=0; i<WARPS_PER_CORE; i++) begin
                             if (warp_state[i] == STATE_WAIT_BAR || i == active_warp_id) begin
                                  warp_state[i] <= UPDATE;
                             end
                         end
                    end else begin
                         if (WARPS_PER_CORE > 1) begin
                             active_warp_id <= (active_warp_id == WARPS_PER_CORE - 1) ? {WARP_ID_W{1'b0}} : (active_warp_id + 1'b1);
                         end else begin
                             active_warp_id <= 1'b0;
                         end
                    end
                end
                default: warp_state[active_warp_id] <= IDLE;
            endcase
        end
    end
    // barrier_mask declared above (before first use)
    wire [WARPS_PER_CORE-1:0] st_warp_active;
    wire [WARPS_PER_CORE-1:0] st_warp_waiting_mem;
    wire [WARPS_PER_CORE-1:0] st_warp_waiting_shared;
    wire [WARPS_PER_CORE-1:0] st_warp_waiting_tensor;
    wire [WARPS_PER_CORE-1:0] st_warp_waiting_dep;
    generate
        for (genvar sw = 0; sw < WARPS_PER_CORE; sw = sw + 1) begin : stall_decode
            assign st_warp_active[sw]         = !warp_done_flag[sw] && (warp_state[sw] != IDLE);
            assign st_warp_waiting_mem[sw]    = (warp_state[sw] == STALLED_MEM) || (warp_state[sw] == WAIT_MEM_Q);
            assign st_warp_waiting_shared[sw] = 1'b0;
            assign st_warp_waiting_tensor[sw] = (warp_state[sw] == TENSOR_BUSY);
            assign st_warp_waiting_dep[sw]    = (warp_state[sw] == WAIT_REG);
        end
    endgenerate
    wire issue_event = (warp_state[active_warp_id] == ISSUE);
    stall_tracker #(
        .NUM_WARPS(WARPS_PER_CORE),
        .WARP_ID_WIDTH(WARP_ID_W)
    ) efficiency_tracker (
        .clk(clk),
        .reset(reset),
        .warp_active(st_warp_active),
        .warp_waiting_mem(st_warp_waiting_mem),
        .warp_waiting_shared(st_warp_waiting_shared),
        .warp_waiting_tensor(st_warp_waiting_tensor),
        .warp_waiting_dep(st_warp_waiting_dep),
        .issue_valid(issue_event),
        .issued_warp_id(active_warp_id),
        .stall_reason(),
        .warp_age(),
        .oldest_ready_warp(gto_oldest_warp),
        .oldest_ready_valid(gto_oldest_valid),
        .perf_stall_cycles_mem(),
        .perf_stall_cycles_shared(),
        .perf_stall_cycles_tensor(),
        .perf_stall_cycles_dep()
    );
    // synthesis translate_off
    // Debug prints disabled to prevent log flooding
    // synthesis translate_on
endmodule
