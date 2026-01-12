`default_nettype none
`timescale 1ns/1ns

// TILE ADDRESS DECODER
// > Decodes global tile address into bank selection and local offset
// > Uses low-order bit interleaving for conflict-free sequential access
// > Supports configurable memory region base/limit via control registers
// > Research-grade: parameterizable for scalability studies
module tile_address_decoder #(
    parameter ADDR_BITS = 8,           // Global address width
    parameter NUM_BANKS = 8,           // Number of SRAM banks
    parameter BANK_DEPTH = 256,        // Rows per bank
    parameter BANK_BITS = $clog2(NUM_BANKS),
    parameter OFFSET_BITS = $clog2(BANK_DEPTH)
) (
    input wire clk,
    input wire reset,

    // Memory region configuration (user-refinement: control register abstraction)
    input wire [ADDR_BITS-1:0] sram_base,   // Base address for SRAM region
    input wire [ADDR_BITS-1:0] sram_limit,  // Upper limit for SRAM region

    // Input address
    input wire [ADDR_BITS-1:0] address,
    input wire address_valid,

    // Decoded outputs
    output reg [BANK_BITS-1:0] bank_select,
    output reg [OFFSET_BITS-1:0] bank_offset,
    output reg is_sram_access,          // Address falls within SRAM region
    output reg is_external_access,      // Address requires external memory
    output reg decode_valid
);
    // Combinational decode logic for minimal latency
    always @(*) begin
        // Region check
        is_sram_access = address_valid && 
                         (address >= sram_base) && 
                         (address <= sram_limit);
        is_external_access = address_valid && (address > sram_limit);
        decode_valid = address_valid;

        if (is_sram_access) begin
            // Bank interleaving: low-order bits select bank
            // This spreads sequential accesses across banks for conflict reduction
            bank_select = address[BANK_BITS-1:0];
            // Higher bits form the offset within the bank
            bank_offset = address[ADDR_BITS-1:BANK_BITS];
        end else begin
            bank_select = {BANK_BITS{1'b0}};
            bank_offset = {OFFSET_BITS{1'b0}};
        end
    end
endmodule
