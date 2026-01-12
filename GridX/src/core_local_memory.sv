`default_nettype none
`timescale 1ns/1ns

// L1 CORE LOCAL MEMORY
// > Private, low-latency SRAM for each core
// > Size: 32KB (Default)
// > Interfaces directly with Core's LSU arbiter
module core_local_memory #(
    parameter ADDR_WIDTH = 15,     // 32KB = 2^15
    parameter DATA_WIDTH = 8,      // Byte-addressable
    parameter MEM_DEPTH = 32768
) (
    input wire clk,
    
    // Core Interface (Single Port - Arbitrated by Core)
    input wire read_valid,
    input wire [ADDR_WIDTH-1:0] read_address,   
    input wire write_valid,
    input wire [ADDR_WIDTH-1:0] write_address,
    input wire [DATA_WIDTH-1:0] write_data,
    
    // Response
    output reg read_ready,
    output reg [DATA_WIDTH-1:0] read_data,
    output reg write_ready
);

    // Memory Array
    reg [DATA_WIDTH-1:0] memory [MEM_DEPTH-1:0];

    // Single-cycle latency
    always @(posedge clk) begin
        read_ready <= 0;
        write_ready <= 0;
        
        // Write
        if (write_valid) begin
            memory[write_address] <= write_data;
            write_ready <= 1;
        end
        
        // Read
        if (read_valid) begin
            read_data <= memory[read_address];
            read_ready <= 1;
        end
    end
    
    // Initial block for simulation/testing zeroing
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            memory[i] = 0;
        end
    end

endmodule
