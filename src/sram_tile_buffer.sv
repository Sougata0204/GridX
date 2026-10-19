
`default_nettype none
`timescale 1ns/1ns

// SRAM tile buffer providing staging storage between the NoC and SRAM banks with request queuing and data alignment.
module sramTileBuffer #(
    parameter NUM_BANKS = 8,
    parameter BANK_DEPTH = 256,
    parameter DATA_WIDTH = 64,
    parameter NUM_REQUESTERS = 8,
    parameter ADDR_BITS = $clog2(NUM_BANKS * BANK_DEPTH),
    parameter BANK_BITS = $clog2(NUM_BANKS),
    parameter OFFSET_BITS = $clog2(BANK_DEPTH)
) (
    input wire clk,
    input wire reset,
    input wire [ADDR_BITS-1:0] sramBase,
    input wire [ADDR_BITS-1:0] sramLimit,
    input wire [NUM_REQUESTERS-1:0] readValid,
    input wire [ADDR_BITS-1:0] readAddress [NUM_REQUESTERS-1:0],
    output reg [NUM_REQUESTERS-1:0] readReady,
    output reg [DATA_WIDTH-1:0] readData [NUM_REQUESTERS-1:0],
    input wire [NUM_REQUESTERS-1:0] writeValid,
    input wire [ADDR_BITS-1:0] writeAddress [NUM_REQUESTERS-1:0],
    input wire [DATA_WIDTH-1:0] writeData [NUM_REQUESTERS-1:0],
    output reg [NUM_REQUESTERS-1:0] writeReady,
    output wire [NUM_REQUESTERS-1:0] bankConflict,
    input wire [NUM_BANKS-1:0] bankPowerEnable,
    output wire [NUM_BANKS-1:0] bankActive,
    output reg [NUM_REQUESTERS-1:0] externalReadValid,
    output reg [ADDR_BITS-1:0] externalReadAddress [NUM_REQUESTERS-1:0],
    output reg [NUM_REQUESTERS-1:0] externalWriteValid,
    output reg [ADDR_BITS-1:0] externalWriteAddress [NUM_REQUESTERS-1:0],
    output reg [DATA_WIDTH-1:0] externalWriteData [NUM_REQUESTERS-1:0]
);
    wire [BANK_BITS-1:0] decodedBank [NUM_REQUESTERS-1:0];
    wire [OFFSET_BITS-1:0] decodedOffset [NUM_REQUESTERS-1:0];
    wire [NUM_REQUESTERS-1:0] isSram;
    wire [NUM_REQUESTERS-1:0] isExternal;
    wire [NUM_REQUESTERS-1:0] decodeValid;
    wire [NUM_REQUESTERS-1:0] arbRequest;
    wire [NUM_REQUESTERS-1:0] arbIsWrite;
    wire [NUM_REQUESTERS-1:0] arbGrant;
    wire [NUM_BANKS-1:0] arbBankReadEnable;
    wire [NUM_BANKS-1:0] arbBankWriteEnable;
    wire [$clog2(NUM_REQUESTERS)-1:0] arbBankOwner [NUM_BANKS-1:0];
    reg [NUM_BANKS-1:0] bankReadValid;
    reg [OFFSET_BITS-1:0] bankReadAddress [NUM_BANKS-1:0];
    wire [NUM_BANKS-1:0] bankReadReady;
    wire [DATA_WIDTH-1:0] bankReadData [NUM_BANKS-1:0];
    reg [NUM_BANKS-1:0] bankWriteValid;
    reg [OFFSET_BITS-1:0] bankWriteAddress [NUM_BANKS-1:0];
    reg [DATA_WIDTH-1:0] bankWriteDataReg [NUM_BANKS-1:0];
    wire [NUM_BANKS-1:0] bankWriteReady;
    genvar r;
    generate
        for (r = 0; r < NUM_REQUESTERS; r = r + 1) begin : addrDecode
            wire [ADDR_BITS-1:0] reqAddr;
            assign reqAddr = readValid[r] ? readAddress[r] : writeAddress[r];
            tileAddressDecoder #(
                .ADDR_BITS(ADDR_BITS),
                .NUM_BANKS(NUM_BANKS),
                .BANK_DEPTH(BANK_DEPTH)
            ) decoderInst (
                .clk(clk),
                .reset(reset),
                .sramBase(sramBase),
                .sramLimit(sramLimit),
                .address(reqAddr),
                .addressValid(readValid[r] | writeValid[r]),
                .bankSelect(decodedBank[r]),
                .bankOffset(decodedOffset[r]),
                .isSramAccess(isSram[r]),
                .isExternalAccess(isExternal[r]),
                .decodeValid(decodeValid[r])
            );
        end
    endgenerate
    assign arbRequest = (readValid | writeValid) & isSram;
    assign arbIsWrite = writeValid;
    bankArbiter #(
        .NUM_REQUESTERS(NUM_REQUESTERS),
        .NUM_BANKS(NUM_BANKS)
    ) arbiterInst (
        .clk(clk),
        .reset(reset),
        .requestValid(arbRequest),
        .requestBank(decodedBank),
        .requestIsWrite(arbIsWrite),
        .grant(arbGrant),
        .bankConflict(bankConflict),
        .bankReadEnable(arbBankReadEnable),
        .bankWriteEnable(arbBankWriteEnable),
        .bankOwner(arbBankOwner),
        .warpStall(),
        .warpConflictCount(),
        .warpGrantCount()
    );
    genvar b;
    generate
        for (b = 0; b < NUM_BANKS; b = b + 1) begin : banks
            sramBank #(
                .BANK_DEPTH(BANK_DEPTH),
                .DATA_WIDTH(DATA_WIDTH)
            ) bankInst (
                .clk(clk),
                .reset(reset),
                .enable(bankPowerEnable[b]),
                .readValid(bankReadValid[b]),
                .readAddress(bankReadAddress[b]),
                .readReady(bankReadReady[b]),
                .readData(bankReadData[b]),
                .writeValid(bankWriteValid[b]),
                .writeAddress(bankWriteAddress[b]),
                .writeData(bankWriteDataReg[b]),
                .writeReady(bankWriteReady[b]),
                .active(bankActive[b])
            );
        end
    endgenerate
    integer i, j;
    always_comb begin
        for (int b_idx = 0; b_idx < NUM_BANKS; b_idx = b_idx + 1) begin
            bankReadValid[b_idx] = 1'b0;
            bankWriteValid[b_idx] = 1'b0;
            bankReadAddress[b_idx] = {OFFSET_BITS{1'b0}};
            bankWriteAddress[b_idx] = {OFFSET_BITS{1'b0}};
            bankWriteDataReg[b_idx] = {DATA_WIDTH{1'b0}};
        end
        for (int r_idx = 0; r_idx < NUM_REQUESTERS; r_idx = r_idx + 1) begin
            if (arbGrant[r_idx] && isSram[r_idx]) begin
                if (readValid[r_idx]) begin
                    bankReadValid[decodedBank[r_idx]] = 1'b1;
                    bankReadAddress[decodedBank[r_idx]] = decodedOffset[r_idx];
                end
                if (writeValid[r_idx]) begin
                    bankWriteValid[decodedBank[r_idx]] = 1'b1;
                    bankWriteAddress[decodedBank[r_idx]] = decodedOffset[r_idx];
                    bankWriteDataReg[decodedBank[r_idx]] = writeData[r_idx];
                end
            end
        end
    end
    always_comb begin
        for (int r2_idx = 0; r2_idx < NUM_REQUESTERS; r2_idx = r2_idx + 1) begin
            readReady[r2_idx] = 1'b0;
            readData[r2_idx] = {DATA_WIDTH{1'b0}};
            writeReady[r2_idx] = 1'b0;
            externalReadValid[r2_idx] = 1'b0;
            externalReadAddress[r2_idx] = {ADDR_BITS{1'b0}};
            externalWriteValid[r2_idx] = 1'b0;
            externalWriteAddress[r2_idx] = {ADDR_BITS{1'b0}};
            externalWriteData[r2_idx] = {DATA_WIDTH{1'b0}};
        end
        for (int r3_idx = 0; r3_idx < NUM_REQUESTERS; r3_idx = r3_idx + 1) begin
            if (isSram[r3_idx] && arbGrant[r3_idx]) begin
                if (readValid[r3_idx]) begin
                    readReady[r3_idx] = bankReadReady[decodedBank[r3_idx]];
                    readData[r3_idx] = bankReadData[decodedBank[r3_idx]];
                end
                if (writeValid[r3_idx]) begin
                    writeReady[r3_idx] = bankWriteReady[decodedBank[r3_idx]];
                end
            end else if (isExternal[r3_idx]) begin
                if (readValid[r3_idx]) begin
                    externalReadValid[r3_idx] = 1'b1;
                    externalReadAddress[r3_idx] = readAddress[r3_idx];
                end
                if (writeValid[r3_idx]) begin
                    externalWriteValid[r3_idx] = 1'b1;
                    externalWriteAddress[r3_idx] = writeAddress[r3_idx];
                    externalWriteData[r3_idx] = writeData[r3_idx];
                end
            end
        end
    end
endmodule
