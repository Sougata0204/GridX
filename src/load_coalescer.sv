
`default_nettype none
`timescale 1ns/1ns

module loadCoalescer #(
    parameter LANES = 4,
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 16,
    parameter CACHE_LINE_SIZE = 16
) (
    input wire clk,
    input wire reset,
    input wire [LANES-1:0] laneValid,
    input wire [ADDR_WIDTH-1:0] laneAddr [LANES-1:0],
    input wire laneReadEnable,
    output reg coalescedReqValid,
    output reg [ADDR_WIDTH-1:0] coalescedReqAddr,
    output reg [4:0] coalescedReqCount,
    output reg [LANES-1:0] coalescedLaneMask,
    input wire coalescedReqReady,
    input wire respValid,
    input wire [DATA_WIDTH*LANES-1:0] respData,
    output reg [LANES-1:0] laneRespValid,
    output reg [DATA_WIDTH-1:0] laneRespData [LANES-1:0],
    output reg [31:0] perfCoalescedRequests,
    output reg [31:0] perfUncoalescedRequests,
    output reg [31:0] perfBytesSaved
);
    localparam IDLE = 2'b00;
    localparam ANALYZE = 2'b01;
    localparam REQUEST = 2'b10;
    localparam RESPONSE = 2'b11;
    reg [1:0] state;
    wire [ADDR_WIDTH-1:0] sortedAddr [LANES-1:0];
    wire [3:0] sortedLaneId [LANES-1:0];
    reg [LANES-1:0] activeLanes;
    reg [ADDR_WIDTH-1:0] baseAddr;
    reg [4:0] contiguousCount;
    integer i, j;
    reg [ADDR_WIDTH-1:0] minAddr;
    reg [3:0] minLane;
    reg [LANES-1:0] remainingLanes;
    always @(*) begin
        contiguousCount = 0;
        baseAddr = 16'hFFFF;
        activeLanes = 0;
        minAddr = 16'hFFFF;
        minLane = 0;
        remainingLanes = 0;
        if (laneReadEnable && |laneValid) begin
            for (i = 0; i < LANES; i = i + 1) begin
                if (laneValid[i] && laneAddr[i] < minAddr) begin
                    minAddr = laneAddr[i];
                    minLane = i[3:0];
                end
            end
            baseAddr = minAddr;
            remainingLanes = laneValid;
            for (j = 0; j < LANES; j = j + 1) begin
                for (i = 0; i < LANES; i = i + 1) begin
                    if (remainingLanes[i] && (laneAddr[i] == baseAddr + j)) begin
                        activeLanes[i] = 1;
                        contiguousCount = contiguousCount + 1;
                        remainingLanes[i] = 0;
                    end
                end
            end
        end
    end
    reg [LANES-1:0] pendingLanes;
    reg [ADDR_WIDTH-1:0] pendingBase;
    reg [4:0] pendingCount;
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            coalescedReqValid <= 0;
            coalescedReqAddr <= 0;
            coalescedReqCount <= 0;
            coalescedLaneMask <= 0;
            laneRespValid <= 0;
            perfCoalescedRequests <= 0;
            perfUncoalescedRequests <= 0;
            perfBytesSaved <= 0;
            pendingLanes <= 0;
            pendingBase <= 0;
            pendingCount <= 0;
            for (i = 0; i < LANES; i = i + 1) laneRespData[i] <= 0;
        end else begin
            laneRespValid <= 0;
            case (state)
                IDLE: begin
                    coalescedReqValid <= 0;
                    if (laneReadEnable && |laneValid) begin
                        state <= ANALYZE;
                    end
                end
                ANALYZE: begin
                    pendingLanes <= activeLanes;
                    pendingBase <= baseAddr;
                    pendingCount <= contiguousCount;
                    coalescedReqValid <= 1;
                    coalescedReqAddr <= baseAddr;
                    coalescedReqCount <= contiguousCount;
                    coalescedLaneMask <= activeLanes;
                    state <= REQUEST;
                    if (contiguousCount > 1) begin
                        perfCoalescedRequests <= perfCoalescedRequests + 1;
                        perfBytesSaved <= perfBytesSaved + ((contiguousCount - 1) * DATA_WIDTH / 8);
                    end else begin
                        perfUncoalescedRequests <= perfUncoalescedRequests + 1;
                    end
                end
                REQUEST: begin
                    if (coalescedReqReady) begin
                        coalescedReqValid <= 0;
                        state <= RESPONSE;
                    end
                end
                RESPONSE: begin
                    if (respValid) begin
                        for (i = 0; i < LANES; i = i + 1) begin
                            if (pendingLanes[i]) begin
                                laneRespValid[i] <= 1;
                                laneRespData[i] <= respData[(laneAddr[i] - pendingBase) * DATA_WIDTH +: DATA_WIDTH];
                            end
                        end
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
