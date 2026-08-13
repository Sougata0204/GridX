
`default_nettype none
`timescale 1ns/1ns

module coreFinRouter #(
    parameter DATA_W    = 8,
    parameter ADDR_W    = 22,
    parameter FIN_ADDR  = 10,
    parameter NUM_CH    = 4,
    parameter NUM_FACES = 6
) (
    input  wire clk,
    input  wire reset,

    input  wire              coreRdValid,
    input  wire [ADDR_W-1:0] coreRdAddr,
    output wire              coreRdReady,
    output wire [DATA_W-1:0] coreRdData,

    input  wire              coreWrValid,
    input  wire [ADDR_W-1:0] coreWrAddr,
    input  wire [DATA_W-1:0] coreWrData,
    output wire              coreWrReady,

    input  wire [5:0]        facePresent,

    output reg  [NUM_CH-1:0] faceRdValid [NUM_FACES-1:0],
    output reg  [FIN_ADDR-1:0] faceRdAddr [NUM_FACES-1:0][NUM_CH-1:0],
    input  wire [NUM_CH-1:0] faceRdReady [NUM_FACES-1:0],
    input  wire [DATA_W-1:0] faceRdData  [NUM_FACES-1:0][NUM_CH-1:0],

    output reg  [NUM_CH-1:0] faceWrValid [NUM_FACES-1:0],
    output reg  [FIN_ADDR-1:0] faceWrAddr [NUM_FACES-1:0][NUM_CH-1:0],
    output reg  [DATA_W-1:0] faceWrData  [NUM_FACES-1:0][NUM_CH-1:0],
    input  wire [NUM_CH-1:0] faceWrReady [NUM_FACES-1:0]
);

    wire [2:0] faceSel  = coreRdValid ? coreRdAddr[ADDR_W-1:ADDR_W-3] :
                           coreWrValid ? coreWrAddr[ADDR_W-1:ADDR_W-3] : 3'd0;

    wire [1:0] chSel    = coreRdValid ? coreRdAddr[FIN_ADDR+1:FIN_ADDR] :
                           coreWrValid ? coreWrAddr[FIN_ADDR+1:FIN_ADDR] : 2'd0;

    wire [2:0] mappedFace = (faceSel < 3'd6) ? faceSel : 3'd0;

    reg rdAck;
    reg [DATA_W-1:0] rdVal;
    reg wrAck;

    integer f, c;
    always @(*) begin
        rdAck = 0;
        rdVal = {DATA_W{1'b0}};
        wrAck = 0;

        for (f = 0; f < NUM_FACES; f = f + 1) begin
            faceRdValid[f] = {NUM_CH{1'b0}};
            faceWrValid[f] = {NUM_CH{1'b0}};
            for (c = 0; c < NUM_CH; c = c + 1) begin
                faceRdAddr[f][c] = {FIN_ADDR{1'b0}};
                faceWrAddr[f][c] = {FIN_ADDR{1'b0}};
                faceWrData[f][c] = {DATA_W{1'b0}};
            end
        end

        if (coreRdValid && facePresent[mappedFace]) begin
            faceRdValid[mappedFace][chSel] = 1'b1;
            faceRdAddr[mappedFace][chSel]  = coreRdAddr[FIN_ADDR-1:0];
            rdAck = faceRdReady[mappedFace][chSel];
            rdVal = faceRdData[mappedFace][chSel];
        end

        if (coreWrValid && facePresent[mappedFace]) begin
            faceWrValid[mappedFace][chSel] = 1'b1;
            faceWrAddr[mappedFace][chSel]  = coreWrAddr[FIN_ADDR-1:0];
            faceWrData[mappedFace][chSel]  = coreWrData;
            wrAck = faceWrReady[mappedFace][chSel];
        end
    end

    assign coreRdReady = rdAck;
    assign coreRdData  = rdVal;
    assign coreWrReady = wrAck;

endmodule
