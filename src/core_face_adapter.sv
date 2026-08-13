
`default_nettype none
`timescale 1ns/1ns

module coreFaceAdapter #(
    parameter FACE_ID = 0,
    parameter CORES_PER_FACE = 16,
    parameter ADDR_WIDTH = 22,
    parameter DATA_WIDTH = 8
) (
    input  wire clk,
    input  wire reset,
    input  wire [CORES_PER_FACE-1:0] l2ReqValid,
    input  wire [CORES_PER_FACE-1:0] l2ReqWrite,
    input  wire [ADDR_WIDTH-1:0] l2ReqAddr [CORES_PER_FACE-1:0],
    input  wire [DATA_WIDTH-1:0] l2ReqWdata [CORES_PER_FACE-1:0],
    output reg  [CORES_PER_FACE-1:0] l2ReqReady,
    output reg  [DATA_WIDTH-1:0] l2ReqRdata [CORES_PER_FACE-1:0],
    output reg  shellReqValid,
    output reg  shellReqWrite,
    output reg  [ADDR_WIDTH-1:0] shellReqAddr,
    output reg  [DATA_WIDTH-1:0] shellReqWdata,
    input  wire shellReqReady,
    input  wire [DATA_WIDTH-1:0] shellReqRdata,
    input  wire shellCreditAvailable,
    output wire shellCreditConsumed,
    output reg  [$clog2(CORES_PER_FACE)-1:0] currentCore,
    output wire adapterBusy
);
    localparam IDLE = 2'b00;
    localparam REQUESTING = 2'b01;
    localparam WAITING = 2'b10;
    reg [1:0] state;
    reg [$clog2(CORES_PER_FACE)-1:0] lastServed;
    reg [$clog2(CORES_PER_FACE)-1:0] activeCore;
    reg foundRequest;
    reg [$clog2(CORES_PER_FACE)-1:0] nextCore;
    assign adapterBusy = (state != IDLE);
    assign shellCreditConsumed = (state == IDLE) && foundRequest && shellCreditAvailable;
    wire [CORES_PER_FACE-1:0] pendingRequests;
    assign pendingRequests = l2ReqValid;
    always @(*) begin
        foundRequest = 0;
        nextCore = lastServed;
        for (int i = 0; i < CORES_PER_FACE; i++) begin
            automatic int checkIdx = (lastServed + 1 + i) % CORES_PER_FACE;
            if (pendingRequests[checkIdx] && !foundRequest) begin
                nextCore = checkIdx[$clog2(CORES_PER_FACE)-1:0];
                foundRequest = 1;
            end
        end
    end
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            lastServed <= 0;
            activeCore <= 0;
            currentCore <= 0;
            shellReqValid <= 0;
            shellReqWrite <= 0;
            shellReqAddr <= 0;
            shellReqWdata <= 0;
            l2ReqReady <= 0;
            for (i = 0; i < CORES_PER_FACE; i++) begin
                l2ReqRdata[i] <= 0;
            end
        end else begin
            l2ReqReady <= 0;
            case (state)
                IDLE: begin
                    if (foundRequest && shellCreditAvailable) begin
                        activeCore <= nextCore;
                        currentCore <= nextCore;
                        shellReqValid <= 1;
                        shellReqWrite <= l2ReqWrite[nextCore];
                        shellReqAddr <= l2ReqAddr[nextCore];
                        shellReqWdata <= l2ReqWdata[nextCore];
                        lastServed <= nextCore;
                        state <= WAITING;
                    end
                end
                WAITING: begin
                    if (shellReqReady) begin
                        shellReqValid <= 0;
                        l2ReqReady[activeCore] <= 1;
                        l2ReqRdata[activeCore] <= shellReqRdata;
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
