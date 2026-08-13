
`default_nettype none
`timescale 1ns/1ns

module memShellController #(
    parameter NUM_FACES = 6,
    parameter ADDR_WIDTH = 22,
    parameter DATA_WIDTH = 8,
    parameter MAX_OUTSTANDING = 8,
    parameter SHELL_SIZE_BYTES = 512 * 1024
) (
    input  wire clk,
    input  wire reset,
    input  wire [NUM_FACES-1:0] faceReqValid,
    input  wire [NUM_FACES-1:0] faceReqWrite,
    input  wire [ADDR_WIDTH-1:0] faceReqAddr [NUM_FACES-1:0],
    input  wire [DATA_WIDTH-1:0] faceReqWdata [NUM_FACES-1:0],
    output reg  [NUM_FACES-1:0] faceReqReady,
    output reg  [DATA_WIDTH-1:0] faceReqRdata [NUM_FACES-1:0],
    output wire [NUM_FACES-1:0] faceCreditAvailable,
    output reg  sramReqValid,
    output reg  sramReqWrite,
    output reg  [ADDR_WIDTH-1:0] sramReqAddr,
    output reg  [DATA_WIDTH-1:0] sramReqWdata,
    input  wire sramReqReady,
    input  wire [DATA_WIDTH-1:0] sramReqRdata,
    output wire [$clog2(MAX_OUTSTANDING):0] outstandingCount,
    output wire shellBusy,
    output reg  [31:0] totalRequests,
    output reg  [31:0] totalCompletions
);
    localparam SHELL_ADDR_BITS = $clog2(SHELL_SIZE_BYTES);
    localparam FACE_CREDITS_MAX = MAX_OUTSTANDING / NUM_FACES;
    localparam QUEUE_DEPTH = MAX_OUTSTANDING;
    localparam QUEUE_ENTRY_WIDTH = 1 + 1 + 3 + ADDR_WIDTH + DATA_WIDTH;
    reg [QUEUE_ENTRY_WIDTH-1:0] requestQueue [QUEUE_DEPTH-1:0];
    reg [$clog2(QUEUE_DEPTH)-1:0] queueHead;
    reg [$clog2(QUEUE_DEPTH)-1:0] queueTail;
    reg [$clog2(QUEUE_DEPTH):0] queueCount;
    reg [$clog2(FACE_CREDITS_MAX):0] faceCredits [NUM_FACES-1:0];
    reg [2:0] pendingFaceId [MAX_OUTSTANDING-1:0];
    reg [$clog2(MAX_OUTSTANDING)-1:0] responseHead;
    reg [$clog2(MAX_OUTSTANDING)-1:0] responseTail;
    reg [2:0] currentFace;
    reg [2:0] lastServedFace;
    genvar f;
    generate
        for (f = 0; f < NUM_FACES; f++) begin : faceCreditGen
            assign faceCreditAvailable[f] = (faceCredits[f] > 0);
        end
    endgenerate
    wire [NUM_FACES-1:0] faceCanRequest;
    assign faceCanRequest = faceReqValid & faceCreditAvailable;
    reg [2:0] nextFace;
    reg foundRequest;
    always @(*) begin
        foundRequest = 0;
        nextFace = lastServedFace;
        for (int i = 0; i < NUM_FACES; i++) begin
            automatic int checkFace = (lastServedFace + 1 + i) % NUM_FACES;
            if (faceCanRequest[checkFace] && !foundRequest) begin
                nextFace = checkFace[2:0];
                foundRequest = 1;
            end
        end
    end
    localparam IDLE = 2'b00;
    localparam WAITING = 2'b01;
    localparam RESPONDING = 2'b10;
    reg [1:0] state;
    reg [2:0] activeFace;
    reg activeWrite;
    assign outstandingCount = queueCount;
    assign shellBusy = (state != IDLE) || (queueCount > 0);
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            queueHead <= 0;
            queueTail <= 0;
            queueCount <= 0;
            lastServedFace <= 0;
            sramReqValid <= 0;
            totalRequests <= 0;
            totalCompletions <= 0;
            for (i = 0; i < NUM_FACES; i++) begin
                faceCredits[i] <= FACE_CREDITS_MAX;
                faceReqReady[i] <= 0;
                faceReqRdata[i] <= 0;
            end
            for (i = 0; i < QUEUE_DEPTH; i++) begin
                requestQueue[i] <= 0;
            end
        end else begin
            faceReqReady <= 0;
            case (state)
                IDLE: begin
                    if (foundRequest && queueCount < QUEUE_DEPTH) begin
                        activeFace <= nextFace;
                        activeWrite <= faceReqWrite[nextFace];
                        faceCredits[nextFace] <= faceCredits[nextFace] - 1;
                        sramReqValid <= 1;
                        sramReqWrite <= faceReqWrite[nextFace];
                        sramReqAddr <= faceReqAddr[nextFace];
                        sramReqWdata <= faceReqWdata[nextFace];
                        pendingFaceId[queueTail] <= nextFace;
                        queueCount <= queueCount + 1;
                        queueTail <= queueTail + 1;
                        lastServedFace <= nextFace;
                        totalRequests <= totalRequests + 1;
                        state <= WAITING;
                    end
                end
                WAITING: begin
                    if (sramReqReady) begin
                        sramReqValid <= 0;
                        faceCredits[activeFace] <= faceCredits[activeFace] + 1;
                        faceReqReady[activeFace] <= 1;
                        if (!activeWrite) begin
                            faceReqRdata[activeFace] <= sramReqRdata;
                        end
                        queueCount <= queueCount - 1;
                        queueHead <= queueHead + 1;
                        totalCompletions <= totalCompletions + 1;
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
`ifdef VERILATOR
    always @(posedge clk) begin
        if (!reset) begin
            if (queueCount > MAX_OUTSTANDING) begin
                $fatal(1, "MEM_SHELL: Queue overflow! count=%d, max=%d",
                       queueCount, MAX_OUTSTANDING);
            end
        end
    end
`endif
endmodule
