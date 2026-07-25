// Through-Silicon Via (TSV) Die-to-Die Bridge
// Models vertical die-to-die interconnect latency and credit-based flow control across 3D stacked layers.

`default_nettype none
`timescale 1ns/1ns

module tsv_bridge #(
    parameter DATA_WIDTH = 1024,
    parameter LATENCY_CYCLES = 1,
    parameter BUFFER_DEPTH = 4
) (
    input  wire clk,
    input  wire reset,
    
    // Transmit Path (Local to TSV)
    input  wire tx_valid,
    input  wire [DATA_WIDTH-1:0] tx_data,
    output wire tx_ready,
    
    // Receive Path (TSV to Local)
    output wire rx_valid,
    output wire [DATA_WIDTH-1:0] rx_data,
    input  wire rx_ready,
    
    // TSV Physical Interface
    output wire tsv_out_valid,
    output wire [DATA_WIDTH-1:0] tsv_out_data,
    input  wire tsv_in_valid,
    input  wire [DATA_WIDTH-1:0] tsv_in_data,
    
    // Performance and Status
    output reg  [31:0] perf_tx_count,
    output reg  [31:0] perf_rx_count,
    output reg  [31:0] perf_stall_cycles,
    output wire link_up
);

    // TX FIFO
    reg [DATA_WIDTH-1:0] tx_fifo [0:BUFFER_DEPTH-1];
    reg [$clog2(BUFFER_DEPTH):0] tx_count;
    reg [$clog2(BUFFER_DEPTH)-1:0] tx_wr_ptr, tx_rd_ptr;
    
    assign tx_ready = (tx_count < BUFFER_DEPTH);
    
    // RX FIFO
    reg [DATA_WIDTH-1:0] rx_fifo [0:BUFFER_DEPTH-1];
    reg [$clog2(BUFFER_DEPTH):0] rx_count;
    reg [$clog2(BUFFER_DEPTH)-1:0] rx_wr_ptr, rx_rd_ptr;
    
    assign rx_valid = (rx_count > 0);
    assign rx_data = rx_fifo[rx_rd_ptr];
    
    // Pipeline for TSV TX latency simulation
    reg [DATA_WIDTH-1:0] tx_pipe_data [0:LATENCY_CYCLES-1];
    reg tx_pipe_valid [0:LATENCY_CYCLES-1];
    
    assign tsv_out_valid = tx_pipe_valid[LATENCY_CYCLES-1];
    assign tsv_out_data = tx_pipe_data[LATENCY_CYCLES-1];
    
    // Link Training State
    reg [2:0] link_train_count;
    reg link_up_reg;
    assign link_up = link_up_reg;
    
    integer i;
    
    wire tx_push = tx_valid && tx_ready;
    wire tx_pop = (tx_count > 0);
    wire tx_bypass = (tx_push && tx_count == 0);
    
    wire rx_push = tsv_in_valid && (rx_count < BUFFER_DEPTH);
    wire rx_pop = rx_valid && rx_ready;
    
    always @(posedge clk) begin
        if (reset) begin
            tx_count <= 0;
            tx_wr_ptr <= 0;
            tx_rd_ptr <= 0;
            rx_count <= 0;
            rx_wr_ptr <= 0;
            rx_rd_ptr <= 0;
            
            for (i = 0; i < LATENCY_CYCLES; i = i + 1) begin
                tx_pipe_valid[i] <= 0;
                tx_pipe_data[i] <= 0;
            end
            
            perf_tx_count <= 0;
            perf_rx_count <= 0;
            perf_stall_cycles <= 0;
            
            link_train_count <= 0;
            link_up_reg <= 0;
        end else begin
            // Link Training Sequence
            if (!link_up_reg) begin
                if (link_train_count == 3) begin
                    link_up_reg <= 1;
                end else begin
                    link_train_count <= link_train_count + 1;
                end
            end
            
            // TX Path FIFO Writes
            if (tx_push) begin
                tx_fifo[tx_wr_ptr] <= tx_data;
                tx_wr_ptr <= (tx_wr_ptr == BUFFER_DEPTH-1) ? 0 : tx_wr_ptr + 1;
                perf_tx_count <= perf_tx_count + 1;
            end else if (tx_valid) begin
                perf_stall_cycles <= perf_stall_cycles + 1;
            end
            
            // TX Path Pipeline Reads / Bypass
            if (tx_pop) begin
                 tx_pipe_valid[0] <= 1;
                 tx_pipe_data[0] <= tx_fifo[tx_rd_ptr];
                 tx_rd_ptr <= (tx_rd_ptr == BUFFER_DEPTH-1) ? 0 : tx_rd_ptr + 1;
            end else if (tx_bypass) begin
                 tx_pipe_valid[0] <= 1;
                 tx_pipe_data[0] <= tx_data;
            end else begin
                 tx_pipe_valid[0] <= 0;
            end
            
            // TX Count Update Logic
            if (tx_push && !tx_pop && !tx_bypass) begin
                tx_count <= tx_count + 1;
            end else if (!tx_push && tx_pop) begin
                tx_count <= tx_count - 1;
            end
            
            // Shift pipeline
            for (i = 1; i < LATENCY_CYCLES; i = i + 1) begin
                tx_pipe_valid[i] <= tx_pipe_valid[i-1];
                tx_pipe_data[i] <= tx_pipe_data[i-1];
            end
            
            // RX Path FIFO Writes
            if (rx_push) begin
                rx_fifo[rx_wr_ptr] <= tsv_in_data;
                rx_wr_ptr <= (rx_wr_ptr == BUFFER_DEPTH-1) ? 0 : rx_wr_ptr + 1;
                perf_rx_count <= perf_rx_count + 1;
            end
            
            // RX Path FIFO Reads
            if (rx_pop) begin
                rx_rd_ptr <= (rx_rd_ptr == BUFFER_DEPTH-1) ? 0 : rx_rd_ptr + 1;
            end
            
            // RX Count Update Logic
            case ({rx_push, rx_pop})
                2'b10: rx_count <= rx_count + 1;
                2'b01: rx_count <= rx_count - 1;
                default: ; // Unchanged on 00 or 11
            endcase
            
        end
    end

endmodule

