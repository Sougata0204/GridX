
`default_nettype none
`timescale 1ns/1ns

module scheduler_v2 #(
    parameter NUM_WARPS = 32,
    parameter NUM_EXEC_UNITS = 4
) (
    input  wire clk,
    input  wire reset,
    
    // Warp status from Scoreboard
    input  wire [NUM_WARPS-1:0] warp_ready, // 1 if warp has an instruction ready to execute
    input  wire [NUM_WARPS-1:0] warp_valid, // 1 if warp is active
    
    // Execution Unit Status
    input  wire [NUM_EXEC_UNITS-1:0] eu_ready, // 1 if EU can accept a new instruction
    
    // Scheduler Output
    output reg  [NUM_EXEC_UNITS-1:0] issue_valid,
    output reg  [$clog2(NUM_WARPS)-1:0] issue_warp_id [NUM_EXEC_UNITS-1:0]
);

    // Round-robin pointers for each execution unit to ensure fairness
    reg [$clog2(NUM_WARPS)-1:0] rr_ptr [NUM_EXEC_UNITS-1:0];
    
    integer eu, w;
    reg [$clog2(NUM_WARPS)-1:0] selected_warp;
    reg found;
    
    // Mask to keep track of which warps have already been selected this cycle
    reg [NUM_WARPS-1:0] selected_mask;
    
    always @(*) begin
        selected_mask = 0;
        
        for (eu = 0; eu < NUM_EXEC_UNITS; eu = eu + 1) begin
            issue_valid[eu] = 0;
            issue_warp_id[eu] = 0;
            
            if (eu_ready[eu]) begin
                found = 0;
                selected_warp = 0;
                
                // Start search from rr_ptr
                for (w = 0; w < NUM_WARPS; w = w + 1) begin
                    if (!found) begin
                        automatic logic [$clog2(NUM_WARPS)-1:0] idx = (rr_ptr[eu] + w) % NUM_WARPS;
                        if (warp_valid[idx] && warp_ready[idx] && !selected_mask[idx]) begin
                            found = 1;
                            selected_warp = idx;
                        end
                    end
                end
                
                if (found) begin
                    issue_valid[eu] = 1;
                    issue_warp_id[eu] = selected_warp;
                    selected_mask[selected_warp] = 1;
                end
            end
        end
    end
    
    always @(posedge clk) begin
        if (reset) begin
            for (eu = 0; eu < NUM_EXEC_UNITS; eu = eu + 1) begin
                rr_ptr[eu] <= eu * (NUM_WARPS / NUM_EXEC_UNITS); // Stagger initial pointers
            end
        end else begin
            for (eu = 0; eu < NUM_EXEC_UNITS; eu = eu + 1) begin
                if (issue_valid[eu]) begin
                    rr_ptr[eu] <= (issue_warp_id[eu] + 1) % NUM_WARPS;
                end
            end
        end
    end

endmodule
