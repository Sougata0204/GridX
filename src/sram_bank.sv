
`default_nettype none
`timescale 1ns/1ns

module sram_bank #(
    parameter BANK_DEPTH = 256,
    parameter DATA_WIDTH = 64,
    parameter ADDR_BITS = $clog2(BANK_DEPTH)
) (
    input wire clk,
    input wire reset,
    input wire enable,
    input wire read_valid,
    input wire [ADDR_BITS-1:0] read_address,
    output reg read_ready,
    output reg [DATA_WIDTH-1:0] read_data,
    input wire write_valid,
    input wire [ADDR_BITS-1:0] write_address,
    input wire [DATA_WIDTH-1:0] write_data,
    output reg write_ready,
    output wire active
);
    reg [DATA_WIDTH-1:0] memory [BANK_DEPTH-1:0] = '{default: '0};
    assign active = enable & (read_valid | write_valid);
    always @(posedge clk) begin
        if (reset) begin
            read_ready <= 1'b0;
            read_data <= {DATA_WIDTH{1'b0}};
            write_ready <= 1'b0;
        end else if (enable) begin
            if (read_valid) begin
                read_data <= memory[read_address];
                read_ready <= 1'b1;
            end else begin
                read_ready <= 1'b0;
            end
            if (write_valid) begin
                memory[write_address] <= write_data;
                write_ready <= 1'b1;
            end else begin
                write_ready <= 1'b0;
            end
        end else begin
            read_ready <= 1'b0;
            write_ready <= 1'b0;
        end
    end
endmodule
