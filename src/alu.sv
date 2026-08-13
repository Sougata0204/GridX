`default_nettype none
`timescale 1ns/1ns

// my ALU handles basic math
module alu #(
    parameter DataBits = 16
)(
    input wire enable,
    input wire [3:0] arithMux,
    input wire signed [DataBits-1:0] rs,
    input wire signed [DataBits-1:0] rt,
    output reg [DataBits-1:0] aluOut,
    output wire divByZero
);

    localparam OpAdd = 4'b0000;
    localparam OpSub = 4'b0001;
    localparam OpMul = 4'b0010;
    localparam OpDiv = 4'b0011;
    localparam OpCmp = 4'b0100;
    localparam OpAnd = 4'b0101;
    localparam OpOr  = 4'b0110;
    localparam OpXor = 4'b0111;
    localparam OpShl = 4'b1000;
    localparam OpShr = 4'b1001;
    
    reg [DataBits-1:0] rawResult;
    assign divByZero = (arithMux == OpDiv) && (rt == '0) && enable;
    
    always @(*) begin
        rawResult = {DataBits{1'b0}};
        case (arithMux)
            OpAdd: rawResult = rs + rt;
            OpSub: rawResult = rs - rt;
            OpMul: rawResult = rs * rt;
            OpDiv: rawResult = (rt != 0) ? (rs / rt) : {DataBits{1'b1}};
            OpCmp: begin
                rawResult = {{(DataBits-3){1'b0}},
                              (rs < rt),
                              (rs == rt),
                              (rs > rt)};
            end
            OpAnd: rawResult = rs & rt;
            OpOr:  rawResult = rs | rt;
            OpXor: rawResult = rs ^ rt;
            OpShl: rawResult = rs << rt[3:0];
            OpShr: rawResult = ($unsigned(rs)) >> rt[3:0];
            default: rawResult = {DataBits{1'b0}};
        endcase
    end
    
    always @(*) begin
        aluOut = rawResult;
    end
endmodule
