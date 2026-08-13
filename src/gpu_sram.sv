
`default_nettype none
`timescale 1ns/1ns

module gpuSram #(
    parameter DATA_MEM_ADDR_BITS = 8,
    parameter DATA_MEM_DATA_BITS = 8,
    parameter DATA_MEM_NUM_CHANNELS = 4,
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter PROGRAM_MEM_NUM_CHANNELS = 1,
    parameter NUM_CORES = 2,
    parameter THREADS_PER_BLOCK = 4,
    parameter ENABLE_SRAM_TILE_BUFFER = 1,
    parameter SRAM_NUM_BANKS = 8,
    parameter SRAM_BANK_DEPTH = 256,
    parameter SRAM_DATA_WIDTH = 64,
    parameter SRAM_BASE_DEFAULT = 8'h00,
    parameter SRAM_LIMIT_DEFAULT = 8'h7F,
    parameter ENABLE_DMA = 1,
    parameter DMA_BURST_SIZE = 8
) (
    input wire clk,
    input wire reset,
    input wire start,
    output wire done,
    input wire deviceControlWriteEnable,
    input wire [7:0] deviceControlData,
    input wire sramRegionWriteEnable,
    input wire [7:0] sramBaseIn,
    input wire [7:0] sramLimitIn,
    output wire [PROGRAM_MEM_NUM_CHANNELS-1:0] programMemReadValid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] programMemReadAddress [PROGRAM_MEM_NUM_CHANNELS-1:0],
    input wire [PROGRAM_MEM_NUM_CHANNELS-1:0] programMemReadReady,
    input wire [PROGRAM_MEM_DATA_BITS-1:0] programMemReadData [PROGRAM_MEM_NUM_CHANNELS-1:0],
    output wire [DATA_MEM_NUM_CHANNELS-1:0] dataMemReadValid,
    output wire [DATA_MEM_ADDR_BITS-1:0] dataMemReadAddress [DATA_MEM_NUM_CHANNELS-1:0],
    input wire [DATA_MEM_NUM_CHANNELS-1:0] dataMemReadReady,
    input wire [DATA_MEM_DATA_BITS-1:0] dataMemReadData [DATA_MEM_NUM_CHANNELS-1:0],
    output wire [DATA_MEM_NUM_CHANNELS-1:0] dataMemWriteValid,
    output wire [DATA_MEM_ADDR_BITS-1:0] dataMemWriteAddress [DATA_MEM_NUM_CHANNELS-1:0],
    output wire [DATA_MEM_DATA_BITS-1:0] dataMemWriteData [DATA_MEM_NUM_CHANNELS-1:0],
    input wire [DATA_MEM_NUM_CHANNELS-1:0] dataMemWriteReady,
    input wire dmaCmdValid,
    input wire dmaCmdDirection,
    input wire [DATA_MEM_ADDR_BITS-1:0] dmaExtAddr,
    input wire [10:0] dmaSramAddr,
    input wire [7:0] dmaLength,
    output wire dmaCmdReady,
    output wire dmaDone,
    output wire dmaBusy,
    input wire [SRAM_NUM_BANKS-1:0] forceBankEnable,
    input wire [SRAM_NUM_BANKS-1:0] forceBankSleep,
    output wire [SRAM_NUM_BANKS-1:0] bankActive,
    output wire [1:0] bankPowerState [SRAM_NUM_BANKS-1:0],
    output wire [SRAM_NUM_BANKS-1:0] bankNeedsReload
);
    reg [7:0] sramBaseReg;
    reg [7:0] sramLimitReg;
    always @(posedge clk) begin
        if (reset) begin
            sramBaseReg <= SRAM_BASE_DEFAULT;
            sramLimitReg <= SRAM_LIMIT_DEFAULT;
        end else if (sramRegionWriteEnable) begin
            sramBaseReg <= sramBaseIn;
            sramLimitReg <= sramLimitIn;
        end
    end
    wire [7:0] threadCount;
    reg [NUM_CORES-1:0] coreStart;
    reg [NUM_CORES-1:0] coreReset;
    reg [NUM_CORES-1:0] coreDone;
    reg [7:0] coreBlockId [NUM_CORES-1:0];
    reg [$clog2(THREADS_PER_BLOCK):0] coreThreadCount [NUM_CORES-1:0];
    localparam NUM_LSUS = NUM_CORES * THREADS_PER_BLOCK;
    wire [NUM_LSUS-1:0] sramReadValid;
    wire [DATA_MEM_ADDR_BITS-1:0] sramReadAddress [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] sramReadReady;
    wire [SRAM_DATA_WIDTH-1:0] sramReadData [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] sramWriteValid;
    wire [DATA_MEM_ADDR_BITS-1:0] sramWriteAddress [NUM_LSUS-1:0];
    wire [SRAM_DATA_WIDTH-1:0] sramWriteData [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] sramWriteReady;
    wire [NUM_LSUS-1:0] bankConflict;
    wire [NUM_LSUS-1:0] extReadValid;
    wire [DATA_MEM_ADDR_BITS-1:0] extReadAddress [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] extReadReady;
    wire [SRAM_DATA_WIDTH-1:0] extReadData [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] extWriteValid;
    wire [DATA_MEM_ADDR_BITS-1:0] extWriteAddress [NUM_LSUS-1:0];
    wire [SRAM_DATA_WIDTH-1:0] extWriteData [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] extWriteReady;
    localparam NUM_FETCHERS = NUM_CORES;
    reg [NUM_FETCHERS-1:0] fetcherReadValid;
    reg [PROGRAM_MEM_ADDR_BITS-1:0] fetcherReadAddress [NUM_FETCHERS-1:0];
    reg [NUM_FETCHERS-1:0] fetcherReadReady;
    reg [PROGRAM_MEM_DATA_BITS-1:0] fetcherReadData [NUM_FETCHERS-1:0];
    wire dmaExtReadValid;
    wire [DATA_MEM_ADDR_BITS-1:0] dmaExtReadAddress;
    wire dmaExtReadReady;
    wire [SRAM_DATA_WIDTH-1:0] dmaExtReadData;
    wire dmaExtWriteValid;
    wire [DATA_MEM_ADDR_BITS-1:0] dmaExtWriteAddress;
    wire [SRAM_DATA_WIDTH-1:0] dmaExtWriteData;
    wire dmaExtWriteReady;
    wire dmaSramReadValid;
    wire [10:0] dmaSramReadAddress;
    wire dmaSramReadReady;
    wire [SRAM_DATA_WIDTH-1:0] dmaSramReadData;
    wire dmaSramWriteValid;
    wire [10:0] dmaSramWriteAddress;
    wire [SRAM_DATA_WIDTH-1:0] dmaSramWriteData;
    wire dmaSramWriteReady;
    wire dmaError;
    wire [7:0] dmaWordsTransferred;
    dcr dcrInstance (
        .clk(clk),
        .reset(reset),
        .deviceControlWriteEnable(deviceControlWriteEnable),
        .deviceControlData(deviceControlData),
        .threadCount(threadCount),
        .dcrValid()
    );
    generate
        if (ENABLE_SRAM_TILE_BUFFER) begin : sramSubsystem
            sramController #(
                .NUM_CORES(NUM_CORES),
                .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
                .NUM_BANKS(SRAM_NUM_BANKS),
                .BANK_DEPTH(SRAM_BANK_DEPTH),
                .DATA_WIDTH(SRAM_DATA_WIDTH),
                .ADDR_BITS(DATA_MEM_ADDR_BITS)
            ) sramCtrlInst (
                .clk(clk),
                .reset(reset),
                .sramBaseReg(sramBaseReg),
                .sramLimitReg(sramLimitReg),
                .coreReadValid(sramReadValid),
                .coreReadAddress(sramReadAddress),
                .coreReadReady(sramReadReady),
                .coreReadData(sramReadData),
                .coreWriteValid(sramWriteValid),
                .coreWriteAddress(sramWriteAddress),
                .coreWriteData(sramWriteData),
                .coreWriteReady(sramWriteReady),
                .coreBankConflict(bankConflict),
                .extReadValid(extReadValid),
                .extReadAddress(extReadAddress),
                .extReadReady(extReadReady),
                .extReadData(extReadData),
                .extWriteValid(extWriteValid),
                .extWriteAddress(extWriteAddress),
                .extWriteData(extWriteData),
                .extWriteReady(extWriteReady),
                .dmaReadValid(dmaSramReadValid),
                .dmaReadAddress(dmaSramReadAddress[DATA_MEM_ADDR_BITS-1:0]),
                .dmaReadReady(dmaSramReadReady),
                .dmaReadData(dmaSramReadData),
                .dmaWriteValid(dmaSramWriteValid),
                .dmaWriteAddress(dmaSramWriteAddress[DATA_MEM_ADDR_BITS-1:0]),
                .dmaWriteData(dmaSramWriteData),
                .dmaWriteReady(dmaSramWriteReady),
                .forceBankEnable(forceBankEnable),
                .forceBankSleep(forceBankSleep),
                .bankActive(bankActive),
                .bankPowerState(bankPowerState),
                .bankNeedsReload(bankNeedsReload)
            );
        end
    endgenerate
    generate
        if (ENABLE_DMA) begin : dmaSubsystem
            dmaEngine #(
                .ADDR_BITS(DATA_MEM_ADDR_BITS),
                .DATA_WIDTH(SRAM_DATA_WIDTH),
                .BURST_SIZE(DMA_BURST_SIZE)
            ) dmaInst (
                .clk(clk),
                .reset(reset),
                .cmdValid(dmaCmdValid),
                .cmdDirection(dmaCmdDirection),
                .cmdExtAddr(dmaExtAddr),
                .cmdSramAddr(dmaSramAddr),
                .cmdLength(dmaLength),
                .cmdReady(dmaCmdReady),
                .cmdDone(dmaDone),
                .cmdError(dmaError),
                .extReadValid(dmaExtReadValid),
                .extReadAddress(dmaExtReadAddress),
                .extReadReady(dmaExtReadReady),
                .extReadData(dmaExtReadData),
                .extWriteValid(dmaExtWriteValid),
                .extWriteAddress(dmaExtWriteAddress),
                .extWriteData(dmaExtWriteData),
                .extWriteReady(dmaExtWriteReady),
                .sramReadValid(dmaSramReadValid),
                .sramReadAddress(dmaSramReadAddress),
                .sramReadReady(dmaSramReadReady),
                .sramReadData(dmaSramReadData),
                .sramWriteValid(dmaSramWriteValid),
                .sramWriteAddress(dmaSramWriteAddress),
                .sramWriteData(dmaSramWriteData),
                .sramWriteReady(dmaSramWriteReady),
                .busy(dmaBusy),
                .wordsTransferred(dmaWordsTransferred)
            );
        end else begin : noDma
            assign dmaCmdReady = 1'b0;
            assign dmaDone = 1'b0;
            assign dmaBusy = 1'b0;
        end
    endgenerate
    dispatch #(
        .NUM_CORES(NUM_CORES),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK)
    ) dispatchInstance (
        .clk(clk),
        .reset(reset),
        .start(start),
        .threadCount(threadCount),
        .coreDone(coreDone),
        .coreStart(coreStart),
        .coreReset(coreReset),
        .coreBlockId(coreBlockId),
        .coreThreadCount(coreThreadCount),
        .allBlocksDone(done)
    );
    controller #(
        .ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_BITS(DATA_MEM_DATA_BITS),
        .NUM_CONSUMERS(NUM_LSUS),
        .NUM_CHANNELS(DATA_MEM_NUM_CHANNELS)
    ) dataMemoryController (
        .clk(clk),
        .reset(reset),
        .consumerReadValid(extReadValid),
        .consumerReadAddress(extReadAddress),
        .consumerReadReady(extReadReady),
        .consumerReadData(extReadData),
        .consumerWriteValid(extWriteValid),
        .consumerWriteAddress(extWriteAddress),
        .consumerWriteData(extWriteData),
        .consumerWriteReady(extWriteReady),
        .memReadValid(dataMemReadValid),
        .memReadAddress(dataMemReadAddress),
        .memReadReady(dataMemReadReady),
        .memReadData(dataMemReadData),
        .memWriteValid(dataMemWriteValid),
        .memWriteAddress(dataMemWriteAddress),
        .memWriteData(dataMemWriteData),
        .memWriteReady(dataMemWriteReady)
    );
    controller #(
        .ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .NUM_CONSUMERS(NUM_FETCHERS),
        .NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS),
        .WRITE_ENABLE(0)
    ) programMemoryController (
        .clk(clk),
        .reset(reset),
        .consumerReadValid(fetcherReadValid),
        .consumerReadAddress(fetcherReadAddress),
        .consumerReadReady(fetcherReadReady),
        .consumerReadData(fetcherReadData),
        .memReadValid(programMemReadValid),
        .memReadAddress(programMemReadAddress),
        .memReadReady(programMemReadReady),
        .memReadData(programMemReadData)
    );
endmodule
