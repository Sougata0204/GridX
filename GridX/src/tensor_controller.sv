`default_nettype none
`timescale 1ns/1ns

module tensor_controller #(
    parameter NUM_WARPS = 4,
    parameter NUM_UNITS = 4
) (
    input wire clk,
    input wire reset,

    // Interface with Core/Scheduler
    input wire request_valid,
    input wire [1:0] warp_id, // 2 bits for 4 warps
    input wire [3:0] dest_reg_idx, // Track destination register
    // Data Inputs (Shared bus from Core's register file)
    input wire signed [3:0][3:0][15:0] src_a,
    input wire signed [3:0][3:0][15:0] src_b,
    input wire signed [3:0][3:0][31:0] src_c,

    // Handshake
    output reg request_ready, // High if a unit is available

    // Status
    output reg [NUM_WARPS-1:0] warp_busy, // 1 if warp has an op in flight
    output reg [NUM_WARPS-1:0] warp_done, // Pulse 1 if warp just finished

    // Writeback
    output reg writeback_valid,
    output reg [1:0] writeback_warp_id,
    output reg signed [3:0][3:0][31:0] writeback_data,
    output reg [3:0] writeback_reg_idx
);

    // Unit Interfaces
    reg [NUM_UNITS-1:0] unit_start;
    wire [NUM_UNITS-1:0] unit_done;
    wire [NUM_UNITS-1:0] unit_busy_status;
    wire signed [3:0][3:0][31:0] unit_result [NUM_UNITS-1:0];

    // Warp Ownership Table (Which unit belongs to which warp?)
    reg [1:0] unit_owner [NUM_UNITS-1:0]; 
    reg [NUM_UNITS-1:0] unit_active; // 1 if assigned and running

    integer i;

    // Instantiate Tensor Units
    genvar u;
    generate
        for (u = 0; u < NUM_UNITS; u = u + 1) begin : tensor_units
            tensor_unit t_unit (
                .clk(clk),
                .reset(reset),
                .start(unit_start[u]),
                .done(unit_done[u]),
                .busy(unit_busy_status[u]),
                .matrix_a(src_a), // Shared input bus (valid only when unit_start[u] is high)
                .matrix_b(src_b),
                .matrix_c(src_c),
                .matrix_d(unit_result[u])
            );
        end
    endgenerate

    // Allocation Logic (Combinational + Sequential)
    // Find first free unit
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

    // Mux Request Ready
    assign request_ready = found_free;

    // Unit Register Destination Tracking
    reg [3:0] unit_dest_reg [NUM_UNITS-1:0];

    // Main Control Logic
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
            end
        end else begin
            // Reset Pulses
            unit_start <= 0;
            warp_done <= 0;
            writeback_valid <= 0;

            // 1. Handle New Requests
            if (request_valid && found_free) begin
                // Assign free unit to this warp
                unit_start[free_unit_idx] <= 1;
                unit_active[free_unit_idx] <= 1;
                unit_owner[free_unit_idx] <= warp_id;
                unit_dest_reg[free_unit_idx] <= dest_reg_idx; // Track destination
                
                // Mark warp as busy (Core should check this)
                warp_busy[warp_id] <= 1;
            end

            // 2. Handle Completions
            // We assume max 1 completion per cycle for writeback simplicity.
            // But structurally, multiple could finish if started same time?
            // "one_warp_issued_per_cycle" -> Sequential starts -> Sequential finishes (Fixed latency).
            // So we are safe scanning for *one* done signal.
            
            for (i = 0; i < NUM_UNITS; i = i + 1) begin
                if (unit_done[i]) begin
                    // Unit finished!
                    writeback_valid <= 1;
                    writeback_warp_id <= unit_owner[i];
                    writeback_data <= unit_result[i];
                    writeback_reg_idx <= unit_dest_reg[i]; // Return destination register
                    
                    // Release Unit
                    unit_active[i] <= 0;
                    
                    // Release Warp
                    warp_busy[unit_owner[i]] <= 0;
                    warp_done[unit_owner[i]] <= 1; // Signal scheduler to wake up
                end
            end
        end
    end

endmodule
