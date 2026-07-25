
`default_nettype none
`timescale 1ns/1ns

module alu #(
    parameter DATA_BITS = 16
)(
    input wire enable,
    input wire [3:0] alu_arith_mux,
    input wire signed [DATA_BITS-1:0] rs,
    input wire signed [DATA_BITS-1:0] rt,
    output reg [DATA_BITS-1:0] alu_out,
    output wire div_by_zero
);
    localparam OP_ADD = 4'b0000;
    localparam OP_SUB = 4'b0001;
    localparam OP_MUL = 4'b0010;
    localparam OP_DIV = 4'b0011;
    localparam OP_CMP = 4'b0100;
    localparam OP_AND = 4'b0101;
    localparam OP_OR  = 4'b0110;
    localparam OP_XOR = 4'b0111;
    localparam OP_SHL = 4'b1000;
    localparam OP_SHR = 4'b1001;
    reg [DATA_BITS-1:0] raw_result;
    assign div_by_zero = (alu_arith_mux == OP_DIV) && (rt == '0) && enable;
    always @(*) begin
        raw_result = {DATA_BITS{1'b0}};
        case (alu_arith_mux)
            OP_ADD: raw_result = rs + rt;
            OP_SUB: raw_result = rs - rt;
            OP_MUL: raw_result = rs * rt;
            OP_DIV: raw_result = (rt != 0) ? (rs / rt) : {DATA_BITS{1'b1}};
            OP_CMP: begin
                raw_result = {{(DATA_BITS-3){1'b0}},
                              (rs < rt),
                              (rs == rt),
                              (rs > rt)};
            end
            OP_AND: raw_result = rs & rt;
            OP_OR:  raw_result = rs | rt;
            OP_XOR: raw_result = rs ^ rt;
            OP_SHL: raw_result = rs << rt[3:0];
            OP_SHR: raw_result = ($unsigned(rs)) >> rt[3:0];
            default: raw_result = {DATA_BITS{1'b0}};
        endcase
    end
    always @(*) begin
        alu_out = raw_result;
    end
endmodule
