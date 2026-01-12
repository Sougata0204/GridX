`default_nettype none
`timescale 1ns/1ns

// SCHEDULER (Control Plane & Spine Driver)
module scheduler #(
    parameter THREADS_PER_BLOCK = 64,
    parameter WARPS_PER_CORE = 4
) (
    input wire clk,
    input wire reset,
    input wire start,
    
    // Peripherals Events
    input wire [WARPS_PER_CORE-1:0] tensor_done, // Pulse when tensor unit finishes
    input wire power_sleep_req,                  // Request from Power Controller (Placeholder) (Active High)
    
    // Instruction Spine (Packet Input for Control Decisions)
    // We sniff the opcode and flags from the Decoder to make state decisions
    input wire [63:0] decoded_packet,
    
    // Memory Access State
    input reg [2:0] fetcher_state,
    input reg [1:0] lsu_state [THREADS_PER_BLOCK-1:0],

    // PC Interface
    output reg [7:0] current_pc,
    input reg [7:0] next_pc [THREADS_PER_BLOCK-1:0], // Only need last thread of warp

    // Control Plane Outputs
    output reg [3:0] core_state,       // Extended width for new states
    output reg [3:0] warp_state [WARPS_PER_CORE-1:0], 
    output reg [$clog2(WARPS_PER_CORE)-1:0] active_warp_id,
    
    // Instruction Spine Controls
    output reg [WARPS_PER_CORE-1:0] warp_issue_enable, // Latch enable for per-warp instruction register
    
    output reg done
);
    localparam THREADS_PER_WARP = THREADS_PER_BLOCK / WARPS_PER_CORE;

    // FSM States
    localparam IDLE         = 4'b0000,
               FETCH        = 4'b0001,
               DECODE       = 4'b0010,
               ISSUE        = 4'b0011, // New: Dedicated Issue Cycle for Spine Latching
               EXECUTE      = 4'b0100,
               UPDATE       = 4'b0101, // Update PC/Regs
               STALLED_MEM  = 4'b0110, // Explicit Memory Stall
               TENSOR_BUSY  = 4'b0111, // Explicit Tensor Busy
               SLEEP        = 4'b1000, // Power Gating
               DONE         = 4'b1111;

    // Unpack minimal control flags from packet
    // [46:43] Opcode (for debug/branch checks)
    // [42] Tensor Op
    // [41] Ret
    // [33] Mem Write
    // [32] Mem Read
    // [34] NZP Write (CMP)
    wire pkt_tensor = decoded_packet[42];
    wire pkt_ret    = decoded_packet[41];
    wire pkt_mem    = decoded_packet[32] || decoded_packet[33];
    
    // Warp Contexts
    reg [7:0] warp_pc [WARPS_PER_CORE-1:0];
    reg warp_done_flag [WARPS_PER_CORE-1:0];
    reg start_latched;

    integer w;

    // Output Muxing
    always @(*) begin
        current_pc = warp_pc[active_warp_id];
        core_state = warp_state[active_warp_id];
        
        // Spine Issue Logic:
        // Only valid during ISSUE state.
        // Enable ONLY the active warp.
        warp_issue_enable = 0;
        if (warp_state[active_warp_id] == ISSUE) begin
            warp_issue_enable[active_warp_id] = 1'b1;
        end

        // Global done
        done = 1;
        for (int i = 0; i < WARPS_PER_CORE; i++) begin
            if (!warp_done_flag[i]) done = 0;
        end
    end

    always @(posedge clk) begin 
        if (reset) begin
            active_warp_id <= 0;
            start_latched <= 0;
            for (w = 0; w < WARPS_PER_CORE; w = w + 1) begin
                
                warp_pc[w] <= 0;
                warp_state[w] <= IDLE;
                warp_done_flag[w] <= 0;
            end
        end else begin 
            if (start) start_latched <= 1;

            // --- State Machine ---
            case (warp_state[active_warp_id])
                IDLE: begin
                    if (start || start_latched) begin 
                        if (!warp_done_flag[active_warp_id])
                            warp_state[active_warp_id] <= FETCH;
                    end
                    // Check for Sleep Request if stuck in IDLE?
                    // For now, only enter sleep from Update loop or specific logic.
                end
                
                FETCH: begin 
                    if (fetcher_state == 3'b010) begin // FETCHED
                        warp_state[active_warp_id] <= DECODE;
                    end
                end
                
                DECODE: begin
                    // Scheduler "peeks" at the decoded packet here?
                    // OR we move to ISSUE and then decide?
                    // Core pipeline: FETCH data -> DECODE logic (comb) -> Latch to Spine.
                    // If we are in DECODE state, the Decoder module is effectively producing valid output combinatorially from the fetched instruction.
                    // So next cycle is ISSUE, where we LATCH it.
                    warp_state[active_warp_id] <= ISSUE;
                end

                ISSUE: begin
                    // In this cycle, `warp_issue_enable` is convex high (comb).
                    // The core will latch `decoded_packet` into `warp_latch[id]` on rising edge.
                    // Now we determine NEXT state based on the packet content.
                    
                    if (pkt_tensor) begin
                        warp_state[active_warp_id] <= TENSOR_BUSY;
                        // Tensor Controller starts execution naturally when it sees valid + logic?
                        // Or we need an explicit start trigger?
                        // Tensor Controller uses `active_core_state == 3'b011` (Old REQUEST).
                        // We need to map `ISSUE` to that or update T-Ctrl.
                        // Let's assume T-Ctrl triggers on `ISSUE` (mapped to old REQUEST logic in Core).
                    end else if (pkt_mem) begin
                        warp_state[active_warp_id] <= STALLED_MEM;
                        // Similarly, LSUs trigger on ISSUE.
                    end else begin
                        // ALU / Branch / Control
                        warp_state[active_warp_id] <= EXECUTE;
                    end
                end

                STALLED_MEM: begin 
                    // Check LSUs for this warp
                    // Logic: We expect completion (DONE). 
                    // IDLE, REQUESTING, WAITING = Loading/Storing.
                    // Deviation: If thread is masked (not supported yet), it stays IDLE.
                    // For now, assume all threads run the instruction.
                    reg all_done = 1'b1;
                    int start_idx = active_warp_id * THREADS_PER_WARP;
                    int end_idx = start_idx + THREADS_PER_WARP;
                    
                    for (int i = 0; i < THREADS_PER_BLOCK; i++) begin
                        if (i >= start_idx && i < end_idx) begin
                             if (lsu_state[i] != 2'b11) begin // If NOT DONE
                                all_done = 1'b0;
                                break;
                            end
                        end
                    end

                    if (all_done) begin
                        warp_state[active_warp_id] <= EXECUTE; // Move to completion/update
                    end else begin
                        // Context Switch
                        active_warp_id <= active_warp_id + 1; 
                    end
                end

                TENSOR_BUSY: begin
                    if (tensor_done[active_warp_id]) begin
                        warp_state[active_warp_id] <= EXECUTE;
                    end else begin
                        // Context Switch
                        active_warp_id <= active_warp_id + 1;
                    end
                end

                EXECUTE: begin
                    warp_state[active_warp_id] <= UPDATE;
                end


                UPDATE: begin 
                    if (pkt_ret) begin 
                         warp_done_flag[active_warp_id] <= 1;
                         warp_state[active_warp_id] <= DONE;
                         active_warp_id <= active_warp_id + 1;
                    end else begin 
                        // Update PC
                        int last_thread_idx = (active_warp_id * THREADS_PER_WARP) + THREADS_PER_WARP - 1;
                        warp_pc[active_warp_id] <= next_pc[last_thread_idx];
                        
                        // Check Sleep
                        if (power_sleep_req) begin
                            warp_state[active_warp_id] <= SLEEP;
                        end else begin
                            warp_state[active_warp_id] <= FETCH;
                        end
                    end
                end
                
                SLEEP: begin
                    if (!power_sleep_req) begin // Wakeup
                        warp_state[active_warp_id] <= FETCH;
                    end else begin
                         active_warp_id <= active_warp_id + 1; // Yield
                    end
                end

                DONE: begin 
                     active_warp_id <= active_warp_id + 1;
                end
                
                default: warp_state[active_warp_id] <= IDLE;
            endcase
        end
    end
endmodule
