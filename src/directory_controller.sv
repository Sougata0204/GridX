// Directory-Based Coherence Controller
// Tracks MOESI cache coherence states and directs snoop invalidations across 3D compute nodes.

`default_nettype none
`timescale 1ns/1ns

module directory_controller #(
    parameter NUM_CORES = 8,
    parameter ADDR_WIDTH = 22,
    parameter DATA_WIDTH = 256,
    parameter DIRECTORY_ENTRIES = 256,
    parameter CORE_ID_WIDTH = 3
) (
    input  wire clk,
    input  wire reset,
    
    // Request Interface
    input  wire req_valid,
    input  wire [CORE_ID_WIDTH-1:0] req_core_id,
    input  wire [ADDR_WIDTH-1:0] req_addr,
    input  wire [2:0] req_type, // 0: READ, 1: WRITE, 2: INVALIDATE, 3: WRITEBACK, 4: UPGRADE
    input  wire [DATA_WIDTH-1:0] req_data,
    output reg  req_ready,
    
    // Response Interface
    output reg  resp_valid,
    output reg  [CORE_ID_WIDTH-1:0] resp_core_id,
    output reg  [DATA_WIDTH-1:0] resp_data,
    output reg  [1:0] resp_type, // 0: ACK, 1: DATA, 2: NACK
    
    // Snoop Interface
    output reg  snoop_valid,
    output reg  [NUM_CORES-1:0] snoop_core_mask,
    output reg  [ADDR_WIDTH-1:0] snoop_addr,
    output reg  [1:0] snoop_type, // 0: INVALIDATE, 1: FETCH, 2: WRITEBACK
    input  wire snoop_resp_valid,
    input  wire [CORE_ID_WIDTH-1:0] snoop_resp_core_id,
    input  wire [DATA_WIDTH-1:0] snoop_resp_data,
    
    // Performance
    output reg [31:0] perf_hits,
    output reg [31:0] perf_misses,
    output reg [31:0] perf_invalidations,
    output reg [31:0] perf_writebacks
);

    localparam REQ_READ       = 3'd0;
    localparam REQ_WRITE      = 3'd1;
    localparam REQ_INVALIDATE = 3'd2;
    localparam REQ_WRITEBACK  = 3'd3;
    localparam REQ_UPGRADE    = 3'd4;
    
    localparam RESP_ACK  = 2'd0;
    localparam RESP_DATA = 2'd1;
    localparam RESP_NACK = 2'd2;
    
    localparam SNOOP_INV   = 2'd0;
    localparam SNOOP_FETCH = 2'd1;
    localparam SNOOP_WB    = 2'd2;
    
    // MOESI States
    localparam STATE_I = 3'd0; // Invalid
    localparam STATE_S = 3'd1; // Shared
    localparam STATE_E = 3'd2; // Exclusive
    localparam STATE_O = 3'd3; // Owned
    localparam STATE_M = 3'd4; // Modified

    reg valid_array [DIRECTORY_ENTRIES-1:0];
    reg [ADDR_WIDTH-1:0] tag_array [DIRECTORY_ENTRIES-1:0];
    reg [2:0] state_array [DIRECTORY_ENTRIES-1:0];
    reg [NUM_CORES-1:0] sharers_array [DIRECTORY_ENTRIES-1:0];
    reg [CORE_ID_WIDTH-1:0] owner_array [DIRECTORY_ENTRIES-1:0];
    
    // Simple hash function for index
    wire [$clog2(DIRECTORY_ENTRIES)-1:0] lookup_idx = req_addr[$clog2(DIRECTORY_ENTRIES)-1:0];
    
    typedef enum logic [2:0] {
        IDLE,
        EVALUATE,
        WAIT_SNOOP,
        RESPOND
    } fsm_state_e;
    
    fsm_state_e state;
    
    reg [CORE_ID_WIDTH-1:0] latched_req_core_id;
    reg [ADDR_WIDTH-1:0] latched_req_addr;
    reg [2:0] latched_req_type;
    reg [DATA_WIDTH-1:0] latched_req_data;
    
    reg [4:0] snoop_expected;
    reg [4:0] snoop_ack_cnt;
    reg [8:0] snoop_timeout;
    
    wire match_comb = valid_array[lookup_idx] && (tag_array[lookup_idx] == latched_req_addr);
    wire [2:0] line_state_comb = match_comb ? state_array[lookup_idx] : STATE_I;
    wire [NUM_CORES-1:0] sharers_comb = match_comb ? sharers_array[lookup_idx] : 0;
    wire [NUM_CORES-1:0] invalidation_mask_comb = sharers_comb & ~(1 << latched_req_core_id);
    
    function [4:0] count_ones;
        input [NUM_CORES-1:0] mask;
        integer j;
        begin
            count_ones = 0;
            for (j = 0; j < NUM_CORES; j = j + 1) begin
                if (mask[j]) count_ones = count_ones + 1;
            end
        end
    endfunction
    
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            req_ready <= 1;
            resp_valid <= 0;
            snoop_valid <= 0;
            perf_hits <= 0;
            perf_misses <= 0;
            perf_invalidations <= 0;
            perf_writebacks <= 0;
            
            for (i = 0; i < DIRECTORY_ENTRIES; i = i + 1) begin
                valid_array[i] <= 0;
            end
        end else begin
            resp_valid <= 0;
            snoop_valid <= 0;
            
            case (state)
                IDLE: begin
                    if (req_valid) begin
                        latched_req_core_id <= req_core_id;
                        latched_req_addr <= req_addr;
                        latched_req_type <= req_type;
                        latched_req_data <= req_data;
                        req_ready <= 0;
                        state <= EVALUATE;
                    end
                end
                
                EVALUATE: begin
                    if (!match_comb) begin
                        // Cache miss / line not tracked
                        perf_misses <= perf_misses + 1;
                        valid_array[lookup_idx] <= 1;
                        tag_array[lookup_idx] <= latched_req_addr;
                        
                        if (latched_req_type == REQ_READ) begin
                            state_array[lookup_idx] <= STATE_E;
                            owner_array[lookup_idx] <= latched_req_core_id;
                            sharers_array[lookup_idx] <= (1 << latched_req_core_id);
                            
                            resp_valid <= 1;
                            resp_type <= RESP_DATA;
                            resp_data <= 0; // Fetch from memory in real impl
                            resp_core_id <= latched_req_core_id;
                            state <= IDLE;
                            req_ready <= 1;
                        end else if (latched_req_type == REQ_WRITE) begin
                            state_array[lookup_idx] <= STATE_M;
                            owner_array[lookup_idx] <= latched_req_core_id;
                            sharers_array[lookup_idx] <= 0;
                            
                            resp_valid <= 1;
                            resp_type <= RESP_ACK;
                            resp_core_id <= latched_req_core_id;
                            state <= IDLE;
                            req_ready <= 1;
                        end else begin
                            // other types like writeback on miss shouldn't happen, ignore
                            resp_valid <= 1;
                            resp_type <= RESP_NACK;
                            resp_core_id <= latched_req_core_id;
                            state <= IDLE;
                            req_ready <= 1;
                        end
                    end else begin
                        perf_hits <= perf_hits + 1;
                        
                        // Hit processing based on request type
                        case (latched_req_type)
                            REQ_READ: begin
                                if (line_state_comb == STATE_M || line_state_comb == STATE_O) begin
                                    // Snoop owner for data
                                    snoop_valid <= 1;
                                    snoop_core_mask <= (1 << owner_array[lookup_idx]);
                                    snoop_addr <= latched_req_addr;
                                    snoop_type <= SNOOP_FETCH;
                                    snoop_expected <= 1;
                                    snoop_ack_cnt <= 0;
                                    snoop_timeout <= 0;
                                    state <= WAIT_SNOOP;
                                    
                                    // Downgrade M to O, O stays O
                                    if (line_state_comb == STATE_M) state_array[lookup_idx] <= STATE_O;
                                    sharers_array[lookup_idx] <= sharers_comb | (1 << latched_req_core_id);
                                end else begin
                                    // State S or E
                                    if (line_state_comb == STATE_E) state_array[lookup_idx] <= STATE_S;
                                    sharers_array[lookup_idx] <= sharers_comb | (1 << latched_req_core_id);
                                    
                                    resp_valid <= 1;
                                    resp_type <= RESP_DATA;
                                    resp_data <= 0; // Data from memory
                                    resp_core_id <= latched_req_core_id;
                                    state <= IDLE;
                                    req_ready <= 1;
                                end
                            end
                            
                            REQ_WRITE, REQ_UPGRADE: begin
                                if (invalidation_mask_comb != 0) begin
                                    snoop_valid <= 1;
                                    snoop_core_mask <= invalidation_mask_comb;
                                    snoop_addr <= latched_req_addr;
                                    snoop_type <= SNOOP_INV;
                                    snoop_expected <= count_ones(invalidation_mask_comb);
                                    snoop_ack_cnt <= 0;
                                    snoop_timeout <= 0;
                                    perf_invalidations <= perf_invalidations + 1;
                                    state <= WAIT_SNOOP;
                                end else begin
                                    resp_valid <= 1;
                                    resp_type <= RESP_ACK;
                                    resp_core_id <= latched_req_core_id;
                                    state <= IDLE;
                                    req_ready <= 1;
                                end
                                
                                state_array[lookup_idx] <= STATE_M;
                                owner_array[lookup_idx] <= latched_req_core_id;
                                sharers_array[lookup_idx] <= 0;
                            end
                            
                            REQ_WRITEBACK: begin
                                if (latched_req_core_id == owner_array[lookup_idx] && (line_state_comb == STATE_M || line_state_comb == STATE_O)) begin
                                    perf_writebacks <= perf_writebacks + 1;
                                    if (sharers_comb == 0) valid_array[lookup_idx] <= 0;
                                    else begin
                                        state_array[lookup_idx] <= STATE_S;
                                        // Pick arbitrary new owner if needed or leave as S without owner
                                    end
                                end else begin
                                    sharers_array[lookup_idx] <= sharers_comb & ~(1 << latched_req_core_id);
                                end
                                resp_valid <= 1;
                                resp_type <= RESP_ACK;
                                resp_core_id <= latched_req_core_id;
                                state <= IDLE;
                                req_ready <= 1;
                            end
                        endcase
                    end
                end
                
                WAIT_SNOOP: begin
                    snoop_timeout <= snoop_timeout + 1;
                    if (snoop_resp_valid) begin
                        snoop_ack_cnt <= snoop_ack_cnt + 1;
                        if (latched_req_type == REQ_READ) begin
                            resp_valid <= 1;
                            resp_type <= RESP_DATA;
                            resp_data <= snoop_resp_data;
                            resp_core_id <= latched_req_core_id;
                            state <= IDLE;
                            req_ready <= 1;
                        end else begin
                            if (snoop_ack_cnt + 1 == snoop_expected) begin
                                resp_valid <= 1;
                                resp_type <= RESP_ACK;
                                resp_core_id <= latched_req_core_id;
                                state <= IDLE;
                                req_ready <= 1;
                            end
                        end
                    end else if (snoop_timeout >= 256) begin
                        resp_valid <= 1;
                        resp_type <= RESP_NACK;
                        resp_core_id <= latched_req_core_id;
                        state <= IDLE;
                        req_ready <= 1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
