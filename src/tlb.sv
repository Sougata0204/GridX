// Translation Lookaside Buffer
// Fully-associative virtual memory address translation cache with LRU replacement.

`default_nettype none
`timescale 1ns/1ns

module tlb #(
    parameter NUM_ENTRIES = 64,
    parameter VIRTUAL_ADDR_BITS = 48,
    parameter PHYSICAL_ADDR_BITS = 40,
    parameter PAGE_OFFSET_BITS = 12,
    parameter ASID_BITS = 8
) (
    input  wire clk,
    input  wire reset,
    
    // Lookup port
    input  wire lookup_valid,
    input  wire [VIRTUAL_ADDR_BITS-1:0] lookup_vaddr,
    input  wire [ASID_BITS-1:0] lookup_asid,
    output reg  lookup_hit,
    output reg  [PHYSICAL_ADDR_BITS-1:0] lookup_paddr,
    output reg  [2:0] lookup_permissions,
    
    // Write/Update port
    input  wire write_valid,
    input  wire [VIRTUAL_ADDR_BITS-1:0] write_vaddr,
    input  wire [PHYSICAL_ADDR_BITS-1:0] write_paddr,
    input  wire [ASID_BITS-1:0] write_asid,
    input  wire [2:0] write_permissions,
    
    // Invalidation
    input  wire invalidate_all,
    input  wire invalidate_asid_valid,
    input  wire [ASID_BITS-1:0] invalidate_asid,
    
    // Performance counters
    output reg [31:0] perf_hits,
    output reg [31:0] perf_misses
);

    localparam VPN_BITS = VIRTUAL_ADDR_BITS - PAGE_OFFSET_BITS;
    localparam PPN_BITS = PHYSICAL_ADDR_BITS - PAGE_OFFSET_BITS;
    
    reg valid [NUM_ENTRIES-1:0];
    reg [VPN_BITS-1:0] vpn_array [NUM_ENTRIES-1:0];
    reg [PPN_BITS-1:0] ppn_array [NUM_ENTRIES-1:0];
    reg [ASID_BITS-1:0] asid_array [NUM_ENTRIES-1:0];
    reg [2:0] perm_array [NUM_ENTRIES-1:0];
    reg [31:0] age_array [NUM_ENTRIES-1:0];
    
    wire [VPN_BITS-1:0] lookup_vpn = lookup_vaddr[VIRTUAL_ADDR_BITS-1:PAGE_OFFSET_BITS];
    wire [PAGE_OFFSET_BITS-1:0] lookup_offset = lookup_vaddr[PAGE_OFFSET_BITS-1:0];
    
    integer i;
    
    // Find LRU entry for replacement
    reg [$clog2(NUM_ENTRIES)-1:0] lru_idx;
    reg [31:0] max_age;
    
    always @(*) begin
        lru_idx = 0;
        max_age = 0;
        for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
            if (!valid[i]) begin
                lru_idx = i;
                max_age = 32'hFFFFFFFF; // prioritize invalid entries
            end else if (age_array[i] > max_age && max_age != 32'hFFFFFFFF) begin
                max_age = age_array[i];
                lru_idx = i;
            end
        end
    end

    // Combinational Lookup
    reg hit_comb;
    reg [PPN_BITS-1:0] ppn_comb;
    reg [2:0] perm_comb;
    reg [$clog2(NUM_ENTRIES)-1:0] hit_idx;
    
    always @(*) begin
        hit_comb = 0;
        ppn_comb = 0;
        perm_comb = 0;
        hit_idx = 0;
        
        for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
            if (valid[i] && vpn_array[i] == lookup_vpn && asid_array[i] == lookup_asid) begin
                hit_comb = 1;
                ppn_comb = ppn_array[i];
                perm_comb = perm_array[i];
                hit_idx = i;
            end
        end
    end
    
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                valid[i] <= 0;
                age_array[i] <= 0;
            end
            lookup_hit <= 0;
            lookup_paddr <= 0;
            lookup_permissions <= 0;
            perf_hits <= 0;
            perf_misses <= 0;
        end else begin
            // 1. Process invalidations
            if (invalidate_all) begin
                for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                    valid[i] <= 0;
                end
            end else if (invalidate_asid_valid) begin
                for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                    if (valid[i] && asid_array[i] == invalidate_asid) begin
                        valid[i] <= 0;
                    end
                end
            end
            
            // 2. Process Write
            if (write_valid) begin
                valid[lru_idx] <= 1;
                vpn_array[lru_idx] <= write_vaddr[VIRTUAL_ADDR_BITS-1:PAGE_OFFSET_BITS];
                ppn_array[lru_idx] <= write_paddr[PHYSICAL_ADDR_BITS-1:PAGE_OFFSET_BITS];
                asid_array[lru_idx] <= write_asid;
                perm_array[lru_idx] <= write_permissions;
                age_array[lru_idx] <= 0;
            end
            
            // 3. Process Lookup
            lookup_hit <= 0;
            if (lookup_valid) begin
                if (hit_comb) begin
                    lookup_hit <= 1;
                    lookup_paddr <= {ppn_comb, lookup_offset};
                    lookup_permissions <= perm_comb;
                    perf_hits <= perf_hits + 1;
                    // Update LRU
                    for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                        if (valid[i]) begin
                            if (i == hit_idx) age_array[i] <= 0;
                            else age_array[i] <= age_array[i] + 1;
                        end
                    end
                end else begin
                    perf_misses <= perf_misses + 1;
                end
            end
            
            // Age valid entries (simplified: every cycle if no hit)
            if (!lookup_valid || !hit_comb) begin
                for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                    if (valid[i] && age_array[i] < 32'hFFFFFFFE) begin
                        age_array[i] <= age_array[i] + 1;
                    end
                end
            end
        end
    end

endmodule
