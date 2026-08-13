
`default_nettype none
`timescale 1ns/1ns

module tileAddressDecoder #(
    parameter ADDR_BITS = 8,
    parameter NUM_BANKS = 8,
    parameter BANK_DEPTH = 256,
    parameter BANK_BITS = $clog2(NUM_BANKS),
    parameter OFFSET_BITS = $clog2(BANK_DEPTH)
) (
    input wire clk,
    input wire reset,
    input wire [ADDR_BITS-1:0] sramBase,
    input wire [ADDR_BITS-1:0] sramLimit,
    input wire [ADDR_BITS-1:0] address,
    input wire addressValid,
    output reg [BANK_BITS-1:0] bankSelect,
    output reg [OFFSET_BITS-1:0] bankOffset,
    output reg isSramAccess,
    output reg isExternalAccess,
    output reg decodeValid
);
    always @(*) begin
        isSramAccess = addressValid &&
                         (address >= sramBase) &&
                         (address <= sramLimit);
        isExternalAccess = addressValid && (address > sramLimit);
        decodeValid = addressValid;
        if (isSramAccess) begin
            bankSelect = address[BANK_BITS-1:0];
            bankOffset = address[ADDR_BITS-1:BANK_BITS];
        end else begin
            bankSelect = {BANK_BITS{1'b0}};
            bankOffset = {OFFSET_BITS{1'b0}};
        end
    end
endmodule
