`default_nettype none
`timescale 1ns/1ns

// LOAD-STORE UNIT
module lsu #(
    parameter ADDR_BITS = 16,
    parameter MEM_DATA_WIDTH = 8,
    parameter REG_WIDTH = 16
) (
    input wire clk,
    input wire reset,
    input wire enable, // If current block has less threads then block size, some LSUs will be inactive

    // State
    input reg [2:0] core_state,

    // Memory Control Sgiansl
    input reg decoded_mem_read_enable,
    input reg decoded_mem_write_enable,

    // Registers
    input wire [REG_WIDTH-1:0] rs, // Address Source (Full width)
    input wire [REG_WIDTH-1:0] rt, // Data Source (Full width, truncated for mem write)

    // Data Memory
    output reg mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_address,
    input reg mem_read_ready,
    input reg [MEM_DATA_WIDTH-1:0] mem_read_data,
    output reg mem_write_valid,
    output reg [ADDR_BITS-1:0] mem_write_address,
    output reg [MEM_DATA_WIDTH-1:0] mem_write_data,
    input reg mem_write_ready,

    // LSU Outputs
    output reg [1:0] lsu_state,
    output reg [REG_WIDTH-1:0] lsu_out
);
    localparam IDLE = 2'b00, REQUESTING = 2'b01, WAITING = 2'b10, DONE = 2'b11;

    always @(posedge clk) begin
        if (reset) begin
            lsu_state <= IDLE;
            lsu_out <= 0;
            mem_read_valid <= 0;
            mem_read_address <= 0;
            mem_write_valid <= 0;
            mem_write_address <= 0;
            mem_write_data <= 0;
        end else if (enable) begin
            // If memory read enable is triggered (LDR instruction)
            if (decoded_mem_read_enable) begin 
                case (lsu_state)
                    IDLE: begin
                        // Only read when core_state = REQUEST
                        if (core_state == 3'b011) begin 
                            lsu_state <= REQUESTING;
                        end
                    end
                    REQUESTING: begin 
                        mem_read_valid <= 1;
                        mem_read_address <= rs;
                        if (mem_read_ready) begin
                            mem_read_valid <= 0;
                            lsu_out <= {{(REG_WIDTH-MEM_DATA_WIDTH){1'b0}}, mem_read_data}; // Zero Extend
                            lsu_state <= DONE;
                        end else begin
                            lsu_state <= WAITING;
                        end
                    end
                    WAITING: begin
                        if (mem_read_ready == 1) begin
                            mem_read_valid <= 0;
                            lsu_out <= {{(REG_WIDTH-MEM_DATA_WIDTH){1'b0}}, mem_read_data}; // Zero Extend
                            lsu_state <= DONE;
                        end
                    end
                    DONE: begin 
                        // Reset when core_state = UPDATE
                        if (core_state == 3'b110) begin 
                            lsu_state <= IDLE;
                        end
                    end
                endcase
            end

            // If memory write enable is triggered (STR instruction)
            if (decoded_mem_write_enable) begin 
                case (lsu_state)
                    IDLE: begin
                        // Only read when core_state = REQUEST
                        if (core_state == 3'b011) begin 
                            lsu_state <= REQUESTING;
                        end
                    end
                    REQUESTING: begin 
                        mem_write_valid <= 1;
                        mem_write_address <= rs[ADDR_BITS-1:0]; // Use RS as address
                        mem_write_data <= rt[MEM_DATA_WIDTH-1:0]; // Truncate RT for memory
                        if (mem_write_ready) begin
                            mem_write_valid <= 0;
                            lsu_state <= DONE;
                        end else begin
                            lsu_state <= WAITING;
                        end
                    end
                    WAITING: begin
                        if (mem_write_ready) begin
                            mem_write_valid <= 0;
                            lsu_state <= DONE;
                        end
                    end
                    DONE: begin 
                        // Reset when core_state = UPDATE
                        if (core_state == 3'b110) begin 
                            lsu_state <= IDLE;
                        end
                    end
                endcase
            end
        end
    end
endmodule
