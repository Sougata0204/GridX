// UVM multi-clock DV sequence verifying GALS clock domain crossings, Gray pointers, and credit invariants.
`ifndef GRIDX_MULTICLOCK_DV_SEQ_SV
`define GRIDX_MULTICLOCK_DV_SEQ_SV

class gridx_multiclock_dv_seq extends uvm_sequence #(gridx_host_seq_item);
    `uvm_object_utils(gridx_multiclock_dv_seq)

    function new(string name = "gridx_multiclock_dv_seq");
        super.new(name);
    endfunction

    virtual task body();
        gridx_host_seq_item item;

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_RESET;
        `uvm_send(item)
        `uvm_info("MCLK_DV_SEQ", "Step 1: System and GALS Mesh reset completed successfully", UVM_LOW)

        `uvm_create(item) item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM; item.mem_addr = 22'h000010; item.mem_data = 8'h00; `uvm_send(item)
        `uvm_create(item) item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM; item.mem_addr = 22'h000011; item.mem_data = 8'h55; `uvm_send(item)
        `uvm_create(item) item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM; item.mem_addr = 22'h000012; item.mem_data = 8'hAA; `uvm_send(item)
        `uvm_create(item) item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM; item.mem_addr = 22'h000013; item.mem_data = 8'hFF; `uvm_send(item)

        for (int i = 0; i < 32; i++) begin
            `uvm_create(item)
            item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM;
            item.mem_addr = 22'h0000E0 + i;
            item.mem_data = (i % 4 == 0) ? 8'h00 :
                            (i % 4 == 1) ? 8'h55 :
                            (i % 4 == 2) ? 8'hAA : 8'hFF;
            `uvm_send(item)
        end

        `uvm_create(item) item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM; item.mem_addr = 22'h000200; item.mem_data = 8'h00; `uvm_send(item)
        `uvm_create(item) item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM; item.mem_addr = 22'h000201; item.mem_data = 8'h55; `uvm_send(item)
        `uvm_create(item) item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM; item.mem_addr = 22'h000202; item.mem_data = 8'hAA; `uvm_send(item)
        `uvm_create(item) item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM; item.mem_addr = 22'h000203; item.mem_data = 8'hFF; `uvm_send(item)

        `uvm_info("MCLK_DV_SEQ", "Step 2: Seed data populated across intra-layer, TSV, and HBM memory partitions", UVM_LOW)

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_LOAD_PROG;
        item.program_binary = new[20];

        item.program_binary[0]  = enc_const(4'h5, 8'hF0);
        item.program_binary[1]  = enc_const(4'h6, 8'h40);
        item.program_binary[2]  = {OP_STR, 4'h0, 4'h5, 4'h6};

        item.program_binary[3]  = enc_const(4'h1, 8'hDE);
        item.program_binary[4]  = enc_const(4'h2, 8'hA0);
        item.program_binary[5]  = enc_rrr(OP_ADD, 4'h3, 4'h2, 4'hF);
        item.program_binary[6]  = {OP_STR, 4'h0, 4'h3, 4'h1};

        item.program_binary[7]  = {4'h0 , 12'h000};
        item.program_binary[8]  = {4'h0 , 12'h000};

        item.program_binary[9]  = enc_const(4'h7, 8'h00);
        item.program_binary[10] = enc_rrr(OP_CMP, 4'h0, 4'hD, 4'h7);
        item.program_binary[11] = {OP_BRnzp, 3'b001, 1'b0, 8'd16};

        item.program_binary[12] = {4'h0 , 12'h000};
        item.program_binary[13] = {4'h0 , 12'h000};
        item.program_binary[14] = {OP_LDR, 4'h4, 4'h3, 4'h0};
        item.program_binary[15] = {4'h0 , 12'h000};

        item.program_binary[16] = {OP_RET, 12'h000};
        item.program_binary[17] = {OP_RET, 12'h000};
        item.program_binary[18] = {OP_RET, 12'h000};
        item.program_binary[19] = {OP_RET, 12'h000};

        `uvm_send(item)
        `uvm_info("MCLK_DV_SEQ", "Step 3: Multi-clock GALS stress kernel loaded (20 instructions)", UVM_LOW)

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_CONFIGURE;
        item.thread_count = 16'd32;
        `uvm_send(item)
        `uvm_info("MCLK_DV_SEQ", "Step 4: Kernel configured for 32 threads across 8 physical cores", UVM_LOW)

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_START;
        `uvm_send(item)
        `uvm_info("MCLK_DV_SEQ", "Step 5: Kernel launched - initiating concurrent GALS cross-layer bursts", UVM_LOW)

    endtask
endclass

`endif
