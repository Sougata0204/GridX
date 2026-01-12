`default_nettype none
`timescale 1ns/1ns

// DMA ENGINE
// > Burst transfer between external memory and SRAM tile buffer
// > Supports configurable burst sizes for efficient bandwidth utilization
// > Generates completion signals for software synchronization
// > Optional module - GPU functions without external memory
module dma_engine #(
    parameter ADDR_BITS = 8,
    parameter DATA_WIDTH = 64,
    parameter BURST_SIZE = 8,           // Words per burst
    parameter MAX_OUTSTANDING = 2,      // Concurrent DMA operations
    parameter SRAM_ADDR_BITS = 11       // SRAM address width
) (
    input wire clk,
    input wire reset,

    // DMA command interface (from software/CSR)
    input wire cmd_valid,
    input wire cmd_direction,           // 0 = External→SRAM (READ), 1 = SRAM→External (WRITE)
    input wire [ADDR_BITS-1:0] cmd_ext_addr,
    input wire [SRAM_ADDR_BITS-1:0] cmd_sram_addr,
    input wire [7:0] cmd_length,        // Number of words to transfer
    output reg cmd_ready,
    output reg cmd_done,
    output reg cmd_error,

    // External memory interface
    output reg ext_read_valid,
    output reg [ADDR_BITS-1:0] ext_read_address,
    input wire ext_read_ready,
    input wire [DATA_WIDTH-1:0] ext_read_data,

    output reg ext_write_valid,
    output reg [ADDR_BITS-1:0] ext_write_address,
    output reg [DATA_WIDTH-1:0] ext_write_data,
    input wire ext_write_ready,

    // SRAM tile buffer interface
    output reg sram_read_valid,
    output reg [SRAM_ADDR_BITS-1:0] sram_read_address,
    input wire sram_read_ready,
    input wire [DATA_WIDTH-1:0] sram_read_data,

    output reg sram_write_valid,
    output reg [SRAM_ADDR_BITS-1:0] sram_write_address,
    output reg [DATA_WIDTH-1:0] sram_write_data,
    input wire sram_write_ready,

    // Status
    output reg busy,
    output reg [7:0] words_transferred
);
    // DMA state machine
    localparam IDLE = 3'b000,
               LOAD_CMD = 3'b001,
               READ_EXT = 3'b010,
               WRITE_SRAM = 3'b011,
               READ_SRAM = 3'b100,
               WRITE_EXT = 3'b101,
               COMPLETE = 3'b110,
               ERROR = 3'b111;

    reg [2:0] state;
    reg direction;
    reg [ADDR_BITS-1:0] ext_addr;
    reg [SRAM_ADDR_BITS-1:0] sram_addr;
    reg [7:0] remaining;
    reg [DATA_WIDTH-1:0] data_buffer;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            cmd_ready <= 1'b1;
            cmd_done <= 1'b0;
            cmd_error <= 1'b0;
            busy <= 1'b0;
            words_transferred <= 8'b0;
            
            ext_read_valid <= 1'b0;
            ext_read_address <= {ADDR_BITS{1'b0}};
            ext_write_valid <= 1'b0;
            ext_write_address <= {ADDR_BITS{1'b0}};
            ext_write_data <= {DATA_WIDTH{1'b0}};
            
            sram_read_valid <= 1'b0;
            sram_read_address <= {SRAM_ADDR_BITS{1'b0}};
            sram_write_valid <= 1'b0;
            sram_write_address <= {SRAM_ADDR_BITS{1'b0}};
            sram_write_data <= {DATA_WIDTH{1'b0}};
            
            direction <= 1'b0;
            ext_addr <= {ADDR_BITS{1'b0}};
            sram_addr <= {SRAM_ADDR_BITS{1'b0}};
            remaining <= 8'b0;
            data_buffer <= {DATA_WIDTH{1'b0}};
        end else begin
            // Default signal deassertions
            cmd_done <= 1'b0;
            cmd_error <= 1'b0;

            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    cmd_ready <= 1'b1;
                    
                    if (cmd_valid && cmd_ready) begin
                        // Latch command parameters
                        direction <= cmd_direction;
                        ext_addr <= cmd_ext_addr;
                        sram_addr <= cmd_sram_addr;
                        remaining <= cmd_length;
                        words_transferred <= 8'b0;
                        
                        cmd_ready <= 1'b0;
                        busy <= 1'b1;
                        state <= LOAD_CMD;
                    end
                end
                
                LOAD_CMD: begin
                    if (remaining == 0) begin
                        state <= COMPLETE;
                    end else if (direction == 0) begin
                        // External → SRAM: Start by reading from external
                        state <= READ_EXT;
                    end else begin
                        // SRAM → External: Start by reading from SRAM
                        state <= READ_SRAM;
                    end
                end
                
                READ_EXT: begin
                    ext_read_valid <= 1'b1;
                    ext_read_address <= ext_addr;
                    
                    if (ext_read_ready) begin
                        data_buffer <= ext_read_data;
                        ext_read_valid <= 1'b0;
                        state <= WRITE_SRAM;
                    end
                end
                
                WRITE_SRAM: begin
                    sram_write_valid <= 1'b1;
                    sram_write_address <= sram_addr;
                    sram_write_data <= data_buffer;
                    
                    if (sram_write_ready) begin
                        sram_write_valid <= 1'b0;
                        
                        // Update counters
                        ext_addr <= ext_addr + 1;
                        sram_addr <= sram_addr + 1;
                        remaining <= remaining - 1;
                        words_transferred <= words_transferred + 1;
                        
                        if (remaining == 1) begin
                            state <= COMPLETE;
                        end else begin
                            state <= READ_EXT;
                        end
                    end
                end
                
                READ_SRAM: begin
                    sram_read_valid <= 1'b1;
                    sram_read_address <= sram_addr;
                    
                    if (sram_read_ready) begin
                        data_buffer <= sram_read_data;
                        sram_read_valid <= 1'b0;
                        state <= WRITE_EXT;
                    end
                end
                
                WRITE_EXT: begin
                    ext_write_valid <= 1'b1;
                    ext_write_address <= ext_addr;
                    ext_write_data <= data_buffer;
                    
                    if (ext_write_ready) begin
                        ext_write_valid <= 1'b0;
                        
                        // Update counters
                        ext_addr <= ext_addr + 1;
                        sram_addr <= sram_addr + 1;
                        remaining <= remaining - 1;
                        words_transferred <= words_transferred + 1;
                        
                        if (remaining == 1) begin
                            state <= COMPLETE;
                        end else begin
                            state <= READ_SRAM;
                        end
                    end
                end
                
                COMPLETE: begin
                    cmd_done <= 1'b1;
                    busy <= 1'b0;
                    state <= IDLE;
                end
                
                ERROR: begin
                    cmd_error <= 1'b1;
                    busy <= 1'b0;
                    state <= IDLE;
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
