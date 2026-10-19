`default_nettype none
`timescale 1ns/1ns

// Instruction fetcher reading program memory with PC-based addressing and providing instructions to the decode stage.
module fetcher #(
    parameter ProgMemAddrBits = 8,
    parameter ProgMemDataBits = 16
) (
    input wire clk,
    input wire reset,
    input wire [2:0] coreState,
    input wire [ProgMemAddrBits-1:0] currentPc,
    output logic                          memReadValid,
    output logic [ProgMemAddrBits-1:0]     memReadAddress,
    input wire                             memReadReady,
    input wire [ProgMemDataBits-1:0]       memReadData,
    output logic [2:0]                     fetcherState,
    output logic [ProgMemDataBits-1:0]     instruction
);
    localparam Idle = 3'b000,
        Fetching = 3'b001,
        Fetched = 3'b010;

    localparam CORE_FETCH  = 3'b001;
    localparam CORE_DECODE = 3'b010;
        
    always @(posedge clk) begin
        if (reset) begin
            fetcherState <= Idle;
            memReadValid <= 0;
            memReadAddress <= 0;
            instruction <= {ProgMemDataBits{1'b0}};
        end else begin
            case (fetcherState)
                Idle: begin
                    if (coreState == CORE_FETCH) begin
                        fetcherState <= Fetching;
                        memReadValid <= 1;
                        memReadAddress <= currentPc;
                    end
                end
                Fetching: begin
                    if (memReadReady) begin
                        `ifdef GRIDX_DEBUG
                        $display("[%0t] FETCHER: Fetched instruction %x from PC %x", $time, memReadData, memReadAddress);
                        `endif
                        fetcherState <= Fetched;
                        instruction <= memReadData;
                        memReadValid <= 0;
                    end
                end
                Fetched: begin
                    if (coreState == CORE_DECODE) begin
                        fetcherState <= Idle;
                    end
                end
            endcase
        end
    end
endmodule
