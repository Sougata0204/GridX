`default_nettype none
`timescale 1ns/1ns

// SRAM TILE BUFFER
// > Multi-bank SRAM array with bank interleaving for parallel access
// > Explicit scratchpad memory (not hardware-managed cache)
// > Software-visible allocation with deterministic latency
// > Supports bank-level power gating for energy efficiency
// > Parameterizable for research scalability studies (8KB-128KB)
module sram_tile_buffer #(
    parameter NUM_BANKS = 8,                    // Default: 8 banks (user-approved)
    parameter BANK_DEPTH = 256,                 // Rows per bank
    parameter DATA_WIDTH = 64,                  // Bits per row (8 bytes)
    parameter NUM_REQUESTERS = 8,               // Parallel thread requests
    parameter ADDR_BITS = $clog2(NUM_BANKS * BANK_DEPTH),
    parameter BANK_BITS = $clog2(NUM_BANKS),
    parameter OFFSET_BITS = $clog2(BANK_DEPTH)
) (
    input wire clk,
    input wire reset,

    // Memory region configuration
    input wire [ADDR_BITS-1:0] sram_base,
    input wire [ADDR_BITS-1:0] sram_limit,

    // Multi-thread read interface
    input wire [NUM_REQUESTERS-1:0] read_valid,
    input wire [ADDR_BITS-1:0] read_address [NUM_REQUESTERS-1:0],
    output reg [NUM_REQUESTERS-1:0] read_ready,
    output reg [DATA_WIDTH-1:0] read_data [NUM_REQUESTERS-1:0],

    // Multi-thread write interface
    input wire [NUM_REQUESTERS-1:0] write_valid,
    input wire [ADDR_BITS-1:0] write_address [NUM_REQUESTERS-1:0],
    input wire [DATA_WIDTH-1:0] write_data [NUM_REQUESTERS-1:0],
    output reg [NUM_REQUESTERS-1:0] write_ready,

    // Conflict reporting (to scheduler)
    output wire [NUM_REQUESTERS-1:0] bank_conflict,

    // Power management interface
    input wire [NUM_BANKS-1:0] bank_power_enable,
    output wire [NUM_BANKS-1:0] bank_active,

    // External access routing (addresses outside SRAM region)
    output reg [NUM_REQUESTERS-1:0] external_read_valid,
    output reg [ADDR_BITS-1:0] external_read_address [NUM_REQUESTERS-1:0],
    output reg [NUM_REQUESTERS-1:0] external_write_valid,
    output reg [ADDR_BITS-1:0] external_write_address [NUM_REQUESTERS-1:0],
    output reg [DATA_WIDTH-1:0] external_write_data [NUM_REQUESTERS-1:0]
);
    // Internal signals
    wire [BANK_BITS-1:0] decoded_bank [NUM_REQUESTERS-1:0];
    wire [OFFSET_BITS-1:0] decoded_offset [NUM_REQUESTERS-1:0];
    wire [NUM_REQUESTERS-1:0] is_sram;
    wire [NUM_REQUESTERS-1:0] is_external;
    wire [NUM_REQUESTERS-1:0] decode_valid;

    // Arbiter signals
    wire [NUM_REQUESTERS-1:0] arb_request;
    wire [NUM_REQUESTERS-1:0] arb_is_write;
    wire [NUM_REQUESTERS-1:0] arb_grant;
    wire [NUM_BANKS-1:0] arb_bank_read_enable;
    wire [NUM_BANKS-1:0] arb_bank_write_enable;
    wire [$clog2(NUM_REQUESTERS)-1:0] arb_bank_owner [NUM_BANKS-1:0];

    // Bank interface signals
    reg [NUM_BANKS-1:0] bank_read_valid;
    reg [OFFSET_BITS-1:0] bank_read_address [NUM_BANKS-1:0];
    wire [NUM_BANKS-1:0] bank_read_ready;
    wire [DATA_WIDTH-1:0] bank_read_data [NUM_BANKS-1:0];
    reg [NUM_BANKS-1:0] bank_write_valid;
    reg [OFFSET_BITS-1:0] bank_write_address [NUM_BANKS-1:0];
    reg [DATA_WIDTH-1:0] bank_write_data_reg [NUM_BANKS-1:0];
    wire [NUM_BANKS-1:0] bank_write_ready;

    // Address decoders for each requester
    genvar r;
    generate
        for (r = 0; r < NUM_REQUESTERS; r = r + 1) begin : addr_decode
            wire [ADDR_BITS-1:0] req_addr;
            assign req_addr = read_valid[r] ? read_address[r] : write_address[r];
            
            tile_address_decoder #(
                .ADDR_BITS(ADDR_BITS),
                .NUM_BANKS(NUM_BANKS),
                .BANK_DEPTH(BANK_DEPTH)
            ) decoder_inst (
                .clk(clk),
                .reset(reset),
                .sram_base(sram_base),
                .sram_limit(sram_limit),
                .address(req_addr),
                .address_valid(read_valid[r] | write_valid[r]),
                .bank_select(decoded_bank[r]),
                .bank_offset(decoded_offset[r]),
                .is_sram_access(is_sram[r]),
                .is_external_access(is_external[r]),
                .decode_valid(decode_valid[r])
            );
        end
    endgenerate

    // Prepare arbiter inputs
    assign arb_request = (read_valid | write_valid) & is_sram;
    assign arb_is_write = write_valid;

    // Bank arbiter
    bank_arbiter #(
        .NUM_REQUESTERS(NUM_REQUESTERS),
        .NUM_BANKS(NUM_BANKS)
    ) arbiter_inst (
        .clk(clk),
        .reset(reset),
        .request_valid(arb_request),
        .request_bank(decoded_bank),
        .request_is_write(arb_is_write),
        .grant(arb_grant),
        .bank_conflict(bank_conflict),
        .bank_read_enable(arb_bank_read_enable),
        .bank_write_enable(arb_bank_write_enable),
        .bank_owner(arb_bank_owner)
    );

    // SRAM banks
    genvar b;
    generate
        for (b = 0; b < NUM_BANKS; b = b + 1) begin : banks
            sram_bank #(
                .BANK_DEPTH(BANK_DEPTH),
                .DATA_WIDTH(DATA_WIDTH)
            ) bank_inst (
                .clk(clk),
                .reset(reset),
                .enable(bank_power_enable[b]),
                .read_valid(bank_read_valid[b]),
                .read_address(bank_read_address[b]),
                .read_ready(bank_read_ready[b]),
                .read_data(bank_read_data[b]),
                .write_valid(bank_write_valid[b]),
                .write_address(bank_write_address[b]),
                .write_data(bank_write_data_reg[b]),
                .write_ready(bank_write_ready[b]),
                .active(bank_active[b])
            );
        end
    endgenerate

    // Route requests to banks based on arbiter decisions
    integer i, j;
    always @(*) begin
        // Reset bank signals
        for (i = 0; i < NUM_BANKS; i = i + 1) begin
            bank_read_valid[i] = 1'b0;
            bank_write_valid[i] = 1'b0;
            bank_read_address[i] = {OFFSET_BITS{1'b0}};
            bank_write_address[i] = {OFFSET_BITS{1'b0}};
            bank_write_data_reg[i] = {DATA_WIDTH{1'b0}};
        end

        // Route granted requests to banks
        for (j = 0; j < NUM_REQUESTERS; j = j + 1) begin
            if (arb_grant[j] && is_sram[j]) begin
                if (read_valid[j]) begin
                    bank_read_valid[decoded_bank[j]] = 1'b1;
                    bank_read_address[decoded_bank[j]] = decoded_offset[j];
                end
                if (write_valid[j]) begin
                    bank_write_valid[decoded_bank[j]] = 1'b1;
                    bank_write_address[decoded_bank[j]] = decoded_offset[j];
                    bank_write_data_reg[decoded_bank[j]] = write_data[j];
                end
            end
        end
    end

    // Route responses back to requesters
    always @(*) begin
        for (i = 0; i < NUM_REQUESTERS; i = i + 1) begin
            read_ready[i] = 1'b0;
            read_data[i] = {DATA_WIDTH{1'b0}};
            write_ready[i] = 1'b0;
            external_read_valid[i] = 1'b0;
            external_read_address[i] = {ADDR_BITS{1'b0}};
            external_write_valid[i] = 1'b0;
            external_write_address[i] = {ADDR_BITS{1'b0}};
            external_write_data[i] = {DATA_WIDTH{1'b0}};
        end

        for (j = 0; j < NUM_REQUESTERS; j = j + 1) begin
            if (is_sram[j] && arb_grant[j]) begin
                // SRAM access - route bank response
                if (read_valid[j]) begin
                    read_ready[j] = bank_read_ready[decoded_bank[j]];
                    read_data[j] = bank_read_data[decoded_bank[j]];
                end
                if (write_valid[j]) begin
                    write_ready[j] = bank_write_ready[decoded_bank[j]];
                end
            end else if (is_external[j]) begin
                // External access - pass through
                if (read_valid[j]) begin
                    external_read_valid[j] = 1'b1;
                    external_read_address[j] = read_address[j];
                end
                if (write_valid[j]) begin
                    external_write_valid[j] = 1'b1;
                    external_write_address[j] = write_address[j];
                    external_write_data[j] = write_data[j];
                end
            end
        end
    end
endmodule
