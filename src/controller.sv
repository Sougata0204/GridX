
`default_nettype none
`timescale 1ns/1ns

module controller #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 16,
    parameter NUM_CONSUMERS = 4,
    parameter NUM_CHANNELS = 1,
    parameter WRITE_ENABLE = 1
) (
    input wire clk,
    input wire reset,
    input wire [NUM_CONSUMERS-1:0] consumer_read_valid,
    input wire [ADDR_BITS-1:0] consumer_read_address [NUM_CONSUMERS-1:0],
    output reg [NUM_CONSUMERS-1:0] consumer_read_ready,
    output reg [DATA_BITS-1:0] consumer_read_data [NUM_CONSUMERS-1:0],
    input wire [NUM_CONSUMERS-1:0] consumer_write_valid,
    input wire [ADDR_BITS-1:0] consumer_write_address [NUM_CONSUMERS-1:0],
    input wire [DATA_BITS-1:0] consumer_write_data [NUM_CONSUMERS-1:0],
    output reg [NUM_CONSUMERS-1:0] consumer_write_ready,
    output reg [NUM_CHANNELS-1:0] mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_address [NUM_CHANNELS-1:0],
    input wire [NUM_CHANNELS-1:0] mem_read_ready,
    input wire [DATA_BITS-1:0] mem_read_data [NUM_CHANNELS-1:0],
    output reg [NUM_CHANNELS-1:0] mem_write_valid,
    output reg [ADDR_BITS-1:0] mem_write_address [NUM_CHANNELS-1:0],
    output reg [DATA_BITS-1:0] mem_write_data [NUM_CHANNELS-1:0],
    input wire [NUM_CHANNELS-1:0] mem_write_ready,
    output wire [$clog2(NUM_CHANNELS+1)-1:0] pending_transactions
);
    localparam IDLE = 3'b000,
        READ_WAITING = 3'b010,
        WRITE_WAITING = 3'b011,
        READ_RELAYING = 3'b100,
        WRITE_RELAYING = 3'b101;
    reg [2:0] controller_state [NUM_CHANNELS-1:0];
    reg [$clog2(NUM_CONSUMERS)-1:0] current_consumer [NUM_CHANNELS-1:0];
    reg [NUM_CONSUMERS-1:0] channel_serving_consumer_ff;
    wire [NUM_CONSUMERS-1:0] channel_serving_consumer;
    assign channel_serving_consumer = channel_serving_consumer_ff;
    always @(posedge clk) begin
        if (reset) begin
            mem_read_valid <= 0;
            mem_write_valid <= 0;
            consumer_read_ready <= 0;
            consumer_write_ready <= 0;
            channel_serving_consumer_ff <= 0;
            for (int i = 0; i < NUM_CHANNELS; i = i + 1) begin
                mem_read_address[i] <= 0;
                mem_write_address[i] <= 0;
                mem_write_data[i] <= 0;
                current_consumer[i] <= 0;
                controller_state[i] <= 0;
            end
            for (int j = 0; j < NUM_CONSUMERS; j = j + 1) begin
                consumer_read_data[j] <= 0;
            end
        end else begin
            for (int i = 0; i < NUM_CHANNELS; i = i + 1) begin
                case (controller_state[i])
                    IDLE: begin
                        for (int j = 0; j < NUM_CONSUMERS; j = j + 1) begin
                            if (consumer_read_valid[j] && !channel_serving_consumer_ff[j]) begin
                                channel_serving_consumer_ff[j] <= 1;
                                current_consumer[i] <= j;
                                mem_read_valid[i] <= 1;
                                mem_read_address[i] <= consumer_read_address[j];
                                controller_state[i] <= READ_WAITING;
                                break;
                            end else if (consumer_write_valid[j] && !channel_serving_consumer_ff[j]) begin
                                channel_serving_consumer_ff[j] <= 1;
                                current_consumer[i] <= j;
                                mem_write_valid[i] <= 1;
                                mem_write_address[i] <= consumer_write_address[j];
                                mem_write_data[i] <= consumer_write_data[j];
                                controller_state[i] <= WRITE_WAITING;
                                break;
                            end
                        end
                    end
                    READ_WAITING: begin
                        if (mem_read_ready[i]) begin
                            mem_read_valid[i] <= 0;
                            consumer_read_ready[current_consumer[i]] <= 1;
                            consumer_read_data[current_consumer[i]] <= mem_read_data[i];
                            controller_state[i] <= READ_RELAYING;
                        end
                    end
                    WRITE_WAITING: begin
                        if (mem_write_ready[i]) begin
                            mem_write_valid[i] <= 0;
                            consumer_write_ready[current_consumer[i]] <= 1;
                            controller_state[i] <= WRITE_RELAYING;
                        end
                    end
                    READ_RELAYING: begin
                        if (!consumer_read_valid[current_consumer[i]]) begin
                            channel_serving_consumer_ff[current_consumer[i]] <= 0;
                            consumer_read_ready[current_consumer[i]] <= 0;
                            controller_state[i] <= IDLE;
                        end
                    end
                    WRITE_RELAYING: begin
                        if (!consumer_write_valid[current_consumer[i]]) begin
                            channel_serving_consumer_ff[current_consumer[i]] <= 0;
                            consumer_write_ready[current_consumer[i]] <= 0;
                            controller_state[i] <= IDLE;
                        end
                    end
                endcase
            end
        end
    end
    reg [$clog2(NUM_CHANNELS+1)-1:0] pending_count;
    integer pc;
    always @(*) begin
        pending_count = 0;
        for (pc = 0; pc < NUM_CHANNELS; pc = pc + 1) begin
            if (controller_state[pc] != IDLE) begin
                pending_count = pending_count + 1;
            end
        end
    end
    assign pending_transactions = pending_count;
    // synthesis translate_off
    localparam TRACE_ADDR = 'h00c000;
    reg [31:0] debug_counter;
    always @(posedge clk) begin
        if (reset) debug_counter <= 0;
        else debug_counter <= debug_counter + 1;
        if (!reset && (debug_counter % 2000 == 0)) begin
            $display("[CTRL] Cycle %0d: Ch0 State=%d Consumer=%d PendingTx=%0d",
                     debug_counter, controller_state[0], current_consumer[0], pending_count);
            $display("       MemValid[0]=%b MemReady[0]=%b ConsReadValid[0:7]=%b",
                     mem_read_valid[0], mem_read_ready[0], consumer_read_valid[7:0]);
        end
        for (int t = 0; t < NUM_CHANNELS; t = t + 1) begin
            if (controller_state[t] == IDLE) begin
                for (int c = 0; c < NUM_CONSUMERS; c = c + 1) begin
                    if (consumer_read_valid[c] && !channel_serving_consumer[c] &&
                        consumer_read_address[c] == TRACE_ADDR) begin
                        $display("[TRACE 00c000] Cycle %0d CTRL_ENQUEUE: Ch=%0d Consumer=%0d",
                                 debug_counter, t, c);
                    end
                end
            end
            if (controller_state[t] == READ_WAITING && mem_read_ready[t] &&
                mem_read_address[t] == TRACE_ADDR) begin
                $display("[TRACE 00c000] Cycle %0d CTRL_RESPONSE: Ch=%0d Consumer=%0d Data=%02x",
                         debug_counter, t, current_consumer[t], mem_read_data[t]);
            end
            if (controller_state[t] == READ_RELAYING &&
                consumer_read_address[current_consumer[t]] == TRACE_ADDR) begin
                $display("[TRACE 00c000] Cycle %0d CTRL_RELAY: Ch=%0d Consumer=%0d Ready=%b",
                         debug_counter, t, current_consumer[t], consumer_read_ready[current_consumer[t]]);
            end
        end
    end
    // synthesis translate_on
endmodule
