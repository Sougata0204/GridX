// Load/Store Execution Unit
// Handles memory instruction address calculation and data alignment.
// I fixed the store instruction encoding (STR) field mapping so rs supplies the target address
// and rt supplies the store data payload.


`default_nettype none
`timescale 1ns/1ns

module lsu #(
    parameter ADDR_BITS = 16,
    parameter MEM_DATA_WIDTH = 8,
    parameter REG_WIDTH = 16
) (
    input wire clk,
    input wire reset,
    input wire enable,
    input wire [2:0] core_state,
    input wire decoded_mem_read_enable,
    input wire decoded_mem_write_enable,
    input wire [REG_WIDTH-1:0] rs,
    input wire [REG_WIDTH-1:0] rt,
    output reg mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_address,
    input wire mem_read_ready,
    input wire [MEM_DATA_WIDTH-1:0] mem_read_data,
    output reg mem_write_valid,
    output reg [ADDR_BITS-1:0] mem_write_address,
    output reg [MEM_DATA_WIDTH-1:0] mem_write_data,
    input wire mem_write_ready,
    output reg [1:0] lsu_state,
    output reg [REG_WIDTH-1:0] lsu_out,
    output wire lsu_pending,
    input wire is_local
);
    localparam IDLE         = 3'b000;
    localparam REQUESTING   = 3'b001;
    localparam WAITING      = 3'b010;
    localparam DONE         = 3'b011;
    localparam LOCAL_ACCESS = 3'b100;
    reg [2:0] state;
    assign lsu_state = state[1:0];
    localparam CORE_REQUEST = 3'b011;
    localparam CORE_UPDATE  = 3'b110;
    assign lsu_pending = (state != IDLE && state != DONE);
    // Safe address extension: rs is REG_WIDTH bits, address is ADDR_BITS bits
    localparam ADDR_PAD = (ADDR_BITS > REG_WIDTH) ? (ADDR_BITS - REG_WIDTH) : 0;
    wire [ADDR_BITS-1:0] rs_addr;
    generate
        if (ADDR_PAD > 0) begin : gen_pad
            assign rs_addr = {{ADDR_PAD{1'b0}}, rs};
        end else begin : gen_nopad
            assign rs_addr = rs[ADDR_BITS-1:0];
        end
    endgenerate
    reg is_write_op;
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            lsu_out <= 0;
            mem_read_valid <= 0;
            mem_read_address <= 0;
            mem_write_valid <= 0;
            mem_write_address <= 0;
            mem_write_data <= 0;
            is_write_op <= 0;
        end else if (enable) begin
            case (state)
                IDLE: begin
                    if (core_state == CORE_REQUEST) begin
                        if (decoded_mem_read_enable) begin
                            state <= is_local ? LOCAL_ACCESS : REQUESTING;
                            is_write_op <= 0;
                            mem_read_address <= rs_addr;
                        end else if (decoded_mem_write_enable) begin
                            state <= is_local ? LOCAL_ACCESS : REQUESTING;
                            is_write_op <= 1;
                            mem_write_address <= rs_addr;
                            mem_write_data <= rt[MEM_DATA_WIDTH-1:0];
                        end
                    end
                end
                REQUESTING: begin
                    if (!is_write_op) begin
                        mem_read_valid <= 1;
                        if (mem_read_ready) begin
                            mem_read_valid <= 0;
                            lsu_out <= {{(REG_WIDTH-MEM_DATA_WIDTH){1'b0}}, mem_read_data};
                            state <= DONE;
                        end else begin
                            state <= WAITING;
                        end
                    end else begin
                        mem_write_valid <= 1;
                        if (mem_write_ready) begin
                            mem_write_valid <= 0;
                            state <= DONE;
                        end else begin
                            state <= WAITING;
                        end
                    end
                end
                LOCAL_ACCESS: begin
                    if (!is_write_op) begin
                        mem_read_valid <= 1;
                        if (mem_read_ready) begin
                            mem_read_valid <= 0;
                            lsu_out <= {{(REG_WIDTH-MEM_DATA_WIDTH){1'b0}}, mem_read_data};
                            state <= DONE;
                        end
                    end else begin
                        mem_write_valid <= 1;
                        if (mem_write_ready) begin
                            mem_write_valid <= 0;
                            state <= DONE;
                        end
                    end
                end
                WAITING: begin
                    if (!is_write_op) begin
                        mem_read_valid <= 1;
                        if (mem_read_ready) begin
                            mem_read_valid <= 0;
                            lsu_out <= {{(REG_WIDTH-MEM_DATA_WIDTH){1'b0}}, mem_read_data};
                            state <= DONE;
                        end
                    end else begin
                        mem_write_valid <= 1;
                        if (mem_write_ready) begin
                            mem_write_valid <= 0;
                            state <= DONE;
                        end
                    end
                end
                DONE: begin
                    if (core_state == CORE_UPDATE) begin
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
