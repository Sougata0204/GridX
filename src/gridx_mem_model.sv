
`default_nettype none
`timescale 1ns/1ns

// SystemVerilog DPI-C memory model wrapper interfacing the C backing store to the simulation environment.
module gridxMemModel #(
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 8,
    parameter memId       = 0,
    parameter initFile    = "",
    parameter LATENCY      = 1
) (
    input  wire                    clk,
    input  wire                    reset,

    input  wire                    rdValid,
    input  wire [ADDR_WIDTH-1:0]  rdAddr,
    output reg                     rdReady,
    output reg  [DATA_WIDTH-1:0]  rdData,

    input  wire                    wrValid,
    input  wire [ADDR_WIDTH-1:0]  wrAddr,
    input  wire [DATA_WIDTH-1:0]  wrData,
    output reg                     wrReady,

    output reg  [31:0]            totalReads,
    output reg  [31:0]            totalWrites,
    output reg  [31:0]            pagesAllocated
);

`ifdef GRIDX_USE_DPI_C
    import "DPI-C" function void   memModelInit(input int memId, input string initFile);
    import "DPI-C" function void   memModelWrite(
        input int memId, 
        input longint addr, 
        input int d0, input int d1, input int d2, input int d3,
        input int d4, input int d5, input int d6, input int d7
    );
    import "DPI-C" function void   memModelRead(
        input int memId, 
        input longint addr,
        output int d0, output int d1, output int d2, output int d3,
        output int d4, output int d5, output int d6, output int d7
    );
    import "DPI-C" function int    memModelPages(input int memId);
    import "DPI-C" function void   memModelDestroy(input int memId);
`endif

    localparam FALLBACK_DEPTH = 65536;
    reg [DATA_WIDTH-1:0] fallbackMem [0:FALLBACK_DEPTH-1];

    initial begin
`ifdef GRIDX_USE_DPI_C
        memModelInit(memId, initFile);
        $display("[MEM_MODEL %0d] DPI-C mode: sparse hash map, initFile=%s", memId, initFile);
`else
        for (integer i = 0; i < FALLBACK_DEPTH; i = i + 1)
            fallbackMem[i] = {DATA_WIDTH{1'b0}};
        $display("[MEM_MODEL %0d] Fallback mode: %0d-entry SV array", memId, FALLBACK_DEPTH);
`endif
    end

    reg                    pipeValid [0:LATENCY-1];
    reg [DATA_WIDTH-1:0]  pipeData  [0:LATENCY-1];

    longint rdCAddr;
    int rdD0, rdD1, rdD2, rdD3, rdD4, rdD5, rdD6, rdD7;
    longint wrCAddr;

    integer p;
    always @(posedge clk) begin
        if (reset) begin
            for (p = 0; p < LATENCY; p = p + 1) begin
                pipeValid[p] <= 1'b0;
                pipeData[p]  <= {DATA_WIDTH{1'b0}};
            end
            rdReady      <= 1'b0;
            rdData       <= {DATA_WIDTH{1'b0}};
            wrReady      <= 1'b0;
            totalReads   <= 32'd0;
            totalWrites  <= 32'd0;
            pagesAllocated <= 32'd0;
            rdCAddr     <= 64'd0;
            wrCAddr     <= 64'd0;
        end else begin
            wrReady <= 1'b0;
            if (wrValid) begin
`ifdef GRIDX_USE_DPI_C
                wrCAddr = wrAddr;
                memModelWrite(memId, wrCAddr,
                    wrData[31:0],    wrData[63:32],   wrData[95:64],   wrData[127:96],
                    wrData[159:128], wrData[191:160], wrData[223:192], wrData[255:224]
                );
`else
                if (wrAddr < FALLBACK_DEPTH)
                    fallbackMem[wrAddr] <= wrData;
`endif
                wrReady     <= 1'b1;
                totalWrites <= totalWrites + 32'd1;
            end

            if (rdValid) begin
`ifdef GRIDX_USE_DPI_C
                rdCAddr = rdAddr;
                memModelRead(memId, rdCAddr,
                    rdD0, rdD1, rdD2, rdD3,
                    rdD4, rdD5, rdD6, rdD7
                );
                pipeData[0]  <= {rdD7, rdD6, rdD5, rdD4, rdD3, rdD2, rdD1, rdD0};
`else
                pipeData[0]  <= (rdAddr < FALLBACK_DEPTH) ? fallbackMem[rdAddr] : {DATA_WIDTH{1'b0}};
`endif
                pipeValid[0] <= 1'b1;
                totalReads   <= totalReads + 32'd1;
            end else begin
                pipeValid[0] <= 1'b0;
            end

            for (p = 1; p < LATENCY; p = p + 1) begin
                pipeValid[p] <= pipeValid[p-1];
                pipeData[p]  <= pipeData[p-1];
            end

            rdReady <= pipeValid[LATENCY-1];
            rdData  <= pipeData[LATENCY-1];

`ifdef GRIDX_USE_DPI_C
            if ((totalReads + totalWrites) % 1024 == 0)
                pagesAllocated <= memModelPages(memId);
`else
            pagesAllocated <= 32'd1;
`endif
        end
    end

    final begin
`ifdef GRIDX_USE_DPI_C
        memModelDestroy(memId);
`endif
        $display("[MEM_MODEL %0d] Final stats: reads=%0d writes=%0d pages=%0d",
                 memId, totalReads, totalWrites, pagesAllocated);
    end

endmodule
