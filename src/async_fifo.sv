
`default_nettype none
`timescale 1ns/1ns

module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 8,
    parameter PTR_WIDTH  = $clog2(DEPTH)
) (

    input  wire                  wr_clk,
    input  wire                  wr_rst,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  wr_full,

    input  wire                  rd_clk,
    input  wire                  rd_rst,
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire                  rd_empty
);

    reg [DATA_WIDTH-1:0] mem [DEPTH-1:0];

    reg [PTR_WIDTH:0] wr_ptr_bin, wr_ptr_gray;
    reg [PTR_WIDTH:0] rd_ptr_bin, rd_ptr_gray;

    reg [PTR_WIDTH:0] wr_ptr_gray_rd_sync1, wr_ptr_gray_rd_sync2;
    reg [PTR_WIDTH:0] rd_ptr_gray_wr_sync1, rd_ptr_gray_wr_sync2;

    function automatic [PTR_WIDTH:0] bin2gray(input [PTR_WIDTH:0] bin);
        bin2gray = bin ^ (bin >> 1);
    endfunction

    wire [PTR_WIDTH:0] wr_ptr_bin_next = wr_ptr_bin + (wr_en && !wr_full);
    wire wr_full_internal = (wr_ptr_gray == {~rd_ptr_gray_wr_sync2[PTR_WIDTH:PTR_WIDTH-1],
                                              rd_ptr_gray_wr_sync2[PTR_WIDTH-2:0]});
    assign wr_full = wr_full_internal;

    always @(posedge wr_clk) begin
        if (wr_rst) begin
            wr_ptr_bin  <= 0;
            wr_ptr_gray <= 0;
        end else begin
            if (wr_en && !wr_full_internal) begin
                mem[wr_ptr_bin[PTR_WIDTH-1:0]] <= wr_data;
                wr_ptr_bin  <= wr_ptr_bin_next;
                wr_ptr_gray <= bin2gray(wr_ptr_bin_next);
            end
        end
    end

    always @(posedge wr_clk) begin
        if (wr_rst) begin
            rd_ptr_gray_wr_sync1 <= 0;
            rd_ptr_gray_wr_sync2 <= 0;
        end else begin
            rd_ptr_gray_wr_sync1 <= rd_ptr_gray;
            rd_ptr_gray_wr_sync2 <= rd_ptr_gray_wr_sync1;
        end
    end

    wire [PTR_WIDTH:0] rd_ptr_bin_next = rd_ptr_bin + (rd_en && !rd_empty);
    wire rd_empty_internal = (rd_ptr_gray == wr_ptr_gray_rd_sync2);
    assign rd_empty = rd_empty_internal;
    assign rd_data = mem[rd_ptr_bin[PTR_WIDTH-1:0]];

    always @(posedge rd_clk) begin
        if (rd_rst) begin
            rd_ptr_bin  <= 0;
            rd_ptr_gray <= 0;
        end else begin
            if (rd_en && !rd_empty_internal) begin
                rd_ptr_bin  <= rd_ptr_bin_next;
                rd_ptr_gray <= bin2gray(rd_ptr_bin_next);
            end
        end
    end

    always @(posedge rd_clk) begin
        if (rd_rst) begin
            wr_ptr_gray_rd_sync1 <= 0;
            wr_ptr_gray_rd_sync2 <= 0;
        end else begin
            wr_ptr_gray_rd_sync1 <= wr_ptr_gray;
            wr_ptr_gray_rd_sync2 <= wr_ptr_gray_rd_sync1;
        end
    end

endmodule
