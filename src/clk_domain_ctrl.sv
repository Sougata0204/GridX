
`default_nettype none
`timescale 1ns/1ns

module clk_domain_ctrl #(
    parameter NUM_CLUSTERS      = 8,
    parameter CORES_PER_CLUSTER = 4,
    parameter SAMPLE_WINDOW     = 1024,
    parameter UP_THRESHOLD      = 75,
    parameter DOWN_THRESHOLD    = 25,
    parameter HYSTERESIS        = 8
) (
    input  wire clk,
    input  wire reset,

    input  wire [NUM_CLUSTERS-1:0] cluster_alu_active,
    input  wire [NUM_CLUSTERS-1:0] cluster_tensor_active,
    input  wire [NUM_CLUSTERS-1:0] cluster_stall_mem,

    input  wire [6:0]              cluster_temp [NUM_CLUSTERS-1:0],
    input  wire [6:0]              thermal_limit,

    output reg  [1:0]              cluster_perf_level [NUM_CLUSTERS-1:0],
    output reg  [NUM_CLUSTERS-1:0] cluster_clock_enable,
    output reg  [NUM_CLUSTERS-1:0] cluster_power_gate,

    output reg  [NUM_CLUSTERS-1:0] cluster_throttled,
    output wire [31:0]             total_gated_cycles
);

    localparam [1:0] PERF_IDLE = 2'b00;
    localparam [1:0] PERF_LOW  = 2'b01;
    localparam [1:0] PERF_MED  = 2'b10;
    localparam [1:0] PERF_HIGH = 2'b11;

    reg [15:0] active_cycles  [NUM_CLUSTERS-1:0];
    reg [15:0] sample_counter;
    reg [31:0] gated_cycles;
    assign total_gated_cycles = gated_cycles;

    integer c;

    always @(posedge clk) begin
        if (reset) begin
            sample_counter <= 0;
            gated_cycles   <= 0;
            for (c = 0; c < NUM_CLUSTERS; c = c + 1) begin
                active_cycles[c]      <= 0;
                cluster_perf_level[c] <= PERF_MED;
                cluster_clock_enable[c] <= 1;
                cluster_power_gate[c]   <= 0;
                cluster_throttled[c]    <= 0;
            end
        end else begin
            sample_counter <= sample_counter + 1;

            for (c = 0; c < NUM_CLUSTERS; c = c + 1) begin
                if (cluster_alu_active[c] || cluster_tensor_active[c])
                    active_cycles[c] <= active_cycles[c] + 1;

                if (!cluster_clock_enable[c])
                    gated_cycles <= gated_cycles + 1;
            end

            if (sample_counter >= SAMPLE_WINDOW) begin
                sample_counter <= 0;

                for (c = 0; c < NUM_CLUSTERS; c = c + 1) begin

                    if (cluster_temp[c] >= thermal_limit) begin

                        cluster_perf_level[c] <= PERF_LOW;
                        cluster_throttled[c]  <= 1;
                    end else begin
                        cluster_throttled[c] <= 0;

                        if (active_cycles[c] > ((UP_THRESHOLD * SAMPLE_WINDOW) / 100)) begin

                            if (cluster_perf_level[c] < PERF_HIGH)
                                cluster_perf_level[c] <= cluster_perf_level[c] + 1;
                        end else if (active_cycles[c] < ((DOWN_THRESHOLD * SAMPLE_WINDOW) / 100)) begin

                            if (cluster_perf_level[c] > PERF_IDLE)
                                cluster_perf_level[c] <= cluster_perf_level[c] - 1;
                        end

                    end

                    cluster_clock_enable[c] <= (cluster_perf_level[c] != PERF_IDLE);

                    cluster_power_gate[c] <= (cluster_perf_level[c] == PERF_IDLE) &&
                                              (active_cycles[c] == 0);

                    active_cycles[c] <= 0;
                end
            end
        end
    end

endmodule
