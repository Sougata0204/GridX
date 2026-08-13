
`default_nettype none
`timescale 1ns/1ns

// LSU Arbiter - Round-robin arbiter for Load/Store Unit memory requests.


module lsuArbiter #(
    parameter NUM_REQUESTERS = 4,
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 8,
    parameter IS_RESP = 0
) (
    input wire clk,
    input wire reset,
    input wire [NUM_REQUESTERS-1:0] requestValid,
    input wire [NUM_REQUESTERS-1:0] requestWrite,
    input wire [ADDR_WIDTH-1:0] requestAddr [NUM_REQUESTERS-1:0],
    input wire [DATA_WIDTH-1:0] requestData [NUM_REQUESTERS-1:0],
    output reg memValid,
    output reg memWrite,
    output reg [ADDR_WIDTH-1:0] memAddr,
    output reg [DATA_WIDTH-1:0] memData,
    input wire memReady,
    output reg [NUM_REQUESTERS-1:0] grant
);

    // Round-robin pointer: starts search from this index
    reg [$clog2(NUM_REQUESTERS)-1:0] rrPtr;

    integer i;
    reg found;

    always @(*) begin
        memValid = 0;
        memWrite = 0;
        memAddr = 0;
        memData = 0;
        grant = 0;
        found = 0;

        // Search starting from rrPtr, wrapping around
        for (i = 0; i < NUM_REQUESTERS; i = i + 1) begin
            automatic integer idx = (rrPtr + i) % NUM_REQUESTERS;
            if (requestValid[idx] && !found) begin
                memValid = 1;
                memWrite = requestWrite[idx];
                memAddr = requestAddr[idx];
                memData = requestData[idx];
                if (memReady) begin
                    grant[idx] = 1;
                end
                found = 1;
            end
        end
    end

    // Advance round-robin pointer after each grant
    always @(posedge clk) begin
        if (reset) begin
            rrPtr <= 0;
        end else if (|grant) begin
            // Move to next requester after the one just granted
            for (i = 0; i < NUM_REQUESTERS; i = i + 1) begin
                if (grant[i]) begin
                    rrPtr <= (i + 1) % NUM_REQUESTERS;
                end
            end
        end
    end

    `ifdef GRIDX_ARB_DEBUG
    reg [31:0] dbgCycleCnt;
    always @(posedge clk) begin
        if (reset)
            dbgCycleCnt <= 32'd0;
        else
            dbgCycleCnt <= dbgCycleCnt + 32'd1;
    end
    always @(posedge clk) begin
        if (!reset && (dbgCycleCnt < 350)) begin
            $display("[ARB-DEBUG-%0d] Cycle %0d: requestValid=%b memReady=%b grant=%b rrPtr=%0d",
                     IS_RESP, dbgCycleCnt, requestValid, memReady, grant, rrPtr);
        end
    end
    `endif

endmodule
