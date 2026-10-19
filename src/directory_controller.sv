
`default_nettype none
`timescale 1ns/1ns

// Directory-based cache coherence controller maintaining per-line sharer vectors and processing snoop/invalidation requests.
module directoryController #(
    parameter NUM_CORES = 8,
    parameter ADDR_WIDTH = 22,
    parameter DATA_WIDTH = 256,
    parameter DIRECTORY_ENTRIES = 256,
    parameter CORE_ID_WIDTH = 3
) (
    input  wire clk,
    input  wire reset,
    
    input  wire reqValid,
    input  wire [CORE_ID_WIDTH-1:0] reqCoreId,
    input  wire [ADDR_WIDTH-1:0] reqAddr,
    input  wire [2:0] reqType,
    input  wire [DATA_WIDTH-1:0] reqData,
    output reg  reqReady,
    
    output reg  respValid,
    output reg  [CORE_ID_WIDTH-1:0] respCoreId,
    output reg  [DATA_WIDTH-1:0] respData,
    output reg  [1:0] respType,
    
    output reg  snoopValid,
    output reg  [NUM_CORES-1:0] snoopCoreMask,
    output reg  [ADDR_WIDTH-1:0] snoopAddr,
    output reg  [1:0] snoopType,
    input  wire snoopRespValid,
    input  wire [CORE_ID_WIDTH-1:0] snoopRespCoreId,
    input  wire [DATA_WIDTH-1:0] snoopRespData,
    
    output reg [31:0] perfHits,
    output reg [31:0] perfMisses,
    output reg [31:0] perfInvalidations,
    output reg [31:0] perfWritebacks
);

    localparam REQ_READ       = 3'd0;
    localparam REQ_WRITE      = 3'd1;
    localparam REQ_INVALIDATE = 3'd2;
    localparam REQ_WRITEBACK  = 3'd3;
    localparam REQ_UPGRADE    = 3'd4;
    
    localparam RESP_ACK  = 2'd0;
    localparam RESP_DATA_TYPE = 2'd1;
    localparam RESP_NACK = 2'd2;
    
    localparam SNOOP_INV   = 2'd0;
    localparam SNOOP_FETCH = 2'd1;
    localparam SNOOP_WB    = 2'd2;
    
    localparam STATE_I = 3'd0;
    localparam STATE_S = 3'd1;
    localparam STATE_E = 3'd2;
    localparam STATE_O = 3'd3;
    localparam STATE_M = 3'd4;

    reg validArray [DIRECTORY_ENTRIES-1:0];
    reg [ADDR_WIDTH-1:0] tagArray [DIRECTORY_ENTRIES-1:0];
    reg [2:0] stateArray [DIRECTORY_ENTRIES-1:0];
    reg [NUM_CORES-1:0] sharersArray [DIRECTORY_ENTRIES-1:0];
    reg [CORE_ID_WIDTH-1:0] ownerArray [DIRECTORY_ENTRIES-1:0];
    
    wire [$clog2(DIRECTORY_ENTRIES)-1:0] lookupIdx = reqAddr[$clog2(DIRECTORY_ENTRIES)-1:0];
    
    typedef enum logic [2:0] {
        IDLE,
        EVALUATE,
        WAIT_SNOOP,
        RESPOND
    } fsmSTATE_E;
    
    fsmSTATE_E state;
    
    reg [CORE_ID_WIDTH-1:0] latchedReqCoreId;
    reg [ADDR_WIDTH-1:0] latchedReqAddr;
    reg [2:0] latchedReqType;
    reg [DATA_WIDTH-1:0] latchedReqData;
    
    reg [4:0] snoopExpected;
    reg [4:0] snoopAckCnt;
    reg [8:0] snoopTimeout;
    
    reg [2:0] pendingNewState;
    reg [CORE_ID_WIDTH-1:0] pendingNewOwner;
    reg [NUM_CORES-1:0] pendingNewSharers;
    
    wire matchComb = validArray[lookupIdx] && (tagArray[lookupIdx] == latchedReqAddr);
    wire [2:0] lineStateComb = matchComb ? stateArray[lookupIdx] : STATE_I;
    wire [NUM_CORES-1:0] sharersComb = matchComb ? sharersArray[lookupIdx] : 0;
    wire [NUM_CORES-1:0] invalidationMaskComb = sharersComb & ~(1 << latchedReqCoreId);
    
    function [4:0] countOnes;
        input [NUM_CORES-1:0] mask;
        integer j;
        begin
            countOnes = 0;
            for (j = 0; j < NUM_CORES; j = j + 1) begin
                if (mask[j]) countOnes = countOnes + 1;
            end
        end
    endfunction
    
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            reqReady <= 1;
            respValid <= 0;
            snoopValid <= 0;
            perfHits <= 0;
            perfMisses <= 0;
            perfInvalidations <= 0;
            perfWritebacks <= 0;
            
            for (i = 0; i < DIRECTORY_ENTRIES; i = i + 1) begin
                validArray[i] <= 0;
            end
        end else begin
            respValid <= 0;
            snoopValid <= 0;
            
            case (state)
                IDLE: begin
                    if (reqValid) begin
                        latchedReqCoreId <= reqCoreId;
                        latchedReqAddr <= reqAddr;
                        latchedReqType <= reqType;
                        latchedReqData <= reqData;
                        reqReady <= 0;
                        state <= EVALUATE;
                    end
                end
                
                EVALUATE: begin
                    if (!matchComb) begin
                        perfMisses <= perfMisses + 1;
                        validArray[lookupIdx] <= 1;
                        tagArray[lookupIdx] <= latchedReqAddr;
                        
                        if (latchedReqType == REQ_READ) begin
                            stateArray[lookupIdx] <= STATE_E;
                            ownerArray[lookupIdx] <= latchedReqCoreId;
                            sharersArray[lookupIdx] <= (1 << latchedReqCoreId);
                            
                            respValid <= 1;
                            respType <= RESP_DATA_TYPE;
                            respData <= 0;
                            respCoreId <= latchedReqCoreId;
                            state <= IDLE;
                            reqReady <= 1;
                        end else if (latchedReqType == REQ_WRITE) begin
                            stateArray[lookupIdx] <= STATE_M;
                            ownerArray[lookupIdx] <= latchedReqCoreId;
                            sharersArray[lookupIdx] <= 0;
                            
                            respValid <= 1;
                            respType <= RESP_ACK;
                            respCoreId <= latchedReqCoreId;
                            state <= IDLE;
                            reqReady <= 1;
                        end else begin
                            respValid <= 1;
                            respType <= RESP_NACK;
                            respCoreId <= latchedReqCoreId;
                            state <= IDLE;
                            reqReady <= 1;
                        end
                    end else begin
                        perfHits <= perfHits + 1;
                        
                        case (latchedReqType)
                            REQ_READ: begin
                                if (lineStateComb == STATE_M || lineStateComb == STATE_O) begin
                                    snoopValid <= 1;
                                    snoopCoreMask <= (1 << ownerArray[lookupIdx]);
                                    snoopAddr <= latchedReqAddr;
                                    snoopType <= SNOOP_FETCH;
                                    snoopExpected <= 1;
                                    snoopAckCnt <= 0;
                                    snoopTimeout <= 0;
                                    state <= WAIT_SNOOP;
                                    
                                    pendingNewState <= STATE_O;
                                    pendingNewOwner <= ownerArray[lookupIdx];
                                    pendingNewSharers <= sharersComb | (1 << latchedReqCoreId);
                                end else begin
                                    if (lineStateComb == STATE_E) stateArray[lookupIdx] <= STATE_S;
                                    sharersArray[lookupIdx] <= sharersComb | (1 << latchedReqCoreId);
                                    
                                    respValid <= 1;
                                    respType <= RESP_DATA_TYPE;
                                    respData <= 0;
                                    respCoreId <= latchedReqCoreId;
                                    state <= IDLE;
                                    reqReady <= 1;
                                end
                            end
                            
                            REQ_WRITE, REQ_UPGRADE: begin
                                if (invalidationMaskComb != 0) begin
                                    snoopValid <= 1;
                                    snoopCoreMask <= invalidationMaskComb;
                                    snoopAddr <= latchedReqAddr;
                                    snoopType <= SNOOP_INV;
                                    snoopExpected <= countOnes(invalidationMaskComb);
                                    snoopAckCnt <= 0;
                                    snoopTimeout <= 0;
                                    perfInvalidations <= perfInvalidations + 1;
                                    state <= WAIT_SNOOP;
                                    
                                    pendingNewState <= STATE_M;
                                    pendingNewOwner <= latchedReqCoreId;
                                    pendingNewSharers <= 0;
                                end else begin
                                    respValid <= 1;
                                    respType <= RESP_ACK;
                                    respCoreId <= latchedReqCoreId;
                                    state <= IDLE;
                                    reqReady <= 1;
                                    
                                    stateArray[lookupIdx] <= STATE_M;
                                    ownerArray[lookupIdx] <= latchedReqCoreId;
                                    sharersArray[lookupIdx] <= 0;
                                end
                            end
                            
                            REQ_WRITEBACK: begin
                                if (latchedReqCoreId == ownerArray[lookupIdx] && (lineStateComb == STATE_M || lineStateComb == STATE_O)) begin
                                    perfWritebacks <= perfWritebacks + 1;
                                    if (sharersComb == 0) validArray[lookupIdx] <= 0;
                                    else begin
                                        stateArray[lookupIdx] <= STATE_S;
                                    end
                                end else begin
                                    sharersArray[lookupIdx] <= sharersComb & ~(1 << latchedReqCoreId);
                                end
                                respValid <= 1;
                                respType <= RESP_ACK;
                                respCoreId <= latchedReqCoreId;
                                state <= IDLE;
                                reqReady <= 1;
                            end
                        endcase
                    end
                end
                
                WAIT_SNOOP: begin
                    snoopTimeout <= snoopTimeout + 1;
                    if (snoopRespValid) begin
                        snoopAckCnt <= snoopAckCnt + 1;
                        if (latchedReqType == REQ_READ) begin
                            respValid <= 1;
                            respType <= RESP_DATA_TYPE;
                            respData <= snoopRespData;
                            respCoreId <= latchedReqCoreId;
                            state <= IDLE;
                            reqReady <= 1;
                            
                            stateArray[lookupIdx] <= pendingNewState;
                            ownerArray[lookupIdx] <= pendingNewOwner;
                            sharersArray[lookupIdx] <= pendingNewSharers;
                        end else begin
                            if (snoopAckCnt + 1 == snoopExpected) begin
                                respValid <= 1;
                                respType <= RESP_ACK;
                                respCoreId <= latchedReqCoreId;
                                state <= IDLE;
                                reqReady <= 1;
                                
                                stateArray[lookupIdx] <= pendingNewState;
                                ownerArray[lookupIdx] <= pendingNewOwner;
                                sharersArray[lookupIdx] <= pendingNewSharers;
                            end
                        end
                    end else if (snoopTimeout >= 256) begin
                        respValid <= 1;
                        respType <= RESP_NACK;
                        respCoreId <= latchedReqCoreId;
                        state <= IDLE;
                        reqReady <= 1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
