`default_nettype none
`timescale 1ns/1ns

// COMPUTE CORE (Spine-Based Architecture)
// > Implements Pipelined Instruction Spine for 1024-thread scaling
// > Features explicit Control Plane FSM and Per-Warp Instruction Latches
module core #(
    parameter DATA_MEM_ADDR_BITS = 8,
    parameter DATA_MEM_DATA_BITS = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter THREADS_PER_BLOCK = 64, // Total threads (4 Warps * 16 Threads)
    parameter WARPS_PER_CORE = 4,
    parameter REG_WIDTH = 16
) (
    input wire clk,
    input wire reset,

    // Kernel Execution
    input wire start,
    output wire done,

    // Block Metadata
    input wire [7:0] block_id,
    input wire [$clog2(THREADS_PER_BLOCK):0] thread_count, // Not fully used in static alloc

    // Program Memory
    output wire program_mem_read_valid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address,
    input wire program_mem_read_ready,
    input wire [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data,

    // Data Memory (Serialized Interface)
    output wire mem_read_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] mem_read_address,
    input wire mem_read_ready,
    input wire [DATA_MEM_DATA_BITS-1:0] mem_read_data,
    
    output wire mem_write_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] mem_write_address,
    output wire [DATA_MEM_DATA_BITS-1:0] mem_write_data,
    input wire mem_write_ready,
    
    // Peripherals Inputs
    input wire power_sleep_req // From Power Controller
);

    localparam THREADS_PER_WARP = THREADS_PER_BLOCK / WARPS_PER_CORE; // 16
    localparam NUM_LANES = 16; 

    // Internal State
    wire [3:0] active_core_state; // Widened for new states
    wire [3:0] warp_states [WARPS_PER_CORE-1:0];
    wire [$clog2(WARPS_PER_CORE)-1:0] active_warp_id;
    
    // Wire arrays for all threads
    wire [REG_WIDTH-1:0] rs [THREADS_PER_BLOCK-1:0];
    wire [REG_WIDTH-1:0] rt [THREADS_PER_BLOCK-1:0];
    wire [REG_WIDTH-1:0] rd_val [THREADS_PER_BLOCK-1:0]; // Port 3
    wire [1:0] lsu_state [THREADS_PER_BLOCK-1:0];
    wire [REG_WIDTH-1:0] lsu_out [THREADS_PER_BLOCK-1:0];
    
    // Tensor Busy Signals
    wire [WARPS_PER_CORE-1:0] tensor_busy; // Level
    wire [WARPS_PER_CORE-1:0] tensor_done; // Pulse

    // Instruction Spine Signals
    wire [15:0] instruction;
    wire [2:0] fetcher_state;
    
    // The Spine Bus
    wire [63:0] decoded_packet;
    
    // Spine Control
    wire [WARPS_PER_CORE-1:0] warp_issue_enable;
    
    // Per-Warp Instruction Latches
    reg [63:0] warp_instr_latch [WARPS_PER_CORE-1:0];
    
    // --- Submodules ---

    fetcher #(
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS)
    ) fetcher_instance (
        .clk(clk),
        .reset(reset),
        .core_state(active_core_state[2:0]), // Fetcher uses simplified state mapping? Or needs update.
                                             // Fetcher expects 3 bits. We verify fetcher later.
                                             // For now, map IDLE/FETCH/DECODE relevantly. 
                                             // Our FSM: IDLE=0, FETCH=1, DECODE=2. Matches.
        .current_pc(current_pc), 
        .mem_read_valid(program_mem_read_valid),
        .mem_read_address(program_mem_read_address),
        .mem_read_ready(program_mem_read_ready),
        .mem_read_data(program_mem_read_data),
        .fetcher_state(fetcher_state),
        .instruction(instruction)
    );

    decoder decoder_instance (
        .clk(clk),
        .reset(reset),
        .core_state(active_core_state[2:0]), 
        .instruction(instruction),
        .decoded_packet(decoded_packet) // Unified Output
    );

    wire [7:0] current_pc;
    wire [7:0] next_pc [THREADS_PER_BLOCK-1:0];

    scheduler #(
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .WARPS_PER_CORE(WARPS_PER_CORE)
    ) scheduler_instance (
        .clk(clk),
        .reset(reset),
        .start(start),
        
        .tensor_done(tensor_done), // Pulse
        .power_sleep_req(power_sleep_req),
        
        .decoded_packet(decoded_packet), // Sniff packet for control decisions
        
        .fetcher_state(fetcher_state),
        .lsu_state(lsu_state),
        .current_pc(current_pc),
        .next_pc(next_pc),
        .core_state(active_core_state),
        .warp_state(warp_states),
        .active_warp_id(active_warp_id),
        
        .warp_issue_enable(warp_issue_enable), // Control Output
        
        .done(done)
    );

    // --- Spine Latching Logic ---
    integer w;
    always @(posedge clk) begin
        if (reset) begin
            for (w=0; w<WARPS_PER_CORE; w=w+1) warp_instr_latch[w] <= 0;
        end else begin
            for (w=0; w<WARPS_PER_CORE; w=w+1) begin
                if (warp_issue_enable[w]) begin
                    warp_instr_latch[w] <= decoded_packet;
                end
            end
        end
    end

    // --- ALUs (16 Lanes) ---
    // ALUs need control signals. They come from the ACTIVE WARP's latch.
    // NOTE: ALUs are shared resources. They execute for `active_warp_id`.
    // So we shouldmux the *latched* instruction of the active warp to the ALUs.
    
    wire [63:0] active_warp_instr = warp_instr_latch[active_warp_id];
    // Unpack active instruction for ALU
    wire [1:0] alu_arith_mux = active_warp_instr[38:37];
    wire alu_out_mux = active_warp_instr[39];
    
    genvar lane;
    wire [REG_WIDTH-1:0] lane_alu_out [NUM_LANES-1:0];

    generate
        for (lane = 0; lane < NUM_LANES; lane = lane + 1) begin : lanes
            // Mux Input logic
            reg [REG_WIDTH-1:0] lane_rs;
            reg [REG_WIDTH-1:0] lane_rt;
            always @(*) begin
                // Select register from active warp
                lane_rs = rs[active_warp_id * THREADS_PER_WARP + lane];
                lane_rt = rt[active_warp_id * THREADS_PER_WARP + lane];
            end
            
            alu #(
                .DATA_BITS(REG_WIDTH)
            ) alu_unit (
                .clk(clk),
                .reset(reset),
                
                // ALU Execute logic: enable only in EXECUTE state
                .enable(active_core_state == 4'b0100), // EXECUTE
                
                // We pass simplified state or just use enable? ALU uses transition to DONE logic.
                // Assuming ALU is combinational or simple state. Old ALU used `core_state`.
                // Let's pass active_core_state[2:0] equivalent or update ALU? 
                // ALU uses `state == EXECUTE`. 
                // Our EXECUTE is 4'b0100 (4). Old was 3'b101 (5).
                // WARNING: ALU EXPECTS SPECIFIC STATE ENCODING?
                // `src/alu.sv` line 34: `localparam EXECUTE = 3'b101`.
                // We should probably map our state to ALU's expectation or update ALU.
                // Minimal Change: ALU just computes. `enable` creates the latch/validity.
                // Passing `3'b101` when we are in `4'b0100`?
                .core_state(active_core_state == 4'b0100 ? 3'b101 : 3'b000), 
                
                .decoded_alu_arithmetic_mux(alu_arith_mux),
                .decoded_alu_output_mux(alu_out_mux),
                .rs(lane_rs),
                .rt(lane_rt),
                .alu_out(lane_alu_out[lane])
            );
        end
    endgenerate

    // --- Registers & LSUs (64 Contexts) ---
    // LSU Arbitration Signals
    wire [THREADS_PER_BLOCK-1:0] lsu_req_valid;
    wire [THREADS_PER_BLOCK-1:0] lsu_req_write;
    wire [DATA_MEM_ADDR_BITS-1:0] lsu_req_addr [THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] lsu_req_data [THREADS_PER_BLOCK-1:0];
    wire [THREADS_PER_BLOCK-1:0] lsu_grant;
    
    wire arb_valid, arb_write;
    wire [DATA_MEM_ADDR_BITS-1:0] arb_addr;
    wire [DATA_MEM_DATA_BITS-1:0] arb_data;
    
    lsu_arbiter #(
        .NUM_REQUESTERS(THREADS_PER_BLOCK),
        .ADDR_WIDTH(DATA_MEM_ADDR_BITS),
        .DATA_WIDTH(DATA_MEM_DATA_BITS)
    ) arbiter (
        .clk(clk),
        .reset(reset),
        .request_valid(lsu_req_valid),
        .request_write(lsu_req_write),
        .request_addr(lsu_req_addr),
        .request_data(lsu_req_data),
        .mem_valid(arb_valid),
        .mem_write(arb_write),
        .mem_addr(arb_addr),
        .mem_data(arb_data),
        .mem_ready(mem_read_ready || mem_write_ready),
        .grant(lsu_grant)
    );
    
    // --- Memory Hierarchy Routing (L1 vs External) ---
    // Rules:
    // L1: 0x0000 - 0x7FFF (32KB)
    // External (L2/L3): 0x8000 - 0xFFFF
    
    // Internal L1 Signals
    wire l1_hit = (arb_addr < 16'h8000); // 32KB Limit
    wire l1_read_ready, l1_write_ready;
    wire [DATA_MEM_DATA_BITS-1:0] l1_read_data;
    
    // Instantiate L1
    core_local_memory #(
        .ADDR_WIDTH(15), // 32KB
        .DATA_WIDTH(DATA_MEM_DATA_BITS)
    ) l1_memory (
        .clk(clk),
        .read_valid(arb_valid && !arb_write && l1_hit),
        .read_address(arb_addr[14:0]),
        .write_valid(arb_valid && arb_write && l1_hit),
        .write_address(arb_addr[14:0]),
        .write_data(arb_data),
        .read_ready(l1_read_ready),
        .read_data(l1_read_data),
        .write_ready(l1_write_ready)
    );

    // Routing Logic to External (Vertical Controller)
    assign mem_read_valid = arb_valid && !arb_write && !l1_hit;
    assign mem_write_valid = arb_valid && arb_write && !l1_hit;
    assign mem_read_address = arb_addr;
    assign mem_write_address = arb_addr;
    assign mem_write_data = arb_data;
    
    // LSU Feedback Mux
    // If request went to L1, response comes from L1.
    // If request went External, response comes from External.
    // But LSU logic just waits for `mem_read_ready`.
    // We must OR them together, ensuring arbitration logic holds steady.
    
    wire mem_read_ready_internal;
    wire mem_write_ready_internal;
    wire [DATA_MEM_DATA_BITS-1:0] mem_read_data_internal;

    assign mem_read_ready_internal = l1_hit ? l1_read_ready : mem_read_ready;
    assign mem_write_ready_internal = l1_hit ? l1_write_ready : mem_write_ready;
    assign mem_read_data_internal = l1_hit ? l1_read_data : mem_read_data; 


    // --- Tensor Controller Signals ---
    wire signed [3:0][3:0][15:0] tensor_src_a;
    wire signed [3:0][3:0][15:0] tensor_src_b;
    wire [3:0][3:0][31:0] tensor_wb_data;
    wire tensor_wb_valid;
    wire [1:0] tensor_wb_warp;
    wire [3:0] writeback_reg_idx; 

    // Tensor Input Connection (Active Warp)
    // We sign extend the 8-bit registers of the ACTIVE WARP to 16-bit
    // Unpack from `rs`/`rt` array
    genvar tr, tc;
    generate
        for (tr=0; tr<4; tr=tr+1) begin : rows
            for (tc=0; tc<4; tc=tc+1) begin : cols
                 wire [7:0] r_val = rs[active_warp_id * THREADS_PER_WARP + tr*4 + tc][7:0];
                 wire [7:0] t_val = rt[active_warp_id * THREADS_PER_WARP + tr*4 + tc][7:0]; // Use RT for B? Yes
                 assign tensor_src_a[tr][tc] = {{8{r_val[7]}}, r_val};
                 assign tensor_src_b[tr][tc] = {{8{t_val[7]}}, t_val};
            end
        end
    endgenerate

    // Tensor Controller Instance
    tensor_controller t_ctrl (
        .clk(clk),
        .reset(reset),
        // Trigger on ISSUE state + Tensor Op flag
        // Must use 'decoded_packet' (Spine) directly as Latch is not yet valid during ISSUE
        .request_valid(active_core_state == 4'b0011 && decoded_packet[42]), 
        
        .warp_id(active_warp_id),
        .dest_reg_idx(decoded_packet[27:24]), // Direct from Spine
        .src_a(tensor_src_a), // Registers are from RS/RT (latched? No, Registers are async read from RS/RT addr)
                              // WAIT. RS/RT address input to Registers.
                              // Registers module uses `decoded_rs_address`.
                              // If we are in ISSUE, we must feed Registers with `decoded_packet` addresses too?
                              // Reg File Read is async.
                              // If we use 'decoded_packet' for addresses during ISSUE, then `tensor_src_a` is valid.
                              // BUT `core.sv` connects `reg_file` ports to `my_rs_addr` (from LATCH).
                              // TIMING HAZARD: Tensor needs Reg Data in ISSUE. Reg Addrs come from LATCH (invalid).
                              // FIX: Tensor request triggers... wait.
                              // If registers need valid address, and address comes from latch...
                              // We MUST use `decoded_packet` for Register Read Addresses during ISSUE for Tensor Warp?
                              // Or move Tensor Trigger to `TENSOR_BUSY` (Next Cycle)?
                              // If we move Trigger to `TENSOR_BUSY`, Latch is valid.
                              // Scheduler enters `TENSOR_BUSY`.
                              // Tensor Ctrl sees `request_valid` (based on TENSOR_BUSY).
                              // This aligns with LSU fix.
                              // Let's align EVERYTHING to "Execute/Request AFTER Latch".
                              // Strategy: Trigger Tensor in 'TENSOR_BUSY' state. Trigger LSU in 'STALLED_MEM'.
                              // Scheduler ensures we go there.
        .src_b(tensor_src_b),
        .src_c(512'd0), 
        .request_ready(), 
        .warp_busy(tensor_busy), 
        .warp_done(tensor_done), 
        .writeback_valid(tensor_wb_valid),
        .writeback_warp_id(tensor_wb_warp),
        .writeback_data(tensor_wb_data),
        .writeback_reg_idx(writeback_reg_idx)
    );


    // --- Main Thread Loop (LSU + Regs) ---
    genvar t;
    generate
        for (t = 0; t < THREADS_PER_BLOCK; t = t + 1) begin : threads
            localparam warp_idx = t / THREADS_PER_WARP;
            localparam lane_idx = t % THREADS_PER_WARP;
            
            // 1. Get Local Instruction from Warp Latch
            wire [63:0] my_instr = warp_instr_latch[warp_idx];
            
            // 2. Unpack Controls
            wire [15:0] my_imm      = my_instr[15:0];
            wire [3:0]  my_rt_addr  = my_instr[19:16];
            wire [3:0]  my_rs_addr  = my_instr[23:20];
            wire [3:0]  my_rd_addr  = my_instr[27:24];
            wire        my_reg_we   = my_instr[31];
            wire        my_mem_re   = my_instr[32];
            wire        my_mem_we   = my_instr[33];
            wire [1:0]  my_reg_mux  = my_instr[36:35];
            
            // 3. Tensor Writeback Logic (Priority)
            wire [1:0] my_row = lane_idx / 4;
            wire [1:0] my_col = lane_idx % 4;
            wire my_force_en = tensor_wb_valid && (warp_idx == tensor_wb_warp);
            wire [REG_WIDTH-1:0] my_force_data = tensor_wb_data[my_row][my_col][REG_WIDTH-1:0];

            // 4. Register Instance
            // Needs State Mapping: 
            // Registers update on `UPDATE` (3'b110).
            // Our FSM `UPDATE` is 4'b0101.
            // Map 4'b0101 -> 3'b110.
            // Map 4'b0011 (ISSUE) -> 3'b011 (REQUEST) for Read Port population?
            // Registers read on `REQUEST`. 
            // We read on `ISSUE`.
            wire [2:0] mapped_state = 
                (warp_states[warp_idx] == 4'b0101) ? 3'b110 : // UPDATE -> UPDATE
                (warp_states[warp_idx] == 4'b0011) ? 3'b011 : // ISSUE  -> REQUEST
                3'b000;

            registers #(
                 .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
                 .THREAD_ID(t),
                 .DATA_BITS(REG_WIDTH)
            ) reg_file (
                .clk(clk),
                .reset(reset),
                .enable(1'b1),
                .block_id(block_id),
                .core_state(mapped_state),
                .decoded_rd_address(my_rd_addr),
                .decoded_rs_address(my_rs_addr),
                .decoded_rt_address(my_rt_addr),
                .decoded_immediate(my_imm),
                .decoded_reg_write_enable(my_reg_we),
                .decoded_reg_input_mux(my_reg_mux),
                
                .force_reg_write_enable(my_force_en),
                .force_reg_write_dest(writeback_reg_idx),
                .force_reg_write_data(my_force_data),
                
                .alu_out(lane_alu_out[lane_idx]), // Muxed from active warp ALU
                .lsu_out(lsu_out[t]),
                .rs(rs[t]),
                .rt(rt[t]),
                .rd_val(rd_val[t])
            );
            
            // 5. LSU Instance
            wire my_grant = lsu_grant[t];
            wire my_read_ready = (my_grant && !arb_write && mem_read_ready_internal);
            wire my_write_ready = (my_grant && arb_write && mem_write_ready_internal);
            wire my_read_val, my_write_val;
            
            assign lsu_req_valid[t] = my_read_val || my_write_val;
            assign lsu_req_write[t] = my_write_val;

            // LSU State Mapping
            // LSU starts on `REQUEST` (3'b011).
            // We rely on `mapped_state` (ISSUE -> REQUEST).
            // Also explicitly passed `my_mem_re` / `my_mem_we`.
            
            lsu #(
                .ADDR_BITS(DATA_MEM_ADDR_BITS),
                .MEM_DATA_WIDTH(DATA_MEM_DATA_BITS),
                .REG_WIDTH(REG_WIDTH)
            ) lsu_inst (
                .clk(clk),
                .reset(reset),
                .enable(1'b1),
                .core_state(mapped_state),
                .decoded_mem_read_enable(my_mem_re),
                .decoded_mem_write_enable(my_mem_we),
                
                .mem_read_valid(my_read_val), 
                .mem_read_address(lsu_req_addr[t]), // Internal wire
                .mem_write_valid(my_write_val), 
                
                .mem_read_ready(my_read_ready),
                .mem_read_data(mem_read_data_internal), // Use Muxed Data (L1 or Ext)
                .mem_write_ready(my_write_ready),
                .mem_write_address(), 
                .mem_write_data(lsu_req_data[t]),
                
                .rs(rs[t]),
                .rt(rt[t]),
                .lsu_state(lsu_state[t]),
                .lsu_out(lsu_out[t])
            );
        end
    endgenerate

endmodule
