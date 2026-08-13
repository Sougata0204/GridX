// GridX3 UVM Sequence - SAXPY Compute Workload
// Handwritten machine code kernel to verify RTL logic flow from Core -> NoC -> HBM

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
            16'h9110, // 0: CONST R1, 0x10  (Address of X)
            16'h9220, // 1: CONST R2, 0x20  (Address of Y)
            16'h9330, // 2: CONST R3, 0x30  (Address of A)
            16'h9740, // 3: CONST R7, 0x40  (Address of Z)
            
            16'h7410, // 4: LDR R4, R1      (R4 = X)
            16'h7520, // 5: LDR R5, R2      (R5 = Y)
            16'h7630, // 6: LDR R6, R3      (R6 = A)
            
            16'h5464, // 7: MUL R4, R6, R4  (R4 = A * X)
            16'h3545, // 8: ADD R5, R4, R5  (R5 = A*X + Y)
            
            16'h8075, // 9: STR R7, R5      (Store R5 to Address Z)
            16'hF000  // 10: RET
        };

        `uvm_info("SAXPY_SEQ", "Starting SAXPY Kernel UVM sequence", UVM_LOW)

        // 1. Reset Core
        req = gridx_host_seq_item::type_id::create("req");
        start_item(req);
        req.cmd_type = gridx_host_seq_item::CMD_RESET;
        finish_item(req);
        get_response(rsp);

        // 2. Load SAXPY Machine Code into prog_mem
        req = gridx_host_seq_item::type_id::create("req");
        start_item(req);
        req.cmd_type = gridx_host_seq_item::CMD_LOAD_PROG;
        req.program_binary = saxpy_kernel;
        finish_item(req);
        get_response(rsp);

        // 3. Write X = 5 into HBM (Address 0x10)
        req = gridx_host_seq_item::type_id::create("req");
        start_item(req);
        req.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM;
        req.mem_addr = 22'h000010;
        req.mem_data = 8'd5;
        finish_item(req);
        get_response(rsp);

        // 4. Write Y = 3 into HBM (Address 0x20)
        req = gridx_host_seq_item::type_id::create("req");
        start_item(req);
        req.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM;
        req.mem_addr = 22'h000020;
        req.mem_data = 8'd3;
        finish_item(req);
        get_response(rsp);

        // 5. Write A = 2 into HBM (Address 0x30)
        req = gridx_host_seq_item::type_id::create("req");
        start_item(req);
        req.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM;
        req.mem_addr = 22'h000030;
        req.mem_data = 8'd2;
        finish_item(req);
        get_response(rsp);

        // 6. Configure single thread execution
        req = gridx_host_seq_item::type_id::create("req");
        start_item(req);
        req.cmd_type = gridx_host_seq_item::CMD_CONFIGURE;
        req.thread_count = 16'd1;
        finish_item(req);
        get_response(rsp);

        // 7. Start execution and wait for done
        `uvm_info("SAXPY_SEQ", "Triggering kernel start!", UVM_LOW)
        req = gridx_host_seq_item::type_id::create("req");
        start_item(req);
        req.cmd_type = gridx_host_seq_item::CMD_START;
        finish_item(req);
        get_response(rsp);

        if (rsp.kernel_faulted) begin
            `uvm_error("SAXPY_SEQ", "Kernel faulted during execution!")
        end else begin
            `uvm_info("SAXPY_SEQ", $sformatf("Kernel completed successfully in %0d cycles.", rsp.execution_cycles), UVM_LOW)
        end

        // 8. Read back Z (Address 0x40)
        req = gridx_host_seq_item::type_id::create("req");
        start_item(req);
        req.cmd_type = gridx_host_seq_item::CMD_READ_DMEM;
        req.mem_addr = 22'h000040;
        finish_item(req);
        get_response(rsp);

        // 9. Verify math! (2 * 5 + 3 = 13)
        if (rsp.read_data == 8'd13) begin
            `uvm_info("SAXPY_SEQ", $sformatf("MATH SUCCESS! Z = %0d. Logic flows perfectly from Core->NoC->HBM", rsp.read_data), UVM_NONE)
        end else begin
            `uvm_error("SAXPY_SEQ", $sformatf("MATH FAIL! Expected 13, got %0d", rsp.read_data))
        end
    endtask
endclass

`endif // GRIDX_SAXPY_SEQ_SV
