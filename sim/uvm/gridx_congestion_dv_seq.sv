// UVM test sequence driving sustained multi-die crossbar congestion and verifying watermark backpressure.
`ifndef GRIDX_CONGESTION_DV_SEQ_SV
`define GRIDX_CONGESTION_DV_SEQ_SV

class gridx_congestion_dv_seq extends uvm_sequence #(gridx_host_seq_item);
    `uvm_object_utils(gridx_congestion_dv_seq)

    function new(string name = "gridx_congestion_dv_seq");
        super.new(name);
    endfunction

    virtual task body();
        gridx_host_seq_item item;

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_RESET;
        `uvm_send(item)
        `uvm_info("CONG_DV_SEQ", "Step 1: System and GALS Mesh reset completed", UVM_LOW)

        `uvm_create(item) item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM; item.mem_addr = 22'h000010; item.mem_data = 8'hA1; `uvm_send(item)
        `uvm_create(item) item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM; item.mem_addr = 22'h000011; item.mem_data = 8'hB2; `uvm_send(item)
        `uvm_create(item) item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM; item.mem_addr = 22'h000012; item.mem_data = 8'hC3; `uvm_send(item)
        `uvm_create(item) item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM; item.mem_addr = 22'h000013; item.mem_data = 8'hD4; `uvm_send(item)

        for (int i = 0; i < 32; i++) begin
            `uvm_create(item)
            item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM;
            item.mem_addr = 22'h0000E0 + i;
            item.mem_data = 8'(i * 7);
            `uvm_send(item)
        end

        `uvm_create(item) item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM; item.mem_addr = 22'h000200; item.mem_data = 8'h55; `uvm_send(item)
        `uvm_create(item) item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM; item.mem_addr = 22'h000201; item.mem_data = 8'hAA; `uvm_send(item)

        `uvm_info("CONG_DV_SEQ", "Step 2: Seed data populated across memory map", UVM_LOW)

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_LOAD_PROG;
        item.program_binary = new[28];

        item.program_binary[0]  = enc_const(4'h5, 8'hF0);
        item.program_binary[1]  = enc_const(4'h6, 8'h40);
        item.program_binary[2]  = {OP_STR, 4'h0, 4'h5, 4'h6};

        item.program_binary[3]  = enc_const(4'h1, 8'hA1);
        item.program_binary[4]  = enc_const(4'h2, 8'hA0);
        item.program_binary[5]  = enc_rrr(OP_ADD, 4'h3, 4'h2, 4'hF);
        item.program_binary[6]  = {OP_STR, 4'h0, 4'h3, 4'h1};

        item.program_binary[7]  = enc_const(4'h1, 8'hB2);
        item.program_binary[8]  = enc_const(4'h2, 8'hB0);
        item.program_binary[9]  = enc_rrr(OP_ADD, 4'h3, 4'h2, 4'hF);
        item.program_binary[10] = {OP_STR, 4'h0, 4'h3, 4'h1};

        item.program_binary[11] = enc_const(4'h1, 8'hC3);
        item.program_binary[12] = enc_const(4'h2, 8'hC0);
        item.program_binary[13] = enc_rrr(OP_ADD, 4'h3, 4'h2, 4'hF);
        item.program_binary[14] = {OP_STR, 4'h0, 4'h3, 4'h1};

        item.program_binary[15] = {4'h0 , 12'h000};
        item.program_binary[16] = {4'h0 , 12'h000};

        item.program_binary[17] = enc_const(4'h7, 8'h00);
        item.program_binary[18] = enc_rrr(OP_CMP, 4'h0, 4'hD, 4'h7);
        item.program_binary[19] = {OP_BRnzp, 3'b001, 1'b0, 8'd24};

        item.program_binary[20] = {4'h0 , 12'h000};
        item.program_binary[21] = {4'h0 , 12'h000};
        item.program_binary[22] = {OP_LDR, 4'h4, 4'h3, 4'h0};
        item.program_binary[23] = {4'h0 , 12'h000};

        item.program_binary[24] = {OP_RET, 12'h000};
        item.program_binary[25] = {OP_RET, 12'h000};
        item.program_binary[26] = {OP_RET, 12'h000};
        item.program_binary[27] = {OP_RET, 12'h000};

        `uvm_send(item)
        `uvm_info("CONG_DV_SEQ", "Step 3: Multi-burst congestion kernel loaded (28 instructions, 3 continuous store waves)", UVM_LOW)

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_CONFIGURE;
        item.thread_count = 16'd32;
        `uvm_send(item)
        `uvm_info("CONG_DV_SEQ", "Step 4: Configured 32 threads across 8 physical cores", UVM_LOW)

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_START;
        `uvm_send(item)
        `uvm_info("CONG_DV_SEQ", "Step 5: Congestion kernel launched - sustained saturation initiated", UVM_LOW)

    endtask
endclass

`endif
