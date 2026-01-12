`default_nettype none
`timescale 1ns/1ns

// SRAM BANK
// > Single SRAM bank with dual-port access (1 read + 1 write per cycle)
// > Deterministic single-cycle latency for on-chip operations
// > Supports power gating via enable signal
// > Synthesizable register-based SRAM model
module sram_bank #(
    parameter BANK_DEPTH = 256,     // Number of addressable rows
    parameter DATA_WIDTH = 64,      // Bits per row
    parameter ADDR_BITS = $clog2(BANK_DEPTH)
) (
    input wire clk,
    input wire reset,
    input wire enable,              // Power enable (clock gating target)

    // Read Port
    input wire read_valid,
    input wire [ADDR_BITS-1:0] read_address,
    output reg read_ready,
    output reg [DATA_WIDTH-1:0] read_data,

    // Write Port
    input wire write_valid,
    input wire [ADDR_BITS-1:0] write_address,
    input wire [DATA_WIDTH-1:0] write_data,
    output reg write_ready,

    // Status
    output wire active                // Bank is currently processing
);
    // SRAM storage array
    reg [DATA_WIDTH-1:0] memory [BANK_DEPTH-1:0];
    
    // Bank activity status
    assign active = enable & (read_valid | write_valid);

    // Initialize memory to zero (for simulation)
    integer i;
    initial begin
        for (i = 0; i < BANK_DEPTH; i = i + 1) begin
            memory[i] = {DATA_WIDTH{1'b0}};
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            read_ready <= 1'b0;
            read_data <= {DATA_WIDTH{1'b0}};
            write_ready <= 1'b0;
        end else if (enable) begin
            // Read operation - single cycle latency
            if (read_valid) begin
                read_data <= memory[read_address];
                read_ready <= 1'b1;
            end else begin
                read_ready <= 1'b0;
            end

            // Write operation - single cycle latency
            if (write_valid) begin
                memory[write_address] <= write_data;
                write_ready <= 1'b1;
            end else begin
                write_ready <= 1'b0;
            end
        end else begin
            // Bank disabled (power gated)
            read_ready <= 1'b0;
            write_ready <= 1'b0;
        end
    end
endmodule
