// UVM compute workload sequence executing SAXPY vector kernel across all SIMT cores and HBM.
`ifndef GRIDX_SAXPY_SEQ_SV
`define GRIDX_SAXPY_SEQ_SV

class gridx_saxpy_seq extends uvm_sequence #(gridx_host_seq_item);
    `uvm_object_utils(gridx_saxpy_seq)

    function new(string name = "gridx_saxpy_seq");
        super.new(name);
    endfunction

    virtual task body();
        gridx_host_seq_item req, rsp;

        logic [15:0] saxpy_kernel[] = '{
            16'h9A80,
            16'h9B10,
            16'h5BBB,
            16'h5AAB,
            16'h9110,
            16'h31A1,
            16'h9220,
            16'h32A2,
            16'h9330,
            16'h33A3,
            16'h9740,
            16'h37A7,
            16'h9890,
            16'h588B,
            16'h9940,
            16'h3889,
            16'h7410,
            16'h7520,
            16'h7630,
            16'h5464,
            16'h3545,
            16'h8075,
            16'h8085,
            16'hF000
        };

        `uvm_info("SAXPY_SEQ", "Starting SAXPY Kernel UVM sequence", UVM_LOW)

        req = gridx_host_seq_item::type_id::create("req");
        start_item(req);
        req.cmd_type = gridx_host_seq_item::CMD_RESET;
        finish_item(req);
        `uvm_info("SAXPY_SEQ", "CMD_RESET finished", UVM_NONE)

        req = gridx_host_seq_item::type_id::create("req");
        start_item(req);
        req.cmd_type = gridx_host_seq_item::CMD_LOAD_PROG;
        req.program_binary = saxpy_kernel;
        finish_item(req);
        `uvm_info("SAXPY_SEQ", "CMD_LOAD_PROG finished", UVM_NONE)

        req = gridx_host_seq_item::type_id::create("req");
        start_item(req);
        req.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM;
        req.mem_addr = 22'h008010;
        req.mem_data = 8'd5;
        finish_item(req);
        `uvm_info("SAXPY_SEQ", "CMD_WRITE_HBM X=5 finished", UVM_NONE)

        req = gridx_host_seq_item::type_id::create("req");
        start_item(req);
        req.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM;
        req.mem_addr = 22'h008020;
        req.mem_data = 8'd3;
        finish_item(req);
        `uvm_info("SAXPY_SEQ", "CMD_WRITE_HBM Y=3 finished", UVM_NONE)

        req = gridx_host_seq_item::type_id::create("req");
        start_item(req);
        req.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM;
        req.mem_addr = 22'h008030;
        req.mem_data = 8'd2;
        finish_item(req);
        `uvm_info("SAXPY_SEQ", "CMD_WRITE_HBM A=2 finished", UVM_NONE)

        req = gridx_host_seq_item::type_id::create("req");
        start_item(req);
        req.cmd_type = gridx_host_seq_item::CMD_CONFIGURE;
        req.thread_count = 16'd1;
        finish_item(req);
        `uvm_info("SAXPY_SEQ", "CMD_CONFIGURE finished", UVM_NONE)

        `uvm_info("SAXPY_SEQ", "Triggering kernel start!", UVM_NONE)

        req = gridx_host_seq_item::type_id::create("req");
        start_item(req);
        req.cmd_type = gridx_host_seq_item::CMD_START;
        finish_item(req);
        `uvm_info("SAXPY_SEQ", "CMD_START finished", UVM_NONE)

        req = gridx_host_seq_item::type_id::create("req");
        start_item(req);
        req.cmd_type = gridx_host_seq_item::CMD_READ_HBM;
        req.mem_addr = 22'h009040;
        finish_item(req);
        `uvm_info("SAXPY_SEQ", "CMD_READ_HBM finished", UVM_NONE)

        if (req.read_data === 8'd13) begin
            `uvm_info("SAXPY_SEQ", $sformatf("MATH SUCCESS! Z = %0d. Logic flows perfectly from Core->NoC->HBM", req.read_data), UVM_NONE)
        end else begin
            `uvm_error("SAXPY_SEQ", $sformatf("MATH FAIL! Expected 13, got %0d (0x%02h)", req.read_data, req.read_data))
        end
    endtask
endclass

`endif
