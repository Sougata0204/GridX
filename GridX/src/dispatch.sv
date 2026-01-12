`default_nettype none
`timescale 1ns/1ps

// BLOCK DISPATCH (FIXED: Non-blocking assignments for sequential logic)
// > The GPU has one dispatch unit at the top level
// > Manages processing of threads and marks kernel execution as done
// > Sends off batches of threads in blocks to be executed by available compute cores
module dispatch #(
    parameter NUM_CORES = 2,
    parameter THREADS_PER_BLOCK = 4
) (
    input wire clk,
    input wire reset,
    input wire start,

    // Kernel Metadata
    input wire [15:0] thread_count,

    // Core States
    input reg [NUM_CORES-1:0] core_done,
    output reg [NUM_CORES-1:0] core_start,
    output reg [NUM_CORES-1:0] core_reset,
    output reg [7:0] core_block_id [NUM_CORES-1:0],
    output reg [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES-1:0],

    // Kernel Execution
    output reg done
);
    // Calculate the total number of blocks based on total threads & threads per block
    wire [15:0] total_blocks;
    assign total_blocks = (thread_count + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK;

    // Keep track of how many blocks have been processed
    reg [15:0] blocks_dispatched;
    reg [15:0] blocks_done;
    reg start_execution;
    
    // Next-state signals for proper non-blocking updates
    reg [15:0] next_blocks_dispatched;
    reg [15:0] next_blocks_done;

    integer i;
    
    always @(posedge clk) begin
        if (reset) begin
            done <= 0;
            blocks_dispatched <= 0;
            blocks_done <= 0;
            start_execution <= 0;

            for (i = 0; i < NUM_CORES; i = i + 1) begin
                core_start[i] <= 0;
                core_reset[i] <= 1;
                core_block_id[i] <= 0;
                core_thread_count[i] <= THREADS_PER_BLOCK;
            end
        end else if (start) begin
            // Default: maintain current values
            next_blocks_dispatched = blocks_dispatched;
            next_blocks_done = blocks_done;
            
            // EDA: Indirect way to get @(posedge start) without driving from 2 different clocks
            if (!start_execution) begin 
                start_execution <= 1;
                for (i = 0; i < NUM_CORES; i = i + 1) begin
                    core_reset[i] <= 1;
                end
            end

            // If the last block has finished processing, mark this kernel as done executing
            if (blocks_done == total_blocks) begin 
                done <= 1;
            end

            // Dispatch blocks to cores that were just reset
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                if (core_reset[i]) begin 
                    core_reset[i] <= 0;

                    // If this core was just reset, check if there are more blocks to be dispatched
                    if (next_blocks_dispatched < total_blocks) begin 
                        core_start[i] <= 1;
                        core_block_id[i] <= next_blocks_dispatched;
                        core_thread_count[i] <= (next_blocks_dispatched == total_blocks - 1) 
                            ? thread_count - (next_blocks_dispatched * THREADS_PER_BLOCK)
                            : THREADS_PER_BLOCK;

                        next_blocks_dispatched = next_blocks_dispatched + 1;
                    end
                end
            end

            // Track completed cores
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                if (core_start[i] && core_done[i]) begin
                    // If a core just finished executing its current block, reset it
                    core_reset[i] <= 1;
                    core_start[i] <= 0;
                    next_blocks_done = next_blocks_done + 1;
                end
            end
            
            // Apply updates using non-blocking assignments
            blocks_dispatched <= next_blocks_dispatched;
            blocks_done <= next_blocks_done;
        end
    end
endmodule