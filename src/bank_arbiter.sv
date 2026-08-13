
`default_nettype none
`timescale 1ns/1ps

module bankArbiter #(
    parameter NUM_REQUESTERS = 4,
    parameter NUM_BANKS = 4,
    parameter NUM_WARPS = 1,
    parameter THREADS_PER_WARP = 4,
    parameter BANK_BITS = $clog2(NUM_BANKS),
    parameter WARP_BITS = (NUM_WARPS > 1) ? $clog2(NUM_WARPS) : 1
) (
    input wire clk,
    input wire reset,
    input wire [NUM_REQUESTERS-1:0] requestValid,
    input wire [BANK_BITS-1:0] requestBank [NUM_REQUESTERS-1:0],
    input wire [NUM_REQUESTERS-1:0] requestIsWrite,
    output reg [NUM_REQUESTERS-1:0] grant,
    output reg [NUM_REQUESTERS-1:0] bankConflict,
    output reg [NUM_WARPS-1:0] warpStall,
    output reg [7:0] warpConflictCount [NUM_WARPS-1:0],
    output reg [7:0] warpGrantCount [NUM_WARPS-1:0],
    output reg [NUM_BANKS-1:0] bankReadEnable,
    output reg [NUM_BANKS-1:0] bankWriteEnable,
    output reg [$clog2(NUM_REQUESTERS)-1:0] bankOwner [NUM_BANKS-1:0]
);
    reg [$clog2(NUM_REQUESTERS)-1:0] priorityPtr [NUM_BANKS-1:0];
    reg [NUM_REQUESTERS-1:0] bankRequesters [NUM_BANKS-1:0];
    reg [NUM_BANKS-1:0] bankHasRequest;
    reg [$clog2(NUM_REQUESTERS)-1:0] selectedRequester [NUM_BANKS-1:0];
    reg [NUM_WARPS-1:0] warpHasConflict;
    reg [NUM_WARPS-1:0] warpHasGrant;
    integer i, j, k, w;

    function [WARP_BITS-1:0] getWarpId;
        input [$clog2(NUM_REQUESTERS)-1:0] threadId;
        begin
            getWarpId = threadId / THREADS_PER_WARP;
        end
    endfunction
    always @(posedge clk) begin
        if (reset) begin
            grant <= {NUM_REQUESTERS{1'b0}};
            bankConflict <= {NUM_REQUESTERS{1'b0}};
            warpStall <= {NUM_WARPS{1'b0}};
            bankReadEnable <= {NUM_BANKS{1'b0}};
            bankWriteEnable <= {NUM_BANKS{1'b0}};
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                priorityPtr[i] <= 0;
                bankOwner[i] <= 0;
            end
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                warpConflictCount[w] <= 0;
                warpGrantCount[w] <= 0;
            end
        end else begin
            grant <= {NUM_REQUESTERS{1'b0}};
            bankConflict <= {NUM_REQUESTERS{1'b0}};
            warpStall <= {NUM_WARPS{1'b0}};
            bankReadEnable <= {NUM_BANKS{1'b0}};
            bankWriteEnable <= {NUM_BANKS{1'b0}};
            warpHasConflict = {NUM_WARPS{1'b0}};
            warpHasGrant = {NUM_WARPS{1'b0}};
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                bankRequesters[i] = {NUM_REQUESTERS{1'b0}};
                bankHasRequest[i] = 1'b0;
            end
            for (j = 0; j < NUM_REQUESTERS; j = j + 1) begin
                if (requestValid[j]) begin
                    bankRequesters[requestBank[j]][j] = 1'b1;
                    bankHasRequest[requestBank[j]] = 1'b1;
                end
            end
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                if (bankHasRequest[i]) begin
                    reg foundReq;
                    selectedRequester[i] = priorityPtr[i];
                    foundReq = 0;
                    for (k = 0; k < NUM_REQUESTERS; k = k + 1) begin
                        if (!foundReq && bankRequesters[i][(priorityPtr[i] + k) % NUM_REQUESTERS]) begin
                            selectedRequester[i] = (priorityPtr[i] + k) % NUM_REQUESTERS;
                            foundReq = 1;
                        end
                    end
                    grant[selectedRequester[i]] <= 1'b1;
                    bankOwner[i] <= selectedRequester[i];
                    warpHasGrant[getWarpId(selectedRequester[i])] = 1'b1;
                    warpGrantCount[getWarpId(selectedRequester[i])] <=
                        warpGrantCount[getWarpId(selectedRequester[i])] + 1;
                    if (requestIsWrite[selectedRequester[i]]) begin
                        bankWriteEnable[i] <= 1'b1;
                    end else begin
                        bankReadEnable[i] <= 1'b1;
                    end
                    priorityPtr[i] <= (selectedRequester[i] + 1) % NUM_REQUESTERS;
                    for (j = 0; j < NUM_REQUESTERS; j = j + 1) begin
                        if (bankRequesters[i][j] && (j != selectedRequester[i])) begin
                            bankConflict[j] <= 1'b1;
                            warpHasConflict[getWarpId(j)] = 1'b1;
                            warpConflictCount[getWarpId(j)] <=
                                warpConflictCount[getWarpId(j)] + 1;
                        end
                    end
                end
            end
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                warpStall[w] <= warpHasConflict[w];
            end
        end
    end
    `ifdef FORMAL
    always @(posedge clk) begin
        if (!reset) begin
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                assert(!(bankReadEnable[i] && bankWriteEnable[i]))
                    else $error("ILLEGAL: Simultaneous read/write to bank %d", i);
            end
        end
    end
    reg [7:0] waitCounter [NUM_REQUESTERS-1:0];
    always @(posedge clk) begin
        if (reset) begin
            for (j = 0; j < NUM_REQUESTERS; j = j + 1) begin
                waitCounter[j] <= 0;
            end
        end else begin
            for (j = 0; j < NUM_REQUESTERS; j = j + 1) begin
                if (requestValid[j] && !grant[j]) begin
                    waitCounter[j] <= waitCounter[j] + 1;
                    assert(waitCounter[j] < NUM_REQUESTERS * 2)
                        else $error("STARVATION: Requester %d waiting too long", j);
                end else begin
                    waitCounter[j] <= 0;
                end
            end
        end
    end
    `endif
endmodule
