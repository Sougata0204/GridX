
`default_nettype none
`timescale 1ns/1ns

module instrBuffer #(
    parameter DEPTH = 32,
    parameter INSTR_WIDTH = 16,
    parameter DECODED_WIDTH = 64,
    parameter NUM_WARPS = 1,
    parameter WARP_ID_W = (NUM_WARPS > 1) ? $clog2(NUM_WARPS) : 1
) (
    input  wire clk,
    input  wire reset,

    input  wire                    wrValid,
    input  wire [WARP_ID_W-1:0] wrWarpId,
    input  wire [DECODED_WIDTH-1:0] wrDecodedInstr,
    input  wire [INSTR_WIDTH-1:0]  wrRawInstr,
    output wire                    wrReady,

    input  wire                    rdValid,
    input  wire [WARP_ID_W-1:0] rdWarpId,
    output wire [DECODED_WIDTH-1:0] rdDecodedInstr,
    output wire [INSTR_WIDTH-1:0]  rdRawInstr,
    output wire                    rdDataValid,

    output wire [NUM_WARPS-1:0]    warpHasInstr,
    output wire [NUM_WARPS-1:0]    warpBufFull,
    output wire [$clog2(DEPTH):0]  totalOccupancy
);

    localparam PTR_W = $clog2(DEPTH);

    reg [DECODED_WIDTH-1:0] bufDecoded [NUM_WARPS-1:0][DEPTH-1:0];
    reg [INSTR_WIDTH-1:0]   bufRaw     [NUM_WARPS-1:0][DEPTH-1:0];
    reg [PTR_W:0]           wrPtr      [NUM_WARPS-1:0];
    reg [PTR_W:0]           rdPtr      [NUM_WARPS-1:0];

    integer w;

    wire [PTR_W:0] warpCount [NUM_WARPS-1:0];
    generate
        genvar g;
        for (g = 0; g < NUM_WARPS; g = g + 1) begin : perWarp
            assign warpCount[g] = wrPtr[g] - rdPtr[g];
            assign warpHasInstr[g] = (warpCount[g] != 0);
            assign warpBufFull[g]  = (warpCount[g] >= DEPTH);
        end
    endgenerate

    assign wrReady = !warpBufFull[wrWarpId];

    assign rdDecodedInstr = bufDecoded[rdWarpId][rdPtr[rdWarpId][PTR_W-1:0]];
    assign rdRawInstr     = bufRaw[rdWarpId][rdPtr[rdWarpId][PTR_W-1:0]];
    assign rdDataValid    = warpHasInstr[rdWarpId] && rdValid;

    reg [$clog2(DEPTH):0] tot;
    always @(*) begin
        tot = 0;
        for (w = 0; w < NUM_WARPS; w = w + 1)
            tot = tot + warpCount[w];
    end
    assign totalOccupancy = tot;

    always @(posedge clk) begin
        if (reset) begin
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                wrPtr[w] <= 0;
                rdPtr[w] <= 0;
            end
        end else begin

            if (wrValid && !warpBufFull[wrWarpId]) begin
                bufDecoded[wrWarpId][wrPtr[wrWarpId][PTR_W-1:0]] <= wrDecodedInstr;
                bufRaw[wrWarpId][wrPtr[wrWarpId][PTR_W-1:0]]     <= wrRawInstr;
                wrPtr[wrWarpId] <= wrPtr[wrWarpId] + 1;
            end

            if (rdValid && warpHasInstr[rdWarpId]) begin
                rdPtr[rdWarpId] <= rdPtr[rdWarpId] + 1;
            end
        end
    end

endmodule
