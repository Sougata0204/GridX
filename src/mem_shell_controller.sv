
`default_nettype none
`timescale 1ns/1ns

module mem_shell_controller #(
    parameter NUM_FACES = 6,
    parameter ADDR_WIDTH = 22,
    parameter DATA_WIDTH = 8,
    parameter MAX_OUTSTANDING = 8,
    parameter SHELL_SIZE_BYTES = 512 * 1024
) (
    input  wire clk,
    input  wire reset,
    input  wire [NUM_FACES-1:0] face_req_valid,
    input  wire [NUM_FACES-1:0] face_req_write,
    input  wire [ADDR_WIDTH-1:0] face_req_addr [NUM_FACES-1:0],
    input  wire [DATA_WIDTH-1:0] face_req_wdata [NUM_FACES-1:0],
    output reg  [NUM_FACES-1:0] face_req_ready,
    output reg  [DATA_WIDTH-1:0] face_req_rdata [NUM_FACES-1:0],
    output wire [NUM_FACES-1:0] face_credit_available,
    output reg  sram_req_valid,
    output reg  sram_req_write,
    output reg  [ADDR_WIDTH-1:0] sram_req_addr,
    output reg  [DATA_WIDTH-1:0] sram_req_wdata,
    input  wire sram_req_ready,
    input  wire [DATA_WIDTH-1:0] sram_req_rdata,
    output wire [$clog2(MAX_OUTSTANDING):0] outstanding_count,
    output wire shell_busy,
    output reg  [31:0] total_requests,
    output reg  [31:0] total_completions
);
    localparam SHELL_ADDR_BITS = $clog2(SHELL_SIZE_BYTES);
    localparam FACE_CREDITS = MAX_OUTSTANDING / NUM_FACES;
    localparam QUEUE_DEPTH = MAX_OUTSTANDING;
    localparam QUEUE_ENTRY_WIDTH = 1 + 1 + 3 + ADDR_WIDTH + DATA_WIDTH;
    reg [QUEUE_ENTRY_WIDTH-1:0] request_queue [QUEUE_DEPTH-1:0];
    reg [$clog2(QUEUE_DEPTH)-1:0] queue_head;
    reg [$clog2(QUEUE_DEPTH)-1:0] queue_tail;
    reg [$clog2(QUEUE_DEPTH):0] queue_count;
    reg [$clog2(FACE_CREDITS):0] face_credits [NUM_FACES-1:0];
    reg [2:0] pending_face_id [MAX_OUTSTANDING-1:0];
    reg [$clog2(MAX_OUTSTANDING)-1:0] response_head;
    reg [$clog2(MAX_OUTSTANDING)-1:0] response_tail;
    reg [2:0] current_face;
    reg [2:0] last_served_face;
    genvar f;
    generate
        for (f = 0; f < NUM_FACES; f++) begin : face_credit_gen
            assign face_credit_available[f] = (face_credits[f] > 0);
        end
    endgenerate
    wire [NUM_FACES-1:0] face_can_request;
    assign face_can_request = face_req_valid & face_credit_available;
    reg [2:0] next_face;
    reg found_request;
    always @(*) begin
        found_request = 0;
        next_face = last_served_face;
        for (int i = 0; i < NUM_FACES; i++) begin
            automatic int check_face = (last_served_face + 1 + i) % NUM_FACES;
            if (face_can_request[check_face] && !found_request) begin
                next_face = check_face[2:0];
                found_request = 1;
            end
        end
    end
    localparam IDLE = 2'b00;
    localparam WAITING = 2'b01;
    localparam RESPONDING = 2'b10;
    reg [1:0] state;
    reg [2:0] active_face;
    reg active_write;
    assign outstanding_count = queue_count;
    assign shell_busy = (state != IDLE) || (queue_count > 0);
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            queue_head <= 0;
            queue_tail <= 0;
            queue_count <= 0;
            last_served_face <= 0;
            sram_req_valid <= 0;
            total_requests <= 0;
            total_completions <= 0;
            for (i = 0; i < NUM_FACES; i++) begin
                face_credits[i] <= FACE_CREDITS;
                face_req_ready[i] <= 0;
                face_req_rdata[i] <= 0;
            end
            for (i = 0; i < QUEUE_DEPTH; i++) begin
                request_queue[i] <= 0;
            end
        end else begin
            face_req_ready <= 0;
            case (state)
                IDLE: begin
                    if (found_request && queue_count < QUEUE_DEPTH) begin
                        active_face <= next_face;
                        active_write <= face_req_write[next_face];
                        face_credits[next_face] <= face_credits[next_face] - 1;
                        sram_req_valid <= 1;
                        sram_req_write <= face_req_write[next_face];
                        sram_req_addr <= face_req_addr[next_face];
                        sram_req_wdata <= face_req_wdata[next_face];
                        pending_face_id[queue_tail] <= next_face;
                        queue_count <= queue_count + 1;
                        queue_tail <= queue_tail + 1;
                        last_served_face <= next_face;
                        total_requests <= total_requests + 1;
                        state <= WAITING;
                    end
                end
                WAITING: begin
                    if (sram_req_ready) begin
                        sram_req_valid <= 0;
                        face_credits[active_face] <= face_credits[active_face] + 1;
                        face_req_ready[active_face] <= 1;
                        if (!active_write) begin
                            face_req_rdata[active_face] <= sram_req_rdata;
                        end
                        queue_count <= queue_count - 1;
                        queue_head <= queue_head + 1;
                        total_completions <= total_completions + 1;
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
`ifdef VERILATOR
    always @(posedge clk) begin
        if (!reset) begin
            if (queue_count > MAX_OUTSTANDING) begin
                $fatal(1, "MEM_SHELL: Queue overflow! count=%d, max=%d",
                       queue_count, MAX_OUTSTANDING);
            end
        end
    end
`endif
endmodule
