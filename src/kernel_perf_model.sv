
`default_nettype none
`timescale 1ns/1ns

module kernel_perf_model #(
    parameter NUM_CORES = 8,
    parameter WARPS_PER_CORE = 1,
    parameter COUNTER_WIDTH = 48
) (
    input wire clk,
    input wire reset,
    input wire kernel_active,
    input wire alu_active_pulse,
    input wire alu_idle_pulse,
    input wire tensor_active_pulse,
    input wire tensor_idle_pulse,
    input wire dual_issue_attempt_pulse,
    input wire dual_issue_success_pulse,
    input wire stall_mem_pulse,
    input wire stall_shared_pulse,
    input wire stall_tensor_pulse,
    input wire stall_dep_pulse,
    input wire stall_ready_pulse,
    input wire store_combined_pulse,
    input wire store_flush_pulse,
    input wire early_wakeup_pulse,
    output reg [31:0] kernel_cycles,
    output reg [31:0] alu_utilization,
    output reg [31:0] tensor_utilization,
    output reg [31:0] dual_issue_rate,
    output reg [31:0] memory_stall_fraction,
    output reg [31:0] store_combine_efficiency,
    output reg [COUNTER_WIDTH-1:0] cnt_alu_active,
    output reg [COUNTER_WIDTH-1:0] cnt_alu_idle,
    output reg [COUNTER_WIDTH-1:0] cnt_tensor_active,
    output reg [COUNTER_WIDTH-1:0] cnt_tensor_idle,
    output reg [COUNTER_WIDTH-1:0] cnt_dual_attempts,
    output reg [COUNTER_WIDTH-1:0] cnt_dual_successes,
    output reg [COUNTER_WIDTH-1:0] cnt_stall_mem,
    output reg [COUNTER_WIDTH-1:0] cnt_stall_shared,
    output reg [COUNTER_WIDTH-1:0] cnt_stall_tensor,
    output reg [COUNTER_WIDTH-1:0] cnt_stall_dep,
    output reg [COUNTER_WIDTH-1:0] cnt_stall_ready,
    output reg [COUNTER_WIDTH-1:0] cnt_store_combined,
    output reg [COUNTER_WIDTH-1:0] cnt_store_flush,
    output reg [COUNTER_WIDTH-1:0] cnt_early_wakeup
);
    reg [31:0] cycle_counter;
    reg was_active;
    always @(posedge clk) begin
        if (reset) begin
            cycle_counter          <= 0;
            kernel_cycles          <= 0;
            alu_utilization        <= 0;
            tensor_utilization     <= 0;
            dual_issue_rate        <= 0;
            memory_stall_fraction  <= 0;
            store_combine_efficiency <= 0;
            was_active             <= 0;
            cnt_alu_active     <= 0;
            cnt_alu_idle       <= 0;
            cnt_tensor_active  <= 0;
            cnt_tensor_idle    <= 0;
            cnt_dual_attempts  <= 0;
            cnt_dual_successes <= 0;
            cnt_stall_mem      <= 0;
            cnt_stall_shared   <= 0;
            cnt_stall_tensor   <= 0;
            cnt_stall_dep      <= 0;
            cnt_stall_ready    <= 0;
            cnt_store_combined <= 0;
            cnt_store_flush    <= 0;
            cnt_early_wakeup   <= 0;
        end else begin
            was_active <= kernel_active;
            if (kernel_active) begin
                cycle_counter <= cycle_counter + 1;
                if (alu_active_pulse)         cnt_alu_active     <= cnt_alu_active + 1;
                if (alu_idle_pulse)           cnt_alu_idle       <= cnt_alu_idle + 1;
                if (tensor_active_pulse)      cnt_tensor_active  <= cnt_tensor_active + 1;
                if (tensor_idle_pulse)        cnt_tensor_idle    <= cnt_tensor_idle + 1;
                if (dual_issue_attempt_pulse) cnt_dual_attempts  <= cnt_dual_attempts + 1;
                if (dual_issue_success_pulse) cnt_dual_successes <= cnt_dual_successes + 1;
                if (stall_mem_pulse)          cnt_stall_mem      <= cnt_stall_mem + 1;
                if (stall_shared_pulse)       cnt_stall_shared   <= cnt_stall_shared + 1;
                if (stall_tensor_pulse)       cnt_stall_tensor   <= cnt_stall_tensor + 1;
                if (stall_dep_pulse)          cnt_stall_dep      <= cnt_stall_dep + 1;
                if (stall_ready_pulse)        cnt_stall_ready    <= cnt_stall_ready + 1;
                if (store_combined_pulse)     cnt_store_combined <= cnt_store_combined + 1;
                if (store_flush_pulse)        cnt_store_flush    <= cnt_store_flush + 1;
                if (early_wakeup_pulse)       cnt_early_wakeup   <= cnt_early_wakeup + 1;
            end
            if (was_active && !kernel_active) begin
                kernel_cycles <= cycle_counter;
                if ((cnt_alu_active + cnt_alu_idle) > 0) begin
                    alu_utilization <= (cnt_alu_active << 16) / (cnt_alu_active + cnt_alu_idle);
                end
                if ((cnt_tensor_active + cnt_tensor_idle) > 0) begin
                    tensor_utilization <= (cnt_tensor_active << 16) / (cnt_tensor_active + cnt_tensor_idle);
                end
                if (cnt_dual_attempts > 0) begin
                    dual_issue_rate <= (cnt_dual_successes << 16) / cnt_dual_attempts;
                end
                if (cycle_counter > 0) begin
                    memory_stall_fraction <= (cnt_stall_mem << 16) / cycle_counter;
                end
                if ((cnt_store_combined + cnt_store_flush) > 0) begin
                    store_combine_efficiency <= (cnt_store_combined << 16) / (cnt_store_combined + cnt_store_flush);
                end
                cycle_counter <= 0;
            end
        end
    end
endmodule
