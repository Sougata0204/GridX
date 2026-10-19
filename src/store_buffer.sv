`default_nettype none
`timescale 1ns/1ns

// Store buffer holding committed store data until it can be written to cache or memory in program order.
module storeBuffer #(
    parameter AddrWidth = 16,
    parameter DataWidth = 8,
    parameter BufferDepth = 8
) (
    input wire clk,
    input wire reset,
    
    input wire coreReqValid,
    input wire coreReqWrite,
    input wire [AddrWidth-1:0] coreReqAddr,
    input wire [DataWidth-1:0] coreReqData,
    output wire coreReqReady,
    
    output wire memReqValid,
    output wire memReqWrite,
    output wire [AddrWidth-1:0] memReqAddr,
    output wire [DataWidth-1:0] memReqData,
    input wire memReqReady,
    
    input wire checkValid,
    input wire [AddrWidth-1:0] checkAddr,
    output wire checkHazard
);

    reg [AddrWidth-1:0] addrArray [BufferDepth-1:0];
    reg [DataWidth-1:0] dataArray [BufferDepth-1:0];
    reg [BufferDepth-1:0] validArray;
    
    reg [$clog2(BufferDepth)-1:0] head;
    reg [$clog2(BufferDepth)-1:0] tail;
    reg [$clog2(BufferDepth):0] count;
    
    assign coreReqReady = (count < BufferDepth);
    assign memReqValid = (count > 0);
    
    assign memReqWrite = 1'b1;
    assign memReqAddr = addrArray[head];
    assign memReqData = dataArray[head];
    
    always @(posedge clk) begin
        if (reset) begin
            head <= 0;
            tail <= 0;
            count <= 0;
            validArray <= 0;
        end else begin
            if (coreReqValid && coreReqWrite && coreReqReady) begin
                addrArray[tail] <= coreReqAddr;
                dataArray[tail] <= coreReqData;
                validArray[tail] <= 1'b1;
            end
            
            if (memReqValid && memReqReady) begin
                validArray[head] <= 1'b0;
            end
            
            if (coreReqValid && coreReqWrite && coreReqReady && !(memReqValid && memReqReady)) begin
                count <= count + 1;
                tail <= (tail == BufferDepth - 1) ? '0 : tail + 1;
            end else if (!(coreReqValid && coreReqWrite && coreReqReady) && memReqValid && memReqReady) begin
                count <= count - 1;
                head <= (head == BufferDepth - 1) ? '0 : head + 1;
            end else if (coreReqValid && coreReqWrite && coreReqReady && memReqValid && memReqReady) begin
                tail <= (tail == BufferDepth - 1) ? '0 : tail + 1;
                head <= (head == BufferDepth - 1) ? '0 : head + 1;
            end
        end
    end

    reg hazardDetected;
    integer i;
    always_comb begin
        hazardDetected = 1'b0;
        if (checkValid) begin
            for (i = 0; i < BufferDepth; i = i + 1) begin
                if (validArray[i] && addrArray[i] == checkAddr) begin
                    hazardDetected = 1'b1;
                end
            end
        end
    end
    assign checkHazard = hazardDetected;

endmodule
