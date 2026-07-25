// `default_nettype none  -- removed: module uses `logic` typed ports
`timescale 1ps/1ps

module mem_mesh_arbiter #(
    parameter int NUM_REQS   = 7,
    parameter int NUM_PRI    = 3
)(
    input  logic clk,
    input  logic rst_n,

    input  logic [NUM_REQS-1:0]       req,
    input  logic [NUM_REQS-1:0][1:0]  pri,
    output logic [NUM_REQS-1:0]       grant
);

    parameter int STARVE_THRESH = 16;
    logic [NUM_REQS-1:0][4:0] wait_counter;

    logic [NUM_PRI-1:0][$clog2(NUM_REQS)-1:0] rr_ptr;

    always_comb begin
        grant = '0;

        for (int pri_lvl = 0; pri_lvl < NUM_PRI; pri_lvl++) begin
            if (grant == '0) begin

                for (int r = 0; r < NUM_REQS; r++) begin
                    automatic int idx;
                    idx = (int'(rr_ptr[pri_lvl]) + r) % NUM_REQS;
                    if (grant == '0 && req[idx] &&
                        (pri[idx] == pri_lvl[1:0] || wait_counter[idx] >= STARVE_THRESH[4:0]))
                        grant[idx] = 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_ptr       <= '0;
            wait_counter <= '0;
        end else begin

            for (int r = 0; r < NUM_REQS; r++) begin
                if (req[r] && !grant[r]) begin
                    if (wait_counter[r] < 5'd31)
                        wait_counter[r] <= wait_counter[r] + 1'b1;
                end else begin
                    wait_counter[r] <= '0;
                end
            end

            for (int r = 0; r < NUM_REQS; r++) begin
                if (grant[r]) begin
                    rr_ptr[pri[r]] <= ($clog2(NUM_REQS))'((r + 1) % NUM_REQS);
                end
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n) begin

            assert ($onehot0(grant))
                else $error("ASSERT FAIL: arbiter grant not one-hot: %b", grant);
        end
    end
`endif

endmodule
