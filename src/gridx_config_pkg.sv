// GridX3 Parameterized Configuration Package
// Defines all global SoC parameters like cube dimensions, core count, address widths, and clock settings.


`default_nettype none
`timescale 1ns/1ns

package gridx_config_pkg;

    // 1. 3D GEOMETRY - Core Array Dimensions
    // Scale the cube to change total core count.
    // Debug:      2x2x2 = 8 cores   (~100 KB total SRAM)
    // Mid:        4x4x2 = 32 cores  (~2 MB total SRAM)
    // Datacenter: 8x8x4 = 256 cores (~64 MB total SRAM)
    localparam int CFG_CUBE_X = 2;
    localparam int CFG_CUBE_Y = 2;
    localparam int CFG_CUBE_Z = 2;
    localparam int CFG_NUM_CORES = CFG_CUBE_X * CFG_CUBE_Y * CFG_CUBE_Z;

    // 2. CORE CONFIGURATION - Threading & Registers
    localparam int CFG_WARPS_PER_CORE    = 1;     // Scale: 1 (debug) to 32
    localparam int CFG_THREADS_PER_WARP  = 4;     // Scale: 4 (debug) to 32
    localparam int CFG_THREADS_PER_CORE  = CFG_WARPS_PER_CORE * CFG_THREADS_PER_WARP;
    localparam int CFG_TOTAL_THREADS     = CFG_NUM_CORES * CFG_THREADS_PER_CORE;
    localparam int CFG_NUM_REGS          = 16;    // General purpose registers per thread
    localparam int CFG_REG_WIDTH         = 16;    // Register width in bits

    // 3. MEMORY ADDRESSING - Widths & Depths
    localparam int CFG_DATA_MEM_ADDR_BITS    = 22;   // 4 MB addressable
    localparam int CFG_DATA_MEM_DATA_BITS    = 8;    // Byte-addressable
    localparam int CFG_PROGRAM_MEM_ADDR_BITS = 12;   // 4K instructions
    localparam int CFG_PROGRAM_MEM_DATA_BITS = 16;   // 16-bit instruction word
    localparam int CFG_PMEM_DEPTH            = 4096; // Program memory depth
    localparam int CFG_DMEM_DEPTH            = 4096; // Data memory depth (on-chip BRAM)

    // 4. CACHE HIERARCHY
    localparam int CFG_L1_SIZE_KB             = 32;
    localparam int CFG_L2_SLICE_KB            = 2;
    localparam int CFG_L2_SLICES_PER_FACE     = 16;
    localparam int CFG_L3_SHELL_KB            = 512;
    localparam int CFG_UNIFIED_L1_KB          = 64;
    localparam int CFG_UNIFIED_L1_SHARED_KB   = 48;
    localparam int CFG_UNIFIED_L1_CACHE_KB    = 16;

    // 5. OUTSTANDING REQUEST TRACKING
    localparam int CFG_MAX_OUTSTANDING_REQUESTS       = 8;
    localparam int CFG_MAX_OUTSTANDING_LOADS_PER_WARP = 2;
    localparam int CFG_MSHR_ENTRIES                   = 4;
    localparam int CFG_INSTR_BUFFER_DEPTH             = 8;
    localparam int CFG_SIMT_STACK_DEPTH               = 16;

    // 6. TENSOR UNIT CONFIGURATION
    localparam int CFG_TENSOR_M            = 4;    // Matrix tile rows
    localparam int CFG_TENSOR_N            = 4;    // Matrix tile cols
    localparam int CFG_TENSOR_K            = 4;    // Matrix tile inner dim
    localparam int CFG_TENSOR_INPUT_BITS   = 16;   // FP16 input
    localparam int CFG_TENSOR_ACCUM_BITS   = 32;   // FP32 accumulator
    localparam int CFG_SPARSITY_RATIO      = 2;    // 2:4 (upgrade to 4:8 with new module)

    // MX Precision modes
    localparam int CFG_MX_BLOCK_SIZE       = 32;   // Elements per shared exponent block
    localparam int CFG_MX4_MANTISSA_BITS   = 3;    // 4-bit MX (1 sign + 3 mantissa)
    localparam int CFG_MX6_MANTISSA_BITS   = 5;    // 6-bit MX (1 sign + 5 mantissa)
    localparam int CFG_MX_EXPONENT_BITS    = 8;    // Shared exponent per block

    // 7. HBM3 MEMORY CONTROLLER
    localparam int CFG_HBM_STACKS             = 1;
    localparam int CFG_HBM_CHANNELS_PER_STACK = 2;
    localparam int CFG_HBM_ROW_BITS           = 10;
    localparam int CFG_HBM_COL_BITS           = 4;
    localparam int CFG_HBM_BANK_BITS          = 3;
    localparam int CFG_NUM_HBM_NODES          = 2;

    // 8. NETWORK-ON-CHIP (NoC) MESH
    localparam int CFG_NOC_FLIT_WIDTH       = 512;   // Wider flit for row-direction BW
    localparam int CFG_NOC_NUM_VCS          = 4;
    localparam int CFG_NOC_VC_ID_W          = 2;
    localparam int CFG_NOC_FLITS_PER_BUFFER = 8;
    localparam int CFG_NOC_NUM_PORTS        = 7;    // LOCAL + 6 directions

    // 9. TSV (THROUGH-SILICON VIA) CONFIGURATION
    localparam int CFG_TSV_DATA_WIDTH       = 1024;  // Bits per TSV bundle (wide for 6 TB/s target)
    localparam int CFG_TSV_LATENCY_CYCLES   = 1;     // Hybrid bonding, sub-cycle crossing
    localparam int CFG_TSV_BUNDLES_PER_CORE = 12;    // Dense TSV array per core column
    localparam int CFG_TSV_AGGREGATE_BW     = CFG_TSV_DATA_WIDTH * CFG_TSV_BUNDLES_PER_CORE;
    // 1024 × 12 = 12,288 bits/cycle → at 4 GHz = 6,144 GB/s ≈ 6 TB/s per core column

    // 10. MMU / TLB CONFIGURATION
    localparam int CFG_TLB_ENTRIES          = 64;   // TLB entry count
    localparam int CFG_PAGE_SIZE_BYTES      = 4096; // 4 KB pages
    localparam int CFG_PAGE_OFFSET_BITS     = 12;   // log2(4096)
    localparam int CFG_VIRTUAL_ADDR_BITS    = 48;   // 48-bit virtual address
    localparam int CFG_PHYSICAL_ADDR_BITS   = 40;   // 40-bit physical address
    localparam int CFG_PAGE_TABLE_LEVELS    = 4;    // 4-level page table

    // 11. CACHE COHERENCE
    localparam int CFG_DIRECTORY_ENTRIES    = 256;   // Coherence directory size
    localparam int CFG_SNOOP_FILTER_ENTRIES = 128;   // Snoop filter size
    localparam int CFG_COH_VC_ID           = 3;      // Dedicated coherence VC

    // 12. NEAR-MEMORY COMPUTE (NMC)
    localparam int CFG_NMC_ALU_COUNT       = 8;     // ALUs per NMC engine
    localparam int CFG_NMC_REDUCTION_WIDTH = 256;   // Bits processed per cycle
    localparam int CFG_NMC_QUEUE_DEPTH     = 8;     // Command queue depth

    // 13. HARDWARE COMMAND PROCESSOR
    localparam int CFG_HCP_MAX_TASKS       = 32;    // Max task graph nodes
    localparam int CFG_HCP_MAX_DEPS        = 4;     // Max dependencies per task
    localparam int CFG_HCP_CMD_WIDTH       = 128;   // Command descriptor width

    // 14. POWER & CLOCK MANAGEMENT
    localparam int CFG_CORE_FREQ_MHZ        = 4000;  // 4 GHz core clock
    localparam int CFG_CORE_PERIOD_PS       = 1000000 / CFG_CORE_FREQ_MHZ; // 250 ps
    localparam int CFG_NUM_CLUSTERS         = 1;
    localparam int CFG_CORES_PER_CLUSTER    = CFG_NUM_CORES;
    localparam int CFG_DVFS_SAMPLE_WINDOW   = 256;
    localparam int CFG_PWR_IDLE_CYCLES      = 16;
    localparam int CFG_PWR_SLEEP_CYCLES     = 256;

    // 15. PREFETCH ENGINE
    localparam int CFG_PREFETCH_STREAMS    = 4;
    localparam int CFG_PREFETCH_DISTANCE   = 4;

    // 16. DMA ENGINE
    localparam int CFG_DMA_DATA_WIDTH      = 64;
    localparam int CFG_DMA_BURST_SIZE      = 8;
    localparam int CFG_DMA_SRAM_ADDR_BITS  = 11;

    // 17. SIMULATION CONTROL
    localparam int CFG_SIM_TIMEOUT_CYCLES  = 500_000;
    localparam int CFG_VCD_DUMP_START      = 0;       // Cycle to start VCD
    localparam int CFG_VCD_DUMP_END        = 100_000;  // Cycle to stop VCD
    localparam int CFG_VCD_DUMP_LEVEL      = 0;       // 0=off, 1=top, 2=cores, 3=all

    // DERIVED PARAMETERS (do not modify directly)
    localparam int CFG_CORE_IDX_W = (CFG_NUM_CORES > 1) ? $clog2(CFG_NUM_CORES) : 1;
    localparam int CFG_WARP_IDX_W = (CFG_WARPS_PER_CORE > 1) ? $clog2(CFG_WARPS_PER_CORE) : 1;
    localparam int CFG_HBM_NODE_BASE = CFG_NUM_CORES - CFG_NUM_HBM_NODES;

    // Memory map
    localparam logic [21:0] CFG_L1_BASE = 22'h000000;
    localparam logic [21:0] CFG_L1_END  = 22'h07FFFF;
    localparam logic [21:0] CFG_L2_BASE = 22'h080000;
    localparam logic [21:0] CFG_L2_END  = 22'h1FFFFF;
    localparam logic [21:0] CFG_L3_BASE = 22'h200000;
    localparam logic [21:0] CFG_L3_END  = 22'h3FFFFF;

    // Coordinate helpers
    function automatic int cfg_coord_to_id(int x, int y, int z);
        cfg_coord_to_id = z * (CFG_CUBE_X * CFG_CUBE_Y) + y * CFG_CUBE_X + x;
    endfunction

    function automatic int cfg_id_to_x(int id);
        cfg_id_to_x = id % CFG_CUBE_X;
    endfunction

    function automatic int cfg_id_to_y(int id);
        cfg_id_to_y = (id / CFG_CUBE_X) % CFG_CUBE_Y;
    endfunction

    function automatic int cfg_id_to_z(int id);
        cfg_id_to_z = id / (CFG_CUBE_X * CFG_CUBE_Y);
    endfunction

endpackage
