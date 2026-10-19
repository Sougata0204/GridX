
`default_nettype none
`timescale 1ns/1ns

// DRAM timing controller managing activate, read, write, precharge, and refresh commands with bank-state tracking.
module dramCtrl #(
    parameter ADDR_WIDTH = 40,
    parameter DATA_WIDTH = 256,
    parameter BURST_LENGTH = 8,
    parameter NUM_RANKS = 2
) (
    input  wire clk,
    input  wire reset,
    
    input  wire reqValid,
    input  wire [ADDR_WIDTH-1:0] reqAddr,
    input  wire [DATA_WIDTH-1:0] reqWdata,
    input  wire reqWrite,
    output reg  reqReady,
    
    output reg  respValid,
    output reg  [DATA_WIDTH-1:0] respData,
    output reg  [ADDR_WIDTH-1:0] respAddr,
    
    output reg  phyCmdValid,
    output reg  [2:0] phyCmd,
    output reg  [ADDR_WIDTH-1:0] phyAddr,
    output reg  [DATA_WIDTH-1:0] phyWdata,
    input  wire [DATA_WIDTH-1:0] phyRdata,
    input  wire phyRdataValid,
    
    output reg  busy,
    output reg  [31:0] totalReads,
    output reg  [31:0] totalWrites,
    output reg  [31:0] rowHits,
    output reg  [31:0] rowMisses
);

    localparam CMD_ACT = 3'd0;
    localparam CMD_PRE = 3'd1;
    localparam CMD_RD  = 3'd2;
    localparam CMD_WR  = 3'd3;
    
    reg validRow [7:0];
    reg [23:0] openRow [7:0];
    
    typedef enum logic [2:0] {
        IDLE,
        PRECHARGE,
        ACTIVATE,
        ACCESS,
        WAIT_PHY
    } stateE;
    
    stateE state;
    
    reg [ADDR_WIDTH-1:0] latchedAddr;
    reg [DATA_WIDTH-1:0] latchedWdata;
    reg latchedWrite;
    
    wire [2:0] curBank = latchedAddr[15:13];
    wire [23:0] curRow = latchedAddr[39:16];
    
    wire rowHit = validRow[curBank] && (openRow[curBank] == curRow);
    
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            reqReady <= 1;
            respValid <= 0;
            phyCmdValid <= 0;
            busy <= 0;
            
            for (i = 0; i < 8; i = i + 1) begin
                validRow[i] <= 0;
            end
            
            totalReads <= 0;
            totalWrites <= 0;
            rowHits <= 0;
            rowMisses <= 0;
        end else begin
            respValid <= 0;
            phyCmdValid <= 0;
            
            if (phyRdataValid) begin
                respValid <= 1;
                respData <= phyRdata;
                respAddr <= latchedAddr;
            end
            
            case (state)
                IDLE: begin
                    if (reqValid) begin
                        latchedAddr <= reqAddr;
                        latchedWdata <= reqWdata;
                        latchedWrite <= reqWrite;
                        reqReady <= 0;
                        busy <= 1;
                        
                        if (validRow[reqAddr[15:13]] && openRow[reqAddr[15:13]] == reqAddr[39:16]) begin
                            state <= ACCESS;
                            rowHits <= rowHits + 1;
                        end else if (validRow[reqAddr[15:13]]) begin
                            state <= PRECHARGE;
                            rowMisses <= rowMisses + 1;
                        end else begin
                            state <= ACTIVATE;
                            rowMisses <= rowMisses + 1;
                        end
                    end else begin
                        busy <= 0;
                        reqReady <= 1;
                    end
                end
                
                PRECHARGE: begin
                    phyCmdValid <= 1;
                    phyCmd <= CMD_PRE;
                    phyAddr <= latchedAddr;
                    validRow[curBank] <= 0;
                    state <= ACTIVATE;
                end
                
                ACTIVATE: begin
                    phyCmdValid <= 1;
                    phyCmd <= CMD_ACT;
                    phyAddr <= latchedAddr;
                    validRow[curBank] <= 1;
                    openRow[curBank] <= curRow;
                    state <= ACCESS;
                end
                
                ACCESS: begin
                    phyCmdValid <= 1;
                    phyCmd <= latchedWrite ? CMD_WR : CMD_RD;
                    phyAddr <= latchedAddr;
                    phyWdata <= latchedWdata;
                    
                    if (latchedWrite) begin
                        totalWrites <= totalWrites + 1;
                        respValid <= 1;
                        respAddr <= latchedAddr;
                        state <= IDLE;
                        reqReady <= 1;
                    end else begin
                        totalReads <= totalReads + 1;
                        state <= WAIT_PHY;
                    end
                end
                
                WAIT_PHY: begin
                    if (phyRdataValid) begin
                        state <= IDLE;
                        reqReady <= 1;
                    end
                end
                
            endcase
        end
        
        if (!reset) begin
            if (reqValid)
                $display("[%0t] [DRAM] reqValid=1, addr=%h, write=%b, ready=%0b", $time, reqAddr, reqWrite, reqReady);
            if (state != IDLE)
                $display("[%0t] [DRAM] state=%s, bank=%0d, row=%h", $time, state.name(), curBank, curRow);
        end
    end

endmodule
