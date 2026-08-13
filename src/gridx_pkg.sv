
`default_nettype none
`timescale 1ns/1ns

package gridxPkg;

    parameter int CUBE_X = 2;
    parameter int CUBE_Y = 2;
    parameter int CUBE_Z = 2;
    parameter int NUM_CORES = CUBE_X * CUBE_Y * CUBE_Z;
    parameter int WARPS_PER_CORE = 1;
    parameter int THREADS_PER_WARP = 4;
    parameter int THREADS_PER_CORE = WARPS_PER_CORE * THREADS_PER_WARP;
    parameter int TOTAL_THREADS = NUM_CORES * THREADS_PER_CORE;
    parameter int NUM_REGS = 16;
    parameter int REG_WIDTH = 16;

    parameter int L1_SIZE_KB = 32;
    parameter int L2_SLICE_KB = 2;
    parameter int L2_SLICES_PER_FACE = 16;
    parameter int L3_SHELL_KB = 512;

    parameter int DATA_MEM_ADDR_BITS = 22;
    parameter int DATA_MEM_DATA_BITS = 8;
    parameter int PROGRAM_MEM_ADDR_BITS = 12;
    parameter int PROGRAM_MEM_DATA_BITS = 16;
    parameter int MAX_OUTSTANDING_REQUESTS = 8;
    parameter int MAX_OUTSTANDING_LOADS_PER_WARP = 2;

    parameter int MSHR_ENTRIES = 4;

    parameter int PREFETCH_STREAMS = 2;
    parameter int PREFETCH_DISTANCE = 2;

    parameter int INSTR_BUFFER_DEPTH = 8;

    parameter int SIMT_STACK_DEPTH = 16;

    parameter int SPARSITY_RATIO = 2;

    typedef enum logic [1:0] {
        PREC_FP16    = 2'b00,
        PREC_FP8_E4M3 = 2'b01,
        PREC_FP8_E5M2 = 2'b10,
        PREC_INT8    = 2'b11
    } precisionModeE;

    parameter int EXPRESS_LINK_STRIDE = 4;
    parameter int EXPRESS_LINK_LATENCY = 2;

    parameter int NUM_CLUSTERS = 1;
    parameter int CORES_PER_CLUSTER = 8;
    parameter int DVFS_SAMPLE_WINDOW = 256;

    parameter int HBM_STACKS = 1;
    parameter int HBM_CHANNELS_PER_STACK = 2;
    parameter int HBM_ROW_BITS = 10;
    parameter int HBM_COL_BITS = 4;
    parameter int HBM_BANK_BITS = 3;

    parameter int UNIFIED_L1_KB = 64;
    parameter int UNIFIED_L1_DEFAULT_SHARED_KB = 48;
    parameter int UNIFIED_L1_DEFAULT_CACHE_KB = 16;

    typedef enum logic [3:0] {
        STATE_IDLE        = 4'b0000,
        STATE_FETCH       = 4'b0001,
        STATE_DECODE      = 4'b0010,
        STATE_ISSUE       = 4'b0011,
        STATE_EXECUTE     = 4'b0100,
        STATE_UPDATE      = 4'b0101,
        STATE_STALLED_MEM = 4'b0110,
        STATE_TENSOR_BUSY = 4'b0111,
        STATE_SLEEP       = 4'b1000,
        STATE_WAIT_REG    = 4'b1001,
        STATE_WAIT_MEM_Q  = 4'b1010,
        STATE_WAIT_BAR    = 4'b1011,
        STATE_WAIT_FENCE  = 4'b1100,
        STATE_DONE        = 4'b1111
    } coreStateE;

    typedef enum logic [1:0] {
        LSU_IDLE       = 2'b00,
        LSU_REQUESTING = 2'b01,
        LSU_WAITING    = 2'b10,
        LSU_DONE       = 2'b11
    } lsuStateE;

    typedef enum logic [2:0] {
        FETCH_IDLE     = 3'b000,
        FETCH_FETCHING = 3'b001,
        FETCH_FETCHED  = 3'b010
    } fetcherStateE;

    typedef enum logic [1:0] {
        POWER_SLEEP  = 2'b00,
        POWER_IDLE   = 2'b01,
        POWER_ACTIVE = 2'b10
    } powerStateE;

    typedef struct packed {
        logic [13:0] reserved;
        logic        isFence;
        logic        isSimtSync;
        logic        isBar;
        logic [3:0]  opcode;
        logic        tensorOp;
        logic        ret;
        logic        pcMux;
        logic        aluOutMux;
        logic [1:0]  aluArithMux;
        logic [1:0]  regMux;
        logic        nzpWe;
        logic        memWe;
        logic        memRe;
        logic        regWe;
        logic [2:0]  nzp;
        logic [3:0]  rd;
        logic [3:0]  rs;
        logic [3:0]  rt;
        logic [15:0] imm;
    } instrPacketT;

    typedef enum logic [3:0] {
        OP_NOP        = 4'b0000,
        OP_BRnzp      = 4'b0001,
        OP_CMP        = 4'b0010,
        OP_ADD        = 4'b0011,
        OP_SUB        = 4'b0100,
        OP_MUL        = 4'b0101,
        OP_DIV        = 4'b0110,
        OP_LDR        = 4'b0111,
        OP_STR        = 4'b1000,
        OP_CONST      = 4'b1001,
        OP_TILE_LD    = 4'b1010,
        OP_TILE_ST    = 4'b1011,
        OP_FENCE      = 4'b1100,
        OP_BAR        = 4'b1101,
        OP_TENSOR_MMA = 4'b1110,
        OP_RET        = 4'b1111
    } opcodeE;

    typedef enum logic [1:0] {
        ALU_ADD = 2'b00,
        ALU_SUB = 2'b01,
        ALU_MUL = 2'b10,
        ALU_DIV = 2'b11
    } aluOpE;

    typedef enum logic [1:0] {
        REG_MUX_ALU   = 2'b00,
        REG_MUX_MEM   = 2'b01,
        REG_MUX_CONST = 2'b10
    } regMuxE;

    typedef enum logic [2:0] {
        DIR_X_POS = 3'd0,
        DIR_X_NEG = 3'd1,
        DIR_Y_POS = 3'd2,
        DIR_Y_NEG = 3'd3,
        DIR_Z_POS = 3'd4,
        DIR_Z_NEG = 3'd5
    } directionE;

    parameter logic [21:0] L1_BASE = 22'h000000;
    parameter logic [21:0] L1_END  = 22'h07FFFF;
    parameter logic [21:0] L2_BASE = 22'h080000;
    parameter logic [21:0] L2_END  = 22'h1FFFFF;
    parameter logic [21:0] L3_BASE = 22'h200000;
    parameter logic [21:0] L3_END  = 22'h3FFFFF;

    typedef enum logic [2:0] {
        gc6Active      = 3'h0,
        GC6_PRE_SLEEP   = 3'h1,
        GC6_DRAIN       = 3'h2,
        gc6PoweredOff = 3'h3,
        GC6_WAKING      = 3'h4,
        GC6_RESTORING   = 3'h5
    } gc6StateT;

    typedef enum logic [0:0] {
        GC6_RETENTION_OFF = 1'b0,
        GC6_RETENTION_ON  = 1'b1
    } gc6RetentionT;

    typedef enum logic [1:0] {
        FAULT_READ    = 2'h0,
        FAULT_WRITE   = 2'h1,
        FAULT_EXECUTE = 2'h2,
        FAULT_ATOMIC  = 2'h3
    } faultTypeT;

    typedef enum logic [1:0] {
        FAULT_MODE_FATAL   = 2'h0,
        FAULT_MODE_RECOVER = 2'h1,
        FAULT_MODE_BOTH    = 2'h2
    } faultModeT;

    typedef struct packed {
        logic [31:0]  faultAddr;
        faultTypeT  faultType;
        logic [4:0]   warpId;
        logic [3:0]   coreId;
        logic [5:0]   threadMask;
        logic         overflow;
    } faultRecordT;

    typedef enum logic [0:0] {
        PREEMPT_INTER_BLOCK = 1'b0,
        PREEMPT_MID_WARP    = 1'b1
    } preemptModeT;

    typedef enum logic [1:0] {
        CH_PRI_0 = 2'h0,
        CH_PRI_1 = 2'h1,
        CH_PRI_2 = 2'h2,
        CH_PRI_3 = 2'h3
    } chPriorityT;

    typedef enum logic [1:0] {
        CH_IDLE      = 2'h0,
        CH_RUNNABLE  = 2'h1,
        CH_RUNNING   = 2'h2,
        CH_PREEMPTED = 2'h3
    } chStateT;

    typedef enum logic [1:0] {
        PERF_P0 = 2'h0,
        PERF_P1 = 2'h1,
        PERF_P2 = 2'h2,
        PERF_P3 = 2'h3
    } perfLevelT;

    // PERF_P8 alias: maps to deepest throttle state (same as PERF_P3)
    localparam perfLevelT PERF_P8 = PERF_P3;

    function automatic logic [1:0] perfDutyNum(perfLevelT lvl);
        case (lvl)
            PERF_P0: perfDutyNum = 2'd3;
            PERF_P1: perfDutyNum = 2'd2;
            PERF_P2: perfDutyNum = 2'd1;
            PERF_P3: perfDutyNum = 2'd0;
            default: perfDutyNum = 2'd3;
        endcase
    endfunction

    typedef enum logic [2:0] {
        KERN_IDLE     = 3'h0,
        KERN_LOADING  = 3'h1,
        KERN_RUNNING  = 3'h2,
        KERN_PREEMPT  = 3'h3,
        KERN_DRAINING = 3'h4,
        KERN_DONE     = 3'h5,
        KERN_FAULT    = 3'h6
    } kernStateT;

    localparam logic [15:0] DCR_KERN_WATCHDOG_THRESH = 16'h0000;
    localparam logic [15:0] DCR_KERN_FORCE_PREEMPT   = 16'h0001;
    localparam logic [15:0] DCR_KERN_STATUS          = 16'h0002;

    localparam logic [15:0] DCR_GC6_ENTER_REQ        = 16'h0010;
    localparam logic [15:0] DCR_GC6_EXIT_REQ         = 16'h0011;
    localparam logic [15:0] DCR_GC6_RETENTION        = 16'h0012;
    localparam logic [15:0] DCR_GC6_WATCHDOG_THRESH  = 16'h0013;
    localparam logic [15:0] DCR_GC6_STATUS           = 16'h0014;

    localparam logic [15:0] DCR_FAULT_MODE           = 16'h0020;
    localparam logic [15:0] DCR_FAULT_FIFO_DEPTH     = 16'h0021;
    localparam logic [15:0] DCR_FAULT_DROP_COUNT     = 16'h0022;
    localparam logic [15:0] DCR_FAULT_CLEAR          = 16'h0023;
    localparam logic [15:0] DCR_FAULT_HEAD           = 16'h0024;
    localparam logic [15:0] DCR_FAULT_HEAD_META      = 16'h0025;

    localparam logic [15:0] DCR_CH_TIMESLICE_P0      = 16'h0030;
    localparam logic [15:0] DCR_CH_TIMESLICE_P1      = 16'h0031;
    localparam logic [15:0] DCR_CH_TIMESLICE_P2      = 16'h0032;
    localparam logic [15:0] DCR_CH_TIMESLICE_P3      = 16'h0033;
    localparam logic [15:0] DCR_CH_AGING_THRESH      = 16'h0034;
    localparam logic [15:0] DCR_CH_STATUS            = 16'h0035;

    localparam logic [15:0] DCR_PERF_FORCE_LEVEL     = 16'h0040;
    localparam logic [15:0] DCR_PERF_FORCE_EN        = 16'h0041;
    localparam logic [15:0] DCR_PERF_UP_THRESH       = 16'h0042;
    localparam logic [15:0] DCR_PERF_DOWN_THRESH     = 16'h0043;
    localparam logic [15:0] DCR_PERF_SAMPLE_WIN      = 16'h0044;
    localparam logic [15:0] DCR_PERF_STATUS          = 16'h0045;

    localparam int FAULT_FIFO_DEPTH_DEFAULT = 4;
    localparam int CH_COUNT                 = 4;
    localparam int CORE_COUNT               = NUM_CORES;
    localparam int GC6_WAKE_WATCHDOG_DEF    = 1024;

    function automatic int coordToId(int x, int y, int z);
        coordToId = z * (CUBE_X * CUBE_Y) + y * CUBE_X + x;
    endfunction

    function automatic int idToX(int id);
        idToX = id % CUBE_X;
    endfunction

    function automatic int idToY(int id);
        idToY = (id / CUBE_X) % CUBE_Y;
    endfunction

    function automatic int idToZ(int id);
        idToZ = id / (CUBE_X * CUBE_Y);
    endfunction

    function automatic logic isSurfaceCore(int id);
        int x, y, z;
        x = idToX(id);
        y = idToY(id);
        z = idToZ(id);
        isSurfaceCore = (x == 0) || (x == CUBE_X-1) ||
               (y == 0) || (y == CUBE_Y-1) ||
               (z == 0) || (z == CUBE_Z-1);
    endfunction

    function automatic int getFaceId(int coreId);
        int x, y, z;
        x = idToX(coreId);
        y = idToY(coreId);
        z = idToZ(coreId);
        if (z == 0)           getFaceId = 5;
        else if (z == CUBE_Z-1)    getFaceId = 4;
        else if (y == 0)           getFaceId = 3;
        else if (y == CUBE_Y-1)    getFaceId = 2;
        else if (x == 0)           getFaceId = 1;
        else if (x == CUBE_X-1)    getFaceId = 0;
        else                       getFaceId = 0;
    endfunction

endpackage



