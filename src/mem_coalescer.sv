
`default_nettype none
`timescale 1ns/1ns

module memCoalescer #(
    parameter THREADS_PER_WARP = 4,
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8,
    parameter CACHE_LINE_SIZE = 32,
    parameter LINE_ADDR_BITS = ADDR_WIDTH - $clog2(CACHE_LINE_SIZE)
) (
    input  wire clk,
    input  wire reset,
    input  wire [THREADS_PER_WARP-1:0] reqValid,
    input  wire [THREADS_PER_WARP-1:0] reqWrite,
    input  wire [ADDR_WIDTH-1:0] reqAddr [THREADS_PER_WARP-1:0],
    input  wire [DATA_WIDTH-1:0] reqWdata [THREADS_PER_WARP-1:0],
    output wire [THREADS_PER_WARP-1:0] reqReady,
    output reg  [DATA_WIDTH-1:0] reqRdata [THREADS_PER_WARP-1:0],
    output reg  coalValid,
    output reg  coalWrite,
    output reg  [ADDR_WIDTH-1:0] coalAddr,
    output reg  [CACHE_LINE_SIZE*8-1:0] coalWdata,
    output reg  [CACHE_LINE_SIZE-1:0] coalWmask,
    input  wire coalReady,
    input  wire [CACHE_LINE_SIZE*8-1:0] coalRdata,
    output wire coalescerBusy,
    output reg  [31:0] totalRequests,
    output reg  [31:0] coalescedTransactions,
    output reg  [15:0] coalesceRatio
);
    localparam OFFSET_BITS = $clog2(CACHE_LINE_SIZE);
    localparam IDLE = 2'b00;
    localparam COALESCING = 2'b01;
    localparam WAITING = 2'b10;
    localparam DISTRIBUTING = 2'b11;
    reg [1:0] state;
    wire [LINE_ADDR_BITS-1:0] threadLine [THREADS_PER_WARP-1:0];
    wire [OFFSET_BITS-1:0] threadOffset [THREADS_PER_WARP-1:0];
    genvar t;
    generate
        for (t = 0; t < THREADS_PER_WARP; t++) begin : addrDecode
            assign threadLine[t] = reqAddr[t][ADDR_WIDTH-1:OFFSET_BITS];
            assign threadOffset[t] = reqAddr[t][OFFSET_BITS-1:0];
        end
    endgenerate
    reg [LINE_ADDR_BITS-1:0] primaryLine;
    reg foundPrimary;
    reg [THREADS_PER_WARP-1:0] sameLineMask;
    always @(*) begin
        foundPrimary = 0;
        primaryLine = 0;
        sameLineMask = 0;
        for (int i = 0; i < THREADS_PER_WARP; i++) begin
            if (reqValid[i] && !foundPrimary) begin
                primaryLine = threadLine[i];
                foundPrimary = 1;
            end
        end
        for (int i = 0; i < THREADS_PER_WARP; i++) begin
            if (reqValid[i] && (threadLine[i] == primaryLine)) begin
                sameLineMask[i] = 1;
            end
        end
    end

    function automatic int countBits;
        input [THREADS_PER_WARP-1:0] vec;
        int cnt;
        begin
            cnt = 0;
            for (int i = 0; i < THREADS_PER_WARP; i++) begin
                if (vec[i]) cnt = cnt + 1;
            end
            countBits = cnt;
        end
    endfunction
    reg [THREADS_PER_WARP-1:0] pending;
    reg [THREADS_PER_WARP-1:0] currentBatch;
    assign coalescerBusy = (state != IDLE) || (|pending);
    assign reqReady = (state == IDLE) ? {THREADS_PER_WARP{1'b1}} : {THREADS_PER_WARP{1'b0}};
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            pending <= 0;
            currentBatch <= 0;
            coalValid <= 0;
            coalWrite <= 0;
            coalAddr <= 0;
            coalWdata <= 0;
            coalWmask <= 0;
            totalRequests <= 0;
            coalescedTransactions <= 0;
            coalesceRatio <= 0;
            for (i = 0; i < THREADS_PER_WARP; i++) begin
                reqRdata[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (|reqValid) begin
                        pending <= reqValid;
                        totalRequests <= totalRequests + countBits(reqValid);
                        state <= COALESCING;
                    end
                end
                COALESCING: begin
                    if (|pending) begin
                        currentBatch <= pending & sameLineMask;
                        coalValid <= 1;
                        coalWrite <= reqWrite[0];
                        coalAddr <= {primaryLine, {OFFSET_BITS{1'b0}}};
                        coalWmask <= 0;
                        coalWdata <= 0;
                        for (i = 0; i < THREADS_PER_WARP; i++) begin
                            if (pending[i] && sameLineMask[i]) begin
                                coalWmask[threadOffset[i]] <= 1;
                                coalWdata[threadOffset[i]*8 +: 8] <= reqWdata[i];
                            end
                        end
                        coalescedTransactions <= coalescedTransactions + 1;
                        state <= WAITING;
                    end else begin
                        state <= IDLE;
                    end
                end
                WAITING: begin
                    if (coalReady) begin
                        coalValid <= 0;
                        for (i = 0; i < THREADS_PER_WARP; i++) begin
                            if (currentBatch[i]) begin
                                reqRdata[i] <= coalRdata[threadOffset[i]*8 +: 8];
                            end
                        end
                        pending <= pending & ~currentBatch;
                        if (|(pending & ~currentBatch)) begin
                            state <= COALESCING;
                        end else begin
                            state <= IDLE;
                            if (coalescedTransactions > 0) begin
                                coalesceRatio <= (totalRequests << 8) / coalescedTransactions;
                            end
                        end
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
