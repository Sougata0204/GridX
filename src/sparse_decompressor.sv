
`default_nettype none
`timescale 1ns/1ns

module sparseDecompressor #(
    parameter DIM = 4,
    parameter DATA_BITS = 16,
    parameter SPARSITY_RATIO = 2 // 4:8 means half zeros, ratio=2
) (
    input  wire clk,
    input  wire reset,
    
    input  wire compressedValid,
    input  wire [(DIM*DIM*(DATA_BITS/SPARSITY_RATIO))-1:0] compressedData,
    input  wire [(DIM*DIM)-1:0] metadataMask,
    
    output reg  decompressReady,
    output reg  decompressedValid,
    output reg  [(DIM*DIM*DATA_BITS)-1:0] decompressedData,
    
    output reg  [31:0] perfZerosSkipped,
    output reg  [31:0] perfNonzerosProcessed
);

    localparam TOTAL_ELEMENTS = DIM * DIM;
    localparam NONZERO_ELEMENTS = TOTAL_ELEMENTS / SPARSITY_RATIO;
    
    reg [(DIM*DIM*DATA_BITS)-1:0] outDataComb;
    reg [5:0] nzCountComb;
    reg [5:0] zCountComb;

    integer i, j;
    
    always @(*) begin
        outDataComb = 0;
        nzCountComb = 0;
        zCountComb = 0;
        
        // Single-cycle scatter based on metadata mask
        // Note: For synthesizability, this requires a priority-encoder/MUX network
        // We will model it behaviorally here
        
        j = 0; // index into compressedData
        for (i = 0; i < TOTAL_ELEMENTS; i = i + 1) begin
            if (metadataMask[i] && j < NONZERO_ELEMENTS) begin
                outDataComb[(i*DATA_BITS) +: DATA_BITS] = compressedData[(j*DATA_BITS) +: DATA_BITS];
                nzCountComb = nzCountComb + 1;
                j = j + 1;
            end else begin
                outDataComb[(i*DATA_BITS) +: DATA_BITS] = {DATA_BITS{1'b0}};
                zCountComb = zCountComb + 1;
            end
        end
    end
    
    always @(posedge clk) begin
        if (reset) begin
            decompressReady <= 1;
            decompressedValid <= 0;
            decompressedData <= 0;
            perfZerosSkipped <= 0;
            perfNonzerosProcessed <= 0;
        end else begin
            decompressReady <= 1; // Always ready for single-cycle latency
            
            if (compressedValid) begin
                decompressedValid <= 1;
                decompressedData <= outDataComb;
                perfZerosSkipped <= perfZerosSkipped + zCountComb;
                perfNonzerosProcessed <= perfNonzerosProcessed + nzCountComb;
            end else begin
                decompressedValid <= 0;
            end
        end
    end

endmodule
