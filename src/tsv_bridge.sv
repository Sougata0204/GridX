// Through-Silicon Via (TSV) Die-to-Die Bridge
// Models vertical die-to-die interconnect latency and credit-based flow control across 3D stacked layers.

`default_nettype none
`timescale 1ns/1ns

module tsvBridge #(
    parameter DATA_WIDTH = 1024,
    parameter LATENCY_CYCLES = 1,
    parameter BUFFER_DEPTH = 4
) (
    input  wire clk,
    input  wire reset,
    
    // Transmit Path (Local to TSV)
    input  wire txValid,
    input  wire [DATA_WIDTH-1:0] txData,
    output wire txReady,
    
    // Receive Path (TSV to Local)
    output wire rxValid,
    output wire [DATA_WIDTH-1:0] rxData,
    input  wire rxReady,
    
    // TSV Physical Interface
    output wire tsvOutValid,
    output wire [DATA_WIDTH-1:0] tsvOutData,
    input  wire tsvInValid,
    input  wire [DATA_WIDTH-1:0] tsvInData,
    
    // Performance and Status
    output reg  [31:0] perfTxCount,
    output reg  [31:0] perfRxCount,
    output reg  [31:0] perfStallCycles,
    output wire linkUp
);

    // TX FIFO
    reg [DATA_WIDTH-1:0] txFifo [0:BUFFER_DEPTH-1];
    reg [$clog2(BUFFER_DEPTH):0] txCount;
    reg [$clog2(BUFFER_DEPTH)-1:0] txWrPtr, txRdPtr;
    
    assign txReady = (txCount < BUFFER_DEPTH);
    
    // RX FIFO
    reg [DATA_WIDTH-1:0] rxFifo [0:BUFFER_DEPTH-1];
    reg [$clog2(BUFFER_DEPTH):0] rxCount;
    reg [$clog2(BUFFER_DEPTH)-1:0] rxWrPtr, rxRdPtr;
    
    assign rxValid = (rxCount > 0);
    assign rxData = rxFifo[rxRdPtr];
    
    // Pipeline for TSV TX latency simulation
    reg [DATA_WIDTH-1:0] txPipeData [0:LATENCY_CYCLES-1];
    reg txPipeValid [0:LATENCY_CYCLES-1];
    
    assign tsvOutValid = txPipeValid[LATENCY_CYCLES-1];
    assign tsvOutData = txPipeData[LATENCY_CYCLES-1];
    
    // Link Training State
    reg [2:0] linkTrainCount;
    reg linkUpReg;
    assign linkUp = linkUpReg;
    
    integer i;
    
    wire txPush = txValid && txReady;
    wire txPop = (txCount > 0);
    wire txBypass = (txPush && txCount == 0);
    
    wire rxPush = tsvInValid && (rxCount < BUFFER_DEPTH);
    wire rxPop = rxValid && rxReady;
    
    always @(posedge clk) begin
        if (reset) begin
            txCount <= 0;
            txWrPtr <= 0;
            txRdPtr <= 0;
            rxCount <= 0;
            rxWrPtr <= 0;
            rxRdPtr <= 0;
            
            for (i = 0; i < LATENCY_CYCLES; i = i + 1) begin
                txPipeValid[i] <= 0;
                txPipeData[i] <= 0;
            end
            
            perfTxCount <= 0;
            perfRxCount <= 0;
            perfStallCycles <= 0;
            
            linkTrainCount <= 0;
            linkUpReg <= 0;
        end else begin
            // Link Training Sequence
            if (!linkUpReg) begin
                if (linkTrainCount == 3) begin
                    linkUpReg <= 1;
                end else begin
                    linkTrainCount <= linkTrainCount + 1;
                end
            end
            
            // TX Path FIFO Writes
            if (txPush) begin
                txFifo[txWrPtr] <= txData;
                txWrPtr <= (txWrPtr == BUFFER_DEPTH-1) ? 0 : txWrPtr + 1;
                perfTxCount <= perfTxCount + 1;
            end else if (txValid) begin
                perfStallCycles <= perfStallCycles + 1;
            end
            
            // TX Path Pipeline Reads / Bypass
            if (txPop) begin
                 txPipeValid[0] <= 1;
                 txPipeData[0] <= txFifo[txRdPtr];
                 txRdPtr <= (txRdPtr == BUFFER_DEPTH-1) ? 0 : txRdPtr + 1;
            end else if (txBypass) begin
                 txPipeValid[0] <= 1;
                 txPipeData[0] <= txData;
            end else begin
                 txPipeValid[0] <= 0;
            end
            
            // TX Count Update Logic
            if (txPush && !txPop && !txBypass) begin
                txCount <= txCount + 1;
            end else if (!txPush && txPop) begin
                txCount <= txCount - 1;
            end
            
            // Shift pipeline
            for (i = 1; i < LATENCY_CYCLES; i = i + 1) begin
                txPipeValid[i] <= txPipeValid[i-1];
                txPipeData[i] <= txPipeData[i-1];
            end
            
            // RX Path FIFO Writes
            if (rxPush) begin
                rxFifo[rxWrPtr] <= tsvInData;
                rxWrPtr <= (rxWrPtr == BUFFER_DEPTH-1) ? 0 : rxWrPtr + 1;
                perfRxCount <= perfRxCount + 1;
            end
            
            // RX Path FIFO Reads
            if (rxPop) begin
                rxRdPtr <= (rxRdPtr == BUFFER_DEPTH-1) ? 0 : rxRdPtr + 1;
            end
            
            // RX Count Update Logic
            case ({rxPush, rxPop})
                2'b10: rxCount <= rxCount + 1;
                2'b01: rxCount <= rxCount - 1;
                default: ; // Unchanged on 00 or 11
            endcase
            
        end
    end

endmodule

