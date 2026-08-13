
`default_nettype none
`timescale 1ns/1ns

module faceController #(
    parameter ADDR_WIDTH    = 13,       // Address bits
    parameter DATA_WIDTH    = 8,        // Data width
    parameter BUFFER_DEPTH  = 4,        // Request/response buffer depth
    parameter FACE_ID       = 0,        // 0=+X, 1=-X, 2=+Y, 3=-Y, 4=+Z, 5=-Z
    parameter creditCount  = 4         // Initial credits for flow control
) (
    // Clock / Reset
    input  wire                    clk,
    input  wire                    reset,

    // Core-side interface (from LSU / memory subsystem)
    // Core request in
    input  wire                    coreReqValid,
    input  wire                    coreReqWrite,
    input  wire [ADDR_WIDTH-1:0]   coreReqAddr,
    input  wire [DATA_WIDTH-1:0]   coreReqWdata,
    output wire                    coreReqReady,     // backpressure to core

    // Core response out
    output wire                    coreRespValid,
    output wire [DATA_WIDTH-1:0]   coreRespRdata,
    input  wire                    coreRespReady,

    // Memory Sheet-side interface (to adjacent Memory Sheet)
    // Sheet request out
    output wire                    sheetReqValid,
    output wire                    sheetReqWrite,
    output wire [ADDR_WIDTH-1:0]   sheetReqAddr,
    output wire [DATA_WIDTH-1:0]   sheetReqWdata,
    input  wire                    sheetReqReady,

    // Sheet response in
    input  wire                    sheetRespValid,
    input  wire [DATA_WIDTH-1:0]   sheetRespRdata,
    output wire                    sheetRespReady,

    // Credit flow & status
    output wire [3:0]              creditsAvailable,   // credits remaining
    output wire                    fcBusy              // pending transactions
);

    // Local parameters

    localparam PTR_W    = (BUFFER_DEPTH <= 1) ? 1 : $clog2(BUFFER_DEPTH);

    // Count width - needs to represent 0 .. BUFFER_DEPTH inclusive
    localparam CNT_W    = $clog2(BUFFER_DEPTH + 1);

    // Credit counter width - needs to represent 0 .. creditCount inclusive
    localparam CREDIT_W = (creditCount <= 1) ? 1 : $clog2(creditCount + 1);

    // Request FIFO entry packing:  { write [1b] , addr [AW] , wdata [DW] }
    localparam REQ_W    = 1 + ADDR_WIDTH + DATA_WIDTH;

    // Typed constants (avoids width-mismatch warnings)
    localparam [PTR_W-1:0]    PTR_ZERO  = {PTR_W{1'b0}};
    localparam [PTR_W-1:0]    PTR_ONE   = {{(PTR_W-1){1'b0}}, 1'b1};
    localparam [PTR_W-1:0]    PTR_LAST  = BUFFER_DEPTH[PTR_W-1:0] - PTR_ONE;
    localparam [CNT_W-1:0]    CNT_ZERO  = {CNT_W{1'b0}};
    localparam [CNT_W-1:0]    CNT_ONE   = {{(CNT_W-1){1'b0}}, 1'b1};
    localparam [CNT_W-1:0]    CNT_FULL  = BUFFER_DEPTH[CNT_W-1:0];
    localparam [CREDIT_W-1:0] CRED_ZERO = {CREDIT_W{1'b0}};
    localparam [CREDIT_W-1:0] CRED_ONE  = {{(CREDIT_W-1){1'b0}}, 1'b1};
    localparam [CREDIT_W-1:0] CRED_INIT = creditCount[CREDIT_W-1:0];

    // Request FIFO - inline circular buffer
    reg  [REQ_W-1:0]   reqMem  [0:BUFFER_DEPTH-1];
    reg  [PTR_W-1:0]   reqWptr;
    reg  [PTR_W-1:0]   reqRptr;
    reg  [CNT_W-1:0]   reqCount;

    wire               reqFull  = (reqCount == CNT_FULL);
    wire               reqEmpty = (reqCount == CNT_ZERO);

    // Handshake fires
    wire reqPush = coreReqValid  & coreReqReady;    // enqueue from core
    wire reqPop  = sheetReqValid & sheetReqReady;    // dequeue to sheet

    // Next-pointer with wrap
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
                2'b10: begin   // push only
                    reqMem[reqWptr] <= {coreReqWrite, coreReqAddr,
                                          coreReqWdata};
                    reqWptr          <= reqWptrNxt;
                    reqCount         <= reqCount + CNT_ONE;
                end
                2'b01: begin   // pop only
                    reqRptr  <= reqRptrNxt;
                    reqCount <= reqCount - CNT_ONE;
                end
                2'b11: begin   // simultaneous push + pop
                    reqMem[reqWptr] <= {coreReqWrite, coreReqAddr,
                                          coreReqWdata};
                    reqWptr          <= reqWptrNxt;
                    reqRptr          <= reqRptrNxt;
                    // count is unchanged
                end
                default: ;     // 2'b00 - idle
            endcase
        end
    end

    // Head-of-queue read (combinational)
    wire [REQ_W-1:0] reqHead = reqMem[reqRptr];

    // Response FIFO - inline circular buffer
    reg  [DATA_WIDTH-1:0] respMem  [0:BUFFER_DEPTH-1];
    reg  [PTR_W-1:0]      respWptr;
    reg  [PTR_W-1:0]      respRptr;
    reg  [CNT_W-1:0]      respCount;

    wire                  respFull  = (respCount == CNT_FULL);
    wire                  respEmpty = (respCount == CNT_ZERO);

    // Handshake fires
    wire respPush = sheetRespValid & sheetRespReady;  // enqueue from sheet
    wire respPop  = coreRespValid  & coreRespReady;   // dequeue to core

    // Next-pointer with wrap
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
                2'b10: begin   // push only
                    respMem[respWptr] <= sheetRespRdata;
                    respWptr           <= respWptrNxt;
                    respCount          <= respCount + CNT_ONE;
                end
                2'b01: begin   // pop only
                    respRptr  <= respRptrNxt;
                    respCount <= respCount - CNT_ONE;
                end
                2'b11: begin   // simultaneous push + pop
                    respMem[respWptr] <= sheetRespRdata;
                    respWptr           <= respWptrNxt;
                    respRptr           <= respRptrNxt;
                    // count is unchanged
                end
                default: ;     // 2'b00 - idle
            endcase
        end
    end

    // Head-of-queue read (combinational)
    wire [DATA_WIDTH-1:0] respHead = respMem[respRptr];

    // Credit Manager
    reg [CREDIT_W-1:0] creditCnt;

    wire creditDec  = reqPop;    // request sent to sheet   ? consume credit
    wire creditInc  = respPush;  // response from sheet     ? return credit
    wire hasCredits = (creditCnt != CRED_ZERO);

    always @(posedge clk) begin
        if (reset) begin
            creditCnt <= CRED_INIT;
        end else begin
            case ({creditInc, creditDec})
                2'b10:   creditCnt <= creditCnt + CRED_ONE;  // return
                2'b01:   creditCnt <= creditCnt - CRED_ONE;  // consume
                default: ;  // 2'b00 no change, 2'b11 net-zero
            endcase
        end
    end

    // Request Scheduler - drives Memory-Sheet-side request port

    // Accept core requests whenever the request FIFO has room
    assign coreReqReady  = ~reqFull;

    // Present a request to the sheet only when:
    // (a) The request FIFO is non-empty, AND
    // (b) We have at least one credit outstanding
    assign sheetReqValid = ~reqEmpty & hasCredits;

    // Unpack the request FIFO head into sheet-side signals
    // Packing order (MSB ? LSB):  { write [1b], addr [AW], wdata [DW] }
    assign sheetReqWrite = reqHead[ADDR_WIDTH + DATA_WIDTH];
    assign sheetReqAddr  = reqHead[DATA_WIDTH +: ADDR_WIDTH];
    assign sheetReqWdata = reqHead[DATA_WIDTH-1:0];

    // Response Scheduler - drives core-side response port

    // Accept sheet responses whenever the response FIFO has room
    assign sheetRespReady = ~respFull;

    // Present a response to the core whenever the response FIFO is non-empty
    assign coreRespValid = ~respEmpty;
    assign coreRespRdata = respHead;

    // Status Outputs

    // Credits remaining (zero-extended or truncated to 4 bits)
    assign creditsAvailable = creditCnt;

    // Busy when any FIFO is non-empty OR there are in-flight transactions
    // (i.e. some credits have been consumed but their responses haven't
    // arrived yet)
    assign fcBusy = ~reqEmpty | ~respEmpty | (creditCnt != CRED_INIT);

    // Performance Counters (synthesisable, free-running, 32-bit)
    reg [31:0] perfReqsSent;   // total requests forwarded to sheet
    reg [31:0] perfRespsRecv;  // total responses delivered to core

    always @(posedge clk) begin
        if (reset) begin
            perfReqsSent  <= 32'd0;
            perfRespsRecv <= 32'd0;
        end else begin
            if (reqPop)  perfReqsSent  <= perfReqsSent  + 32'd1;
            if (respPop) perfRespsRecv <= perfRespsRecv + 32'd1;
        end
    end

    // Parameter Validation (synthesis-time)
    // synopsys translateOff
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
    // synopsys translateOn

endmodule

`default_nettype wire
