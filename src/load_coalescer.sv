
`default_nettype none
`timescale 1ns/1ns

module load_coalescer #(
    parameter LANES = 4,
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 16,
    parameter CACHE_LINE_SIZE = 16
) (
    input wire clk,
    input wire reset,
    input wire [LANES-1:0] lane_valid,
    input wire [ADDR_WIDTH-1:0] lane_addr [LANES-1:0],
    input wire lane_read_enable,
    output reg coalesced_req_valid,
    output reg [ADDR_WIDTH-1:0] coalesced_req_addr,
    output reg [4:0] coalesced_req_count,
    output reg [LANES-1:0] coalesced_lane_mask,
    input wire coalesced_req_ready,
    input wire resp_valid,
    input wire [DATA_WIDTH*LANES-1:0] resp_data,
    output reg [LANES-1:0] lane_resp_valid,
    output reg [DATA_WIDTH-1:0] lane_resp_data [LANES-1:0],
    output reg [31:0] perf_coalesced_requests,
    output reg [31:0] perf_uncoalesced_requests,
    output reg [31:0] perf_bytes_saved
);
    localparam IDLE = 2'b00;
    localparam ANALYZE = 2'b01;
    localparam REQUEST = 2'b10;
    localparam RESPONSE = 2'b11;
    reg [1:0] state;
    wire [ADDR_WIDTH-1:0] sorted_addr [LANES-1:0];
    wire [3:0] sorted_lane_id [LANES-1:0];
    reg [LANES-1:0] active_lanes;
    reg [ADDR_WIDTH-1:0] base_addr;
    reg [4:0] contiguous_count;
    integer i, j;
    reg [ADDR_WIDTH-1:0] min_addr;
    reg [3:0] min_lane;
    reg [LANES-1:0] remaining_lanes;
    always @(*) begin
        contiguous_count = 0;
        base_addr = 16'hFFFF;
        active_lanes = 0;
        min_addr = 16'hFFFF;
        min_lane = 0;
        remaining_lanes = 0;
        if (lane_read_enable && |lane_valid) begin
            for (i = 0; i < LANES; i = i + 1) begin
                if (lane_valid[i] && lane_addr[i] < min_addr) begin
                    min_addr = lane_addr[i];
                    min_lane = i[3:0];
                end
            end
            base_addr = min_addr;
            remaining_lanes = lane_valid;
            for (j = 0; j < LANES; j = j + 1) begin
                for (i = 0; i < LANES; i = i + 1) begin
                    if (remaining_lanes[i] && (lane_addr[i] == base_addr + j)) begin
                        active_lanes[i] = 1;
                        contiguous_count = contiguous_count + 1;
                        remaining_lanes[i] = 0;
                    end
                end
            end
        end
    end
    reg [LANES-1:0] pending_lanes;
    reg [ADDR_WIDTH-1:0] pending_base;
    reg [4:0] pending_count;
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            coalesced_req_valid <= 0;
            coalesced_req_addr <= 0;
            coalesced_req_count <= 0;
            coalesced_lane_mask <= 0;
            lane_resp_valid <= 0;
            perf_coalesced_requests <= 0;
            perf_uncoalesced_requests <= 0;
            perf_bytes_saved <= 0;
            pending_lanes <= 0;
            pending_base <= 0;
            pending_count <= 0;
            for (i = 0; i < LANES; i = i + 1) lane_resp_data[i] <= 0;
        end else begin
            lane_resp_valid <= 0;
            case (state)
                IDLE: begin
                    coalesced_req_valid <= 0;
                    if (lane_read_enable && |lane_valid) begin
                        state <= ANALYZE;
                    end
                end
                ANALYZE: begin
                    pending_lanes <= active_lanes;
                    pending_base <= base_addr;
                    pending_count <= contiguous_count;
                    coalesced_req_valid <= 1;
                    coalesced_req_addr <= base_addr;
                    coalesced_req_count <= contiguous_count;
                    coalesced_lane_mask <= active_lanes;
                    state <= REQUEST;
                    if (contiguous_count > 1) begin
                        perf_coalesced_requests <= perf_coalesced_requests + 1;
                        perf_bytes_saved <= perf_bytes_saved + ((contiguous_count - 1) * DATA_WIDTH / 8);
                    end else begin
                        perf_uncoalesced_requests <= perf_uncoalesced_requests + 1;
                    end
                end
                REQUEST: begin
                    if (coalesced_req_ready) begin
                        coalesced_req_valid <= 0;
                        state <= RESPONSE;
                    end
                end
                RESPONSE: begin
                    if (resp_valid) begin
                        for (i = 0; i < LANES; i = i + 1) begin
                            if (pending_lanes[i]) begin
                                lane_resp_valid[i] <= 1;
                                lane_resp_data[i] <= resp_data[(lane_addr[i] - pending_base) * DATA_WIDTH +: DATA_WIDTH];
                            end
                        end
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
