
`default_nettype none
`timescale 1ns/1ns

module pc #(
    parameter DATA_MEM_DATA_BITS = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 8
)(
    
    input wire clk,
    input wire reset,
    input wire enable,
    input wire [2:0] core_state,
    input wire [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    input wire nzp_we,
    input wire [2:0] decoded_nzp,
    input wire pc_mux,
    input wire [PROGRAM_MEM_ADDR_BITS-1:0] decoded_imm,
    input wire [DATA_MEM_DATA_BITS-1:0] alu_out,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] next_pc
    
); 
    reg [2:0] nzp_reg;
    int pc_val_x_print_count = 0;
    always @(posedge clk) begin
        if (reset) begin
            nzp_reg <= 3'b000;
            next_pc <= 0;
            pc_val_x_print_count <= 0;
        end else if (enable) begin
            if (core_state == 3'b100 || core_state == 3'b011) begin
                if (pc_mux == 1) begin
                    if (((nzp_reg & decoded_nzp) != 3'b0)) begin
                        next_pc <= decoded_imm;
                    end else begin
                        next_pc <= current_pc + 1;
                    end
                end else begin
                    next_pc <= current_pc + 1;
                end
            end
            if (core_state == 3'b110) begin
                if (nzp_we) begin
                    nzp_reg <= alu_out[2:0];
                end
            end
            // synthesis translate_off
            if ($isunknown(next_pc)) begin
                if (pc_val_x_print_count < 20) begin
                    $display("%m [DEBUG_PC_VAL] next_pc is X! current_pc=%h pc_mux=%b core_state=%b enable=%b",
                             current_pc, pc_mux, core_state, enable);
                    pc_val_x_print_count <= pc_val_x_print_count + 1;
                end
            end
            // synthesis translate_on
        end
    end
endmodule
