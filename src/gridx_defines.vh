`ifndef GRIDX_DEFINES_VH
`define GRIDX_DEFINES_VH

`define CUBE_X 2
`define CUBE_Y 2
`define CUBE_Z 2
`define NUM_CORES (`CUBE_X * `CUBE_Y * `CUBE_Z)
`define WARPS_PER_CORE 1
`define THREADS_PER_WARP 4
`define THREADS_PER_CORE (`WARPS_PER_CORE * `THREADS_PER_WARP)
`define TOTAL_THREADS (`NUM_CORES * `THREADS_PER_CORE)
`define NUM_REGS 16
`define REG_WIDTH 16
`define L1_SIZE_KB 32
`define L2_SLICE_KB 2
`define L2_SLICES_PER_FACE 16
`define L3_SHELL_KB 512
`define DATA_MEM_ADDR_BITS 22
`define DATA_MEM_DATA_BITS 8
`define PROGRAM_MEM_ADDR_BITS 12
`define PROGRAM_MEM_DATA_BITS 16
`define MAX_OUTSTANDING_REQUESTS 8
`define MAX_OUTSTANDING_LOADS_PER_WARP 2

`define STATE_IDLE        4'b0000
`define STATE_FETCH       4'b0001
`define STATE_DECODE      4'b0010
`define STATE_ISSUE       4'b0011
`define STATE_EXECUTE     4'b0100
`define STATE_UPDATE      4'b0101
`define STATE_STALLED_MEM 4'b0110
`define STATE_TENSOR_BUSY 4'b0111
`define STATE_SLEEP       4'b1000
`define STATE_WAIT_REG    4'b1001
`define STATE_WAIT_MEM_Q  4'b1010
`define STATE_WAIT_BAR    4'b1011
`define STATE_DONE        4'b1111

`define LSU_IDLE       2'b00
`define LSU_REQUESTING 2'b01
`define LSU_WAITING    2'b10
`define LSU_DONE       2'b11

`define FETCH_IDLE     3'b000
`define FETCH_FETCHING 3'b001
`define FETCH_FETCHED  3'b010

`define POWER_SLEEP  2'b00
`define POWER_IDLE   2'b01
`define POWER_ACTIVE 2'b10

`define OP_NOP        4'b0000
`define OP_BRnzp      4'b0001
`define OP_CMP        4'b0010
`define OP_ADD        4'b0011
`define OP_SUB        4'b0100
`define OP_MUL        4'b0101
`define OP_DIV        4'b0110
`define OP_LDR        4'b0111
`define OP_STR        4'b1000
`define OP_CONST      4'b1001
`define OP_TILE_LD    4'b1010
`define OP_TILE_ST    4'b1011
`define OP_DMA_SYNC   4'b1100
`define OP_BAR        4'b1101
`define OP_TENSOR_MMA 4'b1110
`define OP_RET        4'b1111

`define ALU_ADD 2'b00
`define ALU_SUB 2'b01
`define ALU_MUL 2'b10
`define ALU_DIV 2'b11

`define REG_MUX_ALU   2'b00
`define REG_MUX_MEM   2'b01
`define REG_MUX_CONST 2'b10

`define DIR_X_POS 3'd0
`define DIR_X_NEG 3'd1
`define DIR_Y_POS 3'd2
`define DIR_Y_NEG 3'd3
`define DIR_Z_POS 3'd4
`define DIR_Z_NEG 3'd5

`define L1_BASE 22'h000000
`define L1_END  22'h07FFFF
`define L2_BASE 22'h080000
`define L2_END  22'h1FFFFF
`define L3_BASE 22'h200000
`define L3_END  22'h3FFFFF

`endif
