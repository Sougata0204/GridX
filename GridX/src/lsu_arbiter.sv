`default_nettype none
`timescale 1ns/1ns

module lsu_arbiter #(
    parameter NUM_REQUESTERS = 64,
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 8
) (
    input wire clk,
    input wire reset,

    // Inputs from LSUs
    input wire [NUM_REQUESTERS-1:0] request_valid,
    input wire [NUM_REQUESTERS-1:0] request_write, // 1=Write, 0=Read
    input wire [ADDR_WIDTH-1:0] request_addr [NUM_REQUESTERS-1:0],
    input wire [DATA_WIDTH-1:0] request_data [NUM_REQUESTERS-1:0],

    // Outputs to Memory Controller
    output reg mem_valid,
    output reg mem_write,
    output reg [ADDR_WIDTH-1:0] mem_addr,
    output reg [DATA_WIDTH-1:0] mem_data,
    input wire mem_ready,

    // Feedback to LSUs
    output reg [NUM_REQUESTERS-1:0] grant // One-hot grant signal
);

    integer i;

    // Combinational Logic for Priority Arbitration
    always @(*) begin
        mem_valid = 0;
        mem_write = 0;
        mem_addr = 0;
        mem_data = 0;
        grant = 0;

        // Priority Encoder (Lowest ID gets priority)
        for (i = 0; i < NUM_REQUESTERS; i = i + 1) begin
            if (request_valid[i]) begin
                mem_valid = 1;
                mem_write = request_write[i];
                mem_addr = request_addr[i];
                mem_data = request_data[i];
                
                // If Memory is ready, we grant this request
                if (mem_ready) begin
                    grant[i] = 1;
                end
                
                // Found the winner, break logic
                break;
            end
        end
    end

endmodule
