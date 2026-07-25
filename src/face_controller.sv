// Per-Face Interconnect Controller
// Manages the interface between a compute cube's memory bus and the adjacent Memory Sheet.
// I built credit-based flow control and small request/response FIFOs here to prevent buffer overflow
// across vertical package layers.

`default_nettype none
`timescale 1ns/1ns
// Module:  face_controller
// Project: GridX3 Volumetric GPU SoC
// Description:
// Per-face interface controller for each compute cube in the GridX3
// architecture.  Every compute cube has 6 face controllers (one per
// spatial direction: +X, -X, +Y, -Y, +Z, -Z).  Each face controller
// manages the interface between the compute cube's internal memory bus
// (driven by the LSU / memory subsystem) and the adjacent Memory Sheet.
// Architecture:
// core_req ──►┌─────────────┐──► sheet_req
//             │ Request FIFO│
// core_req ◄──│  (circular) │
// ready       └──────┬──────┘
// │
// ┌──────┴──────┐
// │   Credit    │
// │   Manager   │
// └──────┬──────┘
// │
// core_resp◄──┌──────┴──────┐◄── sheet_resp
//             │Response FIFO│
// core_resp──►│  (circular) │──► sheet_resp
//  ready      └─────────────┘    _ready
// 1. Request FIFO  - BUFFER_DEPTH-entry circular buffer.  Buffers core
// requests before forwarding them to the Memory Sheet.
// Asserts backpressure (core_req_ready = 0) when full.
// 2. Response FIFO - BUFFER_DEPTH-entry circular buffer.  Buffers Memory
// Sheet responses before delivering them to the core.
// Asserts backpressure (sheet_resp_ready = 0) when full.
// 3. Credit Manager - Tracks outstanding (in-flight) requests.
// Initialised to CREDIT_COUNT.
// • Decrement on request send  (sheet handshake).
// • Increment on response recv (sheet handshake).
// New requests are gated when credits == 0.
// 4. Request Scheduler  - Dequeues the request FIFO head when the credit
// counter is non-zero AND sheet_req_ready is high.
// 5. Response Scheduler - Dequeues the response FIFO head when
// core_resp_ready is high.
// Handshake Protocol:
// Valid/ready on every interface.  A transfer completes on the rising
// clock edge where BOTH valid AND ready are asserted.
// Credit-based flow control prevents the Memory Sheet from being
// overwhelmed with more requests than it can buffer responses for.
// Parameters:
// ADDR_WIDTH   - Address bus width in bits  (default 13)
// DATA_WIDTH   - Data bus width in bits     (default 8)
// BUFFER_DEPTH - Request / response FIFO depth  (default 4)
// FACE_ID      - Face direction identifier
// 0 = +X, 1 = -X, 2 = +Y, 3 = -Y, 4 = +Z, 5 = -Z
// CREDIT_COUNT - Initial credits for flow control (default 4)
// Notes:
// • FIFO memory arrays are NOT reset.  Pointer / count logic guarantees
// that unwritten locations are never read - safe for x-propagation.
// • FACE_ID is carried as a parameter for debug / identification and
// does not affect the datapath logic.
// • All control registers are synchronously reset (active-high reset).
// • Fully synthesisable - no latches inferred.
// • Compatible with Vivado XSIM, Verilator, and ASIC synthesis flows.
// Author:  GridX3 RTL Team
// Created: 2026-07-03

module face_controller #(
    parameter ADDR_WIDTH    = 13,       // Address bits
    parameter DATA_WIDTH    = 8,        // Data width
    parameter BUFFER_DEPTH  = 4,        // Request/response buffer depth
    parameter FACE_ID       = 0,        // 0=+X, 1=-X, 2=+Y, 3=-Y, 4=+Z, 5=-Z
    parameter CREDIT_COUNT  = 4         // Initial credits for flow control
) (
    // Clock / Reset
    input  wire                    clk,
    input  wire                    reset,

    // Core-side interface (from LSU / memory subsystem)
    // Core request in
    input  wire                    core_req_valid,
    input  wire                    core_req_write,
    input  wire [ADDR_WIDTH-1:0]   core_req_addr,
    input  wire [DATA_WIDTH-1:0]   core_req_wdata,
    output wire                    core_req_ready,     // backpressure to core

    // Core response out
    output wire                    core_resp_valid,
    output wire [DATA_WIDTH-1:0]   core_resp_rdata,
    input  wire                    core_resp_ready,

    // Memory Sheet-side interface (to adjacent Memory Sheet)
    // Sheet request out
    output wire                    sheet_req_valid,
    output wire                    sheet_req_write,
    output wire [ADDR_WIDTH-1:0]   sheet_req_addr,
    output wire [DATA_WIDTH-1:0]   sheet_req_wdata,
    input  wire                    sheet_req_ready,

    // Sheet response in
    input  wire                    sheet_resp_valid,
    input  wire [DATA_WIDTH-1:0]   sheet_resp_rdata,
    output wire                    sheet_resp_ready,

    // Credit flow & status
    output wire [3:0]              credits_available,   // credits remaining
    output wire                    fc_busy              // pending transactions
);

    // Local parameters

    localparam PTR_W    = (BUFFER_DEPTH <= 1) ? 1 : $clog2(BUFFER_DEPTH);

    // Count width - needs to represent 0 .. BUFFER_DEPTH inclusive
    localparam CNT_W    = $clog2(BUFFER_DEPTH + 1);

    // Credit counter width - needs to represent 0 .. CREDIT_COUNT inclusive
    localparam CREDIT_W = (CREDIT_COUNT <= 1) ? 1 : $clog2(CREDIT_COUNT + 1);

    // Request FIFO entry packing:  { write [1b] , addr [AW] , wdata [DW] }
    localparam REQ_W    = 1 + ADDR_WIDTH + DATA_WIDTH;

    // Typed constants (avoids width-mismatch warnings)
    localparam [PTR_W-1:0]    PTR_ZERO  = {PTR_W{1'b0}};
    localparam [PTR_W-1:0]    PTR_ONE   = {{(PTR_W-1){1'b0}}, 1'b1};
    localparam [PTR_W-1:0]    PTR_LAST  = BUFFER_DEPTH[PTR_W-1:0] - PTR_ONE;
    localparam [CNT_W-1:0]    CNT_ZERO  = {CNT_W{1'b0}};
    localparam [CNT_W-1:0]    CNT_ONE   = {{(CNT_W-1){1'b0}}, 1'b1};
    localparam [CNT_W-1:0]    CNT_FULL  = BUFFER_DEPTH[CNT_W-1:0];
    localparam [CREDIT_W-1:0] CRED_ZERO = {CREDIT_W{1'b0}};
    localparam [CREDIT_W-1:0] CRED_ONE  = {{(CREDIT_W-1){1'b0}}, 1'b1};
    localparam [CREDIT_W-1:0] CRED_INIT = CREDIT_COUNT[CREDIT_W-1:0];

    // Request FIFO - inline circular buffer
    reg  [REQ_W-1:0]   req_mem  [0:BUFFER_DEPTH-1];
    reg  [PTR_W-1:0]   req_wptr;
    reg  [PTR_W-1:0]   req_rptr;
    reg  [CNT_W-1:0]   req_count;

    wire               req_full  = (req_count == CNT_FULL);
    wire               req_empty = (req_count == CNT_ZERO);

    // Handshake fires
    wire req_push = core_req_valid  & core_req_ready;    // enqueue from core
    wire req_pop  = sheet_req_valid & sheet_req_ready;    // dequeue to sheet

    // Next-pointer with wrap
    wire [PTR_W-1:0] req_wptr_nxt = (req_wptr == PTR_LAST) ? PTR_ZERO
                                                            : req_wptr + PTR_ONE;
    wire [PTR_W-1:0] req_rptr_nxt = (req_rptr == PTR_LAST) ? PTR_ZERO
                                                            : req_rptr + PTR_ONE;

    always @(posedge clk) begin
        if (reset) begin
            req_wptr  <= PTR_ZERO;
            req_rptr  <= PTR_ZERO;
            req_count <= CNT_ZERO;
        end else begin
            case ({req_push, req_pop})
                2'b10: begin   // push only
                    req_mem[req_wptr] <= {core_req_write, core_req_addr,
                                          core_req_wdata};
                    req_wptr          <= req_wptr_nxt;
                    req_count         <= req_count + CNT_ONE;
                end
                2'b01: begin   // pop only
                    req_rptr  <= req_rptr_nxt;
                    req_count <= req_count - CNT_ONE;
                end
                2'b11: begin   // simultaneous push + pop
                    req_mem[req_wptr] <= {core_req_write, core_req_addr,
                                          core_req_wdata};
                    req_wptr          <= req_wptr_nxt;
                    req_rptr          <= req_rptr_nxt;
                    // count is unchanged
                end
                default: ;     // 2'b00 - idle
            endcase
        end
    end

    // Head-of-queue read (combinational)
    wire [REQ_W-1:0] req_head = req_mem[req_rptr];

    // Response FIFO - inline circular buffer
    reg  [DATA_WIDTH-1:0] resp_mem  [0:BUFFER_DEPTH-1];
    reg  [PTR_W-1:0]      resp_wptr;
    reg  [PTR_W-1:0]      resp_rptr;
    reg  [CNT_W-1:0]      resp_count;

    wire                  resp_full  = (resp_count == CNT_FULL);
    wire                  resp_empty = (resp_count == CNT_ZERO);

    // Handshake fires
    wire resp_push = sheet_resp_valid & sheet_resp_ready;  // enqueue from sheet
    wire resp_pop  = core_resp_valid  & core_resp_ready;   // dequeue to core

    // Next-pointer with wrap
    wire [PTR_W-1:0] resp_wptr_nxt = (resp_wptr == PTR_LAST) ? PTR_ZERO
                                                              : resp_wptr + PTR_ONE;
    wire [PTR_W-1:0] resp_rptr_nxt = (resp_rptr == PTR_LAST) ? PTR_ZERO
                                                              : resp_rptr + PTR_ONE;

    always @(posedge clk) begin
        if (reset) begin
            resp_wptr  <= PTR_ZERO;
            resp_rptr  <= PTR_ZERO;
            resp_count <= CNT_ZERO;
        end else begin
            case ({resp_push, resp_pop})
                2'b10: begin   // push only
                    resp_mem[resp_wptr] <= sheet_resp_rdata;
                    resp_wptr           <= resp_wptr_nxt;
                    resp_count          <= resp_count + CNT_ONE;
                end
                2'b01: begin   // pop only
                    resp_rptr  <= resp_rptr_nxt;
                    resp_count <= resp_count - CNT_ONE;
                end
                2'b11: begin   // simultaneous push + pop
                    resp_mem[resp_wptr] <= sheet_resp_rdata;
                    resp_wptr           <= resp_wptr_nxt;
                    resp_rptr           <= resp_rptr_nxt;
                    // count is unchanged
                end
                default: ;     // 2'b00 - idle
            endcase
        end
    end

    // Head-of-queue read (combinational)
    wire [DATA_WIDTH-1:0] resp_head = resp_mem[resp_rptr];

    // Credit Manager
    reg [CREDIT_W-1:0] credit_cnt;

    wire credit_dec  = req_pop;    // request sent to sheet   → consume credit
    wire credit_inc  = resp_push;  // response from sheet     → return credit
    wire has_credits = (credit_cnt != CRED_ZERO);

    always @(posedge clk) begin
        if (reset) begin
            credit_cnt <= CRED_INIT;
        end else begin
            case ({credit_inc, credit_dec})
                2'b10:   credit_cnt <= credit_cnt + CRED_ONE;  // return
                2'b01:   credit_cnt <= credit_cnt - CRED_ONE;  // consume
                default: ;  // 2'b00 no change, 2'b11 net-zero
            endcase
        end
    end

    // Request Scheduler - drives Memory-Sheet-side request port

    // Accept core requests whenever the request FIFO has room
    assign core_req_ready  = ~req_full;

    // Present a request to the sheet only when:
    // (a) The request FIFO is non-empty, AND
    // (b) We have at least one credit outstanding
    assign sheet_req_valid = ~req_empty & has_credits;

    // Unpack the request FIFO head into sheet-side signals
    // Packing order (MSB → LSB):  { write [1b], addr [AW], wdata [DW] }
    assign sheet_req_write = req_head[ADDR_WIDTH + DATA_WIDTH];
    assign sheet_req_addr  = req_head[DATA_WIDTH +: ADDR_WIDTH];
    assign sheet_req_wdata = req_head[DATA_WIDTH-1:0];

    // Response Scheduler - drives core-side response port

    // Accept sheet responses whenever the response FIFO has room
    assign sheet_resp_ready = ~resp_full;

    // Present a response to the core whenever the response FIFO is non-empty
    assign core_resp_valid = ~resp_empty;
    assign core_resp_rdata = resp_head;

    // Status Outputs

    // Credits remaining (zero-extended or truncated to 4 bits)
    assign credits_available = credit_cnt;

    // Busy when any FIFO is non-empty OR there are in-flight transactions
    // (i.e. some credits have been consumed but their responses haven't
    // arrived yet)
    assign fc_busy = ~req_empty | ~resp_empty | (credit_cnt != CRED_INIT);

    // Performance Counters (synthesisable, free-running, 32-bit)
    reg [31:0] perf_reqs_sent;   // total requests forwarded to sheet
    reg [31:0] perf_resps_recv;  // total responses delivered to core

    always @(posedge clk) begin
        if (reset) begin
            perf_reqs_sent  <= 32'd0;
            perf_resps_recv <= 32'd0;
        end else begin
            if (req_pop)  perf_reqs_sent  <= perf_reqs_sent  + 32'd1;
            if (resp_pop) perf_resps_recv <= perf_resps_recv + 32'd1;
        end
    end

    // Parameter Validation (synthesis-time)
    // synopsys translate_off
    initial begin
        if (BUFFER_DEPTH < 1) begin
            $fatal(1, "face_controller: BUFFER_DEPTH must be >= 1 (got %0d)",
                   BUFFER_DEPTH);
        end
        if (CREDIT_COUNT < 1) begin
            $fatal(1, "face_controller: CREDIT_COUNT must be >= 1 (got %0d)",
                   CREDIT_COUNT);
        end
        if (FACE_ID > 5) begin
            $warning("face_controller: FACE_ID=%0d is outside 0-5 range",
                     FACE_ID);
        end
    end
    // synopsys translate_on

endmodule

`default_nettype wire
