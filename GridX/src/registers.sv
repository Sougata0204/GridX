`default_nettype none
`timescale 1ns/1ns

// REGISTER FILE
// > Each thread within each core has it's own register file with 13 free registers and 3 read-only registers
// > Read-only registers hold the familiar %blockIdx, %blockDim, and %threadIdx values critical to SIMD
module registers #(
    parameter THREADS_PER_BLOCK = 4,
    parameter THREAD_ID = 0,
    parameter DATA_BITS = 16
) (
    input wire clk,
    input wire reset,
    input wire enable, // If current block has less threads then block size, some registers will be inactive

    // Kernel Execution
    input reg [7:0] block_id,

    // State
    input reg [2:0] core_state,

    // Instruction Signals
    input reg [3:0] decoded_rd_address,
    input reg [3:0] decoded_rs_address,
    input reg [3:0] decoded_rt_address,

    // Control Signals
    input reg decoded_reg_write_enable,
    input reg [1:0] decoded_reg_input_mux,
    input reg [DATA_BITS-1:0] decoded_immediate,

    // Force Write Interface (Tensor Writeback)
    input wire force_reg_write_enable,
    input wire [3:0] force_reg_write_dest,
    input wire [DATA_BITS-1:0] force_reg_write_data,

    // Thread Unit Outputs
    input reg [DATA_BITS-1:0] alu_out,
    input reg [DATA_BITS-1:0] lsu_out,

    // Registers
    output reg [DATA_BITS-1:0] rs,
    output reg [DATA_BITS-1:0] rt,
    output reg [DATA_BITS-1:0] rd_val // 3rd Read Port
);
    localparam ARITHMETIC = 2'b00,
        MEMORY = 2'b01,
        CONSTANT = 2'b10;

    // 16 registers per thread (13 free registers and 3 read-only registers)
    reg [DATA_BITS-1:0] registers[15:0];

    // Read Ports
    always @(*) begin
        rs = (decoded_rs_address == 4'b0000) ? {DATA_BITS{1'b0}} : registers[decoded_rs_address];
        rt = (decoded_rt_address == 4'b0000) ? {DATA_BITS{1'b0}} : registers[decoded_rt_address];
        rd_val = (decoded_rd_address == 4'b0000) ? {DATA_BITS{1'b0}} : registers[decoded_rd_address];
    end

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            // Initialize all registers to 0
            for (i = 0; i < 16; i = i + 1) begin
                registers[i] <= {DATA_BITS{1'b0}};
            end
            // Read-only initialization (static)
            registers[13] <= {{(DATA_BITS-8){1'b0}}, 8'b0};
            registers[14] <= {{(DATA_BITS-8){1'b0}}, THREADS_PER_BLOCK[7:0]};
            registers[15] <= {{(DATA_BITS-8){1'b0}}, THREAD_ID[7:0]};
        end else if (enable) begin 
            // Update special registers
            registers[13] <= {{(DATA_BITS-8){1'b0}}, block_id}; 

            // Priority Write: Force Write (Tensor)
            if (force_reg_write_enable) begin
                 if (force_reg_write_dest != 4'b0000) begin
                     registers[force_reg_write_dest] <= force_reg_write_data;
                 end
            end 
            // Normal Write
            else if (core_state == 3'b110) begin // UPDATE state
                if (decoded_reg_write_enable && decoded_rd_address < 13 && decoded_rd_address != 0) begin
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
