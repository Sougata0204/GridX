
`default_nettype none
`timescale 1ns/1ps

// Core-local scratchpad memory providing single-cycle read/write access for private thread-block data.
module coreLocalMemory #(
    parameter ADDR_WIDTH = 15,
    parameter DATA_WIDTH = 8,
    parameter MEM_DEPTH  = 32768
) (
    input wire clk,
    input wire reset,
    input wire readValid,
    input wire [ADDR_WIDTH-1:0] readAddress,
    input wire writeValid,
    input wire [ADDR_WIDTH-1:0] writeAddress,
    input wire [DATA_WIDTH-1:0] writeData,
    output reg readReady,
    output reg [DATA_WIDTH-1:0] readData,
    output reg writeReady
);
    reg [DATA_WIDTH-1:0] memory [MEM_DEPTH-1:0] = '{default: '0};

    always @(posedge clk) begin
        if (reset) begin
            readReady  <= 1'b0;
            writeReady <= 1'b0;
            readData   <= {DATA_WIDTH{1'b0}};
        end else begin
            readReady  <= 1'b0;
            writeReady <= 1'b0;
            if (writeValid) begin
                memory[writeAddress] <= writeData;
                writeReady <= 1'b1;
            end
            if (readValid) begin
                if (writeValid && (writeAddress == readAddress)) begin
                    readData  <= writeData;
                end else begin
                    readData  <= memory[readAddress];
                end
                readReady <= 1'b1;
            end
        end
    end
endmodule
