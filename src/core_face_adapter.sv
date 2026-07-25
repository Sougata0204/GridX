
`default_nettype none
`timescale 1ns/1ns

module core_face_adapter #(
    parameter FACE_ID = 0,
    parameter CORES_PER_FACE = 16,
    parameter ADDR_WIDTH = 22,
    parameter DATA_WIDTH = 8
) (
    input  wire clk,
    input  wire reset,
    input  wire [CORES_PER_FACE-1:0] l2_req_valid,
    input  wire [CORES_PER_FACE-1:0] l2_req_write,
    input  wire [ADDR_WIDTH-1:0] l2_req_addr [CORES_PER_FACE-1:0],
    input  wire [DATA_WIDTH-1:0] l2_req_wdata [CORES_PER_FACE-1:0],
    output reg  [CORES_PER_FACE-1:0] l2_req_ready,
    output reg  [DATA_WIDTH-1:0] l2_req_rdata [CORES_PER_FACE-1:0],
    output reg  shell_req_valid,
    output reg  shell_req_write,
    output reg  [ADDR_WIDTH-1:0] shell_req_addr,
    output reg  [DATA_WIDTH-1:0] shell_req_wdata,
    input  wire shell_req_ready,
    input  wire [DATA_WIDTH-1:0] shell_req_rdata,
    input  wire shell_credit_available,
    output wire shell_credit_consumed,
    output reg  [$clog2(CORES_PER_FACE)-1:0] current_core,
    output wire adapter_busy
);
    localparam IDLE = 2'b00;
    localparam REQUESTING = 2'b01;
    localparam WAITING = 2'b10;
    reg [1:0] state;
    reg [$clog2(CORES_PER_FACE)-1:0] last_served;
    reg [$clog2(CORES_PER_FACE)-1:0] active_core;
    reg found_request;
    reg [$clog2(CORES_PER_FACE)-1:0] next_core;
    assign adapter_busy = (state != IDLE);
    assign shell_credit_consumed = (state == IDLE) && found_request && shell_credit_available;
    wire [CORES_PER_FACE-1:0] pending_requests;
    assign pending_requests = l2_req_valid;
    always @(*) begin
        found_request = 0;
        next_core = last_served;
        for (int i = 0; i < CORES_PER_FACE; i++) begin
            automatic int check_idx = (last_served + 1 + i) % CORES_PER_FACE;
            if (pending_requests[check_idx] && !found_request) begin
                next_core = check_idx[$clog2(CORES_PER_FACE)-1:0];
                found_request = 1;
            end
        end
    end
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            last_served <= 0;
            active_core <= 0;
            current_core <= 0;
            shell_req_valid <= 0;
            shell_req_write <= 0;
            shell_req_addr <= 0;
            shell_req_wdata <= 0;
            l2_req_ready <= 0;
            for (i = 0; i < CORES_PER_FACE; i++) begin
                l2_req_rdata[i] <= 0;
            end
        end else begin
            l2_req_ready <= 0;
            case (state)
                IDLE: begin
                    if (found_request && shell_credit_available) begin
                        active_core <= next_core;
                        current_core <= next_core;
                        shell_req_valid <= 1;
                        shell_req_write <= l2_req_write[next_core];
                        shell_req_addr <= l2_req_addr[next_core];
                        shell_req_wdata <= l2_req_wdata[next_core];
                        last_served <= next_core;
                        state <= WAITING;
                    end
                end
                WAITING: begin
                    if (shell_req_ready) begin
                        shell_req_valid <= 0;
                        l2_req_ready[active_core] <= 1;
                        l2_req_rdata[active_core] <= shell_req_rdata;
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
