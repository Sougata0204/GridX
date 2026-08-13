`default_nettype none
`timescale 1ns/1ns

// my dcr configures device thread count
module dcr (
    input wire clk,
    input wire reset,
    input wire deviceControlWriteEnable,
    input wire [15:0] deviceControlData,
    output wire [15:0] threadCount,
    output wire dcrValid
);
    reg [15:0] deviceControlRegister;
    reg dcrWritten;
    
    assign threadCount = deviceControlRegister;
    assign dcrValid = dcrWritten && (deviceControlRegister > 0);
    
    always @(posedge clk) begin
        if (reset) begin
            deviceControlRegister <= 16'b0;
            dcrWritten <= 0;
        end else begin
            if (deviceControlWriteEnable) begin
                deviceControlRegister <= deviceControlData;
                dcrWritten <= 1;
            end
        end
    end
endmodule
