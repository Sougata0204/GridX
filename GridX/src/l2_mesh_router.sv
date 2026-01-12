`default_nettype none
`timescale 1ns/1ns

// L2 MESH ROUTER
// > A single node in the 4x4 L2 Mesh
// > Manages 1 Local Core connection
// > Manages 4 Neighbor connections (N/S/E/W)
// > Manages 1 Upstream Global connection
// > Contains 1 L2 Slice (1KB)
module l2_mesh_router #(
    parameter SLICE_ID = 0,         // My ID (0-15)
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8,
    parameter L2_BASE = 16'h8000
) (
    input wire clk,
    input wire reset,

    // --- Core Interface (Client) ---
    input wire c_req_valid,
    input wire c_req_write,
    input wire [ADDR_WIDTH-1:0] c_req_addr,
    input wire [DATA_WIDTH-1:0] c_req_wdata,
    output reg c_req_ready,
    output reg [DATA_WIDTH-1:0] c_req_rdata,

    // --- Neighbor Interfaces (Inbound Requests from Neighbors) ---
    // These neighbors want to access MY Local Slice
    input wire n_in_valid, input wire n_in_write, input wire [ADDR_WIDTH-1:0] n_in_addr, input wire [DATA_WIDTH-1:0] n_in_wdata, output wire n_in_ready, output wire [DATA_WIDTH-1:0] n_in_rdata,
    input wire s_in_valid, input wire s_in_write, input wire [ADDR_WIDTH-1:0] s_in_addr, input wire [DATA_WIDTH-1:0] s_in_wdata, output wire s_in_ready, output wire [DATA_WIDTH-1:0] s_in_rdata,
    input wire e_in_valid, input wire e_in_write, input wire [ADDR_WIDTH-1:0] e_in_addr, input wire [DATA_WIDTH-1:0] e_in_wdata, output wire e_in_ready, output wire [DATA_WIDTH-1:0] e_in_rdata,
    input wire w_in_valid, input wire w_in_write, input wire [ADDR_WIDTH-1:0] w_in_addr, input wire [DATA_WIDTH-1:0] w_in_wdata, output wire w_in_ready, output wire [DATA_WIDTH-1:0] w_in_rdata,

    // --- Neighbor Interfaces (Outbound Requests to Neighbors) ---
    // My Core wants to access THEIR Slice
    output wire n_out_valid, output wire n_out_write, output wire [ADDR_WIDTH-1:0] n_out_addr, output wire [DATA_WIDTH-1:0] n_out_wdata, input wire n_out_ready, input wire [DATA_WIDTH-1:0] n_out_rdata,
    output wire s_out_valid, output wire s_out_write, output wire [ADDR_WIDTH-1:0] s_out_addr, output wire [DATA_WIDTH-1:0] s_out_wdata, input wire s_out_ready, input wire [DATA_WIDTH-1:0] s_out_rdata,
    output wire e_out_valid, output wire e_out_write, output wire [ADDR_WIDTH-1:0] e_out_addr, output wire [DATA_WIDTH-1:0] e_out_wdata, input wire e_out_ready, input wire [DATA_WIDTH-1:0] e_out_rdata,
    output wire w_out_valid, output wire w_out_write, output wire [ADDR_WIDTH-1:0] w_out_addr, output wire [DATA_WIDTH-1:0] w_out_wdata, input wire w_out_ready, input wire [DATA_WIDTH-1:0] w_out_rdata,

    // --- Global Interface (Upstream) ---
    output wire g_out_valid, output wire g_out_write, output wire [ADDR_WIDTH-1:0] g_out_addr, output wire [DATA_WIDTH-1:0] g_out_wdata, input wire g_out_ready, input wire [DATA_WIDTH-1:0] g_out_rdata
);

    // ========================================================================
    // 1. ROUTING LOGIC (Core -> Target)
    // ========================================================================
    
    // Decode Target
    wire [15:0] dest_slice_id = (c_req_addr - L2_BASE) >> 10;
    wire is_l2_access = (c_req_addr >= L2_BASE && c_req_addr < 16'hC000);
    wire is_global = (c_req_addr >= 16'hC000);
    
    // Determine Direction
    // Mesh ID = (Row * 4) + Col.
    // Neighbors: +/-1 (E/W), +/-4 (S/N)
    
    // Note: This logic assumes "My ID" is correct context.
    // SLICE_ID is parameter.
    
    wire target_is_local = is_l2_access && (dest_slice_id == SLICE_ID);
    wire target_is_north = is_l2_access && (dest_slice_id == SLICE_ID - 4); // Check bounds externally via wiring? No, check logic.
    wire target_is_south = is_l2_access && (dest_slice_id == SLICE_ID + 4);
    wire target_is_east  = is_l2_access && (dest_slice_id == SLICE_ID + 1); // Check row wrap? 
                                                                           // If ID=3 (0,3), +1=4 (1,0). 
                                                                           // Visually 3->4 is line break. NOT East neighbor.
                                                                           // Need Row/Col Logic.
    
    function is_valid_east;
        input [4:0] src;
        input [4:0] dst;
        begin
            // Same Row check: src/4 == dst/4
            is_valid_east = (dst == src + 1) && ((src / 4) == (dst / 4));
        end
    endfunction
    
    function is_valid_west;
        input [4:0] src;
        input [4:0] dst;
        begin
            is_valid_west = (dst == src - 1) && ((src / 4) == (dst / 4));
        end
    endfunction
    
    wire valid_east = is_valid_east(SLICE_ID[4:0], dest_slice_id[4:0]);
    wire valid_west = is_valid_west(SLICE_ID[4:0], dest_slice_id[4:0]);
    
    // Assign Core Outputs to Directions
    // We only assert VALID on the correct port.
    
    assign n_out_valid = c_req_valid && target_is_north;
    assign s_out_valid = c_req_valid && target_is_south;
    assign e_out_valid = c_req_valid && target_is_east && valid_east;
    assign w_out_valid = c_req_valid && target_is_west && valid_west;
    // Helper for WEST:
    wire target_is_west = is_l2_access && (dest_slice_id == SLICE_ID - 1);
    
    assign g_out_valid = c_req_valid && is_global;
    
    // Common Data/Addr lines (Fanout is fine, valid gates it)
    assign n_out_write = c_req_write; assign n_out_addr = c_req_addr; assign n_out_wdata = c_req_wdata;
    assign s_out_write = c_req_write; assign s_out_addr = c_req_addr; assign s_out_wdata = c_req_wdata;
    assign e_out_write = c_req_write; assign e_out_addr = c_req_addr; assign e_out_wdata = c_req_wdata;
    assign w_out_write = c_req_write; assign w_out_addr = c_req_addr; assign w_out_wdata = c_req_wdata;
    assign g_out_write = c_req_write; assign g_out_addr = c_req_addr; assign g_out_wdata = c_req_wdata;
    
    // Core Ready/Data Mux (Combinational Return Path)
    always @(*) begin
        c_req_ready = 0;
        c_req_rdata = 0;
        
        if (target_is_local) begin
             c_req_ready = slice_req_ready_mux; // From internal arbitration
             c_req_rdata = slice_req_rdata;
        end else if (target_is_north) begin
             c_req_ready = n_out_ready; c_req_rdata = n_out_rdata;
        end else if (target_is_south) begin
             c_req_ready = s_out_ready; c_req_rdata = s_out_rdata;
        end else if (target_is_east && valid_east) begin
             c_req_ready = e_out_ready; c_req_rdata = e_out_rdata;
        end else if (target_is_west && valid_west) begin
             c_req_ready = w_out_ready; c_req_rdata = w_out_rdata;
        end else if (is_global) begin
             c_req_ready = g_out_ready; c_req_rdata = g_out_rdata;
        end 
        // Else: Invalid/Dropped (or blocked)
    end

    // ========================================================================
    // 2. LOCAL SLICE ARBITRATION (5 Sources -> 1 Slice)
    // Sources: Core(Local), N, S, E, W (Inbound)
    // ========================================================================
    
    // Internal Slice Signals
    wire slice_req_valid; // Output of Arbiter
    wire slice_req_write;
    wire [9:0] slice_req_addr; // Fixed 10-bit for 1KB Slice
    wire [DATA_WIDTH-1:0] slice_wdata;
    wire slice_req_ready; // From Slice
    wire [DATA_WIDTH-1:0] slice_req_rdata;
    
    // Core Request for Local?
    wire c_local_valid = c_req_valid && target_is_local;
    
    // 5-way Round Robin Arbiter
    reg [2:0] rr_ptr;
    reg [2:0] winner;
    reg found;
    
    // Selected Request signals
    reg sel_valid, sel_write;
    reg [9:0] sel_addr;
    reg [DATA_WIDTH-1:0] sel_wdata;
    reg [4:0] grant_vector; // {C, N, S, E, W}

    // Arbitration Logic
    always @(*) begin
        // Defaults
        winner = 0; found = 0;
        sel_valid = 0; sel_write = 0; sel_addr = 0; sel_wdata = 0;
        grant_vector = 0;
        
        // Priority Search based on RR_PTR
        // 0:Core, 1:N, 2:S, 3:E, 4:W
        
        // Simple fixed-loop implementation for combinational selection
        // (In real silicon, expanded logic. Here behavior is key).
        // Iterate 5 times starting from rr_ptr
        
        // Note: Writing Loop in Always block requires integer
    end
    
    // Separate Combinational Arbiter Function
    // Mapping: 0=Core, 1=N, 2=S, 3=E, 4=W
    wire [4:0] req_vec = {w_in_valid, e_in_valid, s_in_valid, n_in_valid, c_local_valid}; // Order: 4,3,2,1,0
    
    // Simple priority for now (Core > N > S > E > W) to save space? 
    // Spec says "Round Robin".
    // Implementing simple rotate logic.
    
    // Separate Combinational Arbiter Function
    // Mapping: 0=Core, 1=N, 2=S, 3=E, 4=W
    
    // Explicit Unrolled Priority Search (Round Robin)
    // We check 5 subsets of priority based on rr_ptr.
    
    reg [2:0] candidate_0, candidate_1, candidate_2, candidate_3, candidate_4;
    reg valid_0, valid_1, valid_2, valid_3, valid_4;
    
    always @(*) begin
        found = 0;
        winner = 0;
        
        // Map logical indices [0..4] to their valid signals
        // 0:Core, 1:N, 2:S, 3:E, 4:W
        
        // Define rotation based on rr_ptr
        case (rr_ptr)
            0: begin candidate_0=0; candidate_1=1; candidate_2=2; candidate_3=3; candidate_4=4; end
            1: begin candidate_0=1; candidate_1=2; candidate_2=3; candidate_3=4; candidate_4=0; end
            2: begin candidate_0=2; candidate_1=3; candidate_2=4; candidate_3=0; candidate_4=1; end
            3: begin candidate_0=3; candidate_1=4; candidate_2=0; candidate_3=1; candidate_4=2; end
            4: begin candidate_0=4; candidate_1=0; candidate_2=1; candidate_3=2; candidate_4=3; end
            default: begin candidate_0=0; candidate_1=1; candidate_2=2; candidate_3=3; candidate_4=4; end
        endcase
        
        // Helper to check validity of a candidate index
        // checks req_vec? No, signals directly.
        
        // Cascading Priority
        if (is_valid(candidate_0)) begin found=1; winner=candidate_0; end
        else if (is_valid(candidate_1)) begin found=1; winner=candidate_1; end
        else if (is_valid(candidate_2)) begin found=1; winner=candidate_2; end
        else if (is_valid(candidate_3)) begin found=1; winner=candidate_3; end
        else if (is_valid(candidate_4)) begin found=1; winner=candidate_4; end
        
        // Mux Selections
        if (found) begin
            case (winner)
                0: begin sel_valid=1; sel_write=c_req_write; sel_addr=(c_req_addr[9:0]); sel_wdata=c_req_wdata; grant_vector=5'b00001; end
                1: begin sel_valid=1; sel_write=n_in_write; sel_addr=(n_in_addr[9:0]); sel_wdata=n_in_wdata; grant_vector=5'b00010; end
                2: begin sel_valid=1; sel_write=s_in_write; sel_addr=(s_in_addr[9:0]); sel_wdata=s_in_wdata; grant_vector=5'b00100; end
                3: begin sel_valid=1; sel_write=e_in_write; sel_addr=(e_in_addr[9:0]); sel_wdata=e_in_wdata; grant_vector=5'b01000; end
                4: begin sel_valid=1; sel_write=w_in_write; sel_addr=(w_in_addr[9:0]); sel_wdata=w_in_wdata; grant_vector=5'b10000; end
                default: begin sel_valid=0; sel_write=0; sel_addr=0; sel_wdata=0; grant_vector=0; end
            endcase
        end else begin
            sel_valid=0; grant_vector=0; sel_addr=0; sel_wdata=0; sel_write=0;
        end
    end
    
    function is_valid;
        input [2:0] cand;
        begin
            case (cand)
                0: is_valid = c_local_valid;
                1: is_valid = n_in_valid;
                2: is_valid = s_in_valid;
                3: is_valid = e_in_valid;
                4: is_valid = w_in_valid;
                default: is_valid = 0;
            endcase
        end
    endfunction

    // RR Ptr Update
    always @(posedge clk) begin
        if (reset) rr_ptr <= 0;
        else if (found && slice_req_ready) begin
             rr_ptr <= (winner + 1) % 5;
        end
    end

    // Slice Assignment
    assign slice_req_valid = sel_valid;
    assign slice_req_write = sel_write;
    assign slice_req_addr  = sel_addr;
    assign slice_wdata     = sel_wdata;
    
    // Ack Routing (Grant + Ready)
    wire slice_req_ready_mux = (found && slice_req_ready); // Only valid if arbiter found a winner and slice accepts
    // But specific source needs its specific ready signal
    // c_req_ready assigned above in Mux 1 (Core side) using `slice_req_ready_mux` IF core was winner
    // We need to verify that logic.
    // Logic: `c_req_ready` = `target_is_local` ? `slice_req_ready_mux` : ...
    // BUT `slice_req_ready_mux` is high if ANYONE won.
    // Core needs to know if IT won.
    // So `c_req_ready` (Local path) = `grant_vector[0] && slice_req_ready`.
    
    // Correcting Ack Logic:
    wire ack = slice_req_ready;
    wire core_won = grant_vector[0];
    
    // We need to re-override the `c_req_ready` assignment block logic?
    // Actually, simple way:
    // `slice_req_ready_mux` was used in block 1.
    // It should be `core_won && ack`.
    
    // Wait, block 1 is `always @(*)`.
    // I can redefine `slice_req_ready_mux` there? No, it's wire.
    // Let's create specific ready signals.
    wire local_ack = core_won && ack;
    
    assign n_in_ready = grant_vector[1] && ack;
    assign n_in_rdata = slice_req_rdata;
    
    assign s_in_ready = grant_vector[2] && ack;
    assign s_in_rdata = slice_req_rdata;
    
    assign e_in_ready = grant_vector[3] && ack;
    assign e_in_rdata = slice_req_rdata;
    
    assign w_in_ready = grant_vector[4] && ack;
    assign w_in_rdata = slice_req_rdata;
    
    // Re-verify Block 1 Core Ready
    // c_req_ready logic:
    // if target_is_local: c_req_ready = local_ack;
    
    // Instantiate Slice
    l2_slice #(
        .ADDR_WIDTH(10), // 1KB
        .DATA_WIDTH(DATA_WIDTH)
    ) memory_slice (
        .clk(clk),
        .req_valid(slice_req_valid),
        .req_write(slice_req_write),
        .req_addr(slice_req_addr),
        .req_wdata(slice_wdata),
        .req_ready(slice_req_ready),
        .req_rdata(slice_req_rdata)
    );
    
    // Fix up Block 1 "c_req_ready" assignment
    // We cannot do `c_req_ready = local_ack` inside the block if local_ack is defined after.
    // Verilog allows it, order is resolved.
    // But let's be explicit.
    
    reg c_ready_temp;
    reg [DATA_WIDTH-1:0] c_rdata_temp;
    
    always @(*) begin
        c_ready_temp = 0;
        c_rdata_temp = 0;
        
        if (target_is_local) begin
             c_ready_temp = local_ack;
             c_rdata_temp = slice_req_rdata;
        end else if (target_is_north) begin
             c_ready_temp = n_out_ready; c_rdata_temp = n_out_rdata;
        end else if (target_is_south) begin
             c_ready_temp = s_out_ready; c_rdata_temp = s_out_rdata;
        end else if (target_is_east && valid_east) begin
             c_ready_temp = e_out_ready; c_rdata_temp = e_out_rdata;
        end else if (target_is_west && valid_west) begin
             c_ready_temp = w_out_ready; c_rdata_temp = w_out_rdata;
        end else if (is_global) begin
             c_ready_temp = g_out_ready; c_rdata_temp = g_out_rdata;
        end 
    end
    
    // Assign Regs to Wire Outputs (Wait, c_req_ready is reg in port list)
    // always @(*) block above drives it directly. OK.
    always @(*) begin
        c_req_ready = c_ready_temp;
        c_req_rdata = c_rdata_temp;
    end

endmodule
