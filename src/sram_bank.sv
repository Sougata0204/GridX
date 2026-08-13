
`default_nettype none
`timescale 1ns/1ns

module sramBank #(
    parameter BANK_DEPTH = 256,
    parameter DATA_WIDTH = 64,
    parameter ADDR_BITS = $clog2(BANK_DEPTH)
) (
    input wire clk,
    input wire reset,
    input wire enable,
    input wire readValid,
    input wire [ADDR_BITS-1:0] readAddress,
    output reg readReady,
    output reg [DATA_WIDTH-1:0] readData,
    input wire writeValid,
    input wire [ADDR_BITS-1:0] writeAddress,
    input wire [DATA_WIDTH-1:0] writeData,
    output reg writeReady,
    output wire active
);
    reg [DATA_WIDTH-1:0] memory [BANK_DEPTH-1:0] = '{default: '0};
    assign active = enable & (readValid | writeValid);
    always @(posedge clk) begin
        if (reset) begin
            readReady <= 1'b0;
            readData <= {DATA_WIDTH{1'b0}};
            writeReady <= 1'b0;
        end else if (enable) begin
            if (readValid) begin
                readData <= memory[readAddress];
                readReady <= 1'b1;
            end else begin
                readReady <= 1'b0;
            end
            if (writeValid) begin
                memory[writeAddress] <= writeData;
                writeReady <= 1'b1;
            end else begin
                writeReady <= 1'b0;
            end
        end else begin
            readReady <= 1'b0;
            writeReady <= 1'b0;
        end
    end
endmodule
