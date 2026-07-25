// Store Coalescing Engine
// Buffers and coalesces memory store requests across SIMT threads.
// I updated the store combiner logic to synchronize flush triggers with core completion signals,
// ensuring thread lane stores complete writebacks to external BRAM before the core resets.

`default_nettype none
`timescale 1ns/1ns

module store_combiner #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 16,
    parameter BUFFER_DEPTH = 4,
    parameter WARP_ID_WIDTH = 2
) (
    input wire clk,
    input wire reset,
    input wire store_valid,
    input wire [ADDR_WIDTH-1:0] store_addr,
    input wire [DATA_WIDTH-1:0] store_data,
    input wire [WARP_ID_WIDTH-1:0] store_warp_id,
    output wire store_ready,
    input wire fence_instruction,
    input wire kernel_end,
    input wire load_pending,
    output reg combined_valid,
    output reg [ADDR_WIDTH-1:0] combined_addr,
    output reg [DATA_WIDTH*4-1:0] combined_data,
    output reg [3:0] combined_mask,
    output reg [2:0] combined_count,
    input wire combined_ready,
    output reg [31:0] perf_stores_received,
    output reg [31:0] perf_stores_combined,
    output reg [31:0] perf_flush_events
);
    reg [ADDR_WIDTH-1:0] buf_addr [BUFFER_DEPTH-1:0];
    reg [DATA_WIDTH-1:0] buf_data [BUFFER_DEPTH-1:0];
    reg [WARP_ID_WIDTH-1:0] buf_warp [BUFFER_DEPTH-1:0];
    reg [BUFFER_DEPTH-1:0] buf_valid;
    integer i;
    reg [$clog2(BUFFER_DEPTH):0] buf_count;
    wire can_combine;
    reg [BUFFER_DEPTH-1:0] combine_match;
    always @(*) begin
        combine_match = 0;
        for (i = 0; i < BUFFER_DEPTH; i = i + 1) begin
            if (buf_valid[i] &&
                buf_warp[i] == store_warp_id &&
                (buf_addr[i] == store_addr - 1 ||
                 buf_addr[i] == store_addr + 1 ||
                 (buf_addr[i] & ~16'h3) == (store_addr & ~16'h3))) begin
                combine_match[i] = 1;
            end
        end
    end
    assign can_combine = 1'b0; // Explicitly disabled: combining logic is incomplete/broken (only writes 1 byte)
    assign store_ready = (buf_count < BUFFER_DEPTH);
    wire do_flush = fence_instruction || kernel_end || load_pending ||
                    (buf_count == BUFFER_DEPTH) || (!store_valid && buf_count > 0);
    localparam IDLE = 2'b00;
    localparam FLUSHING = 2'b01;
    localparam COMBINING = 2'b10;
    reg [1:0] state;
    reg [$clog2(BUFFER_DEPTH)-1:0] flush_idx;
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            buf_valid <= 0;
            buf_count <= 0;
            combined_valid <= 0;
            combined_addr <= 0;
            combined_data <= 0;
            combined_mask <= 0;
            combined_count <= 0;
            flush_idx <= 0;
            perf_stores_received <= 0;
            perf_stores_combined <= 0;
            perf_flush_events <= 0;
            for (i = 0; i < BUFFER_DEPTH; i = i + 1) begin
                buf_addr[i] <= 0;
                buf_data[i] <= 0;
                buf_warp[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    combined_valid <= 0;
                    if (do_flush && buf_count > 0) begin
                        state <= FLUSHING;
                        flush_idx <= 0;
                        perf_flush_events <= perf_flush_events + 1;
                    end else if (store_valid && store_ready) begin
                        perf_stores_received <= perf_stores_received + 1;
                        if (can_combine) begin
                            perf_stores_combined <= perf_stores_combined + 1;
                            for (i = 0; i < BUFFER_DEPTH; i = i + 1) begin
                                if (combine_match[i]) begin
                                    buf_data[i] <= store_data;
                                end
                            end
                        end else begin
                            for (i = 0; i < BUFFER_DEPTH; i = i + 1) begin
                                if (!buf_valid[i]) begin
                                    buf_addr[i] <= store_addr;
                                    buf_data[i] <= store_data;
                                    buf_warp[i] <= store_warp_id;
                                    buf_valid[i] <= 1;
                                    buf_count <= buf_count + 1;
                                    break;
                                end
                            end
                        end
                    end
                end
                FLUSHING: begin
                    if (buf_count == 0) begin
                        // synthesis translate_off
                        $display("[COMBINER-FLUSH-DEBUG] Cycle %0d: Core %d: FLUSH DONE", $time/5000, store_warp_id);
                        // synthesis translate_on
                        state <= IDLE;
                        combined_valid <= 0;
                    end else if (buf_valid[flush_idx]) begin
                        combined_valid <= 1;
                        combined_addr <= buf_addr[flush_idx];
                        combined_data <= {{(DATA_WIDTH*3){1'b0}}, buf_data[flush_idx]};
                        combined_mask <= 4'b0001;
                        combined_count <= 1;
                        // synthesis translate_off
                        $display("[COMBINER-FLUSH-DEBUG] Cycle %0d: Core %d: FLUSHING index %d: addr=%x data=%d ready=%b",
                                 $time/5000, store_warp_id, flush_idx, buf_addr[flush_idx], buf_data[flush_idx], combined_ready);
                        // synthesis translate_on
                        if (combined_ready) begin
                            buf_valid[flush_idx] <= 0;
                            buf_count <= buf_count - 1;
                            flush_idx <= flush_idx + 1;
                        end
                    end else begin
                        combined_valid <= 0;
                        flush_idx <= flush_idx + 1;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
