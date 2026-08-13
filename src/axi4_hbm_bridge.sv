`default_nettype none
`timescale 1ns/1ns

// AXI4 to HBM3 Native Protocol Bridge
// Converts AXI4 AW/W/B/AR/R channel transactions into the simple
// valid/ready/addr/data protocol used by hbm3Ctrl.
module axi4HbmBridge #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 512,
    parameter ID_WIDTH   = 4
) (
    input  wire clk,
    input  wire reset,

    // AXI4 Slave Interface (from NoC or core)
    input  wire [ID_WIDTH-1:0]    sAwid,
    input  wire [ADDR_WIDTH-1:0]  sAwaddr,
    input  wire [7:0]             sAwlen,
    input  wire [2:0]             sAwsize,
    input  wire [1:0]             sAwburst,
    input  wire                   sAwvalid,
    output reg                    sAwready,

    input  wire [DATA_WIDTH-1:0]  sWdata,
    input  wire [DATA_WIDTH/8-1:0] sWstrb,
    input  wire                   sWlast,
    input  wire                   sWvalid,
    output reg                    sWready,

    output reg  [ID_WIDTH-1:0]    sBid,
    output reg  [1:0]             sBresp,
    output reg                    sBvalid,
    input  wire                   sBready,

    input  wire [ID_WIDTH-1:0]    sArid,
    input  wire [ADDR_WIDTH-1:0]  sAraddr,
    input  wire [7:0]             sArlen,
    input  wire [2:0]             sArsize,
    input  wire [1:0]             sArburst,
    input  wire                   sArvalid,
    output reg                    sArready,

    output reg  [ID_WIDTH-1:0]    sRid,
    output reg  [DATA_WIDTH-1:0]  sRdata,
    output reg  [1:0]             sRresp,
    output reg                    sRlast,
    output reg                    sRvalid,
    input  wire                   sRready,

    // HBM3 Native Interface (to hbm3Ctrl)
    output reg                    hbmReqValid,
    output reg  [ADDR_WIDTH-1:0]  hbmReqAddr,
    output reg  [DATA_WIDTH-1:0]  hbmReqWdata,
    output reg                    hbmReqWrite,
    input  wire                   hbmReqReady,

    input  wire                   hbmRespValid,
    input  wire [DATA_WIDTH-1:0]  hbmRespData,
    input  wire [ADDR_WIDTH-1:0]  hbmRespAddr,

    // Performance counters
    output reg  [31:0]            axiWrTxnCount,
    output reg  [31:0]            axiRdTxnCount
);

    // FSM states
    localparam [2:0] ST_IDLE      = 3'd0,
                     ST_WRITE_AW  = 3'd1,
                     ST_WRITE_W   = 3'd2,
                     ST_WRITE_B   = 3'd3,
                     ST_READ_AR   = 3'd4,
                     ST_READ_WAIT = 3'd5;

    reg [2:0] state;

    // Transaction registers
    reg [ID_WIDTH-1:0]   txnId;
    reg [ADDR_WIDTH-1:0] txnAddr;
    reg [7:0]            txnLen;
    reg [7:0]            beatCount;

    always @(posedge clk) begin
        if (reset) begin
            state          <= ST_IDLE;
            sAwready      <= 1'b0;
            sWready       <= 1'b0;
            sBvalid       <= 1'b0;
            sBid          <= '0;
            sBresp        <= 2'b00;
            sArready      <= 1'b0;
            sRvalid       <= 1'b0;
            sRid          <= '0;
            sRdata        <= '0;
            sRresp        <= 2'b00;
            sRlast        <= 1'b0;
            hbmReqValid  <= 1'b0;
            hbmReqAddr   <= '0;
            hbmReqWdata  <= '0;
            hbmReqWrite  <= 1'b0;
            txnId         <= '0;
            txnAddr       <= '0;
            txnLen        <= 8'd0;
            beatCount     <= 8'd0;
            axiWrTxnCount <= 32'd0;
            axiRdTxnCount <= 32'd0;
        end else begin
            // Default de-assertions
            sAwready <= 1'b0;
            sWready  <= 1'b0;
            sArready <= 1'b0;

            case (state)
                ST_IDLE: begin
                    hbmReqValid <= 1'b0;
                    // Write has priority over read
                    if (sAwvalid) begin
                        sAwready  <= 1'b1;
                        txnId     <= sAwid;
                        txnAddr   <= sAwaddr;
                        txnLen    <= sAwlen;
                        beatCount <= 8'd0;
                        state      <= ST_WRITE_W;
                    end else if (sArvalid) begin
                        sArready  <= 1'b1;
                        txnId     <= sArid;
                        txnAddr   <= sAraddr;
                        txnLen    <= sArlen;
                        beatCount <= 8'd0;
                        state      <= ST_READ_AR;
                    end
                    // Clear B channel when accepted
                    if (sBvalid && sBready)
                        sBvalid <= 1'b0;
                    // Clear R channel when accepted
                    if (sRvalid && sRready)
                        sRvalid <= 1'b0;
                end

                // Write data beat ? forward each W beat to HBM
                ST_WRITE_W: begin
                    if (sBvalid && sBready)
                        sBvalid <= 1'b0;

                    if (sWvalid && hbmReqReady) begin
                        sWready       <= 1'b1;
                        hbmReqValid  <= 1'b1;
                        hbmReqWrite  <= 1'b1;
                        hbmReqAddr   <= txnAddr;
                        hbmReqWdata  <= sWdata;
                        txnAddr       <= txnAddr + (DATA_WIDTH / 8);
                        beatCount     <= beatCount + 8'd1;

                        if (sWlast || beatCount == txnLen) begin
                            state <= ST_WRITE_B;
                        end
                    end else begin
                        hbmReqValid <= 1'b0;
                    end
                end

                // Write response
                ST_WRITE_B: begin
                    hbmReqValid    <= 1'b0;
                    sBvalid         <= 1'b1;
                    sBid            <= txnId;
                    sBresp          <= 2'b00; // OKAY
                    axiWrTxnCount <= axiWrTxnCount + 32'd1;
                    state            <= ST_IDLE;
                end

                // Issue read to HBM
                ST_READ_AR: begin
                    if (hbmReqReady) begin
                        hbmReqValid <= 1'b1;
                        hbmReqWrite <= 1'b0;
                        hbmReqAddr  <= txnAddr;
                        hbmReqWdata <= '0;
                        state         <= ST_READ_WAIT;
                    end
                end

                // Wait for HBM read response
                ST_READ_WAIT: begin
                    hbmReqValid <= 1'b0;
                    if (hbmRespValid) begin
                        sRvalid         <= 1'b1;
                        sRid            <= txnId;
                        sRdata          <= hbmRespData;
                        sRresp          <= 2'b00; // OKAY
                        sRlast          <= (beatCount == txnLen);
                        beatCount       <= beatCount + 8'd1;
                        axiRdTxnCount <= axiRdTxnCount + 32'd1;

                        if (beatCount == txnLen) begin
                            state <= ST_IDLE;
                        end else begin
                            txnAddr <= txnAddr + (DATA_WIDTH / 8);
                            state    <= ST_READ_AR;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
