
`default_nettype none
`timescale 1ns/1ns

module mem_fin #(
    parameter BANK_DEPTH = 256,
    parameter DATA_W     = 8,
    parameter ADDR_W     = 10,
    parameter NUM_CH     = 4
) (
    input  wire clk,
    input  wire reset,

    input  wire [NUM_CH-1:0]  a_rd_valid,
    input  wire [ADDR_W-1:0]  a_rd_addr  [NUM_CH-1:0],
    output reg  [NUM_CH-1:0]  a_rd_ready,
    output reg  [DATA_W-1:0]  a_rd_data  [NUM_CH-1:0],

    input  wire [NUM_CH-1:0]  a_wr_valid,
    input  wire [ADDR_W-1:0]  a_wr_addr  [NUM_CH-1:0],
    input  wire [DATA_W-1:0]  a_wr_data  [NUM_CH-1:0],
    output reg  [NUM_CH-1:0]  a_wr_ready,

    input  wire [NUM_CH-1:0]  b_rd_valid,
    input  wire [ADDR_W-1:0]  b_rd_addr  [NUM_CH-1:0],
    output reg  [NUM_CH-1:0]  b_rd_ready,
    output reg  [DATA_W-1:0]  b_rd_data  [NUM_CH-1:0],

    input  wire [NUM_CH-1:0]  b_wr_valid,
    input  wire [ADDR_W-1:0]  b_wr_addr  [NUM_CH-1:0],
    input  wire [DATA_W-1:0]  b_wr_data  [NUM_CH-1:0],
    output reg  [NUM_CH-1:0]  b_wr_ready
);

    genvar ch;
    generate
        for (ch = 0; ch < NUM_CH; ch = ch + 1) begin : banks
            reg [DATA_W-1:0] sram [BANK_DEPTH-1:0];
            reg arb_toggle;

            always @(posedge clk) begin
                if (reset) begin
                    a_rd_ready[ch] <= 0;
                    a_wr_ready[ch] <= 0;
                    b_rd_ready[ch] <= 0;
                    b_wr_ready[ch] <= 0;
                    arb_toggle     <= 0;
                end else begin
                    a_rd_ready[ch] <= 0;
                    a_wr_ready[ch] <= 0;
                    b_rd_ready[ch] <= 0;
                    b_wr_ready[ch] <= 0;

                    if (a_wr_valid[ch] && b_wr_valid[ch]) begin
                        if (arb_toggle) begin
                            sram[a_wr_addr[ch][ADDR_W-3:0]] <= a_wr_data[ch];
                            a_wr_ready[ch] <= 1;
                        end else begin
                            sram[b_wr_addr[ch][ADDR_W-3:0]] <= b_wr_data[ch];
                            b_wr_ready[ch] <= 1;
                        end
                        arb_toggle <= ~arb_toggle;
                    end else if (a_wr_valid[ch]) begin
                        sram[a_wr_addr[ch][ADDR_W-3:0]] <= a_wr_data[ch];
                        a_wr_ready[ch] <= 1;
                    end else if (b_wr_valid[ch]) begin
                        sram[b_wr_addr[ch][ADDR_W-3:0]] <= b_wr_data[ch];
                        b_wr_ready[ch] <= 1;
                    end

                    if (a_rd_valid[ch] && b_rd_valid[ch]) begin
                        if (arb_toggle) begin
                            a_rd_data[ch]  <= sram[a_rd_addr[ch][ADDR_W-3:0]];
                            a_rd_ready[ch] <= 1;
                        end else begin
                            b_rd_data[ch]  <= sram[b_rd_addr[ch][ADDR_W-3:0]];
                            b_rd_ready[ch] <= 1;
                        end
                    end else if (a_rd_valid[ch]) begin
                        a_rd_data[ch]  <= sram[a_rd_addr[ch][ADDR_W-3:0]];
                        a_rd_ready[ch] <= 1;
                    end else if (b_rd_valid[ch]) begin
                        b_rd_data[ch]  <= sram[b_rd_addr[ch][ADDR_W-3:0]];
                        b_rd_ready[ch] <= 1;
                    end
                end
            end
        end
    endgenerate

endmodule
