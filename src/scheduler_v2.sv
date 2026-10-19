
`default_nettype none
`timescale 1ns/1ns

// Simplified v2 warp scheduler providing basic round-robin warp selection for single-warp core configurations.
module schedulerV2 #(
    parameter NUM_WARPS = 32,
    parameter NUM_EXEC_UNITS = 4
) (
    input  wire clk,
    input  wire reset,
    
    input  wire [NUM_WARPS-1:0] warpReady,
    input  wire [NUM_WARPS-1:0] warpValid,
    
    input  wire [NUM_EXEC_UNITS-1:0] euReady,
    
    output reg  [NUM_EXEC_UNITS-1:0] issueValid,
    output reg  [$clog2(NUM_WARPS)-1:0] issueWarpId [NUM_EXEC_UNITS-1:0]
);

    reg [$clog2(NUM_WARPS)-1:0] rrPtr [NUM_EXEC_UNITS-1:0];
    
    integer eu, w;
    reg [$clog2(NUM_WARPS)-1:0] selectedWarp;
    reg found;

    function automatic [$clog2(NUM_WARPS)-1:0] wrap_warp(integer base, integer offset);
        automatic integer raw = base + offset;
        return (raw >= NUM_WARPS) ? (raw - NUM_WARPS) : raw;
    endfunction
    
    reg [NUM_WARPS-1:0] selectedMask;
    
    always_comb begin
        selectedMask = 0;
        
        for (eu = 0; eu < NUM_EXEC_UNITS; eu = eu + 1) begin
            issueValid[eu] = 0;
            issueWarpId[eu] = 0;
            
            if (euReady[eu]) begin
                found = 0;
                selectedWarp = 0;
                
                for (w = 0; w < NUM_WARPS; w = w + 1) begin
                    if (!found) begin
                        automatic logic [$clog2(NUM_WARPS)-1:0] idx = wrap_warp(rrPtr[eu], w);
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
                rrPtr[eu] <= eu * (NUM_WARPS / NUM_EXEC_UNITS);
            end
        end else begin
            for (eu = 0; eu < NUM_EXEC_UNITS; eu = eu + 1) begin
                if (issueValid[eu]) begin
                    rrPtr[eu] <= wrap_warp(issueWarpId[eu], 1);
                end
            end
        end
    end

endmodule
