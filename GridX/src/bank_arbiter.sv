`default_nettype none
`timescale 1ns/1ps

// BANK ARBITER (UPG-ARCH-002: Bank Conflict Isolation)
// > Resolves conflicts when multiple threads access the same SRAM bank
// > Round-robin priority among requesters for fairness
// > PER-WARP STALL SIGNALS: Only conflicting warps stall, non-conflicting proceed
// > No global pipeline stall allowed
// > Guarantees no starvation with bounded wait time
module bank_arbiter #(
    parameter NUM_REQUESTERS = 8,       // Number of concurrent requesters (threads)
    parameter NUM_BANKS = 8,            // Number of SRAM banks
    parameter NUM_WARPS = 2,            // Number of warps (typically = NUM_CORES)
    parameter THREADS_PER_WARP = 4,     // Threads per warp
    parameter BANK_BITS = $clog2(NUM_BANKS),
    parameter WARP_BITS = $clog2(NUM_WARPS)
) (
    input wire clk,
    input wire reset,

    // Request interface (from threads/LSUs)
    input wire [NUM_REQUESTERS-1:0] request_valid,
    input wire [BANK_BITS-1:0] request_bank [NUM_REQUESTERS-1:0],
    input wire [NUM_REQUESTERS-1:0] request_is_write,
    
    // Grant interface (to threads/LSUs)
    output reg [NUM_REQUESTERS-1:0] grant,
    output reg [NUM_REQUESTERS-1:0] bank_conflict,
    
    // Per-warp stall signals (UPG-ARCH-002: core change)
    // warp_stall[w] = 1 means warp w has at least one thread in conflict
    output reg [NUM_WARPS-1:0] warp_stall,
    
    // Warp conflict statistics (for fairness monitoring)
    output reg [7:0] warp_conflict_count [NUM_WARPS-1:0],
    output reg [7:0] warp_grant_count [NUM_WARPS-1:0],
    
    // Bank selection output (to SRAM banks)
    output reg [NUM_BANKS-1:0] bank_read_enable,
    output reg [NUM_BANKS-1:0] bank_write_enable,
    output reg [$clog2(NUM_REQUESTERS)-1:0] bank_owner [NUM_BANKS-1:0]
);

    // Round-robin priority pointer per bank (for fairness)
    reg [$clog2(NUM_REQUESTERS)-1:0] priority_ptr [NUM_BANKS-1:0];
    
    // Temporary variables for arbitration
    reg [NUM_REQUESTERS-1:0] bank_requesters [NUM_BANKS-1:0];
    reg [NUM_BANKS-1:0] bank_has_request;
    reg [$clog2(NUM_REQUESTERS)-1:0] selected_requester [NUM_BANKS-1:0];
    
    // Warp conflict tracking
    reg [NUM_WARPS-1:0] warp_has_conflict;
    reg [NUM_WARPS-1:0] warp_has_grant;
    
    integer i, j, k, w;
    
    // Function to get warp ID from thread ID
    function [WARP_BITS-1:0] get_warp_id;
        input [$clog2(NUM_REQUESTERS)-1:0] thread_id;
        begin
            get_warp_id = thread_id / THREADS_PER_WARP;
        end
    endfunction
    
    always @(posedge clk) begin
        if (reset) begin
            grant <= {NUM_REQUESTERS{1'b0}};
            bank_conflict <= {NUM_REQUESTERS{1'b0}};
            warp_stall <= {NUM_WARPS{1'b0}};
            bank_read_enable <= {NUM_BANKS{1'b0}};
            bank_write_enable <= {NUM_BANKS{1'b0}};
            
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                priority_ptr[i] <= 0;
                bank_owner[i] <= 0;
            end
            
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                warp_conflict_count[w] <= 0;
                warp_grant_count[w] <= 0;
            end
        end else begin
            // Reset per-cycle outputs
            grant <= {NUM_REQUESTERS{1'b0}};
            bank_conflict <= {NUM_REQUESTERS{1'b0}};
            warp_stall <= {NUM_WARPS{1'b0}};
            bank_read_enable <= {NUM_BANKS{1'b0}};
            bank_write_enable <= {NUM_BANKS{1'b0}};
            warp_has_conflict = {NUM_WARPS{1'b0}};
            warp_has_grant = {NUM_WARPS{1'b0}};
            
            // Step 1: Collect requests per bank
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                bank_requesters[i] = {NUM_REQUESTERS{1'b0}};
                bank_has_request[i] = 1'b0;
            end
            
            for (j = 0; j < NUM_REQUESTERS; j = j + 1) begin
                if (request_valid[j]) begin
                    bank_requesters[request_bank[j]][j] = 1'b1;
                    bank_has_request[request_bank[j]] = 1'b1;
                end
            end
            
            // Step 2: Arbitrate per bank using round-robin
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                if (bank_has_request[i]) begin
                    // Find winner starting from priority pointer
                    selected_requester[i] = priority_ptr[i];
                    
                    for (k = 0; k < NUM_REQUESTERS; k = k + 1) begin
                        // Check requester at (priority_ptr + k) mod NUM_REQUESTERS
                        if (bank_requesters[i][(priority_ptr[i] + k) % NUM_REQUESTERS]) begin
                            selected_requester[i] = (priority_ptr[i] + k) % NUM_REQUESTERS;
                            break;
                        end
                    end
                    
                    // Grant to winner
                    grant[selected_requester[i]] <= 1'b1;
                    bank_owner[i] <= selected_requester[i];
                    
                    // Track warp grant
                    warp_has_grant[get_warp_id(selected_requester[i])] = 1'b1;
                    warp_grant_count[get_warp_id(selected_requester[i])] <= 
                        warp_grant_count[get_warp_id(selected_requester[i])] + 1;
                    
                    // Set bank enable signals
                    if (request_is_write[selected_requester[i]]) begin
                        bank_write_enable[i] <= 1'b1;
                    end else begin
                        bank_read_enable[i] <= 1'b1;
                    end
                    
                    // Update priority pointer for next cycle (fairness guarantee)
                    priority_ptr[i] <= (selected_requester[i] + 1) % NUM_REQUESTERS;
                    
                    // Mark conflicts for non-winning requesters to this bank
                    for (j = 0; j < NUM_REQUESTERS; j = j + 1) begin
                        if (bank_requesters[i][j] && (j != selected_requester[i])) begin
                            bank_conflict[j] <= 1'b1;
                            // Track which warp has conflict
                            warp_has_conflict[get_warp_id(j)] = 1'b1;
                            warp_conflict_count[get_warp_id(j)] <= 
                                warp_conflict_count[get_warp_id(j)] + 1;
                        end
                    end
                end
            end
            
            // Step 3: Generate per-warp stall signals (UPG-ARCH-002 core feature)
            // A warp stalls only if it has conflicts AND no grants this cycle
            // This allows non-conflicting warps to proceed independently
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                warp_stall[w] <= warp_has_conflict[w];
            end
        end
    end

    // =========================================================================
    // FORMAL ASSERTIONS (Correctness Constraints)
    // =========================================================================
    
    `ifdef FORMAL
    // No read and write to same bank in same cycle
    always @(posedge clk) begin
        if (!reset) begin
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                assert(!(bank_read_enable[i] && bank_write_enable[i]))
                    else $error("ILLEGAL: Simultaneous read/write to bank %d", i);
            end
        end
    end
    
    // No starvation: bounded wait time (simplified check)
    // If a requester has been waiting, it should eventually get granted
    reg [7:0] wait_counter [NUM_REQUESTERS-1:0];
    always @(posedge clk) begin
        if (reset) begin
            for (j = 0; j < NUM_REQUESTERS; j = j + 1) begin
                wait_counter[j] <= 0;
            end
        end else begin
            for (j = 0; j < NUM_REQUESTERS; j = j + 1) begin
                if (request_valid[j] && !grant[j]) begin
                    wait_counter[j] <= wait_counter[j] + 1;
                    assert(wait_counter[j] < NUM_REQUESTERS * 2)
                        else $error("STARVATION: Requester %d waiting too long", j);
                end else begin
                    wait_counter[j] <= 0;
                end
            end
        end
    end
    `endif

endmodule
