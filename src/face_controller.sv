
`default_nettype none
`timescale 1ns/1ns

// 3D mesh face controller managing packet routing across the six faces of the cube topology with deadlock-free turn restrictions.
module faceController #(
    parameter ADDR_WIDTH    = 13,
    parameter DATA_WIDTH    = 8,
    parameter BUFFER_DEPTH  = 4,
    parameter FACE_ID       = 0,
    parameter creditCount  = 4
) (
    input  wire                    clk,
    input  wire                    reset,

    input  wire                    coreReqValid,
    input  wire                    coreReqWrite,
    input  wire [ADDR_WIDTH-1:0]   coreReqAddr,
    input  wire [DATA_WIDTH-1:0]   coreReqWdata,
    output wire                    coreReqReady,

    output wire                    coreRespValid,
    output wire [DATA_WIDTH-1:0]   coreRespRdata,
    input  wire                    coreRespReady,

    output wire                    sheetReqValid,
    output wire                    sheetReqWrite,
    output wire [ADDR_WIDTH-1:0]   sheetReqAddr,
    output wire [DATA_WIDTH-1:0]   sheetReqWdata,
    input  wire                    sheetReqReady,

    input  wire                    sheetRespValid,
    input  wire [DATA_WIDTH-1:0]   sheetRespRdata,
    output wire                    sheetRespReady,

    output wire [3:0]              creditsAvailable,
    output wire                    fcBusy
);

    localparam PTR_W    = (BUFFER_DEPTH <= 1) ? 1 : $clog2(BUFFER_DEPTH);

    localparam CNT_W    = $clog2(BUFFER_DEPTH + 1);

    localparam CREDIT_W = (creditCount <= 1) ? 1 : $clog2(creditCount + 1);

    localparam REQ_W    = 1 + ADDR_WIDTH + DATA_WIDTH;

    localparam [PTR_W-1:0]    PTR_ZERO  = {PTR_W{1'b0}};
    localparam [PTR_W-1:0]    PTR_ONE   = {{(PTR_W-1){1'b0}}, 1'b1};
    localparam [PTR_W-1:0]    PTR_LAST  = BUFFER_DEPTH[PTR_W-1:0] - PTR_ONE;
    localparam [CNT_W-1:0]    CNT_ZERO  = {CNT_W{1'b0}};
    localparam [CNT_W-1:0]    CNT_ONE   = {{(CNT_W-1){1'b0}}, 1'b1};
    localparam [CNT_W-1:0]    CNT_FULL  = BUFFER_DEPTH[CNT_W-1:0];
    localparam [CREDIT_W-1:0] CRED_ZERO = {CREDIT_W{1'b0}};
    localparam [CREDIT_W-1:0] CRED_ONE  = {{(CREDIT_W-1){1'b0}}, 1'b1};
    localparam [CREDIT_W-1:0] CRED_INIT = creditCount[CREDIT_W-1:0];

    reg  [REQ_W-1:0]   reqMem  [0:BUFFER_DEPTH-1];
    reg  [PTR_W-1:0]   reqWptr;
    reg  [PTR_W-1:0]   reqRptr;
    reg  [CNT_W-1:0]   reqCount;

    wire               reqFull  = (reqCount == CNT_FULL);
    wire               reqEmpty = (reqCount == CNT_ZERO);

    wire reqPush = coreReqValid  & coreReqReady;
    wire reqPop  = sheetReqValid & sheetReqReady;

    wire [PTR_W-1:0] reqWptrNxt = (reqWptr == PTR_LAST) ? PTR_ZERO
                                                            : reqWptr + PTR_ONE;
    wire [PTR_W-1:0] reqRptrNxt = (reqRptr == PTR_LAST) ? PTR_ZERO
                                                            : reqRptr + PTR_ONE;

    always @(posedge clk) begin
        if (reset) begin
            reqWptr  <= PTR_ZERO;
            reqRptr  <= PTR_ZERO;
            reqCount <= CNT_ZERO;
        end else begin
            case ({reqPush, reqPop})
                2'b10: begin
                    reqMem[reqWptr] <= {coreReqWrite, coreReqAddr,
                                          coreReqWdata};
                    reqWptr          <= reqWptrNxt;
                    reqCount         <= reqCount + CNT_ONE;
                end
                2'b01: begin
                    reqRptr  <= reqRptrNxt;
                    reqCount <= reqCount - CNT_ONE;
                end
                2'b11: begin
                    reqMem[reqWptr] <= {coreReqWrite, coreReqAddr,
                                          coreReqWdata};
                    reqWptr          <= reqWptrNxt;
                    reqRptr          <= reqRptrNxt;
                end
                default: ;
            endcase
        end
    end

    wire [REQ_W-1:0] reqHead = reqMem[reqRptr];

    reg  [DATA_WIDTH-1:0] respMem  [0:BUFFER_DEPTH-1];
    reg  [PTR_W-1:0]      respWptr;
    reg  [PTR_W-1:0]      respRptr;
    reg  [CNT_W-1:0]      respCount;

    wire                  respFull  = (respCount == CNT_FULL);
    wire                  respEmpty = (respCount == CNT_ZERO);

    wire respPush = sheetRespValid & sheetRespReady;
    wire respPop  = coreRespValid  & coreRespReady;

    wire [PTR_W-1:0] respWptrNxt = (respWptr == PTR_LAST) ? PTR_ZERO
                                                              : respWptr + PTR_ONE;
    wire [PTR_W-1:0] respRptrNxt = (respRptr == PTR_LAST) ? PTR_ZERO
                                                              : respRptr + PTR_ONE;

    always @(posedge clk) begin
        if (reset) begin
            respWptr  <= PTR_ZERO;
            respRptr  <= PTR_ZERO;
            respCount <= CNT_ZERO;
        end else begin
            case ({respPush, respPop})
                2'b10: begin
                    respMem[respWptr] <= sheetRespRdata;
                    respWptr           <= respWptrNxt;
                    respCount          <= respCount + CNT_ONE;
                end
                2'b01: begin
                    respRptr  <= respRptrNxt;
                    respCount <= respCount - CNT_ONE;
                end
                2'b11: begin
                    respMem[respWptr] <= sheetRespRdata;
                    respWptr           <= respWptrNxt;
                    respRptr           <= respRptrNxt;
                end
                default: ;
            endcase
        end
    end

    wire [DATA_WIDTH-1:0] respHead = respMem[respRptr];

    reg [CREDIT_W-1:0] creditCnt;

    wire creditDec  = reqPop;
    wire creditInc  = respPush;
    wire hasCredits = (creditCnt != CRED_ZERO);

    always @(posedge clk) begin
        if (reset) begin
            creditCnt <= CRED_INIT;
        end else begin
            case ({creditInc, creditDec})
                2'b10:   creditCnt <= creditCnt + CRED_ONE;
                2'b01:   creditCnt <= creditCnt - CRED_ONE;
                default: ;
            endcase
        end
    end

    assign coreReqReady  = ~reqFull;

    assign sheetReqValid = ~reqEmpty & hasCredits;

    assign sheetReqWrite = reqHead[ADDR_WIDTH + DATA_WIDTH];
    assign sheetReqAddr  = reqHead[DATA_WIDTH +: ADDR_WIDTH];
    assign sheetReqWdata = reqHead[DATA_WIDTH-1:0];

    assign sheetRespReady = ~respFull;

    assign coreRespValid = ~respEmpty;
    assign coreRespRdata = respHead;

    assign creditsAvailable = creditCnt;

    assign fcBusy = ~reqEmpty | ~respEmpty | (creditCnt != CRED_INIT);

    reg [31:0] perfReqsSent;
    reg [31:0] perfRespsRecv;

    always @(posedge clk) begin
        if (reset) begin
            perfReqsSent  <= 32'd0;
            perfRespsRecv <= 32'd0;
        end else begin
            if (reqPop)  perfReqsSent  <= perfReqsSent  + 32'd1;
            if (respPop) perfRespsRecv <= perfRespsRecv + 32'd1;
        end
    end

    initial begin
        if (BUFFER_DEPTH < 1) begin
            $fatal(1, "faceController: BUFFER_DEPTH must be >= 1 (got %0d)",
                   BUFFER_DEPTH);
        end
        if (creditCount < 1) begin
            $fatal(1, "faceController: creditCount must be >= 1 (got %0d)",
                   creditCount);
        end
        if (FACE_ID > 5) begin
            $warning("faceController: FACE_ID=%0d is outside 0-5 range",
                     FACE_ID);
        end
    end

endmodule

`default_nettype wire
