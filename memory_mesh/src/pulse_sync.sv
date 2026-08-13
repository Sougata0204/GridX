`default_nettype none
`timescale 1ps/1ps

module pulse_sync (
    input  wire clk_a,
    input  wire rst_a_n,
    input  wire pulse_a,

    input  wire clk_b,
    input  wire rst_b_n,
    output wire pulse_b
);

    reg toggle_a;
    reg sync_b1, sync_b2, sync_b3;

    // Domain A: Toggle on pulse
    always_ff @(posedge clk_a or negedge rst_a_n) begin
        if (!rst_a_n)
            toggle_a <= 1'b0;
        else if (pulse_a)
            toggle_a <= ~toggle_a;
    end

    // Domain B: Synchronize and edge detect
    always_ff @(posedge clk_b or negedge rst_b_n) begin
        if (!rst_b_n) begin
            sync_b1 <= 1'b0;
            sync_b2 <= 1'b0;
            sync_b3 <= 1'b0;
        end else begin
            sync_b1 <= toggle_a;
            sync_b2 <= sync_b1;
            sync_b3 <= sync_b2;
        end
    end

    assign pulse_b = sync_b2 ^ sync_b3;

endmodule
