
`default_nettype none
`timescale 1ns/1ns

module snoop_filter #(
    parameter NUM_CORES = 8,
    parameter ADDR_WIDTH = 22,
    parameter FILTER_ENTRIES = 128,
    parameter CORE_ID_WIDTH = 3
) (
    input  wire clk,
    input  wire reset,
    
    // Query Interface
    input  wire query_valid,
    input  wire [ADDR_WIDTH-1:0] query_addr,
    output reg  query_result_valid,
    output reg  [NUM_CORES-1:0] query_core_mask,
    
    // Update Interface
    input  wire update_valid,
    input  wire [ADDR_WIDTH-1:0] update_addr,
    input  wire [CORE_ID_WIDTH-1:0] update_core_id,
    input  wire update_add, // 1 = add, 0 = remove
    
    // Invalidate ALL for a line
    input  wire invalidate_valid,
    input  wire [ADDR_WIDTH-1:0] invalidate_addr,
    
    // Perf
    output reg [31:0] perf_filtered_snoops
);

    reg valid_array [FILTER_ENTRIES-1:0];
    reg [ADDR_WIDTH-1:0] tag_array [FILTER_ENTRIES-1:0];
    reg [NUM_CORES-1:0] presence_mask [FILTER_ENTRIES-1:0];
    
    // Hash function
    // Mux priority: update > invalidate > query ensures we prioritize state updates
    // over answering new queries in the same cycle.
    wire [$clog2(FILTER_ENTRIES)-1:0] hash_idx = update_valid ? update_addr[$clog2(FILTER_ENTRIES)-1:0] :
                                                 invalidate_valid ? invalidate_addr[$clog2(FILTER_ENTRIES)-1:0] :
                                                 query_addr[$clog2(FILTER_ENTRIES)-1:0];
                                                 
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < FILTER_ENTRIES; i = i + 1) begin
                valid_array[i] <= 0;
                presence_mask[i] <= 0;
            end
            query_result_valid <= 0;
            query_core_mask <= 0;
            perf_filtered_snoops <= 0;
        end else begin
            query_result_valid <= 0;
            query_core_mask <= 0;
            
            // 1. Process Update
            if (update_valid) begin
                if (!valid_array[hash_idx] || tag_array[hash_idx] != update_addr) begin
                    // Replace / New Entry
                    valid_array[hash_idx] <= 1;
                    tag_array[hash_idx] <= update_addr;
                    presence_mask[hash_idx] <= update_add ? (1 << update_core_id) : 0;
                end else begin
                    // Existing Entry
                    if (update_add) begin
                        presence_mask[hash_idx] <= presence_mask[hash_idx] | (1 << update_core_id);
                    end else begin
                        presence_mask[hash_idx] <= presence_mask[hash_idx] & ~(1 << update_core_id);
                        if ((presence_mask[hash_idx] & ~(1 << update_core_id)) == 0) begin
                            valid_array[hash_idx] <= 0;
                        end
                    end
                end
            end
            
            // 2. Process Invalidate
            if (invalidate_valid) begin
                if (valid_array[hash_idx] && tag_array[hash_idx] == invalidate_addr) begin
                    valid_array[hash_idx] <= 0;
                    presence_mask[hash_idx] <= 0;
                end
            end
            
            // 3. Process Query
            if (query_valid && !update_valid && !invalidate_valid) begin
                if (valid_array[hash_idx] && tag_array[hash_idx] == query_addr) begin
                    query_core_mask <= presence_mask[hash_idx];
                    if (presence_mask[hash_idx] != {NUM_CORES{1'b1}}) begin
                        perf_filtered_snoops <= perf_filtered_snoops + 1; // Saved some snoops
                    end
                end else begin
                    query_core_mask <= {NUM_CORES{1'b1}}; // Broadcast if unsure
                end
                query_result_valid <= 1;
            end
        end
    end

endmodule
