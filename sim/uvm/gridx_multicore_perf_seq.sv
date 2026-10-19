// UVM performance benchmark sequence measuring multicore IPC, mesh bandwidth, and HBM throughput.
`ifndef GRIDX_MULTICORE_PERF_SEQ_SV
`define GRIDX_MULTICORE_PERF_SEQ_SV

class gridx_multicore_perf_seq extends uvm_sequence #(gridx_host_seq_item);
    `uvm_object_utils(gridx_multicore_perf_seq)

    function new(string name = "gridx_multicore_perf_seq");
        super.new(name);
    endfunction

    virtual task body();
        gridx_host_seq_item item;

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_RESET;
        `uvm_send(item)
        `uvm_info("MCORE_SEQ", "Reset complete", UVM_LOW)

        for (int i = 0; i < 4; i++) begin
            `uvm_create(item)
            item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM;
            item.mem_addr = 22'h000010 + i;
            item.mem_data = 8'(i + 1);
            `uvm_send(item)
        end

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM;
        item.mem_addr = 22'h000020;
        item.mem_data = 8'd3;
        `uvm_send(item)

        `uvm_info("MCORE_SEQ", "Input data seeded into DMEM (X[0..3] + A)", UVM_LOW)

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_LOAD_PROG;
        item.program_binary = new[12];

        item.program_binary[0]  = {4'h9, 4'h1, 8'hDE};
        item.program_binary[1]  = {4'h9, 4'h2, 8'h40};
        item.program_binary[2]  = {4'h3, 4'h3, 4'h2, 4'hF};
        item.program_binary[3]  = {4'h8, 4'h0, 4'h3, 4'h1};

        item.program_binary[4]  = {4'h9, 4'h1, 8'hAD};
        item.program_binary[5]  = {4'h9, 4'h2, 8'hA0};
        item.program_binary[6]  = {4'h3, 4'h3, 4'h2, 4'hF};
        item.program_binary[7]  = {4'h8, 4'h0, 4'h3, 4'h1};

        item.program_binary[8]  = {4'h5, 4'h4, 4'hF, 4'h1};
        item.program_binary[9]  = {4'h9, 4'h2, 8'h60};
        item.program_binary[10] = {4'h3, 4'h3, 4'h2, 4'hF};
        item.program_binary[11] = {4'hF, 12'h000};

        `uvm_send(item)
        `uvm_info("MCORE_SEQ", "Multicore benchmark kernel loaded (12 instructions, 3 passes: local+HBM+ALU)", UVM_LOW)

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_CONFIGURE;
        item.thread_count = 16'd32;
        `uvm_send(item)
        `uvm_info("MCORE_SEQ", "Kernel configured: 32 total threads across 8 cores", UVM_LOW)

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_START;
        `uvm_send(item)
        `uvm_info("MCORE_SEQ", "Kernel launched - expecting 8-core x 4-thread execution through 3D mesh", UVM_LOW)

    endtask
endclass

`endif
