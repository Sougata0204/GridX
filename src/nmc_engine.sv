
`default_nettype none
`timescale 1ns/1ns

module nmcEngine #(
    parameter DATA_WIDTH = 256,
    parameter REDUCTION_WIDTH = 32,
    parameter QUEUE_DEPTH = 8,
    parameter NUM_ALUS = 4
) (
    input  wire clk,
    input  wire reset,
    
    // Command Interface
    input  wire cmdValid,
    input  wire [3:0] cmdOpcode,
    input  wire [31:0] cmdAddr,
    input  wire [15:0] cmdLength,
    output reg  cmdReady,
    
    // Result Interface
    output reg  resultValid,
    output reg  [DATA_WIDTH-1:0] resultData,
    
    // Memory Interface
    output reg  memReadValid,
    output reg  [31:0] memReadAddr,
    input  wire memReadReady,
    input  wire [DATA_WIDTH-1:0] memReadData,
    
    output reg  memWriteValid,
    output reg  [31:0] memWriteAddr,
    output reg  [DATA_WIDTH-1:0] memWriteData,
    input  wire memWriteReady,
    
    output reg  busy,
    output reg  [31:0] perfOpsCompleted
);

    localparam OP_SUM  = 4'd0;
    localparam OP_MAX  = 4'd1;
    localparam OP_MIN  = 4'd2;
    localparam OP_ABS  = 4'd3;
    localparam OP_RELU = 4'd4;
    
    typedef enum logic [2:0] {
        IDLE,
        READ_MEM,
        PROCESS,
        WRITE_MEM,
        DONE
    } stateE;
    
    stateE state;
    
    reg [3:0] curOpcode;
    reg [31:0] curAddr;
    reg [15:0] curLength;
    reg [15:0] elementsProcessed;
    
    reg [DATA_WIDTH-1:0] accData;
    
    integer i;
    
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            cmdReady <= 1;
            resultValid <= 0;
            memReadValid <= 0;
            memWriteValid <= 0;
            busy <= 0;
            perfOpsCompleted <= 0;
        end else begin
            resultValid <= 0;
            
            case (state)
                IDLE: begin
                    if (cmdValid) begin
                        curOpcode <= cmdOpcode;
                        curAddr <= cmdAddr;
                        curLength <= cmdLength;
                        elementsProcessed <= 0;
                        cmdReady <= 0;
                        busy <= 1;
                        if (cmdOpcode == OP_MAX) accData <= {DATA_WIDTH{1'b0}}; // Should be min val
                        else if (cmdOpcode == OP_MIN) accData <= {DATA_WIDTH{1'b1}}; // Should be max val
                        else accData <= 0;
                        
                        state <= READ_MEM;
                    end else begin
                        cmdReady <= 1;
                        busy <= 0;
                    end
                end
                
                READ_MEM: begin
                    if (elementsProcessed < curLength) begin
                        memReadValid <= 1;
                        memReadAddr <= curAddr + (elementsProcessed * (DATA_WIDTH/8));
                        if (memReadReady && memReadValid) begin
                            memReadValid <= 0;
                            state <= PROCESS;
                        end
                    end else begin
                        state <= DONE;
                    end
                end
                
                PROCESS: begin
                    // Simple ALU (in reality, NUM_ALUS parallel paths)
                    // For now, doing a simple wide operation for demo
                    case (curOpcode)
                        OP_SUM:  accData <= accData + memReadData;
                        OP_MAX:  accData <= (memReadData > accData) ? memReadData : accData;
                        OP_MIN:  accData <= (memReadData < accData) ? memReadData : accData;
                        OP_ABS: begin
                            for (i = 0; i < DATA_WIDTH/32; i = i + 1) begin
                                if (memReadData[i*32 + 31]) begin
                                    accData[i*32 +: 32] <= -memReadData[i*32 +: 32];
                                end else begin
                                    accData[i*32 +: 32] <= memReadData[i*32 +: 32];
                                end
                            end
                        end
                        OP_RELU: begin
                            for (i = 0; i < DATA_WIDTH/32; i = i + 1) begin
                                if (memReadData[i*32 + 31]) begin
                                    accData[i*32 +: 32] <= 32'd0;
                                end else begin
                                    accData[i*32 +: 32] <= memReadData[i*32 +: 32];
                                end
                            end
                        end
                        default: accData <= memReadData;
                    endcase
                    
                    elementsProcessed <= elementsProcessed + 1;
                    
                    // If element-wise, write back immediately
                    if (curOpcode == OP_ABS || curOpcode == OP_RELU) begin
                        state <= WRITE_MEM;
                    end else begin
                        state <= READ_MEM;
                    end
                end
                
                WRITE_MEM: begin
                    memWriteValid <= 1;
                    memWriteAddr <= curAddr + ((elementsProcessed - 1) * (DATA_WIDTH/8));
                    memWriteData <= accData;
                    if (memWriteReady && memWriteValid) begin
                        memWriteValid <= 0;
                        state <= READ_MEM;
                    end
                end
                
                DONE: begin
                    resultValid <= 1;
                    resultData <= accData;
                    perfOpsCompleted <= perfOpsCompleted + 1;
                    cmdReady <= 1;
                    busy <= 0;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
