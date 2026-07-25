
`default_nettype none
`timescale 1ns/1ns

module multicast_tree #(
    parameter NUM_GROUPS   = 16,
    parameter MAX_TARGETS  = 8,
    parameter FLIT_WIDTH   = 512,
    parameter GROUP_ID_W   = 4
) (
    input  wire clk,
    input  wire reset,

    input  wire                         cfg_valid,
    input  wire [GROUP_ID_W-1:0]        cfg_group_id,
    input  wire [MAX_TARGETS-1:0]       cfg_target_mask,
    input  wire                         cfg_enable,

    input  wire                         flit_in_valid,
    input  wire [FLIT_WIDTH-1:0]        flit_in_data,
    input  wire [GROUP_ID_W-1:0]        flit_in_group_id,
    input  wire                         flit_in_is_multicast,

    output reg                          flit_out_valid,
    output reg  [FLIT_WIDTH-1:0]        flit_out_data,
    output reg  [$clog2(MAX_TARGETS)-1:0] flit_out_target_id,
    input  wire                         flit_out_ready,

    output wire                         busy,
    output reg  [15:0]                  multicast_count
);

    reg [MAX_TARGETS-1:0] group_mask   [NUM_GROUPS-1:0];
    reg [NUM_GROUPS-1:0]  group_active;

    reg                          repl_active;
    reg [FLIT_WIDTH-1:0]         repl_data;
    reg [MAX_TARGETS-1:0]        repl_remaining;
    reg [$clog2(MAX_TARGETS)-1:0] repl_current;

    assign busy = repl_active;

    integer i;

    reg [$clog2(MAX_TARGETS)-1:0] next_target;
    reg                           next_found;
    always @(*) begin
        next_found = 0;
        next_target = 0;
        for (i = 0; i < MAX_TARGETS; i = i + 1) begin
            if (repl_remaining[i] && !next_found) begin
                next_found = 1;
                next_target = i;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            repl_active <= 0;
            flit_out_valid <= 0;
            multicast_count <= 0;
            group_active <= 0;
            for (i = 0; i < NUM_GROUPS; i = i + 1) begin
                group_mask[i] <= 0;
            end
        end else begin
            flit_out_valid <= 0;

            if (cfg_valid) begin
                group_mask[cfg_group_id] <= cfg_target_mask;
                group_active[cfg_group_id] <= cfg_enable;
            end

            if (flit_in_valid && flit_in_is_multicast && !repl_active) begin
                if (group_active[flit_in_group_id]) begin
                    repl_active <= 1;
                    repl_data <= flit_in_data;
                    repl_remaining <= group_mask[flit_in_group_id];
                    multicast_count <= multicast_count + 1;
                end
            end

            if (repl_active) begin
                if (next_found) begin
                    flit_out_valid <= 1;
                    flit_out_data <= repl_data;
                    flit_out_target_id <= next_target;
                    repl_current <= next_target;

                    if (flit_out_ready) begin
                        repl_remaining[next_target] <= 0;
                    end
                end else begin

                    repl_active <= 0;
                end
            end
        end
    end

endmodule
