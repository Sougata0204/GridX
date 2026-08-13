`default_nettype none
`timescale 1ns/1ns

// my lsu handles memory accesses
module lsu #(
    parameter AddrBits = 16,
    parameter MemDataWidth = 8,
    parameter RegWidth = 16
) (
    input wire clk,
    input wire reset,
    input wire enable,
    input wire [2:0] coreState,
    input wire decodedMemReadEnable,
    input wire decodedMemWriteEnable,
    input wire [RegWidth-1:0] rs,
    input wire [RegWidth-1:0] rt,
    output reg memReadValid,
    output reg [AddrBits-1:0] memReadAddress,
    input wire memReadReady,
    input wire [MemDataWidth-1:0] memReadData,
    output wire memWriteValid,
    output wire [AddrBits-1:0] memWriteAddress,
    output wire [MemDataWidth-1:0] memWriteData,
    input wire memWriteReady,
    output reg [1:0] lsuStateOut,
    output reg [RegWidth-1:0] lsuOut,
    output wire lsuPending,
    input wire isLocal
);
    localparam Idle = 3'b000;
    localparam Requesting = 3'b001;
    localparam Waiting = 3'b010;
    localparam Done = 3'b011;
    localparam LocalAccess = 3'b100;
    
    reg [2:0] state;
    assign lsuStateOut = state[1:0];
    
    localparam CoreRequest = 3'b011;
    localparam CoreUpdate = 3'b110;
    assign lsuPending = (state != Idle && state != Done);
    
    localparam AddrPad = (AddrBits > RegWidth) ? (AddrBits - RegWidth) : 0;
    wire [AddrBits-1:0] rsAddr;
    generate
        if (AddrPad > 0) begin : genPad
            assign rsAddr = {{AddrPad{1'b0}}, rs};
        end else begin : genNoPad
            assign rsAddr = rs[AddrBits-1:0];
        end
    endgenerate
    
    reg isWriteOp;
    reg memWriteValidInternal;
    reg [AddrBits-1:0] memWriteAddressInternal;
    reg [MemDataWidth-1:0] memWriteDataInternal;
    wire memWriteReadyInternal;
    wire sbCheckHazard;
    
    storeBuffer #(
        .AddrWidth(AddrBits),
        .DataWidth(MemDataWidth),
        .BufferDepth(8)
    ) sbInst (
        .clk(clk),
        .reset(reset),
        .coreReqValid(memWriteValidInternal),
        .coreReqWrite(1'b1),
        .coreReqAddr(memWriteAddressInternal),
        .coreReqData(memWriteDataInternal),
        .coreReqReady(memWriteReadyInternal),
        .memReqValid(memWriteValid),
        .memReqWrite(),
        .memReqAddr(memWriteAddress),
        .memReqData(memWriteData),
        .memReqReady(memWriteReady),
        .checkValid(memReadValid),
        .checkAddr(memReadAddress),
        .checkHazard(sbCheckHazard)
    );
    
    always @(posedge clk) begin
        if (reset) begin
            state <= Idle;
            lsuOut <= 0;
            memReadValid <= 0;
            memReadAddress <= 0;
            memWriteValidInternal <= 0;
            memWriteAddressInternal <= 0;
            memWriteDataInternal <= 0;
            isWriteOp <= 0;
        end else if (enable) begin
            case (state)
                Idle: begin
                    if (coreState == CoreRequest) begin
                        if (decodedMemReadEnable) begin
                            state <= isLocal ? LocalAccess : Requesting;
                            isWriteOp <= 0;
                            memReadAddress <= rsAddr;
                        end else if (decodedMemWriteEnable) begin
                            state <= isLocal ? LocalAccess : Requesting;
                            isWriteOp <= 1;
                            memWriteAddressInternal <= rsAddr;
                            memWriteDataInternal <= rt[MemDataWidth-1:0];
                        end
                    end
                end
                Requesting: begin
                    if (!isWriteOp) begin
                        memReadValid <= 1;
                        if (memReadReady && !sbCheckHazard) begin
                            memReadValid <= 0;
                            lsuOut <= {{(RegWidth-MemDataWidth){1'b0}}, memReadData};
                            state <= Done;
                        end else begin
                            state <= Waiting;
                        end
                    end else begin
                        memWriteValidInternal <= 1;
                        state <= Waiting;
                    end
                end
                LocalAccess: begin
                    if (!isWriteOp) begin
                        memReadValid <= 1;
                        if (memReadReady && !sbCheckHazard) begin
                            memReadValid <= 0;
                            lsuOut <= {{(RegWidth-MemDataWidth){1'b0}}, memReadData};
                            state <= Done;
                        end
                    end else begin
                        memWriteValidInternal <= 1;
                        if (memWriteReadyInternal) begin
                            memWriteValidInternal <= 0;
                            state <= Done;
                        end
                    end
                end
                Waiting: begin
                    if (!isWriteOp) begin
                        memReadValid <= 1;
                        if (memReadReady && !sbCheckHazard) begin
                            memReadValid <= 0;
                            lsuOut <= {{(RegWidth-MemDataWidth){1'b0}}, memReadData};
                            state <= Done;
                        end
                    end else begin
                        memWriteValidInternal <= 1;
                        if (memWriteReadyInternal) begin
                            memWriteValidInternal <= 0;
                            state <= Done;
                        end
                    end
                end
                Done: begin
                    if (coreState == CoreUpdate) begin
                        state <= Idle;
                    end
                end
            endcase
        end
    end
endmodule
