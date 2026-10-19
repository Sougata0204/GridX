// UVM mixed compute-and-memory stress sequence exercising SIMT compute and 3D TSV vertical flits.
`ifndef GRIDX_MIXED_STRESS_SEQ_SV
`define GRIDX_MIXED_STRESS_SEQ_SV

class gridx_mixed_stress_seq extends uvm_sequence #(gridx_host_seq_item);
    `uvm_object_utils(gridx_mixed_stress_seq)

    function new(string name = "gridx_mixed_stress_seq");
        super.new(name);
    endfunction

    virtual task body();
        gridx_host_seq_item item;

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_RESET;
        `uvm_send(item)
        `uvm_info("MIXED_SEQ", "Step 1: System reset completed", UVM_LOW)

        for (int i = 0; i < 16; i++) begin
            `uvm_create(item)
            item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM;
            item.mem_addr = 22'h000010 + i;
            item.mem_data = 8'( (i + 1) * 3 );
            `uvm_send(item)
        end

        for (int i = 0; i < 32; i++) begin
            `uvm_create(item)
            item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM;
            item.mem_addr = 22'h0000A0 + i;
            item.mem_data = 8'h00;
            `uvm_send(item)
        end

        `uvm_info("MIXED_SEQ", "Step 2: Seed data populated in DMEM partitions", UVM_LOW)

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_LOAD_PROG;
        item.program_binary = new[28];

        item.program_binary[0]  = enc_const(4'h5, 8'hF0);
        item.program_binary[1]  = enc_const(4'h6, 8'h40);
        item.program_binary[2]  = {OP_STR, 4'h0, 4'h5, 4'h6};

        item.program_binary[3]  = enc_const(4'h1, 8'h02);
        item.program_binary[4]  = enc_rrr(OP_MUL, 4'h2, 4'hF, 4'h1);
        item.program_binary[5]  = enc_const(4'h3, 8'h05);
        item.program_binary[6]  = enc_rrr(OP_ADD, 4'h4, 4'h2, 4'h3);
        item.program_binary[7]  = enc_const(4'h7, 8'h20);
        item.program_binary[8]  = enc_rrr(OP_ADD, 4'h8, 4'h7, 4'hF);
        item.program_binary[9]  = {OP_STR, 4'h0, 4'h8, 4'h4};

        item.program_binary[10] = enc_const(4'h9, 8'hA0);
        item.program_binary[11] = enc_rrr(OP_ADD, 4'hA, 4'h9, 4'hF);
        item.program_binary[12] = {OP_STR, 4'h0, 4'hA, 4'h4};

        item.program_binary[13] = enc_const(4'h1, 8'h77);
        item.program_binary[14] = enc_rrr(OP_ADD, 4'h4, 4'h4, 4'h1);
        item.program_binary[15] = enc_const(4'h9, 8'hB0);
        item.program_binary[16] = enc_rrr(OP_ADD, 4'hA, 4'h9, 4'hF);
        item.program_binary[17] = {OP_STR, 4'h0, 4'hA, 4'h4};

        item.program_binary[18] = {4'h0 , 12'h000};
        item.program_binary[19] = {4'h0 , 12'h000};

        item.program_binary[20] = enc_const(4'h7, 8'h00);
        item.program_binary[21] = enc_rrr(OP_CMP, 4'h0, 4'hD, 4'h7);
        item.program_binary[22] = {OP_BRnzp, 3'b001, 1'b0, 8'd26};

        item.program_binary[23] = {4'h0 , 12'h000};
        item.program_binary[24] = {4'h0 , 12'h000};
        item.program_binary[25] = {OP_LDR, 4'h4, 4'hA, 4'h0};

        item.program_binary[26] = {OP_RET, 12'h000};
        item.program_binary[27] = {OP_RET, 12'h000};

        `uvm_send(item)
        `uvm_info("MIXED_SEQ", "Step 3: Mixed compute-and-memory stress kernel loaded (28 instructions)", UVM_LOW)

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_CONFIGURE;
        item.thread_count = 16'd32;
        `uvm_send(item)
        `uvm_info("MIXED_SEQ", "Step 4: Configured 32 threads across 8 physical cores", UVM_LOW)

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_START;
        `uvm_send(item)
        `uvm_info("MIXED_SEQ", "Step 5: Mixed stress kernel launched", UVM_LOW)

    endtask
endclass

`endif
