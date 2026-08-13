
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
    input wire [NUM_CONSUMERS-1:0] consumerReadValid,
    input wire [ADDR_BITS-1:0] consumerReadAddress [NUM_CONSUMERS-1:0],
    output reg [NUM_CONSUMERS-1:0] consumerReadReady,
    output reg [DATA_BITS-1:0] consumerReadData [NUM_CONSUMERS-1:0],
    input wire [NUM_CONSUMERS-1:0] consumerWriteValid,
    input wire [ADDR_BITS-1:0] consumerWriteAddress [NUM_CONSUMERS-1:0],
    input wire [DATA_BITS-1:0] consumerWriteData [NUM_CONSUMERS-1:0],
    output reg [NUM_CONSUMERS-1:0] consumerWriteReady,
    output reg [NUM_CHANNELS-1:0] memReadValid,
    output reg [ADDR_BITS-1:0] memReadAddress [NUM_CHANNELS-1:0],
    input wire [NUM_CHANNELS-1:0] memReadReady,
    input wire [DATA_BITS-1:0] memReadData [NUM_CHANNELS-1:0],
    output reg [NUM_CHANNELS-1:0] memWriteValid,
    output reg [ADDR_BITS-1:0] memWriteAddress [NUM_CHANNELS-1:0],
    output reg [DATA_BITS-1:0] memWriteData [NUM_CHANNELS-1:0],
    input wire [NUM_CHANNELS-1:0] memWriteReady,
    output wire [$clog2(NUM_CHANNELS+1)-1:0] pendingTransactions
);
    localparam IDLE = 3'b000,
        READ_WAITING = 3'b010,
        WRITE_WAITING = 3'b011,
        READ_RELAYING = 3'b100,
        WRITE_RELAYING = 3'b101;
    reg [2:0] controllerState [NUM_CHANNELS-1:0];
    reg [$clog2(NUM_CONSUMERS)-1:0] currentConsumer [NUM_CHANNELS-1:0];
    reg [NUM_CONSUMERS-1:0] channelServingConsumerFf;
    wire [NUM_CONSUMERS-1:0] channelServingConsumer;
    assign channelServingConsumer = channelServingConsumerFf;
    always @(posedge clk) begin
        if (reset) begin
            memReadValid <= 0;
            memWriteValid <= 0;
            consumerReadReady <= 0;
            consumerWriteReady <= 0;
            channelServingConsumerFf <= 0;
            for (int i = 0; i < NUM_CHANNELS; i = i + 1) begin
                memReadAddress[i] <= 0;
                memWriteAddress[i] <= 0;
                memWriteData[i] <= 0;
                currentConsumer[i] <= 0;
                controllerState[i] <= 0;
            end
            for (int j = 0; j < NUM_CONSUMERS; j = j + 1) begin
                consumerReadData[j] <= 0;
            end
        end else begin
            for (int i = 0; i < NUM_CHANNELS; i = i + 1) begin
                case (controllerState[i])
                    IDLE: begin
                        for (int j = 0; j < NUM_CONSUMERS; j = j + 1) begin
                            if (consumerReadValid[j] && !channelServingConsumerFf[j]) begin
                                channelServingConsumerFf[j] <= 1;
                                currentConsumer[i] <= j;
                                memReadValid[i] <= 1;
                                memReadAddress[i] <= consumerReadAddress[j];
                                controllerState[i] <= READ_WAITING;
                                break;
                            end else if (consumerWriteValid[j] && !channelServingConsumerFf[j]) begin
                                channelServingConsumerFf[j] <= 1;
                                currentConsumer[i] <= j;
                                memWriteValid[i] <= 1;
                                memWriteAddress[i] <= consumerWriteAddress[j];
                                memWriteData[i] <= consumerWriteData[j];
                                controllerState[i] <= WRITE_WAITING;
                                break;
                            end
                        end
                    end
                    READ_WAITING: begin
                        if (memReadReady[i]) begin
                            memReadValid[i] <= 0;
                            consumerReadReady[currentConsumer[i]] <= 1;
                            consumerReadData[currentConsumer[i]] <= memReadData[i];
                            controllerState[i] <= READ_RELAYING;
                        end
                    end
                    WRITE_WAITING: begin
                        if (memWriteReady[i]) begin
                            memWriteValid[i] <= 0;
                            consumerWriteReady[currentConsumer[i]] <= 1;
                            controllerState[i] <= WRITE_RELAYING;
                        end
                    end
                    READ_RELAYING: begin
                        if (!consumerReadValid[currentConsumer[i]]) begin
                            channelServingConsumerFf[currentConsumer[i]] <= 0;
                            consumerReadReady[currentConsumer[i]] <= 0;
                            controllerState[i] <= IDLE;
                        end
                    end
                    WRITE_RELAYING: begin
                        if (!consumerWriteValid[currentConsumer[i]]) begin
                            channelServingConsumerFf[currentConsumer[i]] <= 0;
                            consumerWriteReady[currentConsumer[i]] <= 0;
                            controllerState[i] <= IDLE;
                        end
                    end
                endcase
            end
        end
    end
    reg [$clog2(NUM_CHANNELS+1)-1:0] pendingCount;
    integer pc;
    always @(*) begin
        pendingCount = 0;
        for (pc = 0; pc < NUM_CHANNELS; pc = pc + 1) begin
            if (controllerState[pc] != IDLE) begin
                pendingCount = pendingCount + 1;
            end
        end
    end
    assign pendingTransactions = pendingCount;
    // synthesis translateOff
    localparam TRACE_ADDR = 'h00c000;
    reg [31:0] debugCounter;
    always @(posedge clk) begin
        if (reset) debugCounter <= 0;
        else debugCounter <= debugCounter + 1;
        if (!reset && (debugCounter % 2000 == 0)) begin
            $display("[CTRL] Cycle %0d: Ch0 State=%d Consumer=%d PendingTx=%0d",
                     debugCounter, controllerState[0], currentConsumer[0], pendingCount);
            $display("       MemValid[0]=%b MemReady[0]=%b ConsReadValid[0:7]=%b",
                     memReadValid[0], memReadReady[0], consumerReadValid[7:0]);
        end
        for (int t = 0; t < NUM_CHANNELS; t = t + 1) begin
            if (controllerState[t] == IDLE) begin
                for (int c = 0; c < NUM_CONSUMERS; c = c + 1) begin
                    if (consumerReadValid[c] && !channelServingConsumer[c] &&
                        consumerReadAddress[c] == TRACE_ADDR) begin
                        $display("[TRACE 00c000] Cycle %0d CTRL_ENQUEUE: Ch=%0d Consumer=%0d",
                                 debugCounter, t, c);
                    end
                end
            end
            if (controllerState[t] == READ_WAITING && memReadReady[t] &&
                memReadAddress[t] == TRACE_ADDR) begin
                $display("[TRACE 00c000] Cycle %0d CTRL_RESPONSE: Ch=%0d Consumer=%0d Data=%02x",
                         debugCounter, t, currentConsumer[t], memReadData[t]);
            end
            if (controllerState[t] == READ_RELAYING &&
                consumerReadAddress[currentConsumer[t]] == TRACE_ADDR) begin
                $display("[TRACE 00c000] Cycle %0d CTRL_RELAY: Ch=%0d Consumer=%0d Ready=%b",
                         debugCounter, t, currentConsumer[t], consumerReadReady[currentConsumer[t]]);
            end
        end
    end
    // synthesis translateOn
endmodule
