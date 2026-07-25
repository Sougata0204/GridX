// GPU Core Array & Subsystem Top
// This module instantiates the core array, block dispatcher, and kernel state machine.
// I wired the core active gating and core_reset_w signals to ensure cores get properly reset
// between recycled thread blocks without breaking execution flow.
`default_nettype none
`timescale 1ns/1ns

module gpu #(
    parameter DATA_MEM_ADDR_BITS = 22,
    parameter DATA_MEM_DATA_BITS = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 12,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter PROGRAM_MEM_NUM_CHANNELS = 8,
    parameter NUM_CORES = 8,
    parameter THREADS_PER_BLOCK = 4,
    parameter WARPS_PER_CORE = 1,
    parameter CUBE_X = 2,
    parameter CUBE_Y = 2,
    parameter CUBE_Z = 2
) (
    input wire clk,
    input wire reset,
    input wire start,
    output wire done,
    input wire device_control_write_enable,
    input wire [15:0] device_control_data,

    output wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_valid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address [PROGRAM_MEM_NUM_CHANNELS-1:0],
    input wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_ready,
    input wire [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data [PROGRAM_MEM_NUM_CHANNELS-1:0],

    output wire [NUM_CORES-1:0] core_mem_read_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] core_mem_read_address [NUM_CORES-1:0],
    input  wire [NUM_CORES-1:0] core_mem_read_ready,
    input  wire [DATA_MEM_DATA_BITS-1:0] core_mem_read_data [NUM_CORES-1:0],

    output wire [NUM_CORES-1:0] core_mem_write_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] core_mem_write_address [NUM_CORES-1:0],
    output wire [DATA_MEM_DATA_BITS-1:0] core_mem_write_data [NUM_CORES-1:0],
    input  wire [NUM_CORES-1:0] core_mem_write_ready,
    output wire [2:0] kernel_state_o,

    // Face Controller Interfaces per Core
    output wire [NUM_CORES-1:0][5:0] core_face_req_valid,
    output wire [NUM_CORES-1:0][5:0] core_face_req_write,
    output wire [NUM_CORES-1:0][5:0][DATA_MEM_ADDR_BITS-1:0] core_face_req_addr,
    output wire [NUM_CORES-1:0][5:0][DATA_MEM_DATA_BITS-1:0] core_face_req_wdata,
    input  wire [NUM_CORES-1:0][5:0] core_face_req_ready,

    input  wire [NUM_CORES-1:0][5:0] core_face_resp_valid,
    input  wire [NUM_CORES-1:0][5:0][DATA_MEM_DATA_BITS-1:0] core_face_resp_rdata,
    output wire [NUM_CORES-1:0][5:0] core_face_resp_ready
);

    wire [15:0] thread_count;
    wire dcr_valid;
    wire [2:0] kernel_state;
    wire kernel_running;
    wire kernel_draining;
    wire kernel_fault;
    wire kernel_preempting;
    wire allow_dispatch_gate;
    wire [15:0] blocks_dispatched;
    wire [15:0] blocks_done_count;
    wire [15:0] total_blocks;
    wire all_blocks_dispatched;
    wire all_blocks_done;
    wire [6:0] outstanding_mem;
    wire [4:0] outstanding_pmem;
    wire [3:0] tensor_inflight = 4'b0000;  // No tensor pipeline tracking - default to idle (4-bit clean)
    wire instr_retired;
    wire mem_response;
    wire tensor_complete;
    wire [NUM_CORES-1:0] core_start;
    wire [NUM_CORES-1:0] core_reset_w;
    wire [NUM_CORES-1:0] core_done;
    wire [7:0] core_block_id [NUM_CORES-1:0];
    wire [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES-1:0];
    wire [NUM_CORES-1:0] core_instr_retired;
    wire [NUM_CORES-1:0] core_perf_smem_access;
    wire [NUM_CORES-1:0] core_perf_smem_conflict;
    wire [NUM_CORES-1:0] core_perf_ext_access;
    wire [NUM_CORES-1:0] core_perf_alu_active;
    wire [NUM_CORES-1:0] core_perf_alu_idle;
    wire [NUM_CORES-1:0] core_perf_tensor_active;
    wire [NUM_CORES-1:0] core_perf_tensor_idle;
    wire [NUM_CORES-1:0] core_perf_stall_mem;
    wire [NUM_CORES-1:0] core_perf_stall_shared;
    wire [NUM_CORES-1:0] core_perf_stall_tensor;
    wire [NUM_CORES-1:0] core_perf_stall_dep;
    wire [NUM_CORES-1:0] core_perf_stall_ready;
    wire [NUM_CORES-1:0] core_perf_store_combined;
    wire [NUM_CORES-1:0] core_perf_early_wakeup;
    wire [NUM_CORES-1:0] core_perf_dual_issue_attempt;
    wire [NUM_CORES-1:0] core_perf_dual_issue_success;
    assign instr_retired = |core_instr_retired;
    assign mem_response = |core_mem_read_ready | |core_mem_write_ready;
    assign kernel_state_o = kernel_state;

    wire gc6_context_save_req;
    wire gc6_context_restore_req;
    wire gc6_power_gate;
    wire gc6_clock_gate;
    wire [2:0] gc6_state;
    wire gc6_watchdog_fault;
    wire gc6_active;
    wire gc6_powered_off;
    wire kernel_context_save_trigger;

    wire fault_interrupt;
    wire fault_kill_kernel;
    wire ch_all_idle;
    wire perf_clock_enable;
    wire [1:0] perf_level;

    localparam NUM_FETCHERS = NUM_CORES;
    wire [NUM_FETCHERS-1:0] fetcher_read_valid;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] fetcher_read_address [NUM_FETCHERS-1:0];
    wire [NUM_FETCHERS-1:0] fetcher_read_ready;
    wire [PROGRAM_MEM_DATA_BITS-1:0] fetcher_read_data [NUM_FETCHERS-1:0];

    dcr dcr_instance (
        .clk(clk),
        .reset(reset),
        .device_control_write_enable(device_control_write_enable),
        .device_control_data(device_control_data),
        .thread_count(thread_count),
        .dcr_valid(dcr_valid)
    );

    reg [6:0] outstanding_mem_reg;
    always @(posedge clk or posedge reset) begin
        if (reset) outstanding_mem_reg <= 7'd0;
        else begin
            outstanding_mem_reg <= outstanding_mem_reg
                + (|core_mem_read_valid  ? 1'd1 : 1'd0)
                - (|core_mem_read_ready  ? 1'd1 : 1'd0)
                + (|core_mem_write_valid ? 1'd1 : 1'd0)
                - (|core_mem_write_ready ? 1'd1 : 1'd0);
        end
    end
    assign outstanding_mem = outstanding_mem_reg;

    controller #(
        .ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .NUM_CONSUMERS(NUM_FETCHERS),
        .NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS),
        .WRITE_ENABLE(0)
    ) program_memory_controller (
        .clk(clk),
        .reset(reset),
        .consumer_read_valid(fetcher_read_valid),
        .consumer_read_address(fetcher_read_address),
        .consumer_read_ready(fetcher_read_ready),
        .consumer_read_data(fetcher_read_data),
        .mem_read_valid(program_mem_read_valid),
        .mem_read_address(program_mem_read_address),
        .mem_read_ready(program_mem_read_ready),
        .mem_read_data(program_mem_read_data),
        .pending_transactions(outstanding_pmem)
    );

    kernel_fsm #(
        .NUM_CORES(NUM_CORES),
        .WARPS_PER_CORE(WARPS_PER_CORE),
        .WATCHDOG_THRESHOLD(8192),
        .MAX_DRAIN_CYCLES(4096)
    ) kernel_control (
        .clk(clk),
        .reset(reset),
        .start(start),
        .dcr_valid(dcr_valid),
        .thread_count(thread_count),
        .all_blocks_dispatched(all_blocks_dispatched),
        .all_blocks_done(all_blocks_done),
        .blocks_dispatched(blocks_dispatched),
        .total_blocks(total_blocks),
        .core_done(core_done),
        .outstanding_mem(outstanding_mem),
        .tensor_inflight(tensor_inflight),
        .instr_retired(instr_retired),
        .mem_response(mem_response),
        .tensor_complete(1'b0),
        .force_preempt(1'b0),
        .gc6_sleep_req(gc6_context_save_req),
        .context_save_trigger(kernel_context_save_trigger),
        .fault_kill(fault_kill_kernel),
        .dcr_watchdog_thresh(32'd0),
        .kernel_state(kernel_state),
        .kernel_done(done),
        .kernel_running(kernel_running),
        .kernel_draining(kernel_draining),
        .kernel_fault(kernel_fault),
        .kernel_preempting(kernel_preempting),
        .allow_dispatch(allow_dispatch_gate),
        .allow_fetch(),
        .allow_issue(),
        .allow_memory(),
        .allow_tensor(),
        .allow_writeback()
    );

    gc6_power_fsm #(
        .DRAIN_TIMEOUT(2048),
        .WAKE_TIMEOUT(1024),
        .RESTORE_TIMEOUT(512)
    ) gc6_ctrl (
        .clk(clk),
        .rst_n(!reset),
        .dcr_enter_req_i(1'b0),
        .dcr_exit_req_i(1'b0),
        .dcr_retention_i(1'b1),
        .dcr_watchdog_thresh_i(32'd0),
        .all_pipelines_empty_i(1'b1),
        .outstanding_mem_i(outstanding_mem),
        .tensor_inflight_i(tensor_inflight),
        .context_save_req_o(gc6_context_save_req),
        .context_save_ack_i(kernel_context_save_trigger),
        .context_restore_req_o(gc6_context_restore_req),
        .context_restore_ack_i(1'b0),
        .pll_lock_i(1'b1),
        .power_gate_enable_o(gc6_power_gate),
        .clock_gate_enable_o(gc6_clock_gate),
        .retention_enable_o(),
        .gc6_state_o(gc6_state),
        .gc6_watchdog_fault_o(gc6_watchdog_fault),
        .gc6_active_o(gc6_active),
        .gc6_powered_off_o(gc6_powered_off)
    );

    fault_handler #(
        .FIFO_DEPTH(16),
        .ADDR_WIDTH(32)
    ) fault_ctrl (
        .clk(clk),
        .rst_n(!reset),
        .fault_valid_i(1'b0),
        .fault_addr_i(32'h0),
        .fault_type_i(2'h0),
        .fault_warp_id_i(5'h0),
        .fault_core_id_i(4'h0),
        .fault_thread_mask_i(6'h0),
        .dcr_fault_mode_i(2'h0),
        .dcr_fault_clear_i(1'b0),
        .fault_interrupt_o(fault_interrupt),
        .fault_kill_kernel_o(fault_kill_kernel),
        .fault_mask_thread_o(),
        .dcr_fault_head_o(),
        .dcr_fault_head_meta_o(),
        .dcr_fault_drop_count_o(),
        .dcr_fault_fifo_depth_o(),
        .fifo_empty_o(),
        .fifo_full_o()
    );

    channel_scheduler #(
        .NUM_CHANNELS(8)
    ) ch_sched (
        .clk(clk),
        .rst_n(!reset),
        .ch_runnable_i(8'h01),
        .ch_priority_i(16'h0),
        .ch_block_done_i(8'h0),
        .dcr_timeslice_p0_i(32'd256),
        .dcr_timeslice_p1_i(32'd512),
        .dcr_timeslice_p2_i(32'd1024),
        .dcr_timeslice_p3_i(32'd2048),
        .dcr_aging_thresh_i(32'd4096),
        .ch_running_o(),
        .ch_state_o(),
        .ch_preempt_o(),
        .ch_aged_promotion_o(),
        .all_channels_idle_o(ch_all_idle),
        .active_channel_o()
    );

    perf_boost_controller perf_ctrl (
        .clk(clk),
        .rst_n(!reset),
        .alu_active_pulse_i(|core_perf_alu_active),
        .tensor_active_pulse_i(|core_perf_tensor_active),
        .kernel_active_i(kernel_running),
        .dcr_force_level_i(2'd0),
        .dcr_force_en_i(1'b0),
        .dcr_up_thresh_i(8'd75),
        .dcr_down_thresh_i(8'd25),
        .dcr_sample_win_i(32'd1024),
        .perf_level_o(perf_level),
        .clock_enable_o(perf_clock_enable),
        .total_active_cycles_o(),
        .total_sample_cycles_o()
    );

    dispatch #(
        .NUM_CORES(NUM_CORES),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK)
    ) dispatch_instance (
        .clk(clk),
        .reset(reset),
        .start(start),
        .kernel_running(allow_dispatch_gate),
        .thread_count(thread_count),
        .core_done(core_done),
        .core_start(core_start),
        .core_reset(core_reset_w),
        .core_block_id(core_block_id),
        .core_thread_count(core_thread_count),
        .blocks_dispatched_out(blocks_dispatched),
        .blocks_done_out(blocks_done_count),
        .total_blocks_out(total_blocks),
        .all_blocks_dispatched(all_blocks_dispatched),
        .all_blocks_done      (all_blocks_done)
    );

    genvar i;
    generate
        for (i = 0; i < NUM_CORES; i = i + 1) begin : cores
            core #(
                .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
                .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
                .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
                .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
                .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
                .WARPS_PER_CORE(WARPS_PER_CORE)
            ) core_instance (
                .clk(clk),
                .reset(core_reset_w[i]),
                .start(core_start[i]),
                .kernel_running(kernel_running),
                .done(core_done[i]),
                .instr_retired(core_instr_retired[i]),
                .block_id(core_block_id[i]),
                .thread_count(core_thread_count[i]),
                .program_mem_read_valid(fetcher_read_valid[i]),
                .program_mem_read_address(fetcher_read_address[i]),
                .program_mem_read_ready(fetcher_read_ready[i]),
                .program_mem_read_data(fetcher_read_data[i]),
                .mem_read_valid(core_mem_read_valid[i]),
                .mem_read_address(core_mem_read_address[i]),
                .mem_read_ready(core_mem_read_ready[i]),
                .mem_read_data(core_mem_read_data[i]),
                .mem_write_valid(core_mem_write_valid[i]),
                .mem_write_address(core_mem_write_address[i]),
                .mem_write_data(core_mem_write_data[i]),
                .mem_write_ready(core_mem_write_ready[i]),
                .perf_shared_mem_access(core_perf_smem_access[i]),
                .perf_shared_mem_conflict(core_perf_smem_conflict[i]),
                .perf_external_mem_access(core_perf_ext_access[i]),
                .perf_alu_active(core_perf_alu_active[i]),
                .perf_alu_idle(core_perf_alu_idle[i]),
                .perf_tensor_active(core_perf_tensor_active[i]),
                .perf_tensor_idle(core_perf_tensor_idle[i]),
                .perf_stall_mem(core_perf_stall_mem[i]),
                .perf_stall_shared(core_perf_stall_shared[i]),
                .perf_stall_tensor(core_perf_stall_tensor[i]),
                .perf_stall_dep(core_perf_stall_dep[i]),
                .perf_stall_ready(core_perf_stall_ready[i]),
                .perf_store_combined(core_perf_store_combined[i]),
                .perf_early_wakeup(core_perf_early_wakeup[i]),
                .perf_dual_issue_attempt(core_perf_dual_issue_attempt[i]),
                .perf_dual_issue_success(core_perf_dual_issue_success[i]),
                
                // Face Controller Interfaces
                .face_req_valid(core_face_req_valid[i]),
                .face_req_write(core_face_req_write[i]),
                .face_req_addr(core_face_req_addr[i]),
                .face_req_wdata(core_face_req_wdata[i]),
                .face_req_ready(core_face_req_ready[i]),
                .face_resp_valid(core_face_resp_valid[i]),
                .face_resp_rdata(core_face_resp_rdata[i]),
                .face_resp_ready(core_face_resp_ready[i])
            );
        end
    endgenerate

    kernel_perf_model perf_model (
        .clk(clk),
        .reset(reset),
        .kernel_active(kernel_running),
        .alu_active_pulse(|core_perf_alu_active),
        .alu_idle_pulse(|core_perf_alu_idle),
        .tensor_active_pulse(|core_perf_tensor_active),
        .tensor_idle_pulse(|core_perf_tensor_idle),
        .dual_issue_attempt_pulse(|core_perf_dual_issue_attempt),
        .dual_issue_success_pulse(|core_perf_dual_issue_success),
        .stall_mem_pulse(|core_perf_stall_mem),
        .stall_shared_pulse(|core_perf_stall_shared),
        .stall_tensor_pulse(|core_perf_stall_tensor),
        .stall_dep_pulse(|core_perf_stall_dep),
        .stall_ready_pulse(|core_perf_stall_ready),
        .store_combined_pulse(|core_perf_store_combined),
        .store_flush_pulse(1'b0),
        .early_wakeup_pulse(|core_perf_early_wakeup)
    );

    performance_counters #(
        .NUM_CORES(NUM_CORES),
        .WARPS_PER_CORE(WARPS_PER_CORE)
    ) global_perf (
        .clk(clk),
        .reset(reset),
        .enable(1'b1),
        .clear(1'b0),
        .core_active({NUM_CORES{kernel_running}}),
        .core_stalled(core_perf_stall_mem | core_perf_stall_tensor),
        .instr_issued(core_instr_retired),
        .instr_retired(core_instr_retired),
        .l1_read_hit({NUM_CORES{1'b0}}),
        .l1_write_hit({NUM_CORES{1'b0}}),
        .l2_read_hit({NUM_CORES{1'b0}}),
        .l2_write_hit({NUM_CORES{1'b0}}),
        .shared_mem_hit(core_perf_smem_access),
        .shared_mem_conflict(core_perf_smem_conflict),
        .external_mem_access(core_perf_ext_access),
        .l3_access({NUM_CORES{1'b0}}),
        .stall_mem(core_perf_stall_mem),
        .stall_tensor(core_perf_stall_tensor),
        .stall_reg_hazard(core_perf_stall_dep),
        .stall_structural({NUM_CORES{1'b0}}),
        .tensor_op_start(core_perf_tensor_active),
        .tensor_op_complete(core_perf_tensor_idle),
        .core_clock_gated({NUM_CORES{1'b0}}),
        .core_power_gated({NUM_CORES{1'b0}})
    );
endmodule
