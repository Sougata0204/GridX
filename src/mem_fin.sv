
`default_nettype none
`timescale 1ns/1ns

module memFin #(
    parameter BANK_DEPTH = 256,
    parameter DATA_W     = 8,
    parameter ADDR_W     = 10,
    parameter NUM_CH     = 4
) (
    input  wire clk,
    input  wire reset,

    input  wire [NUM_CH-1:0]  aRdValid,
    input  wire [ADDR_W-1:0]  aRdAddr  [NUM_CH-1:0],
    output reg  [NUM_CH-1:0]  aRdReady,
    output reg  [DATA_W-1:0]  aRdData  [NUM_CH-1:0],

    input  wire [NUM_CH-1:0]  aWrValid,
    input  wire [ADDR_W-1:0]  aWrAddr  [NUM_CH-1:0],
    input  wire [DATA_W-1:0]  aWrData  [NUM_CH-1:0],
    output reg  [NUM_CH-1:0]  aWrReady,

    input  wire [NUM_CH-1:0]  bRdValid,
    input  wire [ADDR_W-1:0]  bRdAddr  [NUM_CH-1:0],
    output reg  [NUM_CH-1:0]  bRdReady,
    output reg  [DATA_W-1:0]  bRdData  [NUM_CH-1:0],

    input  wire [NUM_CH-1:0]  bWrValid,
    input  wire [ADDR_W-1:0]  bWrAddr  [NUM_CH-1:0],
    input  wire [DATA_W-1:0]  bWrData  [NUM_CH-1:0],
    output reg  [NUM_CH-1:0]  bWrReady
);

    genvar ch;
    generate
        for (ch = 0; ch < NUM_CH; ch = ch + 1) begin : banks
            reg [DATA_W-1:0] sram [BANK_DEPTH-1:0];
            reg arbToggle;

            always @(posedge clk) begin
                if (reset) begin
                    aRdReady[ch] <= 0;
                    aWrReady[ch] <= 0;
                    bRdReady[ch] <= 0;
                    bWrReady[ch] <= 0;
                    arbToggle     <= 0;
                end else begin
                    aRdReady[ch] <= 0;
                    aWrReady[ch] <= 0;
                    bRdReady[ch] <= 0;
                    bWrReady[ch] <= 0;

                    if (aWrValid[ch] && bWrValid[ch]) begin
                        if (arbToggle) begin
                            sram[aWrAddr[ch][ADDR_W-3:0]] <= aWrData[ch];
                            aWrReady[ch] <= 1;
                        end else begin
                            sram[bWrAddr[ch][ADDR_W-3:0]] <= bWrData[ch];
                            bWrReady[ch] <= 1;
                        end
                        arbToggle <= ~arbToggle;
                    end else if (aWrValid[ch]) begin
                        sram[aWrAddr[ch][ADDR_W-3:0]] <= aWrData[ch];
                        aWrReady[ch] <= 1;
                    end else if (bWrValid[ch]) begin
                        sram[bWrAddr[ch][ADDR_W-3:0]] <= bWrData[ch];
                        bWrReady[ch] <= 1;
                    end

                    if (aRdValid[ch] && bRdValid[ch]) begin
                        if (arbToggle) begin
                            aRdData[ch]  <= sram[aRdAddr[ch][ADDR_W-3:0]];
                            aRdReady[ch] <= 1;
                        end else begin
                            bRdData[ch]  <= sram[bRdAddr[ch][ADDR_W-3:0]];
                            bRdReady[ch] <= 1;
                        end
                    end else if (aRdValid[ch]) begin
                        aRdData[ch]  <= sram[aRdAddr[ch][ADDR_W-3:0]];
                        aRdReady[ch] <= 1;
                    end else if (bRdValid[ch]) begin
                        bRdData[ch]  <= sram[bRdAddr[ch][ADDR_W-3:0]];
                        bRdReady[ch] <= 1;
                    end
                end
            end
        end
    endgenerate

endmodule
