
`default_nettype none
`timescale 1ns/1ns

// GridX3 - Core Local Memory (L1 Scratchpad)
// Purpose: Per-cube local SRAM scratchpad for fast, low-latency data access.
// Architecture: Simple single-cycle read/write SRAM with proper reset.
// Parameters: ADDR_WIDTH, DATA_WIDTH, MEM_DEPTH
// Timing: 1-cycle read latency, 1-cycle write latency.
// Integration: Instantiated inside core.sv, mapped to address range 0x2000-0x7FFF.

module coreLocalMemory #(
    parameter ADDR_WIDTH = 15,
    parameter DATA_WIDTH = 8,
    parameter MEM_DEPTH  = 32768
) (
    input wire clk,
    input wire reset,
    input wire readValid,
    input wire [ADDR_WIDTH-1:0] readAddress,
    input wire writeValid,
    input wire [ADDR_WIDTH-1:0] writeAddress,
    input wire [DATA_WIDTH-1:0] writeData,
    output reg readReady,
    output reg [DATA_WIDTH-1:0] readData,
    output reg writeReady
);
    reg [DATA_WIDTH-1:0] memory [MEM_DEPTH-1:0] = '{default: '0};

    always @(posedge clk) begin
        if (reset) begin
            readReady  <= 1'b0;
            writeReady <= 1'b0;
            readData   <= {DATA_WIDTH{1'b0}};
        end else begin
            readReady  <= 1'b0;
            writeReady <= 1'b0;
            if (writeValid) begin
                memory[writeAddress] <= writeData;
                writeReady <= 1'b1;
            end
            if (readValid) begin
                readData  <= memory[readAddress];
                readReady <= 1'b1;
            end
        end
    end
endmodule
