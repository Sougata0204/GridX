
`default_nettype none
`timescale 1ns/1ns

module snoopFilter #(
    parameter NUM_CORES = 8,
    parameter ADDR_WIDTH = 22,
    parameter FILTER_ENTRIES = 128,
    parameter CORE_ID_WIDTH = 3
) (
    input  wire clk,
    input  wire reset,
    
    // Query Interface
    input  wire queryValid,
    input  wire [ADDR_WIDTH-1:0] queryAddr,
    output reg  queryResultValid,
    output reg  [NUM_CORES-1:0] queryCoreMask,
    
    // Update Interface
    input  wire updateValid,
    input  wire [ADDR_WIDTH-1:0] updateAddr,
    input  wire [CORE_ID_WIDTH-1:0] updateCoreId,
    input  wire updateAdd, // 1 = add, 0 = remove
    
    // Invalidate ALL for a line
    input  wire invalidateValid,
    input  wire [ADDR_WIDTH-1:0] invalidateAddr,
    
    // Perf
    output reg [31:0] perfFilteredSnoops
);

    reg validArray [FILTER_ENTRIES-1:0];
    reg [ADDR_WIDTH-1:0] tagArray [FILTER_ENTRIES-1:0];
    reg [NUM_CORES-1:0] presenceMask [FILTER_ENTRIES-1:0];
    
    // Hash function
    // Mux priority: update > invalidate > query ensures we prioritize state updates
    // over answering new queries in the same cycle.
    wire [$clog2(FILTER_ENTRIES)-1:0] hashIdx = updateValid ? updateAddr[$clog2(FILTER_ENTRIES)-1:0] :
                                                 invalidateValid ? invalidateAddr[$clog2(FILTER_ENTRIES)-1:0] :
                                                 queryAddr[$clog2(FILTER_ENTRIES)-1:0];
                                                 
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < FILTER_ENTRIES; i = i + 1) begin
                validArray[i] <= 0;
                presenceMask[i] <= 0;
            end
            queryResultValid <= 0;
            queryCoreMask <= 0;
            perfFilteredSnoops <= 0;
        end else begin
            queryResultValid <= 0;
            queryCoreMask <= 0;
            
            // 1. Process Update
            if (updateValid) begin
                if (!validArray[hashIdx] || tagArray[hashIdx] != updateAddr) begin
                    // Replace / New Entry
                    validArray[hashIdx] <= 1;
                    tagArray[hashIdx] <= updateAddr;
                    presenceMask[hashIdx] <= updateAdd ? (1 << updateCoreId) : 0;
                end else begin
                    // Existing Entry
                    if (updateAdd) begin
                        presenceMask[hashIdx] <= presenceMask[hashIdx] | (1 << updateCoreId);
                    end else begin
                        presenceMask[hashIdx] <= presenceMask[hashIdx] & ~(1 << updateCoreId);
                        if ((presenceMask[hashIdx] & ~(1 << updateCoreId)) == 0) begin
                            validArray[hashIdx] <= 0;
                        end
                    end
                end
            end
            
            // 2. Process Invalidate
            if (invalidateValid) begin
                if (validArray[hashIdx] && tagArray[hashIdx] == invalidateAddr) begin
                    validArray[hashIdx] <= 0;
                    presenceMask[hashIdx] <= 0;
                end
            end
            
            // 3. Process Query
            if (queryValid && !updateValid && !invalidateValid) begin
                if (validArray[hashIdx] && tagArray[hashIdx] == queryAddr) begin
                    queryCoreMask <= presenceMask[hashIdx];
                    if (presenceMask[hashIdx] != {NUM_CORES{1'b1}}) begin
                        perfFilteredSnoops <= perfFilteredSnoops + 1; // Saved some snoops
                    end
                end else begin
                    queryCoreMask <= {NUM_CORES{1'b1}}; // Broadcast if unsure
                end
                queryResultValid <= 1;
            end
        end
    end

endmodule
