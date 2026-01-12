`default_nettype none
`timescale 1ns/1ns

// GPU (1024 Thread Scaled Architecture)
// > 16 Cores * 4 Warps * 16 Threads = 1024 Threads
// > Serialized Memory Interface per Core (via Internal Arbiter)
module gpu #(
    parameter DATA_MEM_ADDR_BITS = 16,         // Number of bits in data memory address (64KB)
    parameter DATA_MEM_DATA_BITS = 8,         // Number of bits in data memory value (8 bit data)
    parameter DATA_MEM_NUM_CHANNELS = 16,     // 16 Channels (1 per core, now 1-to-1 mapping ideal)
    parameter PROGRAM_MEM_ADDR_BITS = 8,      // Number of bits in program memory address (256 rows)
    parameter PROGRAM_MEM_DATA_BITS = 16,     // Number of bits in program memory value (16 bit instruction)
    parameter PROGRAM_MEM_NUM_CHANNELS = 4,   // 4 Fetcher Channels (Arbitrated)
    parameter NUM_CORES = 16,                 // 16 Cores
    parameter THREADS_PER_BLOCK = 64,         // 64 Threads per core (4 Warps * 16 Threads)
    parameter WARPS_PER_CORE = 4              // 4 Warps
) (
    input wire clk,
    input wire reset,

    // Kernel Execution
    input wire start,
    output wire done,

    // Device Control Register
    input wire device_control_write_enable,
    input wire [15:0] device_control_data,

    // Program Memory
    output wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_valid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address [PROGRAM_MEM_NUM_CHANNELS-1:0],
    input wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_ready,
    input wire [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data [PROGRAM_MEM_NUM_CHANNELS-1:0],

    // Data Memory
    output wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [DATA_MEM_NUM_CHANNELS-1:0],
    input wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_ready,
    input wire [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [DATA_MEM_NUM_CHANNELS-1:0],
    output wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [DATA_MEM_NUM_CHANNELS-1:0],
    output wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [DATA_MEM_NUM_CHANNELS-1:0],
    input wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_ready
);
    // Control
    wire [15:0] thread_count;

    // Compute Core State
    reg [NUM_CORES-1:0] core_start;
    reg [NUM_CORES-1:0] core_reset;
    reg [NUM_CORES-1:0] core_done;
    reg [7:0] core_block_id [NUM_CORES-1:0];
    reg [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES-1:0];

    // LSU <> Data Memory Controller Channels
    // Now Serialized: 1 LSU Port per Core
    localparam NUM_LSUS = NUM_CORES; 
    
    // Wire arrays for controller
    wire [NUM_LSUS-1:0] lsu_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] lsu_read_address [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] lsu_read_ready;
    wire [DATA_MEM_DATA_BITS-1:0] lsu_read_data [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] lsu_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] lsu_write_address [NUM_LSUS-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] lsu_write_data [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] lsu_write_ready;

    // Fetcher <> Program Memory Controller Channels
    localparam NUM_FETCHERS = NUM_CORES;
    wire [NUM_FETCHERS-1:0] fetcher_read_valid;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] fetcher_read_address [NUM_FETCHERS-1:0];
    wire [NUM_FETCHERS-1:0] fetcher_read_ready;
    wire [PROGRAM_MEM_DATA_BITS-1:0] fetcher_read_data [NUM_FETCHERS-1:0];
    
    // Device Control Register
    dcr dcr_instance (
        .clk(clk),
        .reset(reset),

        .device_control_write_enable(device_control_write_enable),
        .device_control_data(device_control_data),
        .thread_count(thread_count)
    );

    // Data Memory Controller (Level 3 Gateway)
    // Consumers: 16 L2 Routers (Mesh Nodes)
    localparam NUM_NODES = 16;
    
    // Router -> Global Controller Signals
    wire [NUM_NODES-1:0] mesh_global_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] mesh_global_read_addr [NUM_NODES-1:0];
    wire [NUM_NODES-1:0] mesh_global_read_ready;
    wire [DATA_MEM_DATA_BITS-1:0] mesh_global_read_data [NUM_NODES-1:0];
    
    wire [NUM_NODES-1:0] mesh_global_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] mesh_global_write_addr [NUM_NODES-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] mesh_global_write_data [NUM_NODES-1:0];
    wire [NUM_NODES-1:0] mesh_global_write_ready;
    
    controller #(
        .ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_BITS(DATA_MEM_DATA_BITS),
        .NUM_CONSUMERS(NUM_NODES), // 16 Inputs
        .NUM_CHANNELS(DATA_MEM_NUM_CHANNELS)
    ) data_memory_controller (
        .clk(clk),
        .reset(reset),

        .consumer_read_valid(mesh_global_read_valid),
        .consumer_read_address(mesh_global_read_addr),
        .consumer_read_ready(mesh_global_read_ready),
        .consumer_read_data(mesh_global_read_data),
        
        .consumer_write_valid(mesh_global_write_valid),
        .consumer_write_address(mesh_global_write_addr),
        .consumer_write_data(mesh_global_write_data),
        .consumer_write_ready(mesh_global_write_ready),

        .mem_read_valid(data_mem_read_valid),
        .mem_read_address(data_mem_read_address),
        .mem_read_ready(data_mem_read_ready),
        .mem_read_data(data_mem_read_data),
        .mem_write_valid(data_mem_write_valid),
        .mem_write_address(data_mem_write_address),
        .mem_write_data(data_mem_write_data),
        .mem_write_ready(data_mem_write_ready)
    );
    
    // --- L2 Mesh (4x4 Grid) ---
    // Nodes: 0..15. Row=k/4, Col=k%4.
    
    // Mesh Interconnect Wires
    // We need arrays to handle the mesh connections directionally.
    // [15:0] refers to the SOURCE node outputting the signal.
    // e.g. n_out_valid[5] is coming FROM Node 5, intended for Node 1 (North).
    
    wire [NUM_NODES-1:0] n_out_valid, s_out_valid, e_out_valid, w_out_valid;
    wire [NUM_NODES-1:0] n_out_write, s_out_write, e_out_write, w_out_write;
    wire [DATA_MEM_ADDR_BITS-1:0] n_out_addr[NUM_NODES-1:0], s_out_addr[NUM_NODES-1:0], e_out_addr[NUM_NODES-1:0], w_out_addr[NUM_NODES-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] n_out_wdata[NUM_NODES-1:0], s_out_wdata[NUM_NODES-1:0], e_out_wdata[NUM_NODES-1:0], w_out_wdata[NUM_NODES-1:0];
    wire [NUM_NODES-1:0] n_out_ready, s_out_ready, e_out_ready, w_out_ready; // Valid/Ready backwards
    wire [DATA_MEM_DATA_BITS-1:0] n_out_rdata[NUM_NODES-1:0], s_out_rdata[NUM_NODES-1:0], e_out_rdata[NUM_NODES-1:0], w_out_rdata[NUM_NODES-1:0];

    // Helper Function for Indexing
    function [4:0] idx; input [2:0] r; input [2:0] c; idx = (r * 4) + c; endfunction

    genvar r, c;
    generate
        for (r = 0; r < 4; r = r + 1) begin : rows
            for (c = 0; c < 4; c = c + 1) begin : cols
                localparam integer k = (r * 4) + c;
                localparam integer north_k = ((r - 1) * 4) + c;
                localparam integer south_k = ((r + 1) * 4) + c;
                localparam integer east_k  = (r * 4) + (c + 1);
                localparam integer west_k  = (r * 4) + (c - 1);
                
                // --- Input Wiring (From Neighbors) ---
                // North In: Comes from South Out of Node (r-1, c)
                wire n_in_valid, n_in_write;
                wire [DATA_MEM_ADDR_BITS-1:0] n_in_addr_wire;
                wire [DATA_MEM_DATA_BITS-1:0] n_in_wdata_wire;
                wire n_in_ready_wire;
                wire [DATA_MEM_DATA_BITS-1:0] n_in_rdata_wire;
                
                if (r > 0) begin
                    assign n_in_valid = s_out_valid[north_k];
                    assign n_in_write = s_out_write[north_k];
                    assign n_in_addr_wire = s_out_addr[north_k];
                    assign n_in_wdata_wire = s_out_wdata[north_k];
                    assign s_out_ready[north_k] = n_in_ready_wire;     // Backpressure to Sender
                    assign s_out_rdata[north_k] = n_in_rdata_wire;     // Read Data to Sender
                end else begin
                    // Boundary
                    assign n_in_valid = 0; assign n_in_write = 0; assign n_in_addr_wire = 0; assign n_in_wdata_wire = 0;
                end

                // South In: Comes from North Out of Node (r+1, c)
                wire s_in_valid, s_in_write;
                wire [DATA_MEM_ADDR_BITS-1:0] s_in_addr_wire;
                wire [DATA_MEM_DATA_BITS-1:0] s_in_wdata_wire;
                wire s_in_ready_wire;
                wire [DATA_MEM_DATA_BITS-1:0] s_in_rdata_wire;

                if (r < 3) begin
                    assign s_in_valid = n_out_valid[south_k];
                    assign s_in_write = n_out_write[south_k];
                    assign s_in_addr_wire = n_out_addr[south_k];
                    assign s_in_wdata_wire = n_out_wdata[south_k];
                    assign n_out_ready[south_k] = s_in_ready_wire;
                    assign n_out_rdata[south_k] = s_in_rdata_wire;
                end else begin
                    assign s_in_valid = 0; assign s_in_write = 0; assign s_in_addr_wire = 0; assign s_in_wdata_wire = 0;
                end
                
                // East In: Comes from West Out of Node (r, c+1)
                wire e_in_valid, e_in_write;
                wire [DATA_MEM_ADDR_BITS-1:0] e_in_addr_wire;
                wire [DATA_MEM_DATA_BITS-1:0] e_in_wdata_wire;
                wire e_in_ready_wire;
                wire [DATA_MEM_DATA_BITS-1:0] e_in_rdata_wire;

                if (c < 3) begin
                    assign e_in_valid = w_out_valid[east_k];
                    assign e_in_write = w_out_write[east_k];
                    assign e_in_addr_wire = w_out_addr[east_k];
                    assign e_in_wdata_wire = w_out_wdata[east_k];
                    assign w_out_ready[east_k] = e_in_ready_wire;
                    assign w_out_rdata[east_k] = e_in_rdata_wire;
                end else begin
                    assign e_in_valid = 0; assign e_in_write = 0; assign e_in_addr_wire = 0; assign e_in_wdata_wire = 0;
                end
                
                // West In: Comes from East Out of Node (r, c-1)
                wire w_in_valid, w_in_write;
                wire [DATA_MEM_ADDR_BITS-1:0] w_in_addr_wire;
                wire [DATA_MEM_DATA_BITS-1:0] w_in_wdata_wire;
                wire w_in_ready_wire;
                wire [DATA_MEM_DATA_BITS-1:0] w_in_rdata_wire;

                if (c > 0) begin
                    assign w_in_valid = e_out_valid[west_k];
                    assign w_in_write = e_out_write[west_k];
                    assign w_in_addr_wire = e_out_addr[west_k];
                    assign w_in_wdata_wire = e_out_wdata[west_k];
                    assign e_out_ready[west_k] = w_in_ready_wire;
                    assign e_out_rdata[west_k] = w_in_rdata_wire;
                end else begin
                    assign w_in_valid = 0; assign w_in_write = 0; assign w_in_addr_wire = 0; assign w_in_wdata_wire = 0;
                end

                // --- Router Instance ---
                // Global Interface Wires
                wire g_valid_u, g_write_u;
                wire [DATA_MEM_ADDR_BITS-1:0] g_addr_u;
                wire [DATA_MEM_DATA_BITS-1:0] g_wdata_u;
                wire [DATA_MEM_DATA_BITS-1:0] g_rdata_u = mesh_global_read_data[k];
                wire g_ready_u = mesh_global_read_ready[k] || mesh_global_write_ready[k];
                wire router_core_ready;
                
                l2_mesh_router #(
                    .SLICE_ID(k),
                    .ADDR_WIDTH(DATA_MEM_ADDR_BITS),
                    .DATA_WIDTH(DATA_MEM_DATA_BITS),
                    .L2_BASE(16'h8000)
                ) router (
                    .clk(clk),
                    .reset(reset),
                    // Core
                    .c_req_valid(lsu_read_valid[k] || lsu_write_valid[k]),
                    .c_req_write(lsu_write_valid[k]),
                    .c_req_addr(lsu_write_valid[k] ? lsu_write_address[k] : lsu_read_address[k]),
                    .c_req_wdata(lsu_write_data[k]),
                    .c_req_ready(router_core_ready), 
                    .c_req_rdata(lsu_read_data[k]), 
                    
                    // Neighbors In (Wired above)
                    .n_in_valid(n_in_valid), .n_in_write(n_in_write), .n_in_addr(n_in_addr_wire), .n_in_wdata(n_in_wdata_wire), .n_in_ready(n_in_ready_wire), .n_in_rdata(n_in_rdata_wire),
                    .s_in_valid(s_in_valid), .s_in_write(s_in_write), .s_in_addr(s_in_addr_wire), .s_in_wdata(s_in_wdata_wire), .s_in_ready(s_in_ready_wire), .s_in_rdata(s_in_rdata_wire),
                    .e_in_valid(e_in_valid), .e_in_write(e_in_write), .e_in_addr(e_in_addr_wire), .e_in_wdata(e_in_wdata_wire), .e_in_ready(e_in_ready_wire), .e_in_rdata(e_in_rdata_wire),
                    .w_in_valid(w_in_valid), .w_in_write(w_in_write), .w_in_addr(w_in_addr_wire), .w_in_wdata(w_in_wdata_wire), .w_in_ready(w_in_ready_wire), .w_in_rdata(w_in_rdata_wire),
                    
                    // Neighbors Out (Wired to Arrays)
                    .n_out_valid(n_out_valid[k]), .n_out_write(n_out_write[k]), .n_out_addr(n_out_addr[k]), .n_out_wdata(n_out_wdata[k]), .n_out_ready(n_out_ready[k]), .n_out_rdata(n_out_rdata[k]),
                    .s_out_valid(s_out_valid[k]), .s_out_write(s_out_write[k]), .s_out_addr(s_out_addr[k]), .s_out_wdata(s_out_wdata[k]), .s_out_ready(s_out_ready[k]), .s_out_rdata(s_out_rdata[k]),
                    .e_out_valid(e_out_valid[k]), .e_out_write(e_out_write[k]), .e_out_addr(e_out_addr[k]), .e_out_wdata(e_out_wdata[k]), .e_out_ready(e_out_ready[k]), .e_out_rdata(e_out_rdata[k]),
                    .w_out_valid(w_out_valid[k]), .w_out_write(w_out_write[k]), .w_out_addr(w_out_addr[k]), .w_out_wdata(w_out_wdata[k]), .w_out_ready(w_out_ready[k]), .w_out_rdata(w_out_rdata[k]),
                    
                    // Global
                    .g_out_valid(g_valid_u), .g_out_write(g_write_u), .g_out_addr(g_addr_u), .g_out_wdata(g_wdata_u), .g_out_ready(g_ready_u), .g_out_rdata(g_rdata_u)
                );
                
                // --- Wiring Completion ---
                
                // Core Ready Mapping
                assign lsu_read_ready[k] = router_core_ready && !lsu_write_valid[k];
                assign lsu_write_ready[k] = router_core_ready && lsu_write_valid[k];
                
                // Global Signal Demux (Router Unified -> Controller Split)
                assign mesh_global_read_valid[k] = g_valid_u && !g_write_u;
                assign mesh_global_read_addr[k]  = g_addr_u;
                
                assign mesh_global_write_valid[k] = g_valid_u && g_write_u;
                assign mesh_global_write_addr[k]  = g_addr_u;
                assign mesh_global_write_data[k]  = g_wdata_u;
            end
        end
    endgenerate

    // Program Memory Controller
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

    // Compute Cores
    genvar i;
    generate
        for (i = 0; i < NUM_CORES; i = i + 1) begin : cores
            // Pass-through pipeline registers are REMOVED because we connect directly.
            // If pipeline is needed for timing, we can add it later.
            // For now, direct connection simplifies logic.
            
            // Compute Core
            core #(
                .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
                .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
                .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
                .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
                .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
                .WARPS_PER_CORE(WARPS_PER_CORE)
            ) core_instance (
                .clk(clk),
                .reset(core_reset[i]),
                .start(core_start[i]),
                .done(core_done[i]),
                .block_id(core_block_id[i]),
                .thread_count(core_thread_count[i]),
                
                // Fetcher Interface
                .program_mem_read_valid(fetcher_read_valid[i]),
                .program_mem_read_address(fetcher_read_address[i]),
                .program_mem_read_ready(fetcher_read_ready[i]),
                .program_mem_read_data(fetcher_read_data[i]),

                // Data Interface (Serialized)
                .mem_read_valid(lsu_read_valid[i]),
                .mem_read_address(lsu_read_address[i]),
                .mem_read_ready(lsu_read_ready[i]),
                .mem_read_data(lsu_read_data[i]),
                
                .mem_write_valid(lsu_write_valid[i]),
                .mem_write_address(lsu_write_address[i]),
                .mem_write_data(lsu_write_data[i]),
                .mem_write_ready(lsu_write_ready[i])
            );
        end
    endgenerate
endmodule
