
`default_nettype none
`timescale 1ns/1ns

module tile_address_decoder #(
    parameter ADDR_BITS = 8,
    parameter NUM_BANKS = 8,
    parameter BANK_DEPTH = 256,
    parameter BANK_BITS = $clog2(NUM_BANKS),
    parameter OFFSET_BITS = $clog2(BANK_DEPTH)
) (
    input wire clk,
    input wire reset,
    input wire [ADDR_BITS-1:0] sram_base,
    input wire [ADDR_BITS-1:0] sram_limit,
    input wire [ADDR_BITS-1:0] address,
    input wire address_valid,
    output reg [BANK_BITS-1:0] bank_select,
    output reg [OFFSET_BITS-1:0] bank_offset,
    output reg is_sram_access,
    output reg is_external_access,
    output reg decode_valid
);
    always @(*) begin
        is_sram_access = address_valid &&
                         (address >= sram_base) &&
                         (address <= sram_limit);
        is_external_access = address_valid && (address > sram_limit);
        decode_valid = address_valid;
        if (is_sram_access) begin
            bank_select = address[BANK_BITS-1:0];
            bank_offset = address[ADDR_BITS-1:BANK_BITS];
        end else begin
            bank_select = {BANK_BITS{1'b0}};
            bank_offset = {OFFSET_BITS{1'b0}};
        end
    end
endmodule
