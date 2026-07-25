
`default_nettype none
`timescale 1ns/1ns

module tensor_controller #(
    parameter NUM_WARPS = 1,
    parameter NUM_UNITS = 4,
    parameter WARP_ID_WIDTH = (NUM_WARPS > 1) ? $clog2(NUM_WARPS) : 1
) (
    input wire clk,
    input wire reset,
    input wire request_valid,
    input wire [WARP_ID_WIDTH-1:0] warp_id,
    input wire [3:0] dest_reg_idx,
    input wire signed [3:0][3:0][15:0] src_a,
    input wire signed [3:0][3:0][15:0] src_b,
    input wire signed [3:0][3:0][31:0] src_c,
    input wire [15:0] imm,
    output reg request_ready,
    output reg [NUM_WARPS-1:0] warp_busy,
    output reg [NUM_WARPS-1:0] warp_done,
    output reg writeback_valid,
    output reg [WARP_ID_WIDTH-1:0] writeback_warp_id,
    output reg signed [3:0][3:0][31:0] writeback_data,
    output reg [3:0] writeback_reg_idx,
    output wire [$clog2(NUM_WARPS+1)-1:0] active_tensor_ops
);
    reg [NUM_UNITS-1:0] unit_start;
    wire [NUM_UNITS-1:0] unit_done;
    wire [NUM_UNITS-1:0] unit_busy_status;
    wire signed [3:0][3:0][31:0] unit_result [NUM_UNITS-1:0];
    reg [WARP_ID_WIDTH-1:0] unit_owner [NUM_UNITS-1:0];
    reg [NUM_UNITS-1:0] unit_active;
    integer i;
    reg signed [3:0][3:0][15:0] unit_src_a [NUM_UNITS-1:0];
    reg signed [3:0][3:0][15:0] unit_src_b [NUM_UNITS-1:0];
    reg signed [3:0][3:0][31:0] unit_src_c [NUM_UNITS-1:0];
    wire [3:0] unit_tag_in [NUM_UNITS-1:0];
    wire [3:0] unit_tag_out [NUM_UNITS-1:0];
    wire [NUM_UNITS-1:0] unit_out_valid;
    reg [15:0] unit_imm [NUM_UNITS-1:0];
    wire [NUM_UNITS-1:0] tc_done, rt_done;
    wire signed [3:0][3:0][31:0] tc_result [NUM_UNITS-1:0];
    wire signed [3:0][3:0][31:0] rt_result [NUM_UNITS-1:0];
    wire [NUM_UNITS-1:0] tc_busy_status, rt_busy_status;

    genvar u;
    generate
        for (u = 0; u < NUM_UNITS; u = u + 1) begin : co_processors
            assign unit_tag_in[u] = u[3:0];

            tensor_unit_pipelined t_unit (
                .clk(clk),
                .reset(reset),
                .start(unit_start[u] && unit_imm[u] != 1),
                .tag_in(unit_tag_in[u]),
                .busy(tc_busy_status[u]),
                .done(tc_done[u]),
                .tag_out(),
                .matrix_a(unit_src_a[u]),
                .matrix_b(unit_src_b[u]),
                .matrix_c(unit_src_c[u]),
                .matrix_d(tc_result[u])
            );

            rt_core rt_unit (
                .clk(clk),
                .reset(reset),
                .start(unit_start[u] && unit_imm[u] == 1),
                .tag_in(unit_tag_in[u]),
                .busy(rt_busy_status[u]),
                .done(rt_done[u]),
                .tag_out(),
                .matrix_a(unit_src_a[u]),
                .matrix_b(unit_src_b[u]),
                .matrix_c(unit_src_c[u]),
                .matrix_d(rt_result[u])
            );

            assign unit_done[u] = tc_done[u] | rt_done[u];
            assign unit_result[u] = (unit_imm[u] == 1) ? rt_result[u] : tc_result[u];
            assign unit_busy_status[u] = tc_busy_status[u] | rt_busy_status[u];
        end
    endgenerate
    reg [1:0] free_unit_idx;
    reg found_free;
    always @(*) begin
        found_free = 0;
        free_unit_idx = 0;
        for (i = 0; i < NUM_UNITS; i = i + 1) begin
            if (!unit_active[i] && !found_free) begin
                free_unit_idx = i[1:0];
                found_free = 1;
            end
        end
    end
    assign request_ready = found_free;
    reg [3:0] unit_dest_reg [NUM_UNITS-1:0];
    always @(posedge clk) begin
        if (reset) begin
            unit_start <= 0;
            unit_active <= 0;
            warp_busy <= 0;
            warp_done <= 0;
            writeback_valid <= 0;
            for (i=0; i<NUM_UNITS; i=i+1) begin
                unit_owner[i] <= 0;
                unit_dest_reg[i] <= 0;
                unit_src_a[i] <= 0;
                unit_src_b[i] <= 0;
                unit_src_c[i] <= 0;
                unit_imm[i] <= 0;
            end
        end else begin
            unit_start <= 0;
            warp_done <= 0;
            writeback_valid <= 0;
            if (request_valid && found_free) begin
                unit_start[free_unit_idx] <= 1;
                unit_active[free_unit_idx] <= 1;
                unit_owner[free_unit_idx] <= warp_id;
                unit_dest_reg[free_unit_idx] <= dest_reg_idx;
                warp_busy[warp_id] <= 1;
                unit_src_a[free_unit_idx] <= src_a;
                unit_src_b[free_unit_idx] <= src_b;
                unit_src_c[free_unit_idx] <= src_c;
                unit_imm[free_unit_idx] <= imm;
            end
            for (i = 0; i < NUM_UNITS; i = i + 1) begin
                if (unit_done[i]) begin
                    writeback_valid <= 1;
                    writeback_warp_id <= unit_owner[i];
                    writeback_data <= unit_result[i];
                    writeback_reg_idx <= unit_dest_reg[i];
                    unit_active[i] <= 0;
                    warp_busy[unit_owner[i]] <= 0;
                    warp_done[unit_owner[i]] <= 1;
                end
            end
        end
    end
    assign active_tensor_ops = $countones(warp_busy);
`ifdef DEBUG
    reg [31:0] debug_cycle;
    always @(posedge clk) begin
        if (reset) debug_cycle <= 0;
        else debug_cycle <= debug_cycle + 1;
    end
    always @(posedge clk) begin
        if (request_valid) begin
            $display("[T_CTRL] Cycle %d Request: valid=%b found_free=%b free_unit=%d warp_id=%d imm=%d dest=%d",
                     debug_cycle, request_valid, found_free, free_unit_idx, warp_id, imm, dest_reg_idx);
        end
        for (int u = 0; u < NUM_UNITS; u = u + 1) begin
            if (unit_done[u]) begin
                $display("[T_CTRL] Cycle %d Unit %d DONE: tc_done=%b rt_done=%b data=%h",
                         debug_cycle, u, tc_done[u], rt_done[u], unit_result[u][0][0]);
            end
        end
    end
`endif
endmodule
