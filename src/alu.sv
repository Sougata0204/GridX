
`default_nettype none
`timescale 1ns/1ps

// SIMT execution datapath ALU handling 16-bit integer arithmetic, logic, shifts, comparisons, and fast power-of-two division bypass.
module alu #(
    parameter DataBits = 16
)(
    input  wire                  enable,
    input  wire [3:0]            arithMux,
    input  wire signed [DataBits-1:0] rs,
    input  wire signed [DataBits-1:0] rt,
    output reg  [DataBits-1:0]   aluOut,
    output wire                  divByZero
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

    assign divByZero = (arithMux == OpDiv) && (rt == '0) && enable;

    function automatic logic is_power_of_two(input logic [DataBits-1:0] val);
        is_power_of_two = (val > 0) && ((val & (val - 1'b1)) == '0);
    endfunction

    function automatic logic [3:0] get_log2(input logic [DataBits-1:0] val);
        integer k;
        logic [3:0] shift;
        begin
            shift = 4'd0;
            for (k = 0; k < DataBits; k = k + 1) begin
                if (val[k]) shift = k[3:0];
            end
            get_log2 = shift;
        end
    endfunction

    always_comb begin
        aluOut = {DataBits{1'b0}};
        case (arithMux)
            OpAdd: aluOut = rs + rt;
            OpSub: aluOut = rs - rt;
            OpMul: aluOut = rs * rt;
            OpDiv: begin
                if (rt == '0) begin
                    aluOut = {DataBits{1'b1}};
                end else if (rs == '0) begin
                    aluOut = {DataBits{1'b0}};
                end else if (rt == 1) begin
                    aluOut = rs;
                end else if (is_power_of_two(rt) && (rs >= 0)) begin
                    aluOut = rs >> get_log2(rt);
                end else begin
                    aluOut = rs / rt;
                end
            end
            OpCmp: begin
                aluOut = {{(DataBits-3){1'b0}},
                          (rs < rt),
                          (rs == rt),
                          (rs > rt)};
            end
            OpAnd: aluOut = rs & rt;
            OpOr:  aluOut = rs | rt;
            OpXor: aluOut = rs ^ rt;
            OpShl: aluOut = rs << rt[3:0];
            OpShr: aluOut = ($unsigned(rs)) >> rt[3:0];
            default: aluOut = {DataBits{1'b0}};
        endcase
    end

`ifndef SYNTHESIS
    always @(posedge divByZero) begin
        $display("[ALU_WARN] Thread encountered division by zero at time %0t ps! rs=%0d, rt=%0d", $time, rs, rt);
    end
`endif

endmodule
