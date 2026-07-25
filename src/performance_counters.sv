
`default_nettype none
`timescale 1ns/1ns

module performance_counters #(
    parameter NUM_CORES = 8,
    parameter WARPS_PER_CORE = 1,
    parameter COUNTER_WIDTH = 48
) (
    input wire clk,
    input wire reset,
    input wire enable,
    input wire clear,
    input wire [NUM_CORES-1:0] core_active,
    input wire [NUM_CORES-1:0] core_stalled,
    input wire [NUM_CORES-1:0] instr_issued,
    input wire [NUM_CORES-1:0] instr_retired,
    input wire [NUM_CORES-1:0] l1_read_hit,
    input wire [NUM_CORES-1:0] l1_write_hit,
    input wire [NUM_CORES-1:0] l2_read_hit,
    input wire [NUM_CORES-1:0] l2_write_hit,
    input wire [NUM_CORES-1:0] shared_mem_hit,
    input wire [NUM_CORES-1:0] shared_mem_conflict,
    input wire [NUM_CORES-1:0] external_mem_access,
    input wire [NUM_CORES-1:0] l3_access,
    input wire [NUM_CORES-1:0] stall_mem,
    input wire [NUM_CORES-1:0] stall_tensor,
    input wire [NUM_CORES-1:0] stall_reg_hazard,
    input wire [NUM_CORES-1:0] stall_structural,
    input wire [NUM_CORES-1:0] tensor_op_start,
    input wire [NUM_CORES-1:0] tensor_op_complete,
    input wire [NUM_CORES-1:0] core_clock_gated,
    input wire [NUM_CORES-1:0] core_power_gated,
    output reg [COUNTER_WIDTH-1:0] cycle_count,
    output reg [COUNTER_WIDTH-1:0] total_issued,
    output reg [COUNTER_WIDTH-1:0] total_retired,
    output reg [COUNTER_WIDTH-1:0] l1_read_hits,
    output reg [COUNTER_WIDTH-1:0] l1_write_hits,
    output reg [COUNTER_WIDTH-1:0] l2_read_hits,
    output reg [COUNTER_WIDTH-1:0] l2_write_hits,
    output reg [COUNTER_WIDTH-1:0] shared_mem_hits,
    output reg [COUNTER_WIDTH-1:0] shared_mem_conflicts,
    output reg [COUNTER_WIDTH-1:0] external_mem_accesses,
    output reg [COUNTER_WIDTH-1:0] l3_accesses,
    output reg [COUNTER_WIDTH-1:0] stall_cycles_mem,
    output reg [COUNTER_WIDTH-1:0] stall_cycles_tensor,
    output reg [COUNTER_WIDTH-1:0] stall_cycles_reg,
    output reg [COUNTER_WIDTH-1:0] stall_cycles_structural,
    output reg [COUNTER_WIDTH-1:0] tensor_ops_started,
    output reg [COUNTER_WIDTH-1:0] tensor_ops_completed,
    output reg [COUNTER_WIDTH-1:0] clock_gated_cycles,
    output reg [COUNTER_WIDTH-1:0] power_gated_cycles,
    output reg [15:0] core_utilization,
    output reg [15:0] ipc
);
    reg [COUNTER_WIDTH-1:0] active_core_cycles;

    function automatic int count_ones;
        input [NUM_CORES-1:0] vec;
        int cnt;
        begin
            cnt = 0;
            for (int i = 0; i < NUM_CORES; i++) begin
                if (vec[i]) cnt = cnt + 1;
            end
            count_ones = cnt;
        end
    endfunction
    always @(posedge clk) begin
        if (reset || clear) begin
            cycle_count <= 0;
            total_issued <= 0;
            total_retired <= 0;
            l1_read_hits <= 0;
            l1_write_hits <= 0;
            l2_read_hits <= 0;
            l2_write_hits <= 0;
            shared_mem_hits <= 0;
            shared_mem_conflicts <= 0;
            external_mem_accesses <= 0;
            l3_accesses <= 0;
            stall_cycles_mem <= 0;
            stall_cycles_tensor <= 0;
            stall_cycles_reg <= 0;
            stall_cycles_structural <= 0;
            tensor_ops_started <= 0;
            tensor_ops_completed <= 0;
            clock_gated_cycles <= 0;
            power_gated_cycles <= 0;
            active_core_cycles <= 0;
            core_utilization <= 0;
            ipc <= 0;
        end else if (enable) begin
            cycle_count <= cycle_count + 1;
            total_issued <= total_issued + count_ones(instr_issued);
            total_retired <= total_retired + count_ones(instr_retired);
            l1_read_hits <= l1_read_hits + count_ones(l1_read_hit);
            l1_write_hits <= l1_write_hits + count_ones(l1_write_hit);
            l2_read_hits <= l2_read_hits + count_ones(l2_read_hit);
            l2_write_hits <= l2_write_hits + count_ones(l2_write_hit);
            shared_mem_hits <= shared_mem_hits + count_ones(shared_mem_hit);
            shared_mem_conflicts <= shared_mem_conflicts + count_ones(shared_mem_conflict);
            external_mem_accesses <= external_mem_accesses + count_ones(external_mem_access);
            l3_accesses <= l3_accesses + count_ones(l3_access);
            stall_cycles_mem <= stall_cycles_mem + count_ones(stall_mem);
            stall_cycles_tensor <= stall_cycles_tensor + count_ones(stall_tensor);
            stall_cycles_reg <= stall_cycles_reg + count_ones(stall_reg_hazard);
            stall_cycles_structural <= stall_cycles_structural + count_ones(stall_structural);
            tensor_ops_started <= tensor_ops_started + count_ones(tensor_op_start);
            tensor_ops_completed <= tensor_ops_completed + count_ones(tensor_op_complete);
            clock_gated_cycles <= clock_gated_cycles + count_ones(core_clock_gated);
            power_gated_cycles <= power_gated_cycles + count_ones(core_power_gated);
            active_core_cycles <= active_core_cycles + count_ones(core_active);
            if (cycle_count[7:0] == 8'hFF && cycle_count > 0) begin
                core_utilization <= (active_core_cycles << 8) / (cycle_count * NUM_CORES);
                ipc <= (total_retired << 8) / cycle_count;
            end
        end
    end
endmodule
