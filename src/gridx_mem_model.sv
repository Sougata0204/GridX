
// GridX3 - DPI-C Lightweight Memory Model
// Offloads large memory arrays from SystemVerilog simulator (XSIM) to C++
// via DPI-C. This drastically reduces simulation memory usage, allowing
// multi-GB address spaces to be simulated on 24 GB RAM systems.
// The C backend uses a sparse hash map -- only accessed pages consume memory.

`default_nettype none
`timescale 1ns/1ns

module gridx_mem_model #(
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 8,
    parameter MEM_ID       = 0,      // Unique ID for multi-instance
    parameter INIT_FILE    = "",     // Optional hex init file
    parameter LATENCY      = 1       // Response latency in cycles
) (
    input  wire                    clk,
    input  wire                    reset,

    // Read Port
    input  wire                    rd_valid,
    input  wire [ADDR_WIDTH-1:0]  rd_addr,
    output reg                     rd_ready,
    output reg  [DATA_WIDTH-1:0]  rd_data,

    // Write Port
    input  wire                    wr_valid,
    input  wire [ADDR_WIDTH-1:0]  wr_addr,
    input  wire [DATA_WIDTH-1:0]  wr_data,
    output reg                     wr_ready,

    // Stats
    output reg  [31:0]            total_reads,
    output reg  [31:0]            total_writes,
    output reg  [31:0]            pages_allocated
);

    // DPI-C FUNCTION IMPORTS
    // These functions are implemented in gridx_mem_model.c
    // If DPI-C is not available, fall back to a small SV array.

`ifdef GRIDX_USE_DPI_C
    import "DPI-C" function void   mem_model_init(input int mem_id, input string init_file);
    import "DPI-C" function void   mem_model_write(
        input int mem_id, 
        input longint addr, 
        input int d0, input int d1, input int d2, input int d3,
        input int d4, input int d5, input int d6, input int d7
    );
    import "DPI-C" function void   mem_model_read(
        input int mem_id, 
        input longint addr,
        output int d0, output int d1, output int d2, output int d3,
        output int d4, output int d5, output int d6, output int d7
    );
    import "DPI-C" function int    mem_model_pages(input int mem_id);
    import "DPI-C" function void   mem_model_destroy(input int mem_id);
`endif

    // FALLBACK: Small SystemVerilog array for non-DPI simulation
    localparam FALLBACK_DEPTH = 65536;  // 64K entries max in fallback mode
    reg [DATA_WIDTH-1:0] fallback_mem [0:FALLBACK_DEPTH-1];

    // INITIALIZATION
    initial begin
`ifdef GRIDX_USE_DPI_C
        mem_model_init(MEM_ID, INIT_FILE);
        $display("[MEM_MODEL %0d] DPI-C mode: sparse hash map, init_file=%s", MEM_ID, INIT_FILE);
`else
        for (integer i = 0; i < FALLBACK_DEPTH; i = i + 1)
            fallback_mem[i] = {DATA_WIDTH{1'b0}};
        $display("[MEM_MODEL %0d] Fallback mode: %0d-entry SV array", MEM_ID, FALLBACK_DEPTH);
`endif
    end

    // LATENCY PIPELINE & DPI-C TEMP SIGNALS
    reg                    pipe_valid [0:LATENCY-1];
    reg [DATA_WIDTH-1:0]  pipe_data  [0:LATENCY-1];

    longint rd_c_addr;
    int rd_d0, rd_d1, rd_d2, rd_d3, rd_d4, rd_d5, rd_d6, rd_d7;
    longint wr_c_addr;

    integer p;
    always @(posedge clk) begin
        if (reset) begin
            for (p = 0; p < LATENCY; p = p + 1) begin
                pipe_valid[p] <= 1'b0;
                pipe_data[p]  <= {DATA_WIDTH{1'b0}};
            end
            rd_ready      <= 1'b0;
            rd_data       <= {DATA_WIDTH{1'b0}};
            wr_ready      <= 1'b0;
            total_reads   <= 32'd0;
            total_writes  <= 32'd0;
            pages_allocated <= 32'd0;
            rd_c_addr     <= 64'd0;
            wr_c_addr     <= 64'd0;
        end else begin
            // Write handling (1-cycle ack)
            wr_ready <= 1'b0;
            if (wr_valid) begin
`ifdef GRIDX_USE_DPI_C
                wr_c_addr = wr_addr;
                mem_model_write(MEM_ID, wr_c_addr,
                    wr_data[31:0],    wr_data[63:32],   wr_data[95:64],   wr_data[127:96],
                    wr_data[159:128], wr_data[191:160], wr_data[223:192], wr_data[255:224]
                );
`else
                if (wr_addr < FALLBACK_DEPTH)
                    fallback_mem[wr_addr] <= wr_data;
`endif
                wr_ready     <= 1'b1;
                total_writes <= total_writes + 32'd1;
            end

            // Read handling (with latency pipeline)
            // Stage 0: capture read request
            if (rd_valid) begin
`ifdef GRIDX_USE_DPI_C
                rd_c_addr = rd_addr;
                mem_model_read(MEM_ID, rd_c_addr,
                    rd_d0, rd_d1, rd_d2, rd_d3,
                    rd_d4, rd_d5, rd_d6, rd_d7
                );
                pipe_data[0]  <= {rd_d7, rd_d6, rd_d5, rd_d4, rd_d3, rd_d2, rd_d1, rd_d0};
`else
                pipe_data[0]  <= (rd_addr < FALLBACK_DEPTH) ? fallback_mem[rd_addr] : {DATA_WIDTH{1'b0}};
`endif
                pipe_valid[0] <= 1'b1;
                total_reads   <= total_reads + 32'd1;
            end else begin
                pipe_valid[0] <= 1'b0;
            end

            // Shift pipeline
            for (p = 1; p < LATENCY; p = p + 1) begin
                pipe_valid[p] <= pipe_valid[p-1];
                pipe_data[p]  <= pipe_data[p-1];
            end

            // Output from end of pipeline
            rd_ready <= pipe_valid[LATENCY-1];
            rd_data  <= pipe_data[LATENCY-1];

            // Update page count
`ifdef GRIDX_USE_DPI_C
            if ((total_reads + total_writes) % 1024 == 0)
                pages_allocated <= mem_model_pages(MEM_ID);
`else
            pages_allocated <= 32'd1;
`endif
        end
    end

    // CLEANUP
    // synthesis translate_off
    final begin
`ifdef GRIDX_USE_DPI_C
        mem_model_destroy(MEM_ID);
`endif
        $display("[MEM_MODEL %0d] Final stats: reads=%0d writes=%0d pages=%0d",
                 MEM_ID, total_reads, total_writes, pages_allocated);
    end
    // synthesis translate_on

endmodule
