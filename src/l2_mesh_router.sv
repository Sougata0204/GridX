
`default_nettype none
`timescale 1ns/1ns

module l2_mesh_router #(
    parameter SLICE_ID = 0,
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8,
    parameter L2_BASE = 16'h8000
) (
    input wire clk,
    input wire reset,
    input wire c_req_valid,
    input wire c_req_write,
    input wire [ADDR_WIDTH-1:0] c_req_addr,
    input wire [DATA_WIDTH-1:0] c_req_wdata,
    output reg c_req_ready,
    output reg [DATA_WIDTH-1:0] c_req_rdata,
    input wire n_in_valid, input wire n_in_write, input wire [ADDR_WIDTH-1:0] n_in_addr, input wire [DATA_WIDTH-1:0] n_in_wdata, output wire n_in_ready, output wire [DATA_WIDTH-1:0] n_in_rdata,
    input wire s_in_valid, input wire s_in_write, input wire [ADDR_WIDTH-1:0] s_in_addr, input wire [DATA_WIDTH-1:0] s_in_wdata, output wire s_in_ready, output wire [DATA_WIDTH-1:0] s_in_rdata,
    input wire e_in_valid, input wire e_in_write, input wire [ADDR_WIDTH-1:0] e_in_addr, input wire [DATA_WIDTH-1:0] e_in_wdata, output wire e_in_ready, output wire [DATA_WIDTH-1:0] e_in_rdata,
    input wire w_in_valid, input wire w_in_write, input wire [ADDR_WIDTH-1:0] w_in_addr, input wire [DATA_WIDTH-1:0] w_in_wdata, output wire w_in_ready, output wire [DATA_WIDTH-1:0] w_in_rdata,
    output wire n_out_valid, output wire n_out_write, output wire [ADDR_WIDTH-1:0] n_out_addr, output wire [DATA_WIDTH-1:0] n_out_wdata, input wire n_out_ready, input wire [DATA_WIDTH-1:0] n_out_rdata,
    output wire s_out_valid, output wire s_out_write, output wire [ADDR_WIDTH-1:0] s_out_addr, output wire [DATA_WIDTH-1:0] s_out_wdata, input wire s_out_ready, input wire [DATA_WIDTH-1:0] s_out_rdata,
    output wire e_out_valid, output wire e_out_write, output wire [ADDR_WIDTH-1:0] e_out_addr, output wire [DATA_WIDTH-1:0] e_out_wdata, input wire e_out_ready, input wire [DATA_WIDTH-1:0] e_out_rdata,
    output wire w_out_valid, output wire w_out_write, output wire [ADDR_WIDTH-1:0] w_out_addr, output wire [DATA_WIDTH-1:0] w_out_wdata, input wire w_out_ready, input wire [DATA_WIDTH-1:0] w_out_rdata,
    output wire g_out_valid, output wire g_out_write, output wire [ADDR_WIDTH-1:0] g_out_addr, output wire [DATA_WIDTH-1:0] g_out_wdata, input wire g_out_ready, input wire [DATA_WIDTH-1:0] g_out_rdata
);
    wire [15:0] dest_slice_id = (c_req_addr - L2_BASE) >> 10;
    wire is_l2_access = (c_req_addr >= L2_BASE && c_req_addr < 16'hC000);
    wire is_global = (c_req_addr >= 16'hC000);
    wire target_is_local = is_l2_access && (dest_slice_id == SLICE_ID);
    wire target_is_north = is_l2_access && (dest_slice_id == SLICE_ID - 4);
    wire target_is_south = is_l2_access && (dest_slice_id == SLICE_ID + 4);
    wire target_is_east  = is_l2_access && (dest_slice_id == SLICE_ID + 1);
    wire target_is_west  = is_l2_access && (dest_slice_id == SLICE_ID - 1);

    function is_valid_east;
        input [4:0] src;
        input [4:0] dst;
        begin
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
    assign n_out_valid = c_req_valid && target_is_north;
    assign s_out_valid = c_req_valid && target_is_south;
    assign e_out_valid = c_req_valid && target_is_east && valid_east;
    assign w_out_valid = c_req_valid && target_is_west && valid_west;
    wire vc_g_in_ready;
    virtual_channel #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(4)
    ) global_vc (
        .clk(clk),
        .reset(reset),
        .in_valid(c_req_valid && is_global),
        .in_is_response(1'b0),
        .in_addr(c_req_addr),
        .in_data(c_req_wdata),
        .in_write(c_req_write),
        .in_ready(vc_g_in_ready),
        .vc0_valid(g_out_valid),
        .vc0_addr(g_out_addr),
        .vc0_data(g_out_wdata),
        .vc0_write(g_out_write),
        .vc0_ready(g_out_ready),
        .vc1_valid(), .vc1_addr(), .vc1_data(), .vc1_ready(1'b1),
        .perf_vc0_packets(),
        .perf_vc1_packets(),
        .perf_vc0_blocked_cycles(),
        .perf_vc1_blocked_cycles()
    );
    assign n_out_write = c_req_write; assign n_out_addr = c_req_addr; assign n_out_wdata = c_req_wdata;
    assign s_out_write = c_req_write; assign s_out_addr = c_req_addr; assign s_out_wdata = c_req_wdata;
    assign e_out_write = c_req_write; assign e_out_addr = c_req_addr; assign e_out_wdata = c_req_wdata;
    assign w_out_write = c_req_write; assign w_out_addr = c_req_addr; assign w_out_wdata = c_req_wdata;
    wire slice_req_valid;
    wire slice_req_write;
    wire [9:0] slice_req_addr;
    wire [DATA_WIDTH-1:0] slice_wdata;
    wire slice_req_ready;
    wire [DATA_WIDTH-1:0] slice_req_rdata;
    wire c_local_valid = c_req_valid && target_is_local;
    reg [2:0] rr_ptr;
    reg [2:0] winner;
    reg found;
    reg sel_valid, sel_write;
    reg [9:0] sel_addr;
    reg [DATA_WIDTH-1:0] sel_wdata;
    reg [4:0] grant_vector;
    always @(*) begin
        winner = 0; found = 0;
        sel_valid = 0; sel_write = 0; sel_addr = 0; sel_wdata = 0;
        grant_vector = 0;
    end
    wire [4:0] req_vec = {w_in_valid, e_in_valid, s_in_valid, n_in_valid, c_local_valid};
    reg [2:0] candidate_0, candidate_1, candidate_2, candidate_3, candidate_4;
    reg valid_0, valid_1, valid_2, valid_3, valid_4;
    always @(*) begin
        found = 0;
        winner = 0;
        case (rr_ptr)
            0: begin candidate_0=0; candidate_1=1; candidate_2=2; candidate_3=3; candidate_4=4; end
            1: begin candidate_0=1; candidate_1=2; candidate_2=3; candidate_3=4; candidate_4=0; end
            2: begin candidate_0=2; candidate_1=3; candidate_2=4; candidate_3=0; candidate_4=1; end
            3: begin candidate_0=3; candidate_1=4; candidate_2=0; candidate_3=1; candidate_4=2; end
            4: begin candidate_0=4; candidate_1=0; candidate_2=1; candidate_3=2; candidate_4=3; end
            default: begin candidate_0=0; candidate_1=1; candidate_2=2; candidate_3=3; candidate_4=4; end
        endcase
        if (is_valid(candidate_0)) begin found=1; winner=candidate_0; end
        else if (is_valid(candidate_1)) begin found=1; winner=candidate_1; end
        else if (is_valid(candidate_2)) begin found=1; winner=candidate_2; end
        else if (is_valid(candidate_3)) begin found=1; winner=candidate_3; end
        else if (is_valid(candidate_4)) begin found=1; winner=candidate_4; end
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
    always @(posedge clk) begin
        if (reset) rr_ptr <= 0;
        else if (found && slice_req_ready) begin
             rr_ptr <= (winner + 1) % 5;
        end
    end
    assign slice_req_valid = sel_valid;
    assign slice_req_write = sel_write;
    assign slice_req_addr  = sel_addr;
    assign slice_wdata     = sel_wdata;
    wire slice_req_ready_mux = (found && slice_req_ready);
    wire ack = slice_req_ready;
    wire core_won = grant_vector[0];
    wire local_ack = core_won && ack;
    assign n_in_ready = grant_vector[1] && ack;
    assign n_in_rdata = slice_req_rdata;
    assign s_in_ready = grant_vector[2] && ack;
    assign s_in_rdata = slice_req_rdata;
    assign e_in_ready = grant_vector[3] && ack;
    assign e_in_rdata = slice_req_rdata;
    assign w_in_ready = grant_vector[4] && ack;
    assign w_in_rdata = slice_req_rdata;
    l2_slice #(
        .ADDR_WIDTH(10),
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
    always @(*) begin
        c_req_ready = c_ready_temp;
        c_req_rdata = c_rdata_temp;
    end
    // synthesis translate_off
    reg [31:0] req_seen_count;
    reg [31:0] req_forwarded_count;
    reg [31:0] local_hit_count;
    localparam [ADDR_WIDTH-1:0] TRACE_ADDR = 22'h00c000;
    reg [31:0] debug_counter;
    always @(posedge clk) begin
        if (reset) begin
            debug_counter <= 0;
            req_seen_count <= 0;
            req_forwarded_count <= 0;
            local_hit_count <= 0;
        end else begin
            debug_counter <= debug_counter + 1;
            if (c_req_valid && c_req_ready) begin
                req_seen_count <= req_seen_count + 1;
                if (target_is_local) begin
                    local_hit_count <= local_hit_count + 1;
                end else begin
                    req_forwarded_count <= req_forwarded_count + 1;
                end
            end
            if (c_req_valid && (c_req_addr == TRACE_ADDR) && SLICE_ID == 0) begin
                $display("[TRACE 00c000] Cycle %0d MESH_INGRESS: Router=%0d Valid=%b Ready=%b Write=%b",
                         debug_counter, SLICE_ID, c_req_valid, c_req_ready, c_req_write);
            end
            if (g_out_valid && (g_out_addr == TRACE_ADDR) && SLICE_ID == 0) begin
                $display("[TRACE 00c000] Cycle %0d MESH_TO_GLOBAL: Router=%0d GValid=%b GReady=%b",
                         debug_counter, SLICE_ID, g_out_valid, g_out_ready);
            end
            if ((n_out_valid || s_out_valid || e_out_valid || w_out_valid) &&
                (c_req_addr == TRACE_ADDR) && SLICE_ID == 0) begin
                $display("[TRACE 00c000] Cycle %0d MESH_TO_NEIGHBOR: Router=%0d N=%b S=%b E=%b W=%b",
                         debug_counter, SLICE_ID, n_out_valid, s_out_valid, e_out_valid, w_out_valid);
            end
            if ((debug_counter % 2000 == 0) && SLICE_ID == 0) begin
                $display("[HEARTBEAT] Cycle %0d Router0: Seen=%0d Forwarded=%0d LocalHit=%0d",
                         debug_counter, req_seen_count, req_forwarded_count, local_hit_count);
            end
        end
    end
    // synthesis translate_on
endmodule
