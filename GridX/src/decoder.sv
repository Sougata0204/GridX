`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION DECODER
// > Decodes an instruction into a unified Control Packet (Instruction Spine)
// > Output: [63:0] decoded_packet
module decoder (
    input wire clk,
    input wire reset,

    input reg [2:0] core_state,
    input reg [15:0] instruction,
    
    // Control Signals (Packetized)
    output reg [63:0] decoded_packet
);
    // Packet Layout (64 bits)
    // [15:0] Immediate (Sign Extended)
    // [19:16] Rt
    // [23:20] Rs
    // [27:24] Rd
    // [30:28] NZP
    // [31]    Reg Write Enable
    // [32]    Mem Read Enable
    // [33]    Mem Write Enable
    // [34]    NZP Write Enable
    // [36:35] Reg Input Mux
    // [38:37] ALU Arith Mux
    // [39]    ALU Output Mux
    // [40]    PC Mux
    // [41]    Ret
    // [42]    Tensor Op
    // [46:43] Opcode
    // [63:47] Reserved/Zero

    localparam NOP = 4'b0000,
        BRnzp = 4'b0001,
        CMP = 4'b0010,
        ADD = 4'b0011,
        SUB = 4'b0100,
        MUL = 4'b0101,
        DIV = 4'b0110,
        LDR = 4'b0111,
        STR = 4'b1000,
        CONST = 4'b1001,
        TILE_LD = 4'b1010,      
        TILE_ST = 4'b1011,      
        DMA_SYNC = 4'b1100,     
        TILE_FENCE = 4'b1101,   
        TENSOR_MMA = 4'b1110,   
        RET = 4'b1111;

    // Internal Temps for Clarity
    reg [3:0] i_rd, i_rs, i_rt;
    reg [2:0] i_nzp;
    reg [15:0] i_imm;
    reg [3:0] i_opcode;
    
    // Control Flags
    reg c_reg_we, c_mem_re, c_mem_we, c_nzp_we;
    reg [1:0] c_reg_mux, c_alu_arith_mux;
    reg c_alu_out_mux, c_pc_mux, c_ret, c_tensor;

    always @(*) begin
        // Pack the packet
        decoded_packet = {
            17'b0,                  // [63:47]
            i_opcode,               // [46:43]
            c_tensor,               // [42]
            c_ret,                  // [41]
            c_pc_mux,               // [40]
            c_alu_out_mux,          // [39]
            c_alu_arith_mux,        // [38:37]
            c_reg_mux,              // [36:35]
            c_nzp_we,               // [34]
            c_mem_we,               // [33]
            c_mem_re,               // [32]
            c_reg_we,               // [31]
            i_nzp,                  // [30:28]
            i_rd,                   // [27:24]
            i_rs,                   // [23:20]
            i_rt,                   // [19:16]
            i_imm                   // [15:0]
        };
    end

    always @(posedge clk) begin 
        if (reset) begin 
            i_rd <= 0; i_rs <= 0; i_rt <= 0; i_imm <= 0; i_nzp <= 0; i_opcode <= 0;
            c_reg_we <= 0; c_mem_re <= 0; c_mem_we <= 0; c_nzp_we <= 0;
            c_reg_mux <= 0; c_alu_arith_mux <= 0; c_alu_out_mux <= 0;
            c_pc_mux <= 0; c_ret <= 0; c_tensor <= 0;
        end else begin 
            // Decode when core_state = DECODE
            if (core_state == 3'b010) begin 
                // Parse Instruction Fields
                i_opcode <= instruction[15:12];
                i_rd <= instruction[11:8];
                i_rs <= instruction[7:4];
                i_rt <= instruction[3:0];
                i_nzp <= instruction[11:9];
                // Sign Extend Immediate (8 -> 16)
                i_imm <= {{8{instruction[7]}}, instruction[7:0]};

                // Reset Control Flags
                c_reg_we <= 0; c_mem_re <= 0; c_mem_we <= 0; c_nzp_we <= 0;
                c_reg_mux <= 0; c_alu_arith_mux <= 0; c_alu_out_mux <= 0;
                c_pc_mux <= 0; c_ret <= 0; c_tensor <= 0;

                // Decode Opcode
                case (instruction[15:12])
                    // NOP: Default 0
                    BRnzp: begin 
                        c_pc_mux <= 1;
                    end
                    CMP: begin 
                        c_alu_out_mux <= 1;
                        c_nzp_we <= 1;
                    end
                    ADD: begin 
                        c_reg_we <= 1; c_reg_mux <= 2'b00; c_alu_arith_mux <= 2'b00;
                    end
                    SUB: begin 
                        c_reg_we <= 1; c_reg_mux <= 2'b00; c_alu_arith_mux <= 2'b01;
                    end
                    MUL: begin 
                        c_reg_we <= 1; c_reg_mux <= 2'b00; c_alu_arith_mux <= 2'b10;
                    end
                    DIV: begin 
                        c_reg_we <= 1; c_reg_mux <= 2'b00; c_alu_arith_mux <= 2'b11;
                    end
                    LDR, TILE_LD: begin 
                        c_reg_we <= 1; c_reg_mux <= 2'b01; c_mem_re <= 1;
                    end
                    STR, TILE_ST: begin 
                        c_mem_we <= 1;
                    end
                    CONST: begin 
                        c_reg_we <= 1; c_reg_mux <= 2'b10;
                    end
                    TENSOR_MMA: begin
                        c_tensor <= 1;
                    end
                    RET: begin 
                        c_ret <= 1;
                    end
                endcase
            end
        end
    end
endmodule
