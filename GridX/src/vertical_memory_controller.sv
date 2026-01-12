`default_nettype none
`timescale 1ns/1ns

// VERTICAL MEMORY CONTROLLER (L2)
// > Manages "Vertical Shared Memory" for a column of 4 cores
// > Arbitrates access to internal L2 SRAM and external L3 Global Memory
// > Address Range: Configurable (Default: 0x8000 - 0x83FF for L2)
module vertical_memory_controller #(
    parameter NUM_CORES = 4,
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8,
    parameter L2_BASE_ADDR = 16'h8000,
    parameter L2_LIMIT_ADDR = 16'h83FF,
    parameter L2_DEPTH = 1024 // 1KB
) (
    input wire clk,
    input wire reset,

    // Core Interfaces (x4)
    input wire [NUM_CORES-1:0] core_req_valid,
    input wire [NUM_CORES-1:0] core_req_write,
    input wire [ADDR_WIDTH-1:0] core_req_addr [NUM_CORES-1:0],
    input wire [DATA_WIDTH-1:0] core_req_data [NUM_CORES-1:0],
    output reg [NUM_CORES-1:0] core_req_grant,
    output reg [DATA_WIDTH-1:0] core_req_rdata [NUM_CORES-1:0],
    output reg [NUM_CORES-1:0] core_req_ready,

    // Global Interface (L3 Upstream)
    output reg global_req_valid,
    output reg global_req_write,
    output reg [ADDR_WIDTH-1:0] global_req_addr,
    output reg [DATA_WIDTH-1:0] global_req_data,
    input wire global_req_ready,
    input wire [DATA_WIDTH-1:0] global_req_rdata
);

    // L2 Internal Memory
    reg [DATA_WIDTH-1:0] l2_memory [L2_DEPTH-1:0];

    // Arbitration State
    reg [1:0] rr_ptr; // Round Robin Pointer (0-3)
    
    integer i;
    reg [1:0] winner_id;
    reg found;
    reg [1:0] idx;
    reg [ADDR_WIDTH-1:0] addr;
    reg [ADDR_WIDTH-1:0] offset;

    // Arbitration Logic
    always @(posedge clk) begin
        if (reset) begin
            rr_ptr <= 0;
            core_req_grant <= 0;
            core_req_ready <= 0;
            global_req_valid <= 0;
            // Initialize Memory (Simulation)
            for (i=0; i<L2_DEPTH; i=i+1) l2_memory[i] = 0;
        end else begin
            // Reset pulsed outputs
            core_req_grant <= 0;
            core_req_ready <= 0; 
            global_req_valid <= 0;
            
            // Find valid request starting from rr_ptr
            found = 0;
            
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                idx = (rr_ptr + i) % 4;
                if (core_req_valid[idx] && !found) begin
                    winner_id = idx;
                    found = 1;
                end
            end
            
            if (found) begin
                // Decode Address
                addr = core_req_addr[winner_id];
                
                if (addr >= L2_BASE_ADDR && addr <= L2_LIMIT_ADDR) begin
                    // --- L2 HIT ---
                    offset = addr - L2_BASE_ADDR;
                    
                    if (core_req_write[winner_id]) begin
                        l2_memory[offset] <= core_req_data[winner_id];
                    end else begin
                        core_req_rdata[winner_id] <= l2_memory[offset];
                    end
                    
                    core_req_ready[winner_id] <= 1; // Immediate Ack for SRAM
                    core_req_grant[winner_id] <= 1; // Used for identifying winner for data routing if needed? 
                                                    // core.sv uses grant to know it won.
                                                    
                end else begin
                    // --- L2 MISS -> Route to Global (L3) ---
                    global_req_valid <= 1;
                    global_req_write <= core_req_write[winner_id];
                    global_req_addr <= addr;
                    global_req_data <= core_req_data[winner_id];
                    
                    if (global_req_ready) begin
                        core_req_ready[winner_id] <= 1;
                        core_req_rdata[winner_id] <= global_req_rdata; // Pass global data back
                    end else begin
                        // Stall? We only ack when global is ready.
                        // Simple logic: If global not ready, we don't ack core. Core retries.
                        // Ideally we hold the request... but current core logic retries.
                        // We do NOT increment rr_ptr if we stalled here to ensure fairness?
                        // Actually, if we fail to serve, we should keep trying this one.
                        // But finding logic runs every cycle.
                        // If we don't Ack, core stays valid.
                        if (!global_req_ready) found = 0; // Pretend we didn't find one if we can't serve? 
                                                          // No, that breaks simple arbitration.
                    end
                end

                // Update Round Robin (only if ready/served)
                if (core_req_ready[winner_id]) begin
                    rr_ptr <= rr_ptr + 1;
                end
            end
        end
    end

endmodule
