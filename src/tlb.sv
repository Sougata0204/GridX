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
    input  wire lookupValid,
    input  wire [VIRTUAL_ADDR_BITS-1:0] lookupVaddr,
    input  wire [ASID_BITS-1:0] lookupAsid,
    output reg  lookupHit,
    output reg  [PHYSICAL_ADDR_BITS-1:0] lookupPaddr,
    output reg  [2:0] lookupPermissions,
    
    // Write/Update port
    input  wire writeValid,
    input  wire [VIRTUAL_ADDR_BITS-1:0] writeVaddr,
    input  wire [PHYSICAL_ADDR_BITS-1:0] writePaddr,
    input  wire [ASID_BITS-1:0] writeAsid,
    input  wire [2:0] writePermissions,
    
    // Invalidation
    input  wire invalidateAll,
    input  wire invalidateAsidValid,
    input  wire [ASID_BITS-1:0] invalidateAsid,
    
    // Performance counters
    output reg [31:0] perfHits,
    output reg [31:0] perfMisses
);

    localparam VPN_BITS = VIRTUAL_ADDR_BITS - PAGE_OFFSET_BITS;
    localparam PPN_BITS = PHYSICAL_ADDR_BITS - PAGE_OFFSET_BITS;
    
    reg valid [NUM_ENTRIES-1:0];
    reg [VPN_BITS-1:0] vpnArray [NUM_ENTRIES-1:0];
    reg [PPN_BITS-1:0] ppnArray [NUM_ENTRIES-1:0];
    reg [ASID_BITS-1:0] asidArray [NUM_ENTRIES-1:0];
    reg [2:0] permArray [NUM_ENTRIES-1:0];
    reg [31:0] ageArray [NUM_ENTRIES-1:0];
    
    wire [VPN_BITS-1:0] lookupVpn = lookupVaddr[VIRTUAL_ADDR_BITS-1:PAGE_OFFSET_BITS];
    wire [PAGE_OFFSET_BITS-1:0] lookupOffset = lookupVaddr[PAGE_OFFSET_BITS-1:0];
    
    integer i;
    
    // Find LRU entry for replacement
    reg [$clog2(NUM_ENTRIES)-1:0] lruIdx;
    reg [31:0] maxAge;
    
    always @(*) begin
        lruIdx = 0;
        maxAge = 0;
        for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
            if (!valid[i]) begin
                lruIdx = i;
                maxAge = 32'hFFFFFFFF; // prioritize invalid entries
            end else if (ageArray[i] > maxAge && maxAge != 32'hFFFFFFFF) begin
                maxAge = ageArray[i];
                lruIdx = i;
            end
        end
    end

    // Combinational Lookup
    reg hitComb;
    reg [PPN_BITS-1:0] ppnComb;
    reg [2:0] permComb;
    reg [$clog2(NUM_ENTRIES)-1:0] hitIdx;
    
    always @(*) begin
        hitComb = 0;
        ppnComb = 0;
        permComb = 0;
        hitIdx = 0;
        
        for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
            if (valid[i] && vpnArray[i] == lookupVpn && asidArray[i] == lookupAsid) begin
                hitComb = 1;
                ppnComb = ppnArray[i];
                permComb = permArray[i];
                hitIdx = i;
            end
        end
    end
    
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                valid[i] <= 0;
                ageArray[i] <= 0;
            end
            lookupHit <= 0;
            lookupPaddr <= 0;
            lookupPermissions <= 0;
            perfHits <= 0;
            perfMisses <= 0;
        end else begin
            // 1. Process invalidations
            if (invalidateAll) begin
                for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                    valid[i] <= 0;
                end
            end else if (invalidateAsidValid) begin
                for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                    if (valid[i] && asidArray[i] == invalidateAsid) begin
                        valid[i] <= 0;
                    end
                end
            end
            
            // 2. Process Write
            if (writeValid) begin
                valid[lruIdx] <= 1;
                vpnArray[lruIdx] <= writeVaddr[VIRTUAL_ADDR_BITS-1:PAGE_OFFSET_BITS];
                ppnArray[lruIdx] <= writePaddr[PHYSICAL_ADDR_BITS-1:PAGE_OFFSET_BITS];
                asidArray[lruIdx] <= writeAsid;
                permArray[lruIdx] <= writePermissions;
                ageArray[lruIdx] <= 0;
            end
            
            // 3. Process Lookup
            lookupHit <= 0;
            if (lookupValid) begin
                if (hitComb) begin
                    lookupHit <= 1;
                    lookupPaddr <= {ppnComb, lookupOffset};
                    lookupPermissions <= permComb;
                    perfHits <= perfHits + 1;
                    // Update LRU
                    for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                        if (valid[i]) begin
                            if (i == hitIdx) ageArray[i] <= 0;
                            else ageArray[i] <= ageArray[i] + 1;
                        end
                    end
                end else begin
                    perfMisses <= perfMisses + 1;
                end
            end
            
            // Age valid entries (simplified: every cycle if no hit)
            if (!lookupValid || !hitComb) begin
                for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                    if (valid[i] && ageArray[i] < 32'hFFFFFFFE) begin
                        ageArray[i] <= ageArray[i] + 1;
                    end
                end
            end
        end
    end

endmodule
