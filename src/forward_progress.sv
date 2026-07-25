
`default_nettype none
`timescale 1ns/1ns

module forward_progress #(
    parameter NUM_WARPS = 1,
    parameter WARP_ID_WIDTH = 1,
    parameter WATCHDOG_CYCLES = 10000,
    parameter COUNTER_WIDTH = 16
) (
    input wire clk,
    input wire reset,
    input wire [NUM_WARPS-1:0] warp_active,
    input wire [NUM_WARPS-1:0] warp_made_progress,
    input wire mem_req_issued,
    input wire [15:0] mem_req_id,
    input wire mem_req_completed,
    input wire [15:0] mem_completed_id,
    output reg timeout_detected,
    output reg [WARP_ID_WIDTH-1:0] timeout_warp_id,
    output reg [15:0] pending_mem_requests,
    output reg dump_trigger,
    output reg [NUM_WARPS-1:0] stalled_warps,
    output reg [COUNTER_WIDTH-1:0] warp_stall_cycles [NUM_WARPS-1:0],
    output wire assert_warp_timeout,
    output wire assert_mem_leak
);
    reg [COUNTER_WIDTH-1:0] warp_watchdog [NUM_WARPS-1:0];
    integer w;
    always @(posedge clk) begin
        if (reset) begin
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                warp_watchdog[w] <= 0;
                warp_stall_cycles[w] <= 0;
            end
            timeout_detected <= 0;
            timeout_warp_id <= 0;
            stalled_warps <= 0;
            dump_trigger <= 0;
        end else begin
            timeout_detected <= 0;
            dump_trigger <= 0;
            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                if (warp_active[w]) begin
                    if (warp_made_progress[w]) begin
                        warp_watchdog[w] <= 0;
                        stalled_warps[w] <= 0;
                    end else begin
                        warp_watchdog[w] <= warp_watchdog[w] + 1;
                        warp_stall_cycles[w] <= warp_stall_cycles[w] + 1;
                        if (warp_watchdog[w] >= WATCHDOG_CYCLES) begin
                            timeout_detected <= 1;
                            timeout_warp_id <= w[WARP_ID_WIDTH-1:0];
                            stalled_warps[w] <= 1;
                            dump_trigger <= 1;
                            `ifdef SIMULATION
                                $display("[FORWARD_PROGRESS] TIMEOUT: Warp %0d stalled for %0d cycles",
                                         w, WATCHDOG_CYCLES);
                            `endif
                        end
                    end
                end else begin
                    warp_watchdog[w] <= 0;
                    stalled_warps[w] <= 0;
                end
            end
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            pending_mem_requests <= 0;
        end else begin
            if (mem_req_issued && !mem_req_completed) begin
                pending_mem_requests <= pending_mem_requests + 1;
            end else if (!mem_req_issued && mem_req_completed) begin
                pending_mem_requests <= pending_mem_requests - 1;
            end
        end
    end
    assign assert_warp_timeout = timeout_detected;
    assign assert_mem_leak = (pending_mem_requests > 1000);
endmodule
