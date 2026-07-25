// Thread Block Dispatcher & Recycling Unit
// This module dispatches thread blocks to available physical cores.
// I updated the block allocation logic to track core_done signals and issue remaining blocks
// dynamically when cores finish, enabling workload scaling beyond physical core count.

`default_nettype none
`timescale 1ns/1ps

module dispatch #(
    parameter NUM_CORES = 8,
    parameter THREADS_PER_BLOCK = 4
) (
    input wire clk,
    input wire reset,
    input wire start,
    input wire kernel_running,
    input wire [15:0] thread_count,
    input wire [NUM_CORES-1:0] core_done,
    output reg [NUM_CORES-1:0] core_start,
    output reg [NUM_CORES-1:0] core_reset,
    output reg [7:0] core_block_id [NUM_CORES-1:0],
    output reg [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES-1:0],
    output wire [15:0] blocks_dispatched_out,
    output wire [15:0] blocks_done_out,
    output wire [15:0] total_blocks_out,
    output wire all_blocks_dispatched,
    output wire all_blocks_done
);
    wire [15:0] total_blocks;
    assign total_blocks = (thread_count > 0) ?
                          (thread_count + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK :
                          16'd0;
    reg [15:0] blocks_dispatched;
    reg [15:0] blocks_done;
    reg start_execution;
    reg [15:0] next_blocks_dispatched;
    reg [15:0] next_blocks_done;
    integer i;
    assign blocks_dispatched_out = blocks_dispatched;
    assign blocks_done_out = blocks_done;
    assign total_blocks_out = total_blocks;
    assign all_blocks_dispatched = (blocks_dispatched >= total_blocks) && (total_blocks > 0);
    assign all_blocks_done = (blocks_done >= total_blocks) && (total_blocks > 0);
    always @(posedge clk) begin
        if (reset) begin
            blocks_dispatched <= 0;
            blocks_done <= 0;
            start_execution <= 0;
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                core_start[i] <= 0;
                core_reset[i] <= 1;
                core_block_id[i] <= 0;
                core_thread_count[i] <= THREADS_PER_BLOCK;
            end
        end else if (kernel_running) begin
            next_blocks_dispatched = blocks_dispatched;
            next_blocks_done = blocks_done;
            if (!start_execution) begin
                start_execution <= 1;
                for (i = 0; i < NUM_CORES; i = i + 1) begin
                    core_reset[i] <= 1;
                end
            end
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                if (core_reset[i]) begin
                    core_reset[i] <= 0;
                    if (next_blocks_dispatched < total_blocks) begin
                        core_start[i] <= 1;
                        core_block_id[i] <= next_blocks_dispatched[7:0];
                        core_thread_count[i] <= (next_blocks_dispatched == total_blocks - 1)
                            ? thread_count - (next_blocks_dispatched * THREADS_PER_BLOCK)
                            : THREADS_PER_BLOCK;
                        next_blocks_dispatched = next_blocks_dispatched + 1;
                    end
                end
            end
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                if (core_start[i] && core_done[i]) begin
                    core_reset[i] <= 1;
                    core_start[i] <= 0;
                    next_blocks_done = next_blocks_done + 1;
                end
            end
            blocks_dispatched <= next_blocks_dispatched;
            blocks_done <= next_blocks_done;
        end else if (!kernel_running) begin
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                if (core_start[i] && core_done[i]) begin
                    core_reset[i] <= 1;
                    core_start[i] <= 0;
                    blocks_done <= blocks_done + 1;
                end
            end
        end
    end
endmodule
