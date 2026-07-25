
`default_nettype none
`timescale 1ns/1ns

module mem_coalescer #(
    parameter THREADS_PER_WARP = 4,
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8,
    parameter CACHE_LINE_SIZE = 32,
    parameter LINE_ADDR_BITS = ADDR_WIDTH - $clog2(CACHE_LINE_SIZE)
) (
    input  wire clk,
    input  wire reset,
    input  wire [THREADS_PER_WARP-1:0] req_valid,
    input  wire [THREADS_PER_WARP-1:0] req_write,
    input  wire [ADDR_WIDTH-1:0] req_addr [THREADS_PER_WARP-1:0],
    input  wire [DATA_WIDTH-1:0] req_wdata [THREADS_PER_WARP-1:0],
    output wire [THREADS_PER_WARP-1:0] req_ready,
    output reg  [DATA_WIDTH-1:0] req_rdata [THREADS_PER_WARP-1:0],
    output reg  coal_valid,
    output reg  coal_write,
    output reg  [ADDR_WIDTH-1:0] coal_addr,
    output reg  [CACHE_LINE_SIZE*8-1:0] coal_wdata,
    output reg  [CACHE_LINE_SIZE-1:0] coal_wmask,
    input  wire coal_ready,
    input  wire [CACHE_LINE_SIZE*8-1:0] coal_rdata,
    output wire coalescer_busy,
    output reg  [31:0] total_requests,
    output reg  [31:0] coalesced_transactions,
    output reg  [15:0] coalesce_ratio
);
    localparam OFFSET_BITS = $clog2(CACHE_LINE_SIZE);
    localparam IDLE = 2'b00;
    localparam COALESCING = 2'b01;
    localparam WAITING = 2'b10;
    localparam DISTRIBUTING = 2'b11;
    reg [1:0] state;
    wire [LINE_ADDR_BITS-1:0] thread_line [THREADS_PER_WARP-1:0];
    wire [OFFSET_BITS-1:0] thread_offset [THREADS_PER_WARP-1:0];
    genvar t;
    generate
        for (t = 0; t < THREADS_PER_WARP; t++) begin : addr_decode
            assign thread_line[t] = req_addr[t][ADDR_WIDTH-1:OFFSET_BITS];
            assign thread_offset[t] = req_addr[t][OFFSET_BITS-1:0];
        end
    endgenerate
    reg [LINE_ADDR_BITS-1:0] primary_line;
    reg found_primary;
    reg [THREADS_PER_WARP-1:0] same_line_mask;
    always @(*) begin
        found_primary = 0;
        primary_line = 0;
        same_line_mask = 0;
        for (int i = 0; i < THREADS_PER_WARP; i++) begin
            if (req_valid[i] && !found_primary) begin
                primary_line = thread_line[i];
                found_primary = 1;
            end
        end
        for (int i = 0; i < THREADS_PER_WARP; i++) begin
            if (req_valid[i] && (thread_line[i] == primary_line)) begin
                same_line_mask[i] = 1;
            end
        end
    end

    function automatic int count_bits;
        input [THREADS_PER_WARP-1:0] vec;
        int cnt;
        begin
            cnt = 0;
            for (int i = 0; i < THREADS_PER_WARP; i++) begin
                if (vec[i]) cnt = cnt + 1;
            end
            count_bits = cnt;
        end
    endfunction
    reg [THREADS_PER_WARP-1:0] pending;
    reg [THREADS_PER_WARP-1:0] current_batch;
    assign coalescer_busy = (state != IDLE) || (|pending);
    assign req_ready = (state == IDLE) ? {THREADS_PER_WARP{1'b1}} : {THREADS_PER_WARP{1'b0}};
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            pending <= 0;
            current_batch <= 0;
            coal_valid <= 0;
            coal_write <= 0;
            coal_addr <= 0;
            coal_wdata <= 0;
            coal_wmask <= 0;
            total_requests <= 0;
            coalesced_transactions <= 0;
            coalesce_ratio <= 0;
            for (i = 0; i < THREADS_PER_WARP; i++) begin
                req_rdata[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (|req_valid) begin
                        pending <= req_valid;
                        total_requests <= total_requests + count_bits(req_valid);
                        state <= COALESCING;
                    end
                end
                COALESCING: begin
                    if (|pending) begin
                        current_batch <= pending & same_line_mask;
                        coal_valid <= 1;
                        coal_write <= req_write[0];
                        coal_addr <= {primary_line, {OFFSET_BITS{1'b0}}};
                        coal_wmask <= 0;
                        coal_wdata <= 0;
                        for (i = 0; i < THREADS_PER_WARP; i++) begin
                            if (pending[i] && same_line_mask[i]) begin
                                coal_wmask[thread_offset[i]] <= 1;
                                coal_wdata[thread_offset[i]*8 +: 8] <= req_wdata[i];
                            end
                        end
                        coalesced_transactions <= coalesced_transactions + 1;
                        state <= WAITING;
                    end else begin
                        state <= IDLE;
                    end
                end
                WAITING: begin
                    if (coal_ready) begin
                        coal_valid <= 0;
                        for (i = 0; i < THREADS_PER_WARP; i++) begin
                            if (current_batch[i]) begin
                                req_rdata[i] <= coal_rdata[thread_offset[i]*8 +: 8];
                            end
                        end
                        pending <= pending & ~current_batch;
                        if (|(pending & ~current_batch)) begin
                            state <= COALESCING;
                        end else begin
                            state <= IDLE;
                            if (coalesced_transactions > 0) begin
                                coalesce_ratio <= (total_requests << 8) / coalesced_transactions;
                            end
                        end
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
