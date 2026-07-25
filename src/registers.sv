// Thread Register File & Identity Registers
// Provides per-thread working registers (r1-r12) and hardwired identity registers (r0=0, r13=block_id, r14=TPB, r15=thread_id).


`default_nettype none
`timescale 1ns/1ns

module registers #(
    parameter THREADS_PER_BLOCK = 4,
    parameter THREAD_ID = 0,
    parameter DATA_BITS = 16
) (
    input wire clk,
    input wire reset,
    input wire enable,
    input reg [7:0] block_id,
    input reg [2:0] core_state,
    input reg [3:0] decoded_rd_address,
    input reg [3:0] decoded_rs_address,
    input reg [3:0] decoded_rt_address,
    input reg decoded_reg_write_enable,
    input reg [1:0] decoded_reg_input_mux,
    input reg [DATA_BITS-1:0] decoded_immediate,
    input wire force_reg_write_enable,
    input wire [3:0] force_reg_write_dest,
    input wire [DATA_BITS-1:0] force_reg_write_data,
    input reg [DATA_BITS-1:0] alu_out,
    input reg [DATA_BITS-1:0] lsu_out,
    output reg [DATA_BITS-1:0] rs,
    output reg [DATA_BITS-1:0] rt,
    output reg [DATA_BITS-1:0] rd_val
);
    localparam ARITHMETIC = 2'b00,
        MEMORY = 2'b01,
        CONSTANT = 2'b10;
    reg [DATA_BITS-1:0] registers[15:0];
    always @(*) begin
        rs = (decoded_rs_address == 4'b0000) ? {DATA_BITS{1'b0}} : registers[decoded_rs_address];
        rt = (decoded_rt_address == 4'b0000) ? {DATA_BITS{1'b0}} : registers[decoded_rt_address];
        rd_val = (decoded_rd_address == 4'b0000) ? {DATA_BITS{1'b0}} : registers[decoded_rd_address];
    end
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 16; i = i + 1) begin
                registers[i] <= {DATA_BITS{1'b0}};
            end
            registers[13] <= {{(DATA_BITS-8){1'b0}}, 8'b0};
            registers[14] <= {{(DATA_BITS-8){1'b0}}, THREADS_PER_BLOCK[7:0]};
            registers[15] <= {{(DATA_BITS-8){1'b0}}, THREAD_ID[7:0]};
        end else if (enable) begin
            registers[13] <= {{(DATA_BITS-8){1'b0}}, block_id};
            if (force_reg_write_enable) begin
                 if (force_reg_write_dest != 4'b0000) begin
                     registers[force_reg_write_dest] <= force_reg_write_data;
                 end
            end
            else if (core_state == 3'b110) begin
                if (decoded_reg_write_enable && decoded_rd_address < 13 && decoded_rd_address != 0) begin
                    $display("[REG_WRITE] Cycle %d: Thread %d: Writing reg %d with %h (mux=%d, alu=%h, lsu=%h, imm=%h)",
                     $time, THREAD_ID, decoded_rd_address,
                             (decoded_reg_input_mux == 2'b00) ? alu_out :
                             (decoded_reg_input_mux == 2'b01) ? lsu_out : decoded_immediate,
                             decoded_reg_input_mux, alu_out, lsu_out, decoded_immediate);
                    case (decoded_reg_input_mux)
                        ARITHMETIC: begin
                            registers[decoded_rd_address] <= alu_out;
                        end
                        MEMORY: begin
                            registers[decoded_rd_address] <= lsu_out;
                        end
                        CONSTANT: begin
                            registers[decoded_rd_address] <= decoded_immediate;
                        end
                    endcase
                end
            end
        end
    end
endmodule
