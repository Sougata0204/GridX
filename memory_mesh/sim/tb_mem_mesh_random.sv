module tb_mem_mesh_random;
    timeunit 1ps;
    timeprecision 1ps;

    import gridx_mem_pkg::*;

    logic clk;
    logic rst_n;

    flit_t   [NUM_NODES-1:0] local_flit_in;
    logic    [NUM_NODES-1:0] local_flit_in_valid;
    credit_t [NUM_NODES-1:0] local_credit_out;

    flit_t   [NUM_NODES-1:0] local_flit_out;
    logic    [NUM_NODES-1:0] local_flit_out_valid;
    credit_t [NUM_NODES-1:0] local_credit_in;

    mem_mesh_top dut (.*);

    initial begin
        clk = 0;
        forever #125 clk = ~clk;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_NODES; i++) begin
                local_credit_in[i].valid <= 1'b0;
                local_credit_in[i].vc_id <= '0;
            end
        end else begin
            for (int i = 0; i < NUM_NODES; i++) begin
                local_credit_in[i].valid <= local_flit_out_valid[i] && local_flit_out[i].valid;
                local_credit_in[i].vc_id <= local_flit_out[i].vc_id;
            end
        end
    end

    int unsigned src_node;
    int unsigned dest_node;
    coord_t      dest_c;
    int          received_count = 0;
    int          wait_cycles;

    initial begin
        assert ($bits(head_flit_t) == 128)
            else $fatal(1, "FATAL: head_flit_t is %0d bits, expected 128", $bits(head_flit_t));
    end

    initial begin
        rst_n = 0;
        local_flit_in       = '0;
        local_flit_in_valid = '0;

        #20000;
        rst_n = 1;
        #20000;

        $display("[MESH_NOC] Memory Mesh NoC v2.0 - Randomized Test");
        $display("[MESH_NOC] Topology: %0dx%0dx%0d Mesh (%0d Nodes)", MESH_X, MESH_Y, MESH_Z, NUM_NODES);

        for (int iter = 0; iter < 50; iter++) begin
            src_node  = $urandom_range(0, NUM_NODES-1);
            dest_node = $urandom_range(0, NUM_NODES-1);
            while (dest_node == src_node)
                dest_node = $urandom_range(0, NUM_NODES-1);

            dest_c.x = dest_node % MESH_X;
            dest_c.y = (dest_node / MESH_X) % MESH_Y;
            dest_c.z = dest_node / (MESH_X * MESH_Y);

            $display("[Iter %0d] Node %0d -> Node %0d (X:%0d Y:%0d Z:%0d)",
                     iter, src_node, dest_node, dest_c.x, dest_c.y, dest_c.z);

            @(posedge clk);
            local_flit_in_valid[src_node]          = 1'b1;
            local_flit_in[src_node].valid          = 1'b1;
            local_flit_in[src_node].flit_type      = FLIT_HEAD;
            local_flit_in[src_node].vc_id          = VC_WRITE_REQ;

            begin
                head_flit_t hf;
                hf.pkt_type   = PKT_WRITE_REQ;
                hf.vc_id      = VC_WRITE_REQ;
                hf.src_coord  = '{x:0, y:0, z:0};
                hf.dest_coord = dest_c;
                hf.tx_id      = 5'(iter % 32);
                hf.ctrl_flags = 4'b0;
                hf.metadata   = 102'hCAFE_BABE_DEAD_BEEF;

                local_flit_in[src_node].data = FLIT_WIDTH'(hf);
            end

            @(posedge clk);
            local_flit_in_valid[src_node] = 1'b0;

            wait_cycles = 0;
            while (!local_flit_out_valid[dest_node] && wait_cycles < 50000) begin
                @(posedge clk);
                wait_cycles++;
            end

            if (wait_cycles >= 50000) begin
                $display("ERROR: Timeout at destination node %0d (waited %0d cycles)", dest_node, wait_cycles);
                $finish;
            end else begin
                $display("           --> SUCCESS: Reached Node %0d in %0d cycles", dest_node, wait_cycles);
                received_count++;
            end

            #50000;
        end

        $display("[MESH_NOC] RESULT: ALL %0d RANDOMIZED TESTS PASSED", received_count);
        $finish;
    end
endmodule
