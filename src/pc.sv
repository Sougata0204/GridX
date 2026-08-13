`default_nettype none
`timescale 1ns/1ns

// my pc computes branching and next instruction
module pc #(
    parameter DataMemBits = 8,
    parameter ProgMemBits = 8
)(
    input wire clk,
    input wire reset,
    input wire enable,
    input wire [2:0] coreState,
    input wire [ProgMemBits-1:0] currentPc,
    input wire nzpWe,
    input wire [2:0] decodedNzp,
    input wire pcMux,
    input wire [ProgMemBits-1:0] decodedImm,
    input wire [DataMemBits-1:0] aluOut,
    output reg [ProgMemBits-1:0] nextPc
); 
    
    reg [2:0] nzpReg;
    
    always @(posedge clk) begin
        if (reset) begin
            nzpReg <= 3'b000;
            nextPc <= 0;
        end else if (enable) begin
            if (coreState == 3'b100 || coreState == 3'b011) begin
                if (pcMux == 1) begin
                    if (((nzpReg & decodedNzp) != 3'b0)) begin
                        nextPc <= decodedImm;
                    end else begin
                        nextPc <= currentPc + 1;
                    end
                end else begin
                    nextPc <= currentPc + 1;
                end
            end
            if (coreState == 3'b110) begin
                if (nzpWe) begin
                    nzpReg <= aluOut[2:0];
                end
            end
        end
    end
endmodule
