`default_nettype none
`timescale 1ns/1ns

// my fetcher gets the next instruction from memory
module fetcher #(
    parameter ProgMemAddrBits = 8,
    parameter ProgMemDataBits = 16
) (
    input wire clk,
    input wire reset,
    input wire [2:0] coreState,
    input wire [ProgMemAddrBits-1:0] currentPc,
    output reg memReadValid,
    output reg [ProgMemAddrBits-1:0] memReadAddress,
    input wire memReadReady,
    input wire [ProgMemDataBits-1:0] memReadData,
    output reg [2:0] fetcherState,
    output reg [ProgMemDataBits-1:0] instruction
);
    localparam Idle = 3'b000,
        Fetching = 3'b001,
        Fetched = 3'b010;
        
    always @(posedge clk) begin
        // rset condtion to clr out old state 
        if (reset) begin
            fetcherState <= Idle;
            memReadValid <= 0;
            memReadAddress <= 0;
            instruction <= {ProgMemDataBits{1'b0}};
        end else begin
            case (fetcherState)
                Idle: begin
                    if (coreState == 3'b001) begin
                        fetcherState <= Fetching;
                        memReadValid <= 1;
                        memReadAddress <= currentPc;
                    end
                end
                Fetching: begin
                    if (memReadReady) begin
                        fetcherState <= Fetched;
                        instruction <= memReadData;
                        memReadValid <= 0;
                    end
                end
                Fetched: begin
                    if (coreState == 3'b010) begin
                        fetcherState <= Idle;
                    end
                end
            endcase
        end
    end
endmodule
