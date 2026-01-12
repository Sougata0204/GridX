`default_nettype none
`timescale 1ns/1ns

// L2 SLICE MEMORY (1KB)
// > Storage component for one tile of the L2 Mesh
// > Size: 1KB (Default)
// > Synchronous Read/Write
module l2_slice #(
    parameter ADDR_WIDTH = 10,     // 1KB = 2^10
    parameter DATA_WIDTH = 8,      // Byte-addressable
    parameter MEM_DEPTH = 1024
) (
    input wire clk,
    
    // Single Port Interface (Arbitrated by Router)
    input wire req_valid,
    input wire req_write,
    input wire [ADDR_WIDTH-1:0] req_addr,
    input wire [DATA_WIDTH-1:0] req_wdata,
    
    // Response
    output reg req_ready,
    output reg [DATA_WIDTH-1:0] req_rdata
);

    // Memory Array
    reg [DATA_WIDTH-1:0] memory [MEM_DEPTH-1:0];

    // Single-cycle latency
    always @(posedge clk) begin
        req_ready <= 0;
        
        if (req_valid) begin
            if (req_write) begin
                memory[req_addr] <= req_wdata;
            end else begin
                req_rdata <= memory[req_addr];
            end
            req_ready <= 1; // Immediate Ack
        end
    end
    
    // Simulation Initialization
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            memory[i] = 0;
        end
    end

endmodule
