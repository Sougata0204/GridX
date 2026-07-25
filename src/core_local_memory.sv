
`default_nettype none
`timescale 1ns/1ns

// GridX3 - Core Local Memory (L1 Scratchpad)
// Purpose: Per-cube local SRAM scratchpad for fast, low-latency data access.
// Architecture: Simple single-cycle read/write SRAM with proper reset.
// Parameters: ADDR_WIDTH, DATA_WIDTH, MEM_DEPTH
// Timing: 1-cycle read latency, 1-cycle write latency.
// Integration: Instantiated inside core.sv, mapped to address range 0x2000-0x7FFF.

module core_local_memory #(
    parameter ADDR_WIDTH = 15,
    parameter DATA_WIDTH = 8,
    parameter MEM_DEPTH  = 32768
) (
    input wire clk,
    input wire reset,
    input wire read_valid,
    input wire [ADDR_WIDTH-1:0] read_address,
    input wire write_valid,
    input wire [ADDR_WIDTH-1:0] write_address,
    input wire [DATA_WIDTH-1:0] write_data,
    output reg read_ready,
    output reg [DATA_WIDTH-1:0] read_data,
    output reg write_ready
);
    reg [DATA_WIDTH-1:0] memory [MEM_DEPTH-1:0] = '{default: '0};

    always @(posedge clk) begin
        if (reset) begin
            read_ready  <= 1'b0;
            write_ready <= 1'b0;
            read_data   <= {DATA_WIDTH{1'b0}};
        end else begin
            read_ready  <= 1'b0;
            write_ready <= 1'b0;
            if (write_valid) begin
                memory[write_address] <= write_data;
                write_ready <= 1'b1;
            end
            if (read_valid) begin
                read_data  <= memory[read_address];
                read_ready <= 1'b1;
            end
        end
    end
endmodule
