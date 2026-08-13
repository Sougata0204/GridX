`default_nettype none
`timescale 1ns/1ns

// my stor buffer to fix raw/waw hazzards for memory consistency 
module storeBuffer #(
    parameter AddrWidth = 16,
    parameter DataWidth = 8,
    parameter BufferDepth = 8
) (
    input wire clk,
    input wire reset,
    
    // Core interface
    input wire coreReqValid,
    input wire coreReqWrite,
    input wire [AddrWidth-1:0] coreReqAddr,
    input wire [DataWidth-1:0] coreReqData,
    output wire coreReqReady,
    
    // Memory/LSU interface
    output wire memReqValid,
    output wire memReqWrite,
    output wire [AddrWidth-1:0] memReqAddr,
    output wire [DataWidth-1:0] memReqData,
    input wire memReqReady,
    
    // RAW Hazard check
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
    
    // Pop from head to memory
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
            // Push
            if (coreReqValid && coreReqWrite && coreReqReady) begin
                addrArray[tail] <= coreReqAddr;
                dataArray[tail] <= coreReqData;
                validArray[tail] <= 1'b1;
            end
            
            // Pop
            if (memReqValid && memReqReady) begin
                validArray[head] <= 1'b0;
            end
            
            // Count update
            if (coreReqValid && coreReqWrite && coreReqReady && !(memReqValid && memReqReady)) begin
                count <= count + 1;
                tail <= (tail + 1) % BufferDepth;
            end else if (!(coreReqValid && coreReqWrite && coreReqReady) && memReqValid && memReqReady) begin
                count <= count - 1;
                head <= (head + 1) % BufferDepth;
            end else if (coreReqValid && coreReqWrite && coreReqReady && memReqValid && memReqReady) begin
                tail <= (tail + 1) % BufferDepth;
                head <= (head + 1) % BufferDepth;
            end
        end
    end

    // RAW hazard detection
    reg hazardDetected;
    integer i;
    always @(*) begin
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
