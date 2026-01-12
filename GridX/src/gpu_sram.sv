`default_nettype none
`timescale 1ns/1ns

// GPU WITH SRAM TILE BUFFER
// > Extended GPU module integrating modular SRAM-based memory subsystem
// > Parameterizable SRAM capacity for research scalability studies
// > Optional external memory via DMA (GPU functions without it)
// > Based on tiny-gpu architecture with compute-first philosophy
module gpu_sram #(
    // Original GPU parameters
    parameter DATA_MEM_ADDR_BITS = 8,
    parameter DATA_MEM_DATA_BITS = 8,
    parameter DATA_MEM_NUM_CHANNELS = 4,
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter PROGRAM_MEM_NUM_CHANNELS = 1,
    parameter NUM_CORES = 2,
    parameter THREADS_PER_BLOCK = 4,
    
    // SRAM Tile Buffer parameters (user-approved: 16KB / 8 banks default)
    parameter ENABLE_SRAM_TILE_BUFFER = 1,
    parameter SRAM_NUM_BANKS = 8,
    parameter SRAM_BANK_DEPTH = 256,        // 256 rows per bank
    parameter SRAM_DATA_WIDTH = 64,         // 8 bytes per row = 16KB total
    
    // Memory region defaults (user-approved: configurable base/limit)
    parameter SRAM_BASE_DEFAULT = 8'h00,
    parameter SRAM_LIMIT_DEFAULT = 8'h7F,   // Lower 128 = SRAM
    
    // DMA parameters (external memory optional)
    parameter ENABLE_DMA = 1,
    parameter DMA_BURST_SIZE = 8
) (
    input wire clk,
    input wire reset,

    // Kernel Execution
    input wire start,
    output wire done,

    // Device Control Register
    input wire device_control_write_enable,
    input wire [7:0] device_control_data,

    // Memory Region Configuration (CSR interface)
    input wire sram_region_write_enable,
    input wire [7:0] sram_base_in,
    input wire [7:0] sram_limit_in,

    // Program Memory Interface (unchanged)
    output wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_valid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address [PROGRAM_MEM_NUM_CHANNELS-1:0],
    input wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_ready,
    input wire [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data [PROGRAM_MEM_NUM_CHANNELS-1:0],

    // External Data Memory Interface (optional, for DMA)
    output wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [DATA_MEM_NUM_CHANNELS-1:0],
    input wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_ready,
    input wire [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [DATA_MEM_NUM_CHANNELS-1:0],
    output wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [DATA_MEM_NUM_CHANNELS-1:0],
    output wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [DATA_MEM_NUM_CHANNELS-1:0],
    input wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_ready,

    // DMA Command Interface (optional)
    input wire dma_cmd_valid,
    input wire dma_cmd_direction,           // 0 = External→SRAM, 1 = SRAM→External
    input wire [DATA_MEM_ADDR_BITS-1:0] dma_ext_addr,
    input wire [10:0] dma_sram_addr,
    input wire [7:0] dma_length,
    output wire dma_cmd_ready,
    output wire dma_done,
    output wire dma_busy,

    // Power Management Interface
    input wire [SRAM_NUM_BANKS-1:0] force_bank_enable,
    input wire [SRAM_NUM_BANKS-1:0] force_bank_sleep,
    output wire [SRAM_NUM_BANKS-1:0] bank_active,
    output wire [1:0] bank_power_state [SRAM_NUM_BANKS-1:0],
    output wire [SRAM_NUM_BANKS-1:0] bank_needs_reload
);
    // Memory region registers
    reg [7:0] sram_base_reg;
    reg [7:0] sram_limit_reg;
    
    // Control register management
    always @(posedge clk) begin
        if (reset) begin
            sram_base_reg <= SRAM_BASE_DEFAULT;
            sram_limit_reg <= SRAM_LIMIT_DEFAULT;
        end else if (sram_region_write_enable) begin
            sram_base_reg <= sram_base_in;
            sram_limit_reg <= sram_limit_in;
        end
    end

    // Thread count from DCR
    wire [7:0] thread_count;

    // Compute Core State
    reg [NUM_CORES-1:0] core_start;
    reg [NUM_CORES-1:0] core_reset;
    reg [NUM_CORES-1:0] core_done;
    reg [7:0] core_block_id [NUM_CORES-1:0];
    reg [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES-1:0];

    // LSU signals (total across all cores)
    localparam NUM_LSUS = NUM_CORES * THREADS_PER_BLOCK;
    
    // SRAM Controller signals
    wire [NUM_LSUS-1:0] sram_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] sram_read_address [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] sram_read_ready;
    wire [SRAM_DATA_WIDTH-1:0] sram_read_data [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] sram_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] sram_write_address [NUM_LSUS-1:0];
    wire [SRAM_DATA_WIDTH-1:0] sram_write_data [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] sram_write_ready;
    wire [NUM_LSUS-1:0] bank_conflict;

    // External memory routing
    wire [NUM_LSUS-1:0] ext_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] ext_read_address [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] ext_read_ready;
    wire [SRAM_DATA_WIDTH-1:0] ext_read_data [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] ext_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] ext_write_address [NUM_LSUS-1:0];
    wire [SRAM_DATA_WIDTH-1:0] ext_write_data [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] ext_write_ready;

    // Fetcher signals
    localparam NUM_FETCHERS = NUM_CORES;
    reg [NUM_FETCHERS-1:0] fetcher_read_valid;
    reg [PROGRAM_MEM_ADDR_BITS-1:0] fetcher_read_address [NUM_FETCHERS-1:0];
    reg [NUM_FETCHERS-1:0] fetcher_read_ready;
    reg [PROGRAM_MEM_DATA_BITS-1:0] fetcher_read_data [NUM_FETCHERS-1:0];

    // DMA Engine signals
    wire dma_ext_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] dma_ext_read_address;
    wire dma_ext_read_ready;
    wire [SRAM_DATA_WIDTH-1:0] dma_ext_read_data;
    wire dma_ext_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] dma_ext_write_address;
    wire [SRAM_DATA_WIDTH-1:0] dma_ext_write_data;
    wire dma_ext_write_ready;
    wire dma_sram_read_valid;
    wire [10:0] dma_sram_read_address;
    wire dma_sram_read_ready;
    wire [SRAM_DATA_WIDTH-1:0] dma_sram_read_data;
    wire dma_sram_write_valid;
    wire [10:0] dma_sram_write_address;
    wire [SRAM_DATA_WIDTH-1:0] dma_sram_write_data;
    wire dma_sram_write_ready;
    wire dma_error;
    wire [7:0] dma_words_transferred;

    // Device Control Register
    dcr dcr_instance (
        .clk(clk),
        .reset(reset),
        .device_control_write_enable(device_control_write_enable),
        .device_control_data(device_control_data),
        .thread_count(thread_count)
    );

    // SRAM Controller (conditional generation)
    generate
        if (ENABLE_SRAM_TILE_BUFFER) begin : sram_subsystem
            sram_controller #(
                .NUM_CORES(NUM_CORES),
                .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
                .NUM_BANKS(SRAM_NUM_BANKS),
                .BANK_DEPTH(SRAM_BANK_DEPTH),
                .DATA_WIDTH(SRAM_DATA_WIDTH),
                .ADDR_BITS(DATA_MEM_ADDR_BITS)
            ) sram_ctrl_inst (
                .clk(clk),
                .reset(reset),
                .sram_base_reg(sram_base_reg),
                .sram_limit_reg(sram_limit_reg),
                .core_read_valid(sram_read_valid),
                .core_read_address(sram_read_address),
                .core_read_ready(sram_read_ready),
                .core_read_data(sram_read_data),
                .core_write_valid(sram_write_valid),
                .core_write_address(sram_write_address),
                .core_write_data(sram_write_data),
                .core_write_ready(sram_write_ready),
                .core_bank_conflict(bank_conflict),
                .ext_read_valid(ext_read_valid),
                .ext_read_address(ext_read_address),
                .ext_read_ready(ext_read_ready),
                .ext_read_data(ext_read_data),
                .ext_write_valid(ext_write_valid),
                .ext_write_address(ext_write_address),
                .ext_write_data(ext_write_data),
                .ext_write_ready(ext_write_ready),
                .dma_read_valid(dma_sram_read_valid),
                .dma_read_address(dma_sram_read_address[DATA_MEM_ADDR_BITS-1:0]),
                .dma_read_ready(dma_sram_read_ready),
                .dma_read_data(dma_sram_read_data),
                .dma_write_valid(dma_sram_write_valid),
                .dma_write_address(dma_sram_write_address[DATA_MEM_ADDR_BITS-1:0]),
                .dma_write_data(dma_sram_write_data),
                .dma_write_ready(dma_sram_write_ready),
                .force_bank_enable(force_bank_enable),
                .force_bank_sleep(force_bank_sleep),
                .bank_active(bank_active),
                .bank_power_state(bank_power_state),
                .bank_needs_reload(bank_needs_reload)
            );
        end
    endgenerate

    // DMA Engine (conditional generation)
    generate
        if (ENABLE_DMA) begin : dma_subsystem
            dma_engine #(
                .ADDR_BITS(DATA_MEM_ADDR_BITS),
                .DATA_WIDTH(SRAM_DATA_WIDTH),
                .BURST_SIZE(DMA_BURST_SIZE)
            ) dma_inst (
                .clk(clk),
                .reset(reset),
                .cmd_valid(dma_cmd_valid),
                .cmd_direction(dma_cmd_direction),
                .cmd_ext_addr(dma_ext_addr),
                .cmd_sram_addr(dma_sram_addr),
                .cmd_length(dma_length),
                .cmd_ready(dma_cmd_ready),
                .cmd_done(dma_done),
                .cmd_error(dma_error),
                .ext_read_valid(dma_ext_read_valid),
                .ext_read_address(dma_ext_read_address),
                .ext_read_ready(dma_ext_read_ready),
                .ext_read_data(dma_ext_read_data),
                .ext_write_valid(dma_ext_write_valid),
                .ext_write_address(dma_ext_write_address),
                .ext_write_data(dma_ext_write_data),
                .ext_write_ready(dma_ext_write_ready),
                .sram_read_valid(dma_sram_read_valid),
                .sram_read_address(dma_sram_read_address),
                .sram_read_ready(dma_sram_read_ready),
                .sram_read_data(dma_sram_read_data),
                .sram_write_valid(dma_sram_write_valid),
                .sram_write_address(dma_sram_write_address),
                .sram_write_data(dma_sram_write_data),
                .sram_write_ready(dma_sram_write_ready),
                .busy(dma_busy),
                .words_transferred(dma_words_transferred)
            );
        end else begin : no_dma
            assign dma_cmd_ready = 1'b0;
            assign dma_done = 1'b0;
            assign dma_busy = 1'b0;
        end
    endgenerate

    // Dispatcher
    dispatch #(
        .NUM_CORES(NUM_CORES),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK)
    ) dispatch_instance (
        .clk(clk),
        .reset(reset),
        .start(start),
        .thread_count(thread_count),
        .core_done(core_done),
        .core_start(core_start),
        .core_reset(core_reset),
        .core_block_id(core_block_id),
        .core_thread_count(core_thread_count),
        .done(done)
    );

    // Data Memory Controller (for external memory access)
    controller #(
        .ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_BITS(DATA_MEM_DATA_BITS),
        .NUM_CONSUMERS(NUM_LSUS),
        .NUM_CHANNELS(DATA_MEM_NUM_CHANNELS)
    ) data_memory_controller (
        .clk(clk),
        .reset(reset),
        .consumer_read_valid(ext_read_valid),
        .consumer_read_address(ext_read_address),
        .consumer_read_ready(ext_read_ready),
        .consumer_read_data(ext_read_data),
        .consumer_write_valid(ext_write_valid),
        .consumer_write_address(ext_write_address),
        .consumer_write_data(ext_write_data),
        .consumer_write_ready(ext_write_ready),
        .mem_read_valid(data_mem_read_valid),
        .mem_read_address(data_mem_read_address),
        .mem_read_ready(data_mem_read_ready),
        .mem_read_data(data_mem_read_data),
        .mem_write_valid(data_mem_write_valid),
        .mem_write_address(data_mem_write_address),
        .mem_write_data(data_mem_write_data),
        .mem_write_ready(data_mem_write_ready)
    );

    // Program Memory Controller (unchanged)
    controller #(
        .ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .NUM_CONSUMERS(NUM_FETCHERS),
        .NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS),
        .WRITE_ENABLE(0)
    ) program_memory_controller (
        .clk(clk),
        .reset(reset),
        .consumer_read_valid(fetcher_read_valid),
        .consumer_read_address(fetcher_read_address),
        .consumer_read_ready(fetcher_read_ready),
        .consumer_read_data(fetcher_read_data),
        .mem_read_valid(program_mem_read_valid),
        .mem_read_address(program_mem_read_address),
        .mem_read_ready(program_mem_read_ready),
        .mem_read_data(program_mem_read_data)
    );

    // Note: Core instantiation would follow here similar to original gpu.sv
    // Each core would connect to SRAM controller instead of direct memory controller
    // For full integration, cores need to be modified to support SRAM interface

endmodule
