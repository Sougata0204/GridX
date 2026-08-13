
`default_nettype none
`timescale 1ns/1ns

module verticalMemoryController #(
    parameter NUM_CORES = 4,
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8,
    parameter L2_BASE_ADDR = 16'h8000,
    parameter L2_LIMIT_ADDR = 16'h83FF,
    parameter L2_DEPTH = 1024
) (
    input wire clk,
    input wire reset,
    input wire [NUM_CORES-1:0] coreReqValid,
    input wire [NUM_CORES-1:0] coreReqWrite,
    input wire [ADDR_WIDTH-1:0] coreReqAddr [NUM_CORES-1:0],
    input wire [DATA_WIDTH-1:0] coreReqData [NUM_CORES-1:0],
    output reg [NUM_CORES-1:0] coreReqGrant,
    output reg [DATA_WIDTH-1:0] coreReqRdata [NUM_CORES-1:0],
    output reg [NUM_CORES-1:0] coreReqReady,
    output reg globalReqValid,
    output reg globalReqWrite,
    output reg [ADDR_WIDTH-1:0] globalReqAddr,
    output reg [DATA_WIDTH-1:0] globalReqData,
    input wire globalReqReady,
    input wire [DATA_WIDTH-1:0] globalReqRdata
);
    reg [DATA_WIDTH-1:0] l2Memory [L2_DEPTH-1:0];
    localparam CORE_ID_W = (NUM_CORES > 1) ? $clog2(NUM_CORES) : 1;
    reg [CORE_ID_W-1:0] rrPtr;
    integer i;
    reg [CORE_ID_W-1:0] winnerId;
    reg found;
    reg [CORE_ID_W-1:0] idx;
    reg [ADDR_WIDTH-1:0] addr;
    reg [ADDR_WIDTH-1:0] offset;
    always @(posedge clk) begin
        if (reset) begin
            rrPtr <= 0;
            coreReqGrant <= 0;
            coreReqReady <= 0;
            globalReqValid <= 0;
            for (i=0; i<L2_DEPTH; i=i+1) l2Memory[i] = 0;
        end else begin
            coreReqGrant <= 0;
            coreReqReady <= 0;
            globalReqValid <= 0;
            found = 0;
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                idx = (rrPtr + i[CORE_ID_W-1:0]) % NUM_CORES;
                if (coreReqValid[idx] && !found) begin
                    winnerId = idx;
                    found = 1;
                end
            end
            if (found) begin
                addr = coreReqAddr[winnerId];
                if (addr >= L2_BASE_ADDR && addr <= L2_LIMIT_ADDR) begin
                    offset = addr - L2_BASE_ADDR;
                    if (coreReqWrite[winnerId]) begin
                        l2Memory[offset] <= coreReqData[winnerId];
                    end else begin
                        coreReqRdata[winnerId] <= l2Memory[offset];
                    end
                    coreReqReady[winnerId] <= 1;
                    coreReqGrant[winnerId] <= 1;
                end else begin
                    globalReqValid <= 1;
                    globalReqWrite <= coreReqWrite[winnerId];
                    globalReqAddr <= addr;
                    globalReqData <= coreReqData[winnerId];
                    if (globalReqReady) begin
                        coreReqReady[winnerId] <= 1;
                        coreReqRdata[winnerId] <= globalReqRdata;
                    end else begin
                        if (!globalReqReady) found = 0;
                    end
                end
                if (coreReqReady[winnerId]) begin
                    rrPtr <= rrPtr + 1;
                end
            end
        end
    end
endmodule
