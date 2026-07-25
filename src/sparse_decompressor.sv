
`default_nettype none
`timescale 1ns/1ns

module sparse_decompressor #(
    parameter DIM = 4,
    parameter DATA_BITS = 16,
    parameter SPARSITY_RATIO = 2 // 4:8 means half zeros, ratio=2
) (
    input  wire clk,
    input  wire reset,
    
    input  wire compressed_valid,
    input  wire [(DIM*DIM*(DATA_BITS/SPARSITY_RATIO))-1:0] compressed_data,
    input  wire [(DIM*DIM)-1:0] metadata_mask,
    
    output reg  decompress_ready,
    output reg  decompressed_valid,
    output reg  [(DIM*DIM*DATA_BITS)-1:0] decompressed_data,
    
    output reg  [31:0] perf_zeros_skipped,
    output reg  [31:0] perf_nonzeros_processed
);

    localparam TOTAL_ELEMENTS = DIM * DIM;
    localparam NONZERO_ELEMENTS = TOTAL_ELEMENTS / SPARSITY_RATIO;
    
    reg [(DIM*DIM*DATA_BITS)-1:0] out_data_comb;
    reg [5:0] nz_count_comb;
    reg [5:0] z_count_comb;

    integer i, j;
    
    always @(*) begin
        out_data_comb = 0;
        nz_count_comb = 0;
        z_count_comb = 0;
        
        // Single-cycle scatter based on metadata mask
        // Note: For synthesizability, this requires a priority-encoder/MUX network
        // We will model it behaviorally here
        
        j = 0; // index into compressed_data
        for (i = 0; i < TOTAL_ELEMENTS; i = i + 1) begin
            if (metadata_mask[i] && j < NONZERO_ELEMENTS) begin
                out_data_comb[(i*DATA_BITS) +: DATA_BITS] = compressed_data[(j*DATA_BITS) +: DATA_BITS];
                nz_count_comb = nz_count_comb + 1;
                j = j + 1;
            end else begin
                out_data_comb[(i*DATA_BITS) +: DATA_BITS] = {DATA_BITS{1'b0}};
                z_count_comb = z_count_comb + 1;
            end
        end
    end
    
    always @(posedge clk) begin
        if (reset) begin
            decompress_ready <= 1;
            decompressed_valid <= 0;
            decompressed_data <= 0;
            perf_zeros_skipped <= 0;
            perf_nonzeros_processed <= 0;
        end else begin
            decompress_ready <= 1; // Always ready for single-cycle latency
            
            if (compressed_valid) begin
                decompressed_valid <= 1;
                decompressed_data <= out_data_comb;
                perf_zeros_skipped <= perf_zeros_skipped + z_count_comb;
                perf_nonzeros_processed <= perf_nonzeros_processed + nz_count_comb;
            end else begin
                decompressed_valid <= 0;
            end
        end
    end

endmodule
