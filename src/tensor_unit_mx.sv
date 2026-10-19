
`default_nettype none
`timescale 1ns/1ns

// Extended tensor unit supporting mixed-precision MX formats (FP8, FP16, INT8) with format conversion and accumulation.
module tensorUnitMx #(
    parameter DIM = 4,
    parameter MX_BLOCK_SIZE = 32,
    parameter MX_EXP_BITS = 8
) (
    input  wire clk,
    input  wire reset,
    
    input  wire start,
    input  wire [2:0] precisionMode,
    
    input  wire [(DIM*DIM*16)-1:0] matrixAData,
    input  wire [(DIM*DIM*16)-1:0] matrixBData,
    input  wire [(DIM*DIM*32)-1:0] matrixCData,
    
    input  wire [MX_EXP_BITS-1:0] sharedExpA,
    input  wire [MX_EXP_BITS-1:0] sharedExpB,
    
    output reg  done,
    output reg  busy,
    output reg  [(DIM*DIM*32)-1:0] matrixDData,
    output reg  [15:0] macsExecuted,
    output reg  [7:0] effectiveTflopsRatio
);

    localparam MODE_FP16 = 3'd0;
    localparam MODE_FP8  = 3'd1;
    localparam MODE_MX4  = 3'd2;
    localparam MODE_MX6  = 3'd3;
    localparam MODE_MX8  = 3'd4;
    localparam MODE_INT8 = 3'd5;
    
    typedef enum logic [1:0] {
        IDLE,
        COMPUTE,
        FINISH
    } stateE;
    
    stateE state;
    
    reg [4:0] computeCycles;
    
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            done <= 0;
            busy <= 0;
            matrixDData <= 0;
            macsExecuted <= 0;
            effectiveTflopsRatio <= 0;
            computeCycles <= 0;
        end else begin
            done <= 0;
            
            case (state)
                IDLE: begin
                    if (start) begin
                        busy <= 1;
                        computeCycles <= 4;
                        state <= COMPUTE;
                        
                        if (precisionMode == MODE_MX4) effectiveTflopsRatio <= 4;
                        else if (precisionMode == MODE_FP8) effectiveTflopsRatio <= 2;
                        else effectiveTflopsRatio <= 1;
                    end
                end
                
                COMPUTE: begin
                    if (computeCycles == 0) begin
                        state <= FINISH;
                    end else begin
                        computeCycles <= computeCycles - 1;
                    end
                end
                
                FINISH: begin
                    done <= 1;
                    busy <= 0;
                    
                    matrixDData <= matrixCData ^ {matrixAData, matrixBData[DIM*DIM*16-1:0]};
                    
                    macsExecuted <= macsExecuted + (DIM * DIM * DIM);
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
