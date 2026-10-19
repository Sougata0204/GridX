
`default_nettype none
`timescale 1ns/1ns

// Memory sheet controller managing a 2D array of SRAM tiles with row/column address decoding and banked access.
module memorySheet #(
    parameter ADDR_WIDTH = 13,
    parameter DATA_WIDTH = 8,
    parameter NUM_BANKS = 4,
    parameter BANK_DEPTH = 1024,
    parameter METADATA_BITS = 8,
    parameter SHEET_ID = 0
) (
    input  wire        clk,
    input  wire        reset,

    input  wire        sideAReqValid,
    input  wire        sideAReqWrite,
    input  wire [ADDR_WIDTH-1:0] sideAReqAddr,
    input  wire [DATA_WIDTH-1:0] sideAReqWdata,
    output wire        sideAReqReady,

    output reg         sideARespValid,
    output reg  [DATA_WIDTH-1:0] sideARespRdata,
    input  wire        sideARespReady,

    input  wire        sideBReqValid,
    input  wire        sideBReqWrite,
    input  wire [ADDR_WIDTH-1:0] sideBReqAddr,
    input  wire [DATA_WIDTH-1:0] sideBReqWdata,
    output wire        sideBReqReady,

    output reg         sideBRespValid,
    output reg  [DATA_WIDTH-1:0] sideBRespRdata,
    input  wire        sideBRespReady,

    input  wire        nocReqValid,
    input  wire        nocReqWrite,
    input  wire [ADDR_WIDTH-1:0] nocReqAddr,
    input  wire [DATA_WIDTH-1:0] nocReqWdata,
    output wire        nocReqReady,

    output reg         nocRespValid,
    output reg  [DATA_WIDTH-1:0] nocRespRdata,
    input  wire        nocRespReady,

    output reg  [31:0] perfReads,
    output reg  [31:0] perfWrites,
    output reg  [31:0] perfBankConflicts,
    output reg  [31:0] perfSideAAccesses,
    output reg  [31:0] perfSideBAccesses,
    output reg  [31:0] perfNocAccesses,
    output reg  [31:0] perfMerges
);

    localparam BANK_ID_WIDTH = (NUM_BANKS > 1) ? $clog2(NUM_BANKS) : 1;
    localparam BANK_ADDR_WIDTH = $clog2(BANK_DEPTH);

    reg [DATA_WIDTH-1:0] bankData [NUM_BANKS-1:0][BANK_DEPTH-1:0];
    reg [METADATA_BITS-1:0] bankMeta [NUM_BANKS-1:0][BANK_DEPTH-1:0];

    wire [BANK_ID_WIDTH-1:0] aBankId   = (NUM_BANKS > 1) ? sideAReqAddr[BANK_ID_WIDTH-1:0] : '0;
    wire [BANK_ADDR_WIDTH-1:0] aBankAddr = (NUM_BANKS > 1) ? sideAReqAddr[BANK_ID_WIDTH +: BANK_ADDR_WIDTH] : sideAReqAddr[BANK_ADDR_WIDTH-1:0];
    
    wire [BANK_ID_WIDTH-1:0] bBankId   = (NUM_BANKS > 1) ? sideBReqAddr[BANK_ID_WIDTH-1:0] : '0;
    wire [BANK_ADDR_WIDTH-1:0] bBankAddr = (NUM_BANKS > 1) ? sideBReqAddr[BANK_ID_WIDTH +: BANK_ADDR_WIDTH] : sideBReqAddr[BANK_ADDR_WIDTH-1:0];

    wire [BANK_ID_WIDTH-1:0] nBankId   = (NUM_BANKS > 1) ? nocReqAddr[BANK_ID_WIDTH-1:0] : '0;
    wire [BANK_ADDR_WIDTH-1:0] nBankAddr = (NUM_BANKS > 1) ? nocReqAddr[BANK_ID_WIDTH +: BANK_ADDR_WIDTH] : nocReqAddr[BANK_ADDR_WIDTH-1:0];

    wire aGrant = sideAReqValid;
    wire bGrant = sideBReqValid && (!aGrant || (bBankId != aBankId));
    wire nGrant = nocReqValid && (!aGrant || (nBankId != aBankId)) && (!bGrant || (nBankId != bBankId));

    assign sideAReqReady = aGrant;
    assign sideBReqReady = bGrant;
    assign nocReqReady    = nGrant;

`ifndef SYNTHESIS
    integer bInit, wInit;
    initial begin
        for (bInit = 0; bInit < NUM_BANKS; bInit = bInit + 1)
            for (wInit = 0; wInit < BANK_DEPTH; wInit = wInit + 1)
                bankData[bInit][wInit] = '0;
    end
`endif

    always @(posedge clk) begin
        if (reset) begin
            sideARespValid <= 1'b0;
            sideBRespValid <= 1'b0;
            nocRespValid    <= 1'b0;
            sideARespRdata <= '0;
            sideBRespRdata <= '0;
            nocRespRdata    <= '0;
            
            perfReads <= '0;
            perfWrites <= '0;
            perfBankConflicts <= '0;
            perfSideAAccesses <= '0;
            perfSideBAccesses <= '0;
            perfNocAccesses <= '0;
            perfMerges <= '0;
        end else begin

            sideARespValid <= 1'b0;
            sideBRespValid <= 1'b0;
            nocRespValid    <= 1'b0;
            
            if (aGrant) begin
                perfSideAAccesses <= perfSideAAccesses + 1;
                if (sideAReqWrite) begin
                    bankData[aBankId][aBankAddr] <= sideAReqWdata;
                    perfWrites <= perfWrites + 1;
                end else begin
                    sideARespValid <= 1'b1;
                    sideARespRdata <= bankData[aBankId][aBankAddr];
                    perfReads <= perfReads + 1;
                end
            end else if (sideAReqValid) begin
                 perfBankConflicts <= perfBankConflicts + 1;
            end

            if (bGrant) begin
                perfSideBAccesses <= perfSideBAccesses + 1;
                if (sideBReqWrite) begin
                    bankData[bBankId][bBankAddr] <= sideBReqWdata;
                    perfWrites <= perfWrites + 1;
                end else begin
                    sideBRespValid <= 1'b1;
                    sideBRespRdata <= bankData[bBankId][bBankAddr];
                    perfReads <= perfReads + 1;
                end
            end else if (sideBReqValid) begin
                perfBankConflicts <= perfBankConflicts + 1;
            end

            if (nGrant) begin
                perfNocAccesses <= perfNocAccesses + 1;
                if (nocReqWrite) begin
                    bankData[nBankId][nBankAddr] <= nocReqWdata;
                    perfWrites <= perfWrites + 1;
                end else begin
                    nocRespValid <= 1'b1;
                    nocRespRdata <= bankData[nBankId][nBankAddr];
                    perfReads <= perfReads + 1;
                end
            end else if (nocReqValid) begin
                perfBankConflicts <= perfBankConflicts + 1;
            end
        end
    end
    final begin
        for (int b = 0; b < NUM_BANKS; b++) begin
            for (int w = 0; w < BANK_DEPTH; w++) begin
                if (bankData[b][w] !== '0 && bankData[b][w] !== {DATA_WIDTH{1'bx}}) begin
                    $display("[HBM_DUMP] Sheet=%0d Bank=%0d Addr=0x%0x Data=0x%0x", SHEET_ID, b, w, bankData[b][w]);
                end
            end
        end
    end

endmodule
