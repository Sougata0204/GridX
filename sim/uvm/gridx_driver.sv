// GridX3 UVM Driver
// Drives host commands onto the DUT via virtual interface.

`ifndef GRIDX_DRIVER_SV
`define GRIDX_DRIVER_SV

class gridx_host_driver extends uvm_driver #(gridx_host_seq_item);

    virtual gridx_host_if vif;
    int unsigned timeout_cycles = 500;


    `uvm_component_utils(gridx_host_driver)

    function new(string name = "gridx_host_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual gridx_host_if)::get(this, "", "host_vif", vif))
            `uvm_fatal("NOVIF", "Could not get virtual interface 'host_vif'")
    endfunction

    virtual task run_phase(uvm_phase phase);
        gridx_host_seq_item req;

        // Initialize all outputs to idle
        reset_signals();

        forever begin
            seq_item_port.get_next_item(req);
            drive_transaction(req);
            seq_item_port.item_done();
        end
    endtask

    virtual task reset_signals();
        @(posedge vif.clk);
        vif.host_wr_en   <= 1'b0;
        vif.host_wr_data <= 16'h0;
        vif.host_start   <= 1'b0;
        vif.pmem_wr_en   <= 1'b0;
        vif.pmem_wr_addr <= '0;
        vif.pmem_wr_data <= '0;
        vif.dmem_wr_en   <= 1'b0;
        vif.dmem_wr_addr <= '0;
        vif.dmem_wr_data <= '0;
        vif.dmem_rd_en   <= 1'b0;
        vif.dmem_rd_addr <= '0;
    endtask

    virtual task drive_transaction(gridx_host_seq_item req);
        case (req.cmd_type)
            gridx_host_seq_item::CMD_RESET:      drive_reset();
            gridx_host_seq_item::CMD_LOAD_PROG:  drive_program_load(req);
            gridx_host_seq_item::CMD_WRITE_DMEM: drive_dmem_write(req);
            gridx_host_seq_item::CMD_READ_DMEM:  drive_dmem_read(req);
            gridx_host_seq_item::CMD_CONFIGURE:  drive_configure(req);
            gridx_host_seq_item::CMD_START:      drive_start_and_wait(req);
            default: `uvm_error("DRV", $sformatf("Unknown cmd_type: %0d", req.cmd_type))
        endcase
    endtask

    virtual task drive_reset();
        `uvm_info("DRV", "Applying reset...", UVM_MEDIUM)
        repeat (5) @(posedge vif.clk);
        `uvm_info("DRV", "Reset complete", UVM_MEDIUM)
    endtask

    virtual task drive_program_load(gridx_host_seq_item req);
        `uvm_info("DRV", $sformatf("Loading %0d instructions into PMEM", req.program_binary.size()), UVM_MEDIUM)
        foreach (req.program_binary[i]) begin
            @(posedge vif.clk);
            vif.pmem_wr_en   <= 1'b1;
            vif.pmem_wr_addr <= i[11:0];
            vif.pmem_wr_data <= req.program_binary[i];
        end
        @(posedge vif.clk);
        vif.pmem_wr_en <= 1'b0;
    endtask

    virtual task drive_dmem_write(gridx_host_seq_item req);
        @(posedge vif.clk);
        vif.dmem_wr_en   <= 1'b1;
        vif.dmem_wr_addr <= req.mem_addr;
        vif.dmem_wr_data <= req.mem_data;
        @(posedge vif.clk);
        vif.dmem_wr_en   <= 1'b0;
    endtask

    virtual task drive_dmem_read(gridx_host_seq_item req);
        @(posedge vif.clk);
        vif.dmem_rd_en   <= 1'b1;
        vif.dmem_rd_addr <= req.mem_addr;
        @(posedge vif.clk);
        vif.dmem_rd_en   <= 1'b0;
        @(posedge vif.clk);
        req.read_data = vif.dmem_rd_data;
    endtask

    virtual task drive_configure(gridx_host_seq_item req);
        `uvm_info("DRV", $sformatf("Configuring kernel: thread_count=%0d", req.thread_count), UVM_MEDIUM)
        @(posedge vif.clk);
        vif.host_wr_en   <= 1'b1;
        vif.host_wr_data <= req.thread_count;
        @(posedge vif.clk);
        vif.host_wr_en   <= 1'b0;
        repeat (3) @(posedge vif.clk);
    endtask

    virtual task drive_start_and_wait(gridx_host_seq_item req);
        int unsigned cycle_count = 0;

        `uvm_info("DRV", "Launching kernel...", UVM_MEDIUM)
        @(posedge vif.clk);
        vif.host_start <= 1'b1;
        @(posedge vif.clk);
        vif.host_start <= 1'b0;

        while (cycle_count < timeout_cycles) begin
            @(posedge vif.clk);
            cycle_count++;
        end

        req.execution_cycles = cycle_count;
        `uvm_info("DRV", $sformatf("Kernel wait complete after %0d cycles", cycle_count), UVM_MEDIUM)
    endtask

endclass

`endif // GRIDX_DRIVER_SV
