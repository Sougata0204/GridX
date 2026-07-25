module tb_mem_mesh_router;

    timeunit 1ns;
    timeprecision 1ns;

    import gridx_mem_pkg::*;

    logic clk;
    logic rst_n;

    coord_t my_coord;

    flit_t   [NUM_PORTS-1:0] flit_in;
    logic    [NUM_PORTS-1:0] flit_in_valid;
    credit_t [NUM_PORTS-1:0] credit_out;

    flit_t   [NUM_PORTS-1:0] flit_out;
    logic    [NUM_PORTS-1:0] flit_out_valid;
    credit_t [NUM_PORTS-1:0] credit_in;

    mem_mesh_router dut (
        .clk(clk),
        .rst_n(rst_n),
        .my_coord(my_coord),
        .flit_in(flit_in),
        .flit_in_valid(flit_in_valid),
        .credit_out(credit_out),
        .flit_out(flit_out),
        .flit_out_valid(flit_out_valid),
        .credit_in(credit_in)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 0;
        my_coord = '{x: 2'd1, y: 2'd1, z: 2'd1};

        flit_in = '0;
        flit_in_valid = '0;
        credit_in = '0;

        #20;
        rst_n = 1;

        #20;

        flit_in_valid[PORT_LOCAL] = 1'b1;
        flit_in[PORT_LOCAL].valid = 1'b1;
        flit_in[PORT_LOCAL].flit_type = FLIT_HEAD;
        flit_in[PORT_LOCAL].vc_id = VC_READ_REQ;

        begin
            head_flit_t hf;
            hf.pkt_type = PKT_READ_REQ;
            hf.src_coord = my_coord;
            hf.dest_coord = '{x: 2'd2, y: 2'd1, z: 2'd1};
            hf.vc_id = VC_READ_REQ;
            hf.payload_meta = '0;
            flit_in[PORT_LOCAL].data = hf;
        end

        #10;
        flit_in_valid[PORT_LOCAL] = 1'b0;

        #50;

        if (flit_out_valid[PORT_X_POS]) begin
            $display("SUCCESS: Flit routed to X_POS correctly!");
        end else begin
            $display("ERROR: Flit did not route to X_POS as expected. Out valid signals = %b", flit_out_valid);
        end

        $finish;
    end

endmodule
