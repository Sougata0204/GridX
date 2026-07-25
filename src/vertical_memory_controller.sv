
`default_nettype none
`timescale 1ns/1ns

module vertical_memory_controller #(
    parameter NUM_CORES = 4,
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8,
    parameter L2_BASE_ADDR = 16'h8000,
    parameter L2_LIMIT_ADDR = 16'h83FF,
    parameter L2_DEPTH = 1024
) (
    input wire clk,
    input wire reset,
    input wire [NUM_CORES-1:0] core_req_valid,
    input wire [NUM_CORES-1:0] core_req_write,
    input wire [ADDR_WIDTH-1:0] core_req_addr [NUM_CORES-1:0],
    input wire [DATA_WIDTH-1:0] core_req_data [NUM_CORES-1:0],
    output reg [NUM_CORES-1:0] core_req_grant,
    output reg [DATA_WIDTH-1:0] core_req_rdata [NUM_CORES-1:0],
    output reg [NUM_CORES-1:0] core_req_ready,
    output reg global_req_valid,
    output reg global_req_write,
    output reg [ADDR_WIDTH-1:0] global_req_addr,
    output reg [DATA_WIDTH-1:0] global_req_data,
    input wire global_req_ready,
    input wire [DATA_WIDTH-1:0] global_req_rdata
);
    reg [DATA_WIDTH-1:0] l2_memory [L2_DEPTH-1:0];
    localparam CORE_ID_W = (NUM_CORES > 1) ? $clog2(NUM_CORES) : 1;
    reg [CORE_ID_W-1:0] rr_ptr;
    integer i;
    reg [CORE_ID_W-1:0] winner_id;
    reg found;
    reg [CORE_ID_W-1:0] idx;
    reg [ADDR_WIDTH-1:0] addr;
    reg [ADDR_WIDTH-1:0] offset;
    always @(posedge clk) begin
        if (reset) begin
            rr_ptr <= 0;
            core_req_grant <= 0;
            core_req_ready <= 0;
            global_req_valid <= 0;
            for (i=0; i<L2_DEPTH; i=i+1) l2_memory[i] = 0;
        end else begin
            core_req_grant <= 0;
            core_req_ready <= 0;
            global_req_valid <= 0;
            found = 0;
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                idx = (rr_ptr + i[CORE_ID_W-1:0]) % NUM_CORES;
                if (core_req_valid[idx] && !found) begin
                    winner_id = idx;
                    found = 1;
                end
            end
            if (found) begin
                addr = core_req_addr[winner_id];
                if (addr >= L2_BASE_ADDR && addr <= L2_LIMIT_ADDR) begin
                    offset = addr - L2_BASE_ADDR;
                    if (core_req_write[winner_id]) begin
                        l2_memory[offset] <= core_req_data[winner_id];
                    end else begin
                        core_req_rdata[winner_id] <= l2_memory[offset];
                    end
                    core_req_ready[winner_id] <= 1;
                    core_req_grant[winner_id] <= 1;
                end else begin
                    global_req_valid <= 1;
                    global_req_write <= core_req_write[winner_id];
                    global_req_addr <= addr;
                    global_req_data <= core_req_data[winner_id];
                    if (global_req_ready) begin
                        core_req_ready[winner_id] <= 1;
                        core_req_rdata[winner_id] <= global_req_rdata;
                    end else begin
                        if (!global_req_ready) found = 0;
                    end
                end
                if (core_req_ready[winner_id]) begin
                    rr_ptr <= rr_ptr + 1;
                end
            end
        end
    end
endmodule
