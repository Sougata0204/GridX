
`default_nettype none
`timescale 1ns/1ns

module schedulerV2 #(
    parameter NUM_WARPS = 32,
    parameter NUM_EXEC_UNITS = 4
) (
    input  wire clk,
    input  wire reset,
    
    // Warp status from Scoreboard
    input  wire [NUM_WARPS-1:0] warpReady, // 1 if warp has an instruction ready to execute
    input  wire [NUM_WARPS-1:0] warpValid, // 1 if warp is active
    
    // Execution Unit Status
    input  wire [NUM_EXEC_UNITS-1:0] euReady, // 1 if EU can accept a new instruction
    
    // Scheduler Output
    output reg  [NUM_EXEC_UNITS-1:0] issueValid,
    output reg  [$clog2(NUM_WARPS)-1:0] issueWarpId [NUM_EXEC_UNITS-1:0]
);

    // Round-robin pointers for each execution unit to ensure fairness
    reg [$clog2(NUM_WARPS)-1:0] rrPtr [NUM_EXEC_UNITS-1:0];
    
    integer eu, w;
    reg [$clog2(NUM_WARPS)-1:0] selectedWarp;
    reg found;
    
    // Mask to keep track of which warps have already been selected this cycle
    reg [NUM_WARPS-1:0] selectedMask;
    
    always @(*) begin
        selectedMask = 0;
        
        for (eu = 0; eu < NUM_EXEC_UNITS; eu = eu + 1) begin
            issueValid[eu] = 0;
            issueWarpId[eu] = 0;
            
            if (euReady[eu]) begin
                found = 0;
                selectedWarp = 0;
                
                // Start search from rrPtr
                for (w = 0; w < NUM_WARPS; w = w + 1) begin
                    if (!found) begin
                        automatic logic [$clog2(NUM_WARPS)-1:0] idx = (rrPtr[eu] + w) % NUM_WARPS;
                        if (warpValid[idx] && warpReady[idx] && !selectedMask[idx]) begin
                            found = 1;
                            selectedWarp = idx;
                        end
                    end
                end
                
                if (found) begin
                    issueValid[eu] = 1;
                    issueWarpId[eu] = selectedWarp;
                    selectedMask[selectedWarp] = 1;
                end
            end
        end
    end
    
    always @(posedge clk) begin
        if (reset) begin
            for (eu = 0; eu < NUM_EXEC_UNITS; eu = eu + 1) begin
                rrPtr[eu] <= eu * (NUM_WARPS / NUM_EXEC_UNITS); // Stagger initial pointers
            end
        end else begin
            for (eu = 0; eu < NUM_EXEC_UNITS; eu = eu + 1) begin
                if (issueValid[eu]) begin
                    rrPtr[eu] <= (issueWarpId[eu] + 1) % NUM_WARPS;
                end
            end
        end
    end

endmodule
