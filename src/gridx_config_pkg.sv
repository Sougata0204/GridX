
`default_nettype none
`timescale 1ns/1ns

// GridX configuration package defining compile-time parameters for cube geometry, memory sizes, and feature enables.
package gridxConfigPkg;

    localparam int CFG_CUBE_X = 2;
    localparam int CFG_CUBE_Y = 2;
    localparam int CFG_CUBE_Z = 2;
    localparam int CFG_NUM_CORES = CFG_CUBE_X * CFG_CUBE_Y * CFG_CUBE_Z;

    localparam int CFG_WARPS_PER_CORE    = 4;
    localparam int CFG_THREADS_PER_WARP  = 4;
    localparam int CFG_THREADS_PER_CORE  = CFG_WARPS_PER_CORE * CFG_THREADS_PER_WARP;
    localparam int CFG_TOTAL_THREADS     = CFG_NUM_CORES * CFG_THREADS_PER_CORE;
    localparam int CFG_NUM_REGS          = 16;
    localparam int CFG_REG_WIDTH         = 16;

    localparam int CFG_DATA_MEM_ADDR_BITS    = 22;
    localparam int CFG_DATA_MEM_DATA_BITS    = 8;
    localparam int CFG_PROGRAM_MEM_ADDR_BITS = 12;
    localparam int CFG_PROGRAM_MEM_DATA_BITS = 16;
    localparam int CFG_PMEM_DEPTH            = 4096;
    localparam int CFG_DMEM_DEPTH            = 4096;

    localparam int CFG_L1_SIZE_KB             = 32;
    localparam int CFG_L2_SLICE_KB            = 2;
    localparam int CFG_L2_SLICES_PER_FACE     = 16;
    localparam int CFG_L3_SHELL_KB            = 512;
    localparam int CFG_UNIFIED_L1_KB          = 64;
    localparam int CFG_UNIFIED_L1_SHARED_KB   = 48;
    localparam int CFG_UNIFIED_L1_CACHE_KB    = 16;

    localparam int CFG_MAX_OUTSTANDING_REQUESTS       = 8;
    localparam int CFG_MAX_OUTSTANDING_LOADS_PER_WARP = 2;
    localparam int CFG_MSHR_ENTRIES                   = 4;
    localparam int CFG_INSTR_BUFFER_DEPTH             = 8;
    localparam int CFG_SIMT_STACK_DEPTH               = 16;

    localparam int CFG_TENSOR_M            = 4;
    localparam int CFG_TENSOR_N            = 4;
    localparam int CFG_TENSOR_K            = 4;
    localparam int CFG_TENSOR_INPUT_BITS   = 16;
    localparam int CFG_TENSOR_ACCUM_BITS   = 32;
    localparam int CFG_SPARSITY_RATIO      = 2;

    localparam int CFG_MX_BLOCK_SIZE       = 32;
    localparam int CFG_MX4_MANTISSA_BITS   = 3;
    localparam int CFG_MX6_MANTISSA_BITS   = 5;
    localparam int CFG_MX_EXPONENT_BITS    = 8;

    localparam int CFG_HBM_STACKS             = 1;
    localparam int CFG_HBM_CHANNELS_PER_STACK = 2;
    localparam int CFG_HBM_ROW_BITS           = 10;
    localparam int CFG_HBM_COL_BITS           = 4;
    localparam int CFG_HBM_BANK_BITS          = 3;
    localparam int CFG_NUM_HBM_NODES          = 2;

    localparam int CFG_NOC_FLIT_WIDTH       = 512;
    localparam int CFG_NOC_NUM_VCS          = 4;
    localparam int CFG_NOC_VC_ID_W          = 2;
    localparam int CFG_NOC_FLITS_PER_BUFFER = 8;
    localparam int CFG_NOC_NUM_PORTS        = 7;

    localparam int CFG_TSV_DATA_WIDTH       = 1024;
    localparam int CFG_TSV_LATENCY_CYCLES   = 1;
    localparam int CFG_TSV_BUNDLES_PER_CORE = 12;
    localparam int CFG_TSV_AGGREGATE_BW     = CFG_TSV_DATA_WIDTH * CFG_TSV_BUNDLES_PER_CORE;

    localparam int CFG_TLB_ENTRIES          = 64;
    localparam int CFG_PAGE_SIZE_BYTES      = 4096;
    localparam int CFG_PAGE_OFFSET_BITS     = 12;
    localparam int CFG_VIRTUAL_ADDR_BITS    = 48;
    localparam int CFG_PHYSICAL_ADDR_BITS   = 40;
    localparam int CFG_PAGE_TABLE_LEVELS    = 4;

    localparam int CFG_DIRECTORY_ENTRIES    = 256;
    localparam int CFG_SNOOP_FILTER_ENTRIES = 128;
    localparam int CFG_COH_VC_ID           = 3;

    localparam int CFG_NMC_ALU_COUNT       = 8;
    localparam int CFG_NMC_REDUCTION_WIDTH = 256;
    localparam int CFG_NMC_QUEUE_DEPTH     = 8;

    localparam int CFG_HCP_MAX_TASKS       = 32;
    localparam int CFG_HCP_MAX_DEPS        = 4;
    localparam int CFG_HCP_CMD_WIDTH       = 128;

    localparam int CFG_CORE_FREQ_MHZ        = 4000;
    localparam int CFG_CORE_PERIOD_PS       = 1000000 / CFG_CORE_FREQ_MHZ;
    localparam int CFG_NUM_CLUSTERS         = 1;
    localparam int CFG_CORES_PER_CLUSTER    = CFG_NUM_CORES;
    localparam int CFG_DVFS_SAMPLE_WINDOW   = 256;
    localparam int CFG_PWR_IDLE_CYCLES      = 16;
    localparam int CFG_PWR_SLEEP_CYCLES     = 256;

    localparam int CFG_PREFETCH_STREAMS    = 4;
    localparam int CFG_PREFETCH_DISTANCE   = 4;

    localparam int CFG_DMA_DATA_WIDTH      = 64;
    localparam int CFG_DMA_BURST_SIZE      = 8;
    localparam int CFG_DMA_SRAM_ADDR_BITS  = 11;

    localparam int CFG_SIM_TIMEOUT_CYCLES  = 500_000;
    localparam int CFG_VCD_DUMP_START      = 0;
    localparam int CFG_VCD_DUMP_END        = 100_000;
    localparam int CFG_VCD_DUMP_LEVEL      = 0;

    localparam int CFG_CORE_IDX_W = (CFG_NUM_CORES > 1) ? $clog2(CFG_NUM_CORES) : 1;
    localparam int CFG_WARP_IDX_W = (CFG_WARPS_PER_CORE > 1) ? $clog2(CFG_WARPS_PER_CORE) : 1;
    localparam int CFG_HBM_NODE_BASE = CFG_NUM_CORES - CFG_NUM_HBM_NODES;

    localparam logic [21:0] CFG_L1_BASE = 22'h000000;
    localparam logic [21:0] CFG_L1_END  = 22'h07FFFF;
    localparam logic [21:0] CFG_L2_BASE = 22'h080000;
    localparam logic [21:0] CFG_L2_END  = 22'h1FFFFF;
    localparam logic [21:0] CFG_L3_BASE = 22'h200000;
    localparam logic [21:0] CFG_L3_END  = 22'h3FFFFF;

    function automatic int cfgCoordToId(int x, int y, int z);
        cfgCoordToId = z * (CFG_CUBE_X * CFG_CUBE_Y) + y * CFG_CUBE_X + x;
    endfunction

    function automatic int cfgIdToX(int id);
        cfgIdToX = id % CFG_CUBE_X;
    endfunction

    function automatic int cfgIdToY(int id);
        cfgIdToY = (id / CFG_CUBE_X) % CFG_CUBE_Y;
    endfunction

    function automatic int cfgIdToZ(int id);
        cfgIdToZ = id / (CFG_CUBE_X * CFG_CUBE_Y);
    endfunction

endpackage
