
`default_nettype none
`timescale 1ns/1ns

// GridX3 - LSU Arbiter
// Purpose: Fixed-priority arbiter for Load/Store Unit memory requests.
// Grants access to the lowest-indexed valid requester.
// Parameters: NUM_REQUESTERS, ADDR_WIDTH, DATA_WIDTH, IS_RESP
// Architecture: Combinational priority encoder. Lowest index wins.
// Integration: Instantiated in core.sv for both request and response paths.

module lsu_arbiter #(
    parameter NUM_REQUESTERS = 4,
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 8,
    parameter IS_RESP = 0
) (
    input wire clk,
    input wire reset,
    input wire [NUM_REQUESTERS-1:0] request_valid,
    input wire [NUM_REQUESTERS-1:0] request_write,
    input wire [ADDR_WIDTH-1:0] request_addr [NUM_REQUESTERS-1:0],
    input wire [DATA_WIDTH-1:0] request_data [NUM_REQUESTERS-1:0],
    output reg mem_valid,
    output reg mem_write,
    output reg [ADDR_WIDTH-1:0] mem_addr,
    output reg [DATA_WIDTH-1:0] mem_data,
    input wire mem_ready,
    output reg [NUM_REQUESTERS-1:0] grant
);
    integer i;
    always @(*) begin
        mem_valid = 0;
        mem_write = 0;
        mem_addr = 0;
        mem_data = 0;
        grant = 0;
        for (i = 0; i < NUM_REQUESTERS; i = i + 1) begin
            if (request_valid[i]) begin
                mem_valid = 1;
                mem_write = request_write[i];
                mem_addr = request_addr[i];
                mem_data = request_data[i];
                if (mem_ready) begin
                    grant[i] = 1;
                end
                break;
            end
        end
    end

    `ifdef GRIDX_ARB_DEBUG
    reg [31:0] dbg_cycle_cnt;
    always @(posedge clk) begin
        if (reset)
            dbg_cycle_cnt <= 32'd0;
        else
            dbg_cycle_cnt <= dbg_cycle_cnt + 32'd1;
    end
    always @(posedge clk) begin
        if (!reset && (dbg_cycle_cnt < 350)) begin
            $display("[ARB-DEBUG-%0d] Cycle %0d: request_valid=%b mem_ready=%b grant=%b",
                     IS_RESP, dbg_cycle_cnt, request_valid, mem_ready, grant);
        end
    end
    `endif

endmodule

