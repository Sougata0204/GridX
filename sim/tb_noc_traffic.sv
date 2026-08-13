`timescale 1ns/1ps

import gridx_mem_pkg::*;

module tb_noc_traffic();

    localparam CLK_PERIOD = 5.0; // 200 MHz

    logic [MESH_Z-1:0] clk_layer;
    logic rst_n;

    flit_t   [NUM_NODES-1:0] local_flit_in;
    logic    [NUM_NODES-1:0] local_flit_in_valid;
    credit_t [NUM_NODES-1:0] local_credit_out;

    flit_t   [NUM_NODES-1:0] local_flit_out;
    logic    [NUM_NODES-1:0] local_flit_out_valid;
    credit_t [NUM_NODES-1:0] local_credit_in;

    // Generate clocks
    initial begin
        clk_layer = '0;
        forever #(CLK_PERIOD/2) clk_layer = ~clk_layer;
    end

    // Reset sequence
    initial begin
        rst_n = 0;
        local_flit_in = '0;
        local_flit_in_valid = '0;
        local_credit_in = '0;
        repeat(20) @(posedge clk_layer[0]);
        rst_n = 1;
    end

    mem_mesh_top dut (
        .clk_layer           (clk_layer),
        .rst_n               (rst_n),
        .local_flit_in       (local_flit_in),
        .local_flit_in_valid (local_flit_in_valid),
        .local_credit_out    (local_credit_out),
        .local_flit_out      (local_flit_out),
        .local_flit_out_valid(local_flit_out_valid),
        .local_credit_in     (local_credit_in)
    );

    // Track credits
    int credits[NUM_NODES][NUM_VCS];
    initial begin
        for (int i=0; i<NUM_NODES; i++) begin
            for (int v=0; v<NUM_VCS; v++) begin
                credits[i][v] = FLITS_PER_BUFFER;
            end
        end
    end

    always @(posedge clk_layer[0]) begin
        if (rst_n) begin
            for (int i=0; i<NUM_NODES; i++) begin
                if (local_credit_out[i].valid) begin
                    credits[i][local_credit_out[i].vc_id]++;
                end
                if (local_flit_in_valid[i]) begin
                    credits[i][local_flit_in[i].vc_id]--;
                end
            end
        end
    end

    // Auto-return credits for flits received
    always @(posedge clk_layer[0]) begin
        for (int i=0; i<NUM_NODES; i++) begin
            if (local_flit_out_valid[i]) begin
                local_credit_in[i].valid <= 1'b1;
                local_credit_in[i].vc_id <= local_flit_out[i].vc_id;
            end else begin
                local_credit_in[i].valid <= 1'b0;
            end
        end
    end

    // Traffic generator
    real injection_rate = 0.50; // 50% load
    int flits_sent = 0;
    int flits_received = 0;

    always @(posedge clk_layer[0]) begin
        if (rst_n) begin
            for (int i=0; i<NUM_NODES; i++) begin
                local_flit_in_valid[i] <= 1'b0;
                
                // Uniform Random Traffic Profile
                if ($urandom_range(0, 99) < (injection_rate * 100)) begin
                    int dest = $urandom_range(0, NUM_NODES-1);
                    int vc = $urandom_range(0, NUM_VCS-1);
                    
                    if (dest != i && credits[i][vc] > 0) begin
                        local_flit_in_valid[i] <= 1'b1;
                        local_flit_in[i].flit_type <= FLIT_HEAD;
                        local_flit_in[i].vc_id <= vc_id_e'(vc);
                        // Encode destination in lower bits of data, source in next
                        local_flit_in[i].data <= {224'd0, 16'(i), 16'(dest)};
                        flits_sent++;
                    end
                end
            end
        end
    end

    // Scoreboard / Receiver
    always @(posedge clk_layer[0]) begin
        if (rst_n) begin
            for (int i=0; i<NUM_NODES; i++) begin
                if (local_flit_out_valid[i]) begin
                    int actual_dest = local_flit_out[i].data[15:0];
                    if (actual_dest != i) begin
                        $error("Scoreboard Error: Flit delivered to %0d, but destined for %0d!", i, actual_dest);
                    end
                    flits_received++;
                end
            end
        end
    end

    initial begin
        wait(rst_n);
        $display("[TB] Reset complete. Starting traffic injection at %0f rate.", injection_rate);
        repeat(10000) @(posedge clk_layer[0]);
        $display("[TB] Test complete. Sent: %0d, Received: %0d", flits_sent, flits_received);
        if (flits_sent - flits_received > NUM_NODES * NUM_PORTS * FLITS_PER_BUFFER) begin
            $error("Scoreboard Error: Too many flits in flight. Potential drops!");
        end else begin
            $display("[TB] Scoreboard MATCH!");
        end
        $finish;
    end

endmodule
