
`default_nettype none
`timescale 1ns/1ns

module instr_buffer #(
    parameter DEPTH = 32,
    parameter INSTR_WIDTH = 16,
    parameter DECODED_WIDTH = 64,
    parameter NUM_WARPS = 1,
    parameter WARP_ID_W = (NUM_WARPS > 1) ? $clog2(NUM_WARPS) : 1
) (
    input  wire clk,
    input  wire reset,

    input  wire                    wr_valid,
    input  wire [WARP_ID_W-1:0] wr_warp_id,
    input  wire [DECODED_WIDTH-1:0] wr_decoded_instr,
    input  wire [INSTR_WIDTH-1:0]  wr_raw_instr,
    output wire                    wr_ready,

    input  wire                    rd_valid,
    input  wire [WARP_ID_W-1:0] rd_warp_id,
    output wire [DECODED_WIDTH-1:0] rd_decoded_instr,
    output wire [INSTR_WIDTH-1:0]  rd_raw_instr,
    output wire                    rd_data_valid,

    output wire [NUM_WARPS-1:0]    warp_has_instr,
    output wire [NUM_WARPS-1:0]    warp_buf_full,
    output wire [$clog2(DEPTH):0]  total_occupancy
);

    localparam PTR_W = $clog2(DEPTH);

    reg [DECODED_WIDTH-1:0] buf_decoded [NUM_WARPS-1:0][DEPTH-1:0];
    reg [INSTR_WIDTH-1:0]   buf_raw     [NUM_WARPS-1:0][DEPTH-1:0];
    reg [PTR_W:0]           wr_ptr      [NUM_WARPS-1:0];
    reg [PTR_W:0]           rd_ptr      [NUM_WARPS-1:0];

    integer w;

    wire [PTR_W:0] warp_count [NUM_WARPS-1:0];
    generate
        genvar g;
        for (g = 0; g < NUM_WARPS; g = g + 1) begin : per_warp
            assign warp_count[g] = wr_ptr[g] - rd_ptr[g];
            assign warp_has_instr[g] = (warp_count[g] != 0);
            assign warp_buf_full[g]  = (warp_count[g] >= DEPTH);
        end
    endgenerate

    assign wr_ready = !warp_buf_full[wr_warp_id];

    assign rd_decoded_instr = buf_decoded[rd_warp_id][rd_ptr[rd_warp_id][PTR_W-1:0]];
    assign rd_raw_instr     = buf_raw[rd_warp_id][rd_ptr[rd_warp_id][PTR_W-1:0]];
    assign rd_data_valid    = warp_has_instr[rd_warp_id] && rd_valid;

    reg [$clog2(DEPTH):0] tot;
    always @(*) begin
        tot = 0;
        for (w = 0; w < NUM_WARPS; w = w + 1)
            tot = tot + warp_count[w];
    end
    assign total_occupancy = tot;

    always @(posedge clk) begin
        if (reset) begin
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                wr_ptr[w] <= 0;
                rd_ptr[w] <= 0;
            end
        end else begin

            if (wr_valid && !warp_buf_full[wr_warp_id]) begin
                buf_decoded[wr_warp_id][wr_ptr[wr_warp_id][PTR_W-1:0]] <= wr_decoded_instr;
                buf_raw[wr_warp_id][wr_ptr[wr_warp_id][PTR_W-1:0]]     <= wr_raw_instr;
                wr_ptr[wr_warp_id] <= wr_ptr[wr_warp_id] + 1;
            end

            if (rd_valid && warp_has_instr[rd_warp_id]) begin
                rd_ptr[rd_warp_id] <= rd_ptr[rd_warp_id] + 1;
            end
        end
    end

endmodule
