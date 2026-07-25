
`default_nettype none
`timescale 1ns/1ns

module warp_mem_unit #(
    parameter THREADS_PER_WARP = 4,
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8,
    parameter MAX_TRANSACTIONS = 2
) (
    input wire clk,
    input wire reset,
    input wire start,
    input wire is_read,
    output reg busy,
    output reg done,
    input wire [ADDR_WIDTH-1:0] thread_addr [THREADS_PER_WARP-1:0],
    input wire [THREADS_PER_WARP-1:0] thread_valid,
    input wire [DATA_WIDTH-1:0] thread_write_data [THREADS_PER_WARP-1:0],
    output reg [MAX_TRANSACTIONS-1:0] txn_valid,
    output reg [ADDR_WIDTH-1:0] txn_base_addr [MAX_TRANSACTIONS-1:0],
    output reg [THREADS_PER_WARP-1:0] txn_thread_mask [MAX_TRANSACTIONS-1:0],
    output reg [DATA_WIDTH*THREADS_PER_WARP-1:0] txn_write_data [MAX_TRANSACTIONS-1:0],
    output reg txn_is_read,
    input wire [MAX_TRANSACTIONS-1:0] txn_ready,
    input wire [DATA_WIDTH*THREADS_PER_WARP-1:0] txn_read_data [MAX_TRANSACTIONS-1:0],
    output reg [DATA_WIDTH-1:0] thread_read_data [THREADS_PER_WARP-1:0],
    output reg [THREADS_PER_WARP-1:0] thread_read_valid,
    output reg [7:0] coalesced_count,
    output reg [7:0] transaction_count
);
    localparam IDLE = 3'b000,
               ANALYZE = 3'b001,
               EMIT_TXN = 3'b010,
               WAIT_RESP = 3'b011,
               DISTRIBUTE = 3'b100,
               COMPLETE = 3'b101;
    reg [2:0] state;
    reg [1:0] current_txn;
    localparam SEGMENT_BITS = 6;
    reg [ADDR_WIDTH-SEGMENT_BITS-1:0] segment_base [MAX_TRANSACTIONS-1:0];
    reg [THREADS_PER_WARP-1:0] segment_mask [MAX_TRANSACTIONS-1:0];
    reg [1:0] num_segments;
    reg [THREADS_PER_WARP-1:0] remaining_threads;
    reg [ADDR_WIDTH-SEGMENT_BITS-1:0] first_segment;
    integer t, s;
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            current_txn <= 0;
            num_segments <= 0;
            coalesced_count <= 0;
            transaction_count <= 0;
            for (t = 0; t < MAX_TRANSACTIONS; t = t + 1) begin
                txn_valid[t] <= 1'b0;
                txn_base_addr[t] <= 0;
                txn_thread_mask[t] <= 0;
                segment_base[t] <= 0;
                segment_mask[t] <= 0;
            end
            for (t = 0; t < THREADS_PER_WARP; t = t + 1) begin
                thread_read_data[t] <= 0;
            end
            thread_read_valid <= 0;
            remaining_threads <= 0;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    if (start && (|thread_valid)) begin
                        busy <= 1'b1;
                        state <= ANALYZE;
                        remaining_threads <= thread_valid;
                        num_segments <= 0;
                        coalesced_count <= 0;
                        transaction_count <= 0;
                        txn_is_read <= is_read;
                        for (t = 0; t < MAX_TRANSACTIONS; t = t + 1) begin
                            txn_valid[t] <= 1'b0;
                            segment_mask[t] <= 0;
                        end
                    end
                end
                ANALYZE: begin
                    first_segment = 0;
                    for (t = 0; t < THREADS_PER_WARP; t = t + 1) begin
                        if (remaining_threads[t]) begin
                            first_segment = thread_addr[t][ADDR_WIDTH-1:SEGMENT_BITS];
                            break;
                        end
                    end
                    if (num_segments < MAX_TRANSACTIONS) begin
                        segment_base[num_segments] <= first_segment;
                        for (t = 0; t < THREADS_PER_WARP; t = t + 1) begin
                            if (remaining_threads[t]) begin
                                if (thread_addr[t][ADDR_WIDTH-1:SEGMENT_BITS] == first_segment) begin
                                    segment_mask[num_segments][t] <= 1'b1;
                                    remaining_threads[t] <= 1'b0;
                                    coalesced_count <= coalesced_count + 1;
                                end
                            end
                        end
                        num_segments <= num_segments + 1;
                    end
                    if ((remaining_threads == 0) || (num_segments >= MAX_TRANSACTIONS - 1)) begin
                        state <= EMIT_TXN;
                        current_txn <= 0;
                    end
                end
                EMIT_TXN: begin
                    for (s = 0; s < MAX_TRANSACTIONS; s = s + 1) begin
                        if (s < num_segments) begin
                            txn_valid[s] <= 1'b1;
                            txn_base_addr[s] <= {segment_base[s], {SEGMENT_BITS{1'b0}}};
                            txn_thread_mask[s] <= segment_mask[s];
                            transaction_count <= transaction_count + 1;
                            if (!is_read) begin
                                for (t = 0; t < THREADS_PER_WARP; t = t + 1) begin
                                    if (segment_mask[s][t]) begin
                                        txn_write_data[s][t*DATA_WIDTH +: DATA_WIDTH] <= thread_write_data[t];
                                    end
                                end
                            end
                        end else begin
                            txn_valid[s] <= 1'b0;
                        end
                    end
                    state <= WAIT_RESP;
                end
                WAIT_RESP: begin
                    if ((txn_valid & txn_ready) == txn_valid) begin
                        if (is_read) begin
                            state <= DISTRIBUTE;
                        end else begin
                            state <= COMPLETE;
                        end
                    end
                end
                DISTRIBUTE: begin
                    for (s = 0; s < MAX_TRANSACTIONS; s = s + 1) begin
                        if (txn_valid[s]) begin
                            for (t = 0; t < THREADS_PER_WARP; t = t + 1) begin
                                if (txn_thread_mask[s][t]) begin
                                    thread_read_data[t] <= txn_read_data[s][t*DATA_WIDTH +: DATA_WIDTH];
                                    thread_read_valid[t] <= 1'b1;
                                end
                            end
                        end
                    end
                    state <= COMPLETE;
                end
                COMPLETE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= IDLE;
                    for (t = 0; t < MAX_TRANSACTIONS; t = t + 1) begin
                        txn_valid[t] <= 1'b0;
                    end
                    thread_read_valid <= 0;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
