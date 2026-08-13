
`default_nettype none
`timescale 1ns/1ns

module l2Slice #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 256,
    parameter MEM_DEPTH = 1024
) (
    input  wire clk,
    input  wire reset,
    
    input  wire reqValid,
    input  wire reqWrite,
    input  wire [ADDR_WIDTH-1:0] reqAddr,
    input  wire [DATA_WIDTH-1:0] reqWdata,
    
    output reg  reqReady,
    output reg  respValid,
    output reg  [DATA_WIDTH-1:0] reqRdata,
    
    output reg  [31:0] perfHits,
    output reg  [31:0] perfMisses
);

    localparam INDEX_WIDTH = $clog2(MEM_DEPTH);
    localparam TAG_WIDTH = (ADDR_WIDTH > INDEX_WIDTH) ? (ADDR_WIDTH - INDEX_WIDTH) : 1;
    
    reg [DATA_WIDTH-1:0] dataArray [0:MEM_DEPTH-1];
    reg [TAG_WIDTH-1:0]  tagArray  [0:MEM_DEPTH-1];
    reg                  validArray[0:MEM_DEPTH-1];
    
    wire [INDEX_WIDTH-1:0] index = reqAddr[INDEX_WIDTH-1:0];
    wire [TAG_WIDTH-1:0]   tag   = (ADDR_WIDTH > INDEX_WIDTH) ? reqAddr[ADDR_WIDTH-1 : INDEX_WIDTH] : 1'b0;
    
    integer i;
    
    always @(posedge clk) begin
        if (reset) begin
            reqReady <= 1;
            respValid <= 0;
            reqRdata <= 0;
            perfHits <= 0;
            perfMisses <= 0;
            
            for (i = 0; i < MEM_DEPTH; i = i + 1) begin
                validArray[i] <= 1'b0;
            end
        end else begin
            respValid <= 0;
            reqReady <= 1; // Always ready in this simple slice
            
            if (reqValid) begin
                if (validArray[index] && tagArray[index] == tag) begin
                    // Cache Hit
                    perfHits <= perfHits + 1;
                    if (reqWrite) begin
                        dataArray[index] <= reqWdata;
                    end else begin
                        reqRdata <= dataArray[index];
                        respValid <= 1;
                    end
                end else begin
                    // Cache Miss (simplified: direct allocation on miss)
                    perfMisses <= perfMisses + 1;
                    validArray[index] <= 1'b1;
                    tagArray[index] <= tag;
                    
                    if (reqWrite) begin
                        dataArray[index] <= reqWdata;
                    end else begin
                        dataArray[index] <= 0; // In a real cache, we'd fetch from memory
                        reqRdata <= 0;
                        respValid <= 1;
                    end
                end
            end
        end
    end

endmodule
