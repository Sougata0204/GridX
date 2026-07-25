// Instruction Decoder
// Decodes 16-bit ISA opcode packets into control signals for ALU, LSU, and register files.


`default_nettype none
`timescale 1ns/1ns
import gridx_pkg::*;

module decoder (
    input wire [2:0] core_state,
    input wire [15:0] instruction,
    output wire [63:0] decoded_packet
);
    localparam NOP = OP_NOP,
        BRnzp = OP_BRnzp,
        CMP = OP_CMP,
        ADD = OP_ADD,
        SUB = OP_SUB,
        MUL = OP_MUL,
        DIV = OP_DIV,
        LDR = OP_LDR,
        STR = OP_STR,
        CONST = OP_CONST,
        TILE_LD = OP_TILE_LD,
        TILE_ST = OP_TILE_ST,
        DMA_SYNC = OP_DMA_SYNC,
        BAR = OP_BAR,
        RET = OP_RET;
    reg [3:0] i_rd, i_rs, i_rt;
    reg [2:0] i_nzp;
    reg [15:0] i_imm;
    reg [3:0] i_opcode;
    reg c_reg_we, c_mem_re, c_mem_we, c_nzp_we;
    reg [1:0] c_reg_mux;
    reg [3:0] c_alu_arith_mux;
    reg c_pc_mux, c_ret, c_tensor, c_bar, c_simt_sync;
    localparam ALU_ADD = 4'b0000;
    localparam ALU_SUB = 4'b0001;
    localparam ALU_MUL = 4'b0010;
    localparam ALU_DIV = 4'b0011;
    localparam ALU_CMP = 4'b0100;
    always @(*) begin
        i_opcode = instruction[15:12];
        i_rd     = instruction[11:8];
        i_rs     = instruction[7:4];
        i_rt     = instruction[3:0];
        i_nzp    = instruction[11:9];
        i_imm    = {{8{instruction[7]}}, instruction[7:0]};
        c_reg_we = 0; c_mem_re = 0; c_mem_we = 0; c_nzp_we = 0;
        c_reg_mux = 2'b00; c_alu_arith_mux = ALU_ADD;
        c_pc_mux = 0; c_ret = 0; c_tensor = 0; c_bar = 0; c_simt_sync = 0;
        case (instruction[15:12])
            BRnzp: begin
                c_pc_mux = 1;
            end
            CMP: begin
                c_alu_arith_mux = ALU_CMP;
                c_nzp_we = 1;
            end
            ADD: begin
                c_reg_we = 1; c_reg_mux = 2'b00; c_alu_arith_mux = ALU_ADD;
            end
            SUB: begin
                c_reg_we = 1; c_reg_mux = 2'b00; c_alu_arith_mux = ALU_SUB;
            end
            MUL: begin
                c_reg_we = 1; c_reg_mux = 2'b00; c_alu_arith_mux = ALU_MUL;
            end
            DIV: begin
                c_reg_we = 1; c_reg_mux = 2'b00; c_alu_arith_mux = ALU_DIV;
            end
            LDR, TILE_LD: begin
                c_reg_we = 1; c_reg_mux = 2'b01; c_mem_re = 1;
            end
            STR, TILE_ST: begin
                c_mem_we = 1;
            end
            CONST: begin
                c_reg_we = 1; c_reg_mux = 2'b10;
            end
            OP_TENSOR_MMA: begin
                c_tensor = 1;
            end
            OP_BAR: begin
                if (instruction[0] == 1'b1) begin
                    c_simt_sync = 1;
                end else begin
                    c_bar = 1;
                end
            end
            RET: begin
                c_ret = 1;
            end
            default: begin  end
        endcase
    end
    assign decoded_packet = {
        14'b0,
        c_simt_sync,
        c_bar,
        i_opcode,
        c_tensor,
        c_ret,
        c_pc_mux,
        c_alu_arith_mux,
        c_reg_mux,
        c_nzp_we,
        c_mem_we,
        c_mem_re,
        c_reg_we,
        i_nzp,
        i_rd,
        i_rs,
        i_rt,
        i_imm
    };
endmodule
