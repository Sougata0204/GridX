// SIMT Execution Core
// This is the main SIMT compute core combining fetcher, decoder, ALU, registers, and LSU.
// I integrated the 4-thread execution pipeline and handled core-level reset signals
// so internal registers and state machines clear safely after a thread block completes.

`default_nettype none
`timescale 1ns/1ns
import gridx_pkg::*;

module core #(
    parameter DATA_MEM_ADDR_BITS = 8,
    parameter DATA_MEM_DATA_BITS = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter THREADS_PER_BLOCK = 4,
    parameter WARPS_PER_CORE = 1,
    parameter REG_WIDTH = 16
) (
    input wire clk,
    input wire reset,
    input wire start,
    input wire kernel_running,
    output wire done,
    input wire [7:0] block_id,
    input wire [$clog2(THREADS_PER_BLOCK):0] thread_count,
    output wire program_mem_read_valid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address,
    input wire program_mem_read_ready,
    input wire [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data,
    output wire mem_read_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] mem_read_address,
    input wire mem_read_ready,
    input wire [DATA_MEM_DATA_BITS-1:0] mem_read_data,
    output wire mem_write_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] mem_write_address,
    output wire [DATA_MEM_DATA_BITS-1:0] mem_write_data,
    input wire mem_write_ready,
    input wire power_sleep_req,
    output wire instr_retired,
    output wire perf_shared_mem_access,
    output wire perf_shared_mem_conflict,
    output wire perf_external_mem_access,
    output wire perf_alu_active,
    output wire perf_alu_idle,
    output wire perf_tensor_active,
    output wire perf_tensor_idle,
    output wire perf_stall_mem,
    output wire perf_stall_shared,
    output wire perf_stall_tensor,
    output wire perf_stall_dep,
    output wire perf_stall_ready,
    output wire perf_store_combined,
    output wire perf_early_wakeup,
    output wire perf_dual_issue_attempt,
    output wire perf_dual_issue_success,
    
    // Face Controller Interfaces (0:+X, 1:-X, 2:+Y, 3:-Y, 4:+Z, 5:-Z)
    output wire [5:0] face_req_valid,
    output wire [5:0] face_req_write,
    output wire [5:0][DATA_MEM_ADDR_BITS-1:0] face_req_addr,
    output wire [5:0][DATA_MEM_DATA_BITS-1:0] face_req_wdata,
    input  wire [5:0] face_req_ready,
    input  wire [5:0] face_resp_valid,
    input  wire [5:0][DATA_MEM_DATA_BITS-1:0] face_resp_rdata,
    output wire [5:0] face_resp_ready
);
    localparam THREADS_PER_WARP = THREADS_PER_BLOCK / WARPS_PER_CORE;
    localparam NUM_LANES = THREADS_PER_WARP;
    localparam WARP_ID_W = (WARPS_PER_CORE > 1) ? $clog2(WARPS_PER_CORE) : 1;

    wire [3:0] active_core_state;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] current_pc;

    assign instr_retired = (active_core_state == STATE_UPDATE);
    wire [3:0] warp_states [WARPS_PER_CORE-1:0];
    wire [WARP_ID_W-1:0] active_warp_id;
    wire [REG_WIDTH-1:0] rs [THREADS_PER_BLOCK-1:0];
    wire [REG_WIDTH-1:0] rt [THREADS_PER_BLOCK-1:0];
    wire [REG_WIDTH-1:0] rd_val [THREADS_PER_BLOCK-1:0];
    wire [1:0] lsu_state [THREADS_PER_BLOCK-1:0];
    wire [REG_WIDTH-1:0] lsu_out [THREADS_PER_BLOCK-1:0];
    wire [WARPS_PER_CORE-1:0] tensor_busy;
    wire [WARPS_PER_CORE-1:0] tensor_done;
    wire [15:0] instruction;
    wire [2:0] fetcher_state;
    wire [63:0] decoded_packet;
    wire [WARPS_PER_CORE-1:0] warp_issue_enable;
    reg [63:0] warp_instr_latch [WARPS_PER_CORE-1:0];
    wire sb_hazard;
    wire [1:0] sb_hazard_type;
    wire sb_query_valid;
    wire [$clog2(WARPS_PER_CORE > 1 ? WARPS_PER_CORE : 2)-1:0] sb_query_warp;
    wire [3:0] sb_query_rs, sb_query_rt, sb_query_rd;
    wire compute_issue, memory_issue;
    wire perf_alu_active_pulse;
    wire perf_alu_idle_pulse;
    wire perf_tensor_active_pulse;
    wire perf_tensor_idle_pulse;
    wire core_hang_detected;
    wire perf_stall_mem_pulse;
    wire perf_stall_shared_pulse;
    wire perf_stall_tensor_pulse;
    wire perf_stall_dep_pulse;
    wire perf_stall_ready_pulse;
    wire combined_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] combined_write_addr;
    wire [DATA_MEM_DATA_BITS-1:0] combined_write_data;
    wire combined_write_ready;
    wire [15:0] issue_active_mask;
    reg [15:0] warp_mask_latch [WARPS_PER_CORE-1:0];
    wire rb_resp_ready;
    wire rb_out_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] rb_out_addr;
    wire [DATA_MEM_DATA_BITS-1:0] rb_out_data;
    wire [WARPS_PER_CORE-1:0] rb_warp_can_resume;
    fetcher #(
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS)
    ) fetcher_instance (
        .clk(clk),
        .reset(reset),
        .core_state(active_core_state[2:0]),
        .current_pc(current_pc),
        .mem_read_valid(program_mem_read_valid),
        .mem_read_address(program_mem_read_address),
        .mem_read_ready(program_mem_read_ready),
        .mem_read_data(program_mem_read_data),
        .fetcher_state(fetcher_state),
        .instruction(instruction)
    );
    decoder decoder_instance (
        .core_state(active_core_state[2:0]),
        .instruction(instruction),
        .decoded_packet(decoded_packet)
    );
    wire [PROGRAM_MEM_ADDR_BITS-1:0] next_pc [THREADS_PER_BLOCK-1:0];
    wire tracker_enqueue_valid;
    wire [15:0] warp_rs_val = rs[active_warp_id * THREADS_PER_WARP];
    wire actual_tracker_enqueue_valid = tracker_enqueue_valid && (warp_rs_val >= 16'h2000);
    wire [3:0] tracker_enqueue_dest_reg;
    wire [15:0] tracker_enqueue_tag;
    wire tracker_dequeue_valid = rb_out_valid;
    wire [3:0] tracker_dequeued_dest_reg;
    wire tracker_dequeue_found;
    wire [WARPS_PER_CORE-1:0] tracker_warp_has_pending;
    wire [WARPS_PER_CORE-1:0] tracker_warp_queue_full;
    wire perf_dual_issue_attempt_pulse;
    wire perf_dual_issue_success_pulse;
    wire [63:0] dual_compute_packet, dual_memory_packet;
    wire dual_compute_valid, dual_memory_valid;
    dual_issue #(
        .WARP_ID_WIDTH(WARP_ID_W),
        .INSTR_WIDTH(16)
    ) issue_engine (
        .clk(clk),
        .reset(reset),
        .compute_queue_valid(active_core_state == STATE_ISSUE && !decoded_packet[32] && !decoded_packet[33]),
        .compute_queue_instr(instruction),
        .compute_queue_warp(active_warp_id),
        .memory_queue_valid(active_core_state == STATE_ISSUE && (decoded_packet[32] || decoded_packet[33])),
        .memory_queue_instr(instruction),
        .memory_queue_warp(active_warp_id),
        .sb_query_valid(sb_query_valid),
        .sb_query_warp(sb_query_warp),
        .sb_query_rs(sb_query_rs),
        .sb_query_rt(sb_query_rt),
        .sb_query_rd(sb_query_rd),
        .sb_hazard(sb_hazard),
        .compute_dispatch_ready(1'b1),
        .memory_dispatch_ready(1'b1),
        .compute_unit_busy(1'b0),
        .memory_unit_busy(1'b0),
        .perf_dual_issue_cycles(perf_dual_issue_success_pulse),
        .perf_single_compute_cycles(),
        .perf_single_memory_cycles(),
        .perf_no_issue_cycles()
    );
    scoreboard #(
        .NUM_WARPS(WARPS_PER_CORE),
        .NUM_REGS(16)
    ) core_scoreboard (
        .clk(clk),
        .reset(reset),
        .query_valid(active_core_state == STATE_DECODE || active_core_state == STATE_ISSUE || active_core_state == STATE_WAIT_REG),
        .query_warp_id(active_warp_id),
        .query_rs(decoded_packet[23:20]),
        .query_rt(decoded_packet[19:16]),
        .query_rd(decoded_packet[27:24]),
        .query_hazard(sb_hazard),
        .query_hazard_type(sb_hazard_type),
        .write_pending_set(active_core_state == STATE_ISSUE && decoded_packet[31] && !decoded_packet[32] && !decoded_packet[43]),
        .write_pending_warp(active_warp_id),
        .write_pending_reg(decoded_packet[27:24]),
        .write_complete(active_core_state == STATE_UPDATE && warp_instr_latch[active_warp_id][31]),
        .write_complete_warp(active_warp_id),
        .write_complete_reg(warp_instr_latch[active_warp_id][27:24]),
        .mem_load_start(active_core_state == STATE_ISSUE && decoded_packet[32] && (warp_rs_val >= 16'h2000)),
        .mem_load_warp(active_warp_id),
        .mem_load_dest_reg(decoded_packet[27:24]),
        .mem_load_complete(tracker_dequeue_found),
        .mem_load_complete_warp(active_warp_id),
        .mem_load_complete_reg(tracker_dequeued_dest_reg),
        .tensor_op_start(active_core_state == STATE_ISSUE && decoded_packet[43]),
        .tensor_op_warp(active_warp_id),
        .tensor_op_complete(|tensor_done),
        .tensor_op_complete_warp(active_warp_id),
        .perf_false_stalls_avoided(),
        .perf_true_dependency_stalls()
    );
    async_load_tracker #(
        .WARPS_PER_CORE(WARPS_PER_CORE),
        .MAX_OUTSTANDING_PER_WARP(4),
        .REG_ADDR_BITS(4)
    ) load_tracker (
        .clk(clk),
        .reset(reset),
        .enqueue_valid(actual_tracker_enqueue_valid),
        .enqueue_warp_id(active_warp_id),
        .enqueue_dest_reg(tracker_enqueue_dest_reg),
        .enqueue_tag(tracker_enqueue_tag),
        .dequeue_valid(tracker_dequeue_valid),
        .dequeue_warp_id(active_warp_id),
        .dequeue_tag(16'h0001),
        .dequeued_dest_reg(tracker_dequeued_dest_reg),
        .dequeue_found(tracker_dequeue_found),
        .warp_has_pending(tracker_warp_has_pending),
        .warp_queue_full(tracker_warp_queue_full),
        .pending_count()
    );
    scheduler #(
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .WARPS_PER_CORE(WARPS_PER_CORE),
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS)
    ) scheduler_instance (
        .clk(clk),
        .reset(reset),
        .start(start),
        .kernel_running(kernel_running),
        .tensor_done(tensor_done),
        .power_sleep_req(power_sleep_req),
        .decoded_packet(decoded_packet),
        .latched_packet(warp_instr_latch[active_warp_id]),
        .fetcher_state(fetcher_state),
        .lsu_state(lsu_state),
        .current_pc(current_pc),
        .next_pc(next_pc),
        .core_state(active_core_state),
        .warp_state(warp_states),
        .active_warp_id(active_warp_id),
        .warp_issue_enable(warp_issue_enable),
        .tracker_enqueue_valid(tracker_enqueue_valid),
        .tracker_enqueue_dest_reg(tracker_enqueue_dest_reg),
        .tracker_enqueue_tag(tracker_enqueue_tag),
        .tracker_dequeue_valid(tracker_dequeue_found),
        .tracker_dequeued_dest_reg(tracker_dequeued_dest_reg),
        .tracker_dequeue_found(tracker_dequeue_found),
        .tracker_warp_has_pending(tracker_warp_has_pending),
        .tracker_warp_queue_full(tracker_warp_queue_full),
        .sb_hazard(sb_hazard),
        .sb_hazard_type(sb_hazard_type),
        .perf_stall_mem_pulse(perf_stall_mem_pulse),
        .perf_stall_shared_pulse(perf_stall_shared_pulse),
        .perf_stall_tensor_pulse(perf_stall_tensor_pulse),
        .perf_stall_dep_pulse(perf_stall_dep_pulse),
        .perf_stall_ready_pulse(perf_stall_ready_pulse),
        .warp_early_wakeup(rb_warp_can_resume),
        .active_mask(issue_active_mask),
        .done(done)
    );
    integer w;
    always @(posedge clk) begin
        if (reset) begin
            for (w=0; w<WARPS_PER_CORE; w=w+1) warp_instr_latch[w] <= 0;
        end else begin
            for (w=0; w<WARPS_PER_CORE; w=w+1) begin
                if (warp_issue_enable[w]) begin
                    warp_instr_latch[w] <= decoded_packet;
                    warp_mask_latch[w] <= issue_active_mask;
                end
            end
        end
    end
    wire [63:0] active_warp_instr = warp_instr_latch[active_warp_id];
    wire [3:0] alu_arith_mux = active_warp_instr[40:37];
    wire alu_out_mux = active_warp_instr[39];
    genvar lane;
    wire [REG_WIDTH-1:0] lane_alu_out [NUM_LANES-1:0];
    generate
        for (lane = 0; lane < NUM_LANES; lane = lane + 1) begin : lanes
            reg [REG_WIDTH-1:0] lane_rs;
            reg [REG_WIDTH-1:0] lane_rt;
            always @(*) begin
                lane_rs = rs[active_warp_id * THREADS_PER_WARP + lane];
                lane_rt = rt[active_warp_id * THREADS_PER_WARP + lane];
            end
            alu #(
                .DATA_BITS(REG_WIDTH)
            ) alu_unit (
                .enable(active_core_state == STATE_EXECUTE),
                .alu_arith_mux(alu_arith_mux),
                .rs(lane_rs),
                .rt(lane_rt),
                .alu_out(lane_alu_out[lane]),
                .div_by_zero()
            );
        end
    endgenerate
    wire [THREADS_PER_BLOCK-1:0] resp_arbiter_grant;
    wire [THREADS_PER_BLOCK-1:0] lsu_req_valid;
    wire [THREADS_PER_BLOCK-1:0] lsu_pending;
    wire [THREADS_PER_BLOCK-1:0] lsu_req_write;
    wire [DATA_MEM_ADDR_BITS-1:0] lsu_req_addr [THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] lsu_req_data [THREADS_PER_BLOCK-1:0];
    wire [THREADS_PER_BLOCK-1:0] smem_req_valid;
    wire [12:0] smem_req_addr [THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] smem_req_wdata [THREADS_PER_BLOCK-1:0];
    wire [THREADS_PER_BLOCK-1:0] smem_req_ready;
    wire [DATA_MEM_DATA_BITS-1:0] smem_req_rdata [THREADS_PER_BLOCK-1:0];
    shared_memory #(
        .DATA_BITS(DATA_MEM_DATA_BITS),
        .ADDR_BITS(13),
        .NUM_WARPS(WARPS_PER_CORE),
        .THREADS_PER_WARP(THREADS_PER_WARP)
    ) sh_mem (
        .clk(clk),
        .reset(reset),
        .req_valid(smem_req_valid),
        .req_write(lsu_req_write),
        .req_addr(smem_req_addr),
        .req_wdata(lsu_req_data),
        .req_ready(smem_req_ready),
        .req_rdata(smem_req_rdata),
        .shared_mem_access_pulse(perf_shared_mem_access),
        .shared_mem_conflict_pulse(perf_shared_mem_conflict)
    );
    assign perf_external_mem_access = mem_read_valid || mem_write_valid;
    wire [THREADS_PER_BLOCK-1:0] arb_req_valid;
    wire [THREADS_PER_BLOCK-1:0] lsu_active_req;
    wire [THREADS_PER_BLOCK-1:0] resp_arb_req_valid;
    wire [THREADS_PER_BLOCK-1:0] req_arbiter_grant;
    reg [THREADS_PER_BLOCK-1:0] lsu_req_sent;

    genvar g;
    generate
        for (g = 0; g < THREADS_PER_BLOCK; g = g + 1) begin : arb_filter
            assign arb_req_valid[g] = lsu_req_valid[g] && (lsu_req_addr[g] >= 16'h2000);
            assign smem_req_valid[g] = lsu_req_valid[g] && (lsu_req_addr[g] < 16'h2000);
            assign smem_req_addr[g] = lsu_req_addr[g][12:0];
            assign lsu_active_req[g] = lsu_req_valid[g] && (lsu_req_addr[g] >= 16'h2000) && !lsu_req_sent[g];
            assign resp_arb_req_valid[g] = lsu_pending[g] && (lsu_req_addr[g] >= 16'h2000);
        end
    endgenerate
    wire arb_valid, arb_write;
    wire [DATA_MEM_ADDR_BITS-1:0] arb_addr;
    wire [DATA_MEM_DATA_BITS-1:0] arb_data;
    wire coalesced_req_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] coalesced_req_addr;
    wire [THREADS_PER_BLOCK-1:0] coalescer_grant;
    load_coalescer #(
        .LANES(THREADS_PER_BLOCK),
        .ADDR_WIDTH(DATA_MEM_ADDR_BITS)
    ) coalescer (
        .clk(clk),
        .reset(reset),
        .lane_valid(arb_req_valid),
        .lane_addr(lsu_req_addr),
        .lane_read_enable(1'b0),
        .coalesced_req_valid(coalesced_req_valid),
        .coalesced_req_addr(coalesced_req_addr),
        .coalesced_req_count(),
        .coalesced_lane_mask(),
        .coalesced_req_ready(1'b1),
        .resp_valid(1'b0),
        .resp_data('0),
        .lane_resp_valid(),
        .lane_resp_data(),
        .perf_coalesced_requests(),
        .perf_uncoalesced_requests(),
        .perf_bytes_saved()
    );
    
    always @(posedge clk) begin
        if (reset) begin
            lsu_req_sent <= 0;
        end else begin
            for (integer i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin
                if (!lsu_req_valid[i]) begin
                    lsu_req_sent[i] <= 1'b0;
                end else if (req_arbiter_grant[i]) begin
                    lsu_req_sent[i] <= 1'b1;
                end
            end
        end
    end

    lsu_arbiter #(
        .NUM_REQUESTERS(THREADS_PER_BLOCK),
        .ADDR_WIDTH(DATA_MEM_ADDR_BITS),
        .DATA_WIDTH(DATA_MEM_DATA_BITS)
    ) req_arbiter (
        .clk(clk),
        .reset(reset),
        .request_valid(lsu_active_req),
        .request_write(lsu_we),
        .request_addr(lsu_req_addr),
        .request_data(lsu_req_data),
        .mem_valid(arb_valid),
        .mem_write(arb_write),
        .mem_addr(arb_addr),
        .mem_data(arb_data),
        .mem_ready(1'b1),
        .grant(req_arbiter_grant)
    );

    lsu_arbiter #(
        .NUM_REQUESTERS(THREADS_PER_BLOCK),
        .ADDR_WIDTH(DATA_MEM_ADDR_BITS),
        .DATA_WIDTH(DATA_MEM_DATA_BITS),
        .IS_RESP(1)
    ) resp_arbiter (
        .clk(clk),
        .reset(reset),
        .request_valid(resp_arb_req_valid),
        .request_write(lsu_we),
        .request_addr(lsu_req_addr),
        .request_data(lsu_req_data),
        .mem_valid(),
        .mem_write(),
        .mem_addr(),
        .mem_data(),
        .mem_ready(rb_out_valid || mem_write_ready || l1_read_ready || l1_write_ready),
        .grant(resp_arbiter_grant)
    );
    wire l1_hit = (arb_addr >= 16'h2000 && arb_addr < 16'h8000);
    // Face hit: address bits [21:19] select face direction (1-6), 0 = normal BRAM path
    wire [2:0] arb_face_sel = arb_addr[21:19];
    wire face_hit = (arb_face_sel >= 3'd1) && (arb_face_sel <= 3'd6);
    wire l1_read_ready, l1_write_ready;
    wire [DATA_MEM_DATA_BITS-1:0] l1_read_data;
    core_local_memory #(
        .ADDR_WIDTH(15),
        .DATA_WIDTH(DATA_MEM_DATA_BITS)
    ) l1_memory (
        .clk(clk),
        .reset(reset),
        .read_valid(arb_valid && !arb_write && l1_hit),
        .read_address(arb_addr[14:0]),
        .write_valid(arb_valid && arb_write && l1_hit),
        .write_address(arb_addr[14:0]),
        .write_data(arb_data),
        .read_ready(l1_read_ready),
        .read_data(l1_read_data),
        .write_ready(l1_write_ready)
    );
    assign mem_read_valid = arb_valid && !arb_write && !l1_hit && !face_hit;
    assign mem_read_address = arb_addr;
    store_combiner #(
        .ADDR_WIDTH(DATA_MEM_ADDR_BITS),
        .DATA_WIDTH(DATA_MEM_DATA_BITS)
    ) external_store_combiner (
        .clk(clk),
        .reset(reset),
        .store_valid(arb_valid && arb_write && !l1_hit && !face_hit),
        .store_addr(arb_addr),
        .store_data(arb_data),
        .store_ready(),
        .combined_valid(mem_write_valid),
        .combined_addr(mem_write_address),
        .combined_data(mem_write_data),
        .combined_ready(mem_write_ready),
        .store_warp_id(active_warp_id),
        .fence_instruction(1'b0),
        .kernel_end(done),
        .load_pending(1'b0),
        .combined_mask(),
        .combined_count(),
        .perf_stores_combined(perf_store_combined_pulse),
        .perf_stores_received(),
        .perf_flush_events()
    );
    response_buffer #(
        .BUFFER_DEPTH(4),
        .NUM_WARPS(WARPS_PER_CORE)
    ) external_response_buffer (
        .clk(clk),
        .reset(reset),
        .resp_valid(mem_read_ready),
        .resp_addr(mem_read_address),
        .resp_data(mem_read_data),
        .resp_warp_id(active_warp_id),
        .resp_ready(rb_resp_ready),
        .warp_has_pending_load(tracker_warp_has_pending),
        .warp_pending_count(),
        .out_valid(rb_out_valid),
        .out_addr(rb_out_addr),
        .out_data(rb_out_data),
        .out_warp_id(),
        .out_ready(1'b1),
        .warp_can_resume(rb_warp_can_resume),
        .perf_early_wakeups(perf_early_wakeup_pulse),
        .perf_total_responses(),
        .perf_buffer_full_stalls()
    );
    wire [DATA_MEM_DATA_BITS-1:0] mem_read_data_internal;
    wire mem_read_ready_internal;
    wire mem_write_ready_internal;
    assign mem_read_ready_internal = l1_hit ? l1_read_ready : rb_out_valid;
    assign mem_read_data_internal = l1_hit ? l1_read_data : rb_out_data;
    assign mem_write_ready_internal = l1_hit ? l1_write_ready : mem_write_ready;
    wire signed [3:0][3:0][15:0] tensor_src_a;
    wire signed [3:0][3:0][15:0] tensor_src_b;
    wire [3:0][3:0][31:0] tensor_wb_data;
    wire tensor_wb_valid;
    wire [1:0] tensor_wb_warp;
    wire [3:0] writeback_reg_idx;
    genvar tr, tc;
    generate
        for (tr=0; tr<4; tr=tr+1) begin : rows
            for (tc=0; tc<4; tc=tc+1) begin : cols
                 localparam int TIDX = tr*4 + tc;
                 if (TIDX < THREADS_PER_WARP) begin : valid_lane
                     wire [7:0] r_val = rs[active_warp_id * THREADS_PER_WARP + TIDX][7:0];
                     wire [7:0] t_val = rt[active_warp_id * THREADS_PER_WARP + TIDX][7:0];
                     assign tensor_src_a[tr][tc] = {{8{r_val[7]}}, r_val};
                     assign tensor_src_b[tr][tc] = {{8{t_val[7]}}, t_val};
                 end else begin : zero_lane
                     assign tensor_src_a[tr][tc] = 16'd0;
                     assign tensor_src_b[tr][tc] = 16'd0;
                 end
            end
        end
    endgenerate
    tensor_controller #(
        .NUM_WARPS(WARPS_PER_CORE),
        .NUM_UNITS(4)
    ) t_ctrl (
        .clk(clk),
        .reset(reset),
        .request_valid(active_core_state == STATE_ISSUE && decoded_packet[43]),
        .warp_id(active_warp_id),
        .dest_reg_idx(decoded_packet[27:24]),
        .src_a(tensor_src_a),
        .src_b(tensor_src_b),
        .src_c(512'd0),
        .imm(decoded_packet[15:0]),
        .request_ready(),
        .warp_busy(tensor_busy),
        .warp_done(tensor_done),
        .writeback_valid(tensor_wb_valid),
        .writeback_warp_id(tensor_wb_warp),
        .writeback_data(tensor_wb_data),
        .writeback_reg_idx(writeback_reg_idx)
    );
    compute_utilization utilization_tracker (
        .clk(clk),
        .reset(reset),
        .core_active(kernel_running),
        .alu_enable(active_core_state == STATE_EXECUTE),
        .alu_executing(active_core_state == STATE_EXECUTE),
        .tensor_busy(|tensor_busy),
        .tensor_executing(|tensor_done),
        .alu_active_pulse(perf_alu_active_pulse),
        .alu_idle_pulse(perf_alu_idle_pulse),
        .tensor_active_pulse(perf_tensor_active_pulse),
        .tensor_idle_pulse(perf_tensor_idle_pulse)
    );
    assign perf_alu_active   = perf_alu_active_pulse;
    assign perf_alu_idle     = perf_alu_idle_pulse;
    assign perf_tensor_active = perf_tensor_active_pulse;
    assign perf_tensor_idle   = perf_tensor_idle_pulse;
    assign perf_stall_mem    = perf_stall_mem_pulse;
    assign perf_stall_shared = perf_stall_shared_pulse;
    assign perf_stall_tensor = perf_stall_tensor_pulse;
    assign perf_stall_dep    = perf_stall_dep_pulse;
    assign perf_stall_ready  = perf_stall_ready_pulse;
    wire perf_store_combined_pulse;
    wire perf_early_wakeup_pulse;
    assign perf_store_combined = perf_store_combined_pulse;
    assign perf_early_wakeup   = perf_early_wakeup_pulse;
    // Declared early so always_ff blocks below can use them
    assign perf_dual_issue_attempt = (active_core_state == STATE_ISSUE);
    assign perf_dual_issue_success = perf_dual_issue_success_pulse;
    forward_progress #(
        .WATCHDOG_CYCLES(32768)
    ) progress_watchdog (
        .clk(clk),
        .reset(reset),
        .warp_active(|warp_issue_enable),
        .warp_made_progress(instr_retired),
        .assert_warp_timeout(core_hang_detected),
        .mem_req_issued(1'b0),
        .mem_req_id('0),
        .mem_req_completed(1'b0),
        .mem_completed_id('0),
        .timeout_detected(),
        .timeout_warp_id(),
        .pending_mem_requests(),
        .dump_trigger(),
        .stalled_warps(),
        .warp_stall_cycles(),
        .assert_mem_leak()
    );
    wire [THREADS_PER_BLOCK-1:0] lsu_we;
    genvar t;
    generate
        for (t = 0; t < THREADS_PER_BLOCK; t = t + 1) begin : threads
            localparam warp_idx = t / THREADS_PER_WARP;
            localparam lane_idx = t % THREADS_PER_WARP;
            wire use_bypass = warp_issue_enable[warp_idx];
            wire [63:0] my_instr = use_bypass ? decoded_packet : warp_instr_latch[warp_idx];
            wire [15:0] my_mask_bits = use_bypass ? issue_active_mask : warp_mask_latch[warp_idx];
            wire my_thread_active = my_mask_bits[lane_idx];
            wire [15:0] my_imm      = my_instr[15:0];
            wire [3:0]  my_rt_addr  = my_instr[19:16];
            wire [3:0]  my_rs_addr  = my_instr[23:20];
            wire [3:0]  my_rd_addr  = my_instr[27:24];
            wire        my_reg_we   = my_instr[31];
            wire        my_mem_re   = my_instr[32];
            wire        my_mem_we   = my_instr[33];
            assign lsu_we[t] = my_mem_we && my_thread_active;
            wire [1:0]  my_reg_mux  = my_instr[36:35];
            wire [1:0] my_row = lane_idx / 4;
            wire [1:0] my_col = lane_idx % 4;
            wire my_force_en = tensor_wb_valid && (warp_idx == tensor_wb_warp);
            wire [REG_WIDTH-1:0] my_force_data = tensor_wb_data[my_row][my_col][REG_WIDTH-1:0];
            wire [2:0] mapped_state =
                (warp_states[warp_idx] == STATE_EXECUTE)     ? 3'b100 :
                (warp_states[warp_idx] == STATE_UPDATE)      ? 3'b110 :
                (warp_states[warp_idx] == STATE_ISSUE)       ? 3'b011 :
                (warp_states[warp_idx] == STATE_STALLED_MEM) ? 3'b011 :
                3'b000;
            registers #(
                 .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
                 .THREAD_ID(t),
                 .DATA_BITS(REG_WIDTH)
            ) reg_file (
                .clk(clk),
                .reset(reset),
                .enable(1'b1),
                .block_id(block_id),
                .core_state(mapped_state),
                .decoded_rd_address(my_rd_addr),
                .decoded_rs_address(my_rs_addr),
                .decoded_rt_address(my_rt_addr),
                .decoded_immediate(my_imm),
                .decoded_reg_write_enable(my_reg_we && my_thread_active),
                .decoded_reg_input_mux(my_reg_mux),
                .force_reg_write_enable(my_force_en),
                .force_reg_write_dest(writeback_reg_idx),
                .force_reg_write_data(my_force_data),
                .alu_out(lane_alu_out[lane_idx]),
                .lsu_out(lsu_out[t]),
                .rs(rs[t]),
                .rt(rt[t]),
                .rd_val(rd_val[t])
            );
            wire [2:0]  my_nzp       = my_instr[30:28];
            wire        my_nzp_we    = my_instr[34];
            wire        my_pc_mux    = my_instr[41];
            pc #(
                .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
                .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS)
            ) pc_inst (
                .clk(clk),
                .reset(reset),
                .enable(t < thread_count),
                .core_state(mapped_state),
                .decoded_nzp(my_nzp),
                .decoded_imm(my_imm[PROGRAM_MEM_ADDR_BITS-1:0]),
                .nzp_we(my_nzp_we),
                .pc_mux(my_pc_mux),
                .alu_out(lane_alu_out[lane_idx]),
                .current_pc(current_pc),
                .next_pc(next_pc[t])
            );
            wire my_grant = resp_arbiter_grant[t];
            wire my_read_ready = (my_grant && !lsu_we[t] && mem_read_ready_internal);
            wire my_write_ready = (my_grant && lsu_we[t] && mem_write_ready_internal);
            wire my_read_val, my_write_val;
            wire [DATA_MEM_ADDR_BITS-1:0] lsu_req_rd_addr;
            wire [DATA_MEM_ADDR_BITS-1:0] lsu_req_wr_addr;
            assign lsu_req_addr[t] = lsu_we[t] ? lsu_req_wr_addr : lsu_req_rd_addr;
            assign lsu_req_valid[t] = my_read_val || my_write_val;
            assign lsu_req_write[t] = my_write_val;
            wire is_smem = (rs[t] < 16'h2000);
            wire is_local_addr = (rs[t] < 16'h8000);
            wire thr_read_ready  = is_smem ? smem_req_ready[t]  : (my_grant && !lsu_we[t] && mem_read_ready_internal);
            wire thr_write_ready = is_smem ? smem_req_ready[t]  : (my_grant && lsu_we[t] && mem_write_ready_internal);
            wire [DATA_MEM_DATA_BITS-1:0] thr_read_data = is_smem ? smem_req_rdata[t] : mem_read_data_internal;
            // synthesis translate_off
            reg [31:0] thr_debug_cnt;
            always @(posedge clk) begin
                if (reset) thr_debug_cnt <= 32'd0;
                else        thr_debug_cnt <= thr_debug_cnt + 32'd1;
                if (!reset && (thr_debug_cnt < 350) && (t == 0)) begin
                    $display("[THREAD-0] Cycle %0d: thr_read_ready=%b is_smem=%b lsu_we0=%b mem_read_ready_internal=%b",
                             thr_debug_cnt, thr_read_ready, is_smem, lsu_we[t], mem_read_ready_internal);
                end
            end
            // synthesis translate_on
            lsu #(
                .ADDR_BITS(DATA_MEM_ADDR_BITS),
                .MEM_DATA_WIDTH(DATA_MEM_DATA_BITS),
                .REG_WIDTH(REG_WIDTH)
            ) lsu_inst (
                .clk(clk),
                .reset(reset),
                .enable(1'b1),
                .core_state(mapped_state),
                .decoded_mem_read_enable(my_mem_re && my_thread_active),
                .decoded_mem_write_enable(my_mem_we && my_thread_active),
                .is_local(is_local_addr),
                .mem_read_valid(my_read_val),
                .mem_read_address(lsu_req_rd_addr),
                .mem_read_ready(thr_read_ready),
                .mem_read_data(thr_read_data),
                .mem_write_valid(my_write_val),
                .mem_write_ready(thr_write_ready),
                .mem_write_address(lsu_req_wr_addr),
                .mem_write_data(lsu_req_data[t]),
                .rs(rs[t]),
                .rt(rt[t]),
                .lsu_state(lsu_state[t]),
                .lsu_out(lsu_out[t]),
                .lsu_pending(lsu_pending[t])
            );
        end
    endgenerate
`ifdef DEBUG
    reg [31:0] core_debug_counter;
    always @(posedge clk) begin
        if (reset) core_debug_counter <= 0;
        else core_debug_counter <= core_debug_counter + 1;
        if (!reset && (core_debug_counter < 350)) begin
            if (active_core_state == STATE_ISSUE) begin
                $display("[T_DEBUG] Cycle %d: PC=%x rs[0]=%h rt[0]=%h rd[0]=%h rs_addr=%d warp_rs_val=%h enqueue_valid=%b actual_enqueue_valid=%b",
                         core_debug_counter, current_pc, rs[0], rt[0], rd_val[0], decoded_packet[23:20], warp_rs_val, tracker_enqueue_valid, actual_tracker_enqueue_valid);
            end
            $display("[CORE] Cycle %0d: ArbValid=%b LsuReqValid[0]=%b ArbAddr=%x L1Hit=%b MemReadValid=%b MemReadReady=%b LsuReqAddr0=%h LsuState0=%d lsu_active_req0=%b lsu_we0=%b",
                     core_debug_counter, arb_valid, lsu_req_valid[0], arb_addr, l1_hit, mem_read_valid, mem_read_ready, lsu_req_addr[0], lsu_state[0], lsu_active_req[0], lsu_we[0]);
            $display("[CORE] WarpState[0]=%d WarpIssueEn[0]=%b WarpLatch[0][32]=%b decoded_pkt[32]=%b active_core_st=%d lsu_state0=%d",
                     warp_states[0], warp_issue_enable[0], warp_instr_latch[0][32], decoded_packet[32], active_core_state, lsu_state[0]);
            if (actual_tracker_enqueue_valid) begin
                $display("[CORE-LT] Cycle %d ENQUEUE: dest_reg=%d tag=%h",
                         core_debug_counter, tracker_enqueue_dest_reg, tracker_enqueue_tag);
            end
            if (tracker_dequeue_valid || tracker_dequeue_found) begin
                $display("[CORE-LT] Cycle %d DEQUEUE: deq_val=%b deq_found=%b dest_reg=%d",
                         core_debug_counter, tracker_dequeue_valid, tracker_dequeue_found, tracker_dequeued_dest_reg);
            end
            if (mem_read_ready) begin
                $display("[CORE-MEM] Cycle %d MEM_RD_READY: data=%h", core_debug_counter, mem_read_data);
            end
        end
    end
`endif
    // Volumetric Face Controllers & Routing
    // The core's external memory requests (which miss L1) are routed to the
    // appropriate 3D face based on the address map.
    // Address [21:19] selects the target:
    // 3'd0: Normal external BRAM path (mem_read_valid / mem_write_valid)
    // 3'd1: +X face  (Face 0)
    // 3'd2: -X face  (Face 1)
    // 3'd3: +Y face  (Face 2)
    // 3'd4: -Y face  (Face 3)
    // 3'd5: +Z face  (Face 4)
    // 3'd6: -Z face  (Face 5)
    // 3'd7: Reserved

    wire face_arb_valid = arb_valid && !l1_hit && face_hit;
    wire face_arb_write = arb_write;

    wire [5:0] fc_core_req_valid;
    wire [5:0] fc_core_req_ready;
    wire [5:0] fc_core_resp_valid;
    wire [5:0][DATA_MEM_DATA_BITS-1:0] fc_core_resp_rdata;

    genvar f;
    generate
        for (f = 0; f < 6; f = f + 1) begin : gen_face_controllers
            
            // Face f corresponds to arb_face_sel == (f+1)
            assign fc_core_req_valid[f] = face_arb_valid && (arb_face_sel == (f + 1));
            
            face_controller #(
                .ADDR_WIDTH(DATA_MEM_ADDR_BITS),
                .DATA_WIDTH(DATA_MEM_DATA_BITS),
                .BUFFER_DEPTH(4),
                .FACE_ID(f),
                .CREDIT_COUNT(4)
            ) face_ctrl (
                .clk(clk),
                .reset(reset),
                
                // Core-side - driven directly from arbiter, not from mem_* ports
                .core_req_valid(fc_core_req_valid[f]),
                .core_req_write(face_arb_write),
                .core_req_addr(arb_addr),
                .core_req_wdata(arb_data),
                .core_req_ready(fc_core_req_ready[f]),
                
                .core_resp_valid(fc_core_resp_valid[f]),
                .core_resp_rdata(fc_core_resp_rdata[f]),
                .core_resp_ready(1'b1),
                
                // Sheet-side
                .sheet_req_valid(face_req_valid[f]),
                .sheet_req_write(face_req_write[f]),
                .sheet_req_addr(face_req_addr[f]),
                .sheet_req_wdata(face_req_wdata[f]),
                .sheet_req_ready(face_req_ready[f]),
                
                .sheet_resp_valid(face_resp_valid[f]),
                .sheet_resp_rdata(face_resp_rdata[f]),
                .sheet_resp_ready(face_resp_ready[f]),
                
                .credits_available(),
                .fc_busy()
            );
        end
    endgenerate

endmodule
