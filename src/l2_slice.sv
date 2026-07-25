
`default_nettype none
`timescale 1ns/1ns

module l2_slice #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 256,
    parameter MEM_DEPTH = 1024
) (
    input  wire clk,
    input  wire reset,
    
    input  wire req_valid,
    input  wire req_write,
    input  wire [ADDR_WIDTH-1:0] req_addr,
    input  wire [DATA_WIDTH-1:0] req_wdata,
    
    output reg  req_ready,
    output reg  resp_valid,
    output reg  [DATA_WIDTH-1:0] req_rdata,
    
    output reg  [31:0] perf_hits,
    output reg  [31:0] perf_misses
);

    localparam INDEX_WIDTH = $clog2(MEM_DEPTH);
    localparam TAG_WIDTH = (ADDR_WIDTH > INDEX_WIDTH) ? (ADDR_WIDTH - INDEX_WIDTH) : 1;
    
    reg [DATA_WIDTH-1:0] data_array [0:MEM_DEPTH-1];
    reg [TAG_WIDTH-1:0]  tag_array  [0:MEM_DEPTH-1];
    reg                  valid_array[0:MEM_DEPTH-1];
    
    wire [INDEX_WIDTH-1:0] index = req_addr[INDEX_WIDTH-1:0];
    wire [TAG_WIDTH-1:0]   tag   = (ADDR_WIDTH > INDEX_WIDTH) ? req_addr[ADDR_WIDTH-1 : INDEX_WIDTH] : 1'b0;
    
    integer i;
    
    always @(posedge clk) begin
        if (reset) begin
            req_ready <= 1;
            resp_valid <= 0;
            req_rdata <= 0;
            perf_hits <= 0;
            perf_misses <= 0;
            
            for (i = 0; i < MEM_DEPTH; i = i + 1) begin
                valid_array[i] <= 1'b0;
            end
        end else begin
            resp_valid <= 0;
            req_ready <= 1; // Always ready in this simple slice
            
            if (req_valid) begin
                if (valid_array[index] && tag_array[index] == tag) begin
                    // Cache Hit
                    perf_hits <= perf_hits + 1;
                    if (req_write) begin
                        data_array[index] <= req_wdata;
                    end else begin
                        req_rdata <= data_array[index];
                        resp_valid <= 1;
                    end
                end else begin
                    // Cache Miss (simplified: direct allocation on miss)
                    perf_misses <= perf_misses + 1;
                    valid_array[index] <= 1'b1;
                    tag_array[index] <= tag;
                    
                    if (req_write) begin
                        data_array[index] <= req_wdata;
                    end else begin
                        data_array[index] <= 0; // In a real cache, we'd fetch from memory
                        req_rdata <= 0;
                        resp_valid <= 1;
                    end
                end
            end
        end
    end

endmodule
