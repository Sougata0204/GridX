`default_nettype none
`timescale 1ns/1ns

// islip arbitration algorithm to prevent hol blocking
module islipArbiter #(
    parameter PORTS = 5
) (
    input wire clk,
    input wire reset,
    input wire [PORTS-1:0] reqs,
    output reg [PORTS-1:0] grants,
    input wire accept
);

    reg [PORTS-1:0] pointers [PORTS-1:0];
    reg [PORTS-1:0] nextPointers [PORTS-1:0];
    
    integer i, j, k;
    reg [PORTS-1:0] grantTemp;
    
    always @(*) begin
        grantTemp = 0;
        for (i = 0; i < PORTS; i = i + 1) begin
            if (reqs[i]) begin
                // Fixed priority based on pointer
                for (j = 0; j < PORTS; j = j + 1) begin
                    if (!grantTemp && ((1 << ((pointers[i] + j) % PORTS)) & reqs) != 0) begin
                        if (((pointers[i] + j) % PORTS) == i) begin
                            grantTemp[i] = 1'b1;
                        end
                    end
                end
            end
        end
        grants = grantTemp;
    end
    
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < PORTS; i = i + 1) begin
                pointers[i] <= i;
            end
        end else if (accept && grants != 0) begin
            for (i = 0; i < PORTS; i = i + 1) begin
                if (grants[i]) begin
                    pointers[i] <= (pointers[i] + 1) % PORTS;
                end
            end
        end
    end

endmodule
