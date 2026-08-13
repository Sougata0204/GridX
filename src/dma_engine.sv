// Host DMA Controller
// Autonomous DMA engine for high-speed block transfers between host memory and on-chip SRAM/HBM.


`default_nettype none
`timescale 1ns/1ns

module dmaEngine #(
    parameter ADDR_BITS = 8,
    parameter DATA_WIDTH = 64,
    parameter BURST_SIZE = 8,
    parameter MAX_OUTSTANDING = 2,
    parameter SRAM_ADDR_BITS = 11
) (
    input wire clk,
    input wire reset,
    input wire cmdValid,
    input wire cmdDirection,
    input wire [ADDR_BITS-1:0] cmdExtAddr,
    input wire [SRAM_ADDR_BITS-1:0] cmdSramAddr,
    input wire [7:0] cmdLength,
    output reg cmdReady,
    output reg cmdDone,
    output reg cmdError,
    output reg extReadValid,
    output reg [ADDR_BITS-1:0] extReadAddress,
    input wire extReadReady,
    input wire [DATA_WIDTH-1:0] extReadData,
    output reg extWriteValid,
    output reg [ADDR_BITS-1:0] extWriteAddress,
    output reg [DATA_WIDTH-1:0] extWriteData,
    input wire extWriteReady,
    output reg sramReadValid,
    output reg [SRAM_ADDR_BITS-1:0] sramReadAddress,
    input wire sramReadReady,
    input wire [DATA_WIDTH-1:0] sramReadData,
    output reg sramWriteValid,
    output reg [SRAM_ADDR_BITS-1:0] sramWriteAddress,
    output reg [DATA_WIDTH-1:0] sramWriteData,
    input wire sramWriteReady,
    output reg busy,
    output reg [7:0] wordsTransferred
);
    localparam IDLE = 3'b000,
               LOAD_CMD = 3'b001,
               READ_EXT = 3'b010,
               WRITE_SRAM = 3'b011,
               READ_SRAM = 3'b100,
               WRITE_EXT = 3'b101,
               COMPLETE = 3'b110,
               ERROR = 3'b111;
    reg [2:0] state;
    reg direction;
    reg [ADDR_BITS-1:0] extAddr;
    reg [SRAM_ADDR_BITS-1:0] sramAddr;
    reg [7:0] remaining;
    reg [DATA_WIDTH-1:0] dataBuffer;
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            cmdReady <= 1'b1;
            cmdDone <= 1'b0;
            cmdError <= 1'b0;
            busy <= 1'b0;
            wordsTransferred <= 8'b0;
            extReadValid <= 1'b0;
            extReadAddress <= {ADDR_BITS{1'b0}};
            extWriteValid <= 1'b0;
            extWriteAddress <= {ADDR_BITS{1'b0}};
            extWriteData <= {DATA_WIDTH{1'b0}};
            sramReadValid <= 1'b0;
            sramReadAddress <= {SRAM_ADDR_BITS{1'b0}};
            sramWriteValid <= 1'b0;
            sramWriteAddress <= {SRAM_ADDR_BITS{1'b0}};
            sramWriteData <= {DATA_WIDTH{1'b0}};
            direction <= 1'b0;
            extAddr <= {ADDR_BITS{1'b0}};
            sramAddr <= {SRAM_ADDR_BITS{1'b0}};
            remaining <= 8'b0;
            dataBuffer <= {DATA_WIDTH{1'b0}};
        end else begin
            cmdDone <= 1'b0;
            cmdError <= 1'b0;
            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    cmdReady <= 1'b1;
                    if (cmdValid && cmdReady) begin
                        direction <= cmdDirection;
                        extAddr <= cmdExtAddr;
                        sramAddr <= cmdSramAddr;
                        remaining <= cmdLength;
                        wordsTransferred <= 8'b0;
                        cmdReady <= 1'b0;
                        busy <= 1'b1;
                        state <= LOAD_CMD;
                    end
                end
                LOAD_CMD: begin
                    if (remaining == 0) begin
                        state <= COMPLETE;
                    end else if (direction == 0) begin
                        state <= READ_EXT;
                    end else begin
                        state <= READ_SRAM;
                    end
                end
                READ_EXT: begin
                    extReadValid <= 1'b1;
                    extReadAddress <= extAddr;
                    if (extReadReady) begin
                        dataBuffer <= extReadData;
                        extReadValid <= 1'b0;
                        state <= WRITE_SRAM;
                    end
                end
                WRITE_SRAM: begin
                    sramWriteValid <= 1'b1;
                    sramWriteAddress <= sramAddr;
                    sramWriteData <= dataBuffer;
                    if (sramWriteReady) begin
                        sramWriteValid <= 1'b0;
                        extAddr <= extAddr + 1;
                        sramAddr <= sramAddr + 1;
                        remaining <= remaining - 1;
                        wordsTransferred <= wordsTransferred + 1;
                        if (remaining == 1) begin
                            state <= COMPLETE;
                        end else begin
                            state <= READ_EXT;
                        end
                    end
                end
                READ_SRAM: begin
                    sramReadValid <= 1'b1;
                    sramReadAddress <= sramAddr;
                    if (sramReadReady) begin
                        dataBuffer <= sramReadData;
                        sramReadValid <= 1'b0;
                        state <= WRITE_EXT;
                    end
                end
                WRITE_EXT: begin
                    extWriteValid <= 1'b1;
                    extWriteAddress <= extAddr;
                    extWriteData <= dataBuffer;
                    if (extWriteReady) begin
                        extWriteValid <= 1'b0;
                        extAddr <= extAddr + 1;
                        sramAddr <= sramAddr + 1;
                        remaining <= remaining - 1;
                        wordsTransferred <= wordsTransferred + 1;
                        if (remaining == 1) begin
                            state <= COMPLETE;
                        end else begin
                            state <= READ_SRAM;
                        end
                    end
                end
                COMPLETE: begin
                    cmdDone <= 1'b1;
                    busy <= 1'b0;
                    state <= IDLE;
                end
                ERROR: begin
                    cmdError <= 1'b1;
                    busy <= 1'b0;
                    state <= IDLE;
                end
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
