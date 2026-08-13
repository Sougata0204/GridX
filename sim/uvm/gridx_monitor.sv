// GridX3 UVM Monitor
// Passively observes DUT interfaces and publishes transactions via analysis ports.

`ifndef GRIDX_MONITOR_SV
`define GRIDX_MONITOR_SV

// Host interface monitor
class gridx_host_monitor extends uvm_monitor;

    virtual gridx_host_if vif;

    uvm_analysis_port #(gridx_host_seq_item)   ap_host_cmd;
    uvm_analysis_port #(gridx_mem_transaction) ap_mem_write;
    uvm_analysis_port #(gridx_mem_transaction) ap_mem_read;

    int unsigned cycle_count;

    `uvm_component_utils(gridx_host_monitor)

    function new(string name = "gridx_host_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap_host_cmd  = new("ap_host_cmd", this);
        ap_mem_write = new("ap_mem_write", this);
        ap_mem_read  = new("ap_mem_read", this);

        if (!uvm_config_db#(virtual gridx_host_if)::get(this, "", "host_vif", vif))
            `uvm_fatal("NOVIF", "Could not get virtual interface 'host_vif'")
    endfunction

    virtual task run_phase(uvm_phase phase);
        cycle_count = 0;

        fork
            monitor_host_commands();
            monitor_dmem_writes();
            monitor_dmem_reads();
            count_cycles();
        join
    endtask

    virtual task count_cycles();
        forever begin
            @(posedge vif.clk);
            cycle_count++;
        end
    endtask

    virtual task monitor_host_commands();
        gridx_host_seq_item txn;
        forever begin
            @(posedge vif.clk);
            if (vif.host_wr_en) begin
                txn = gridx_host_seq_item::type_id::create("host_cmd_txn");
                txn.cmd_type = gridx_host_seq_item::CMD_CONFIGURE;
                txn.thread_count = vif.host_wr_data;
                ap_host_cmd.write(txn);
                `uvm_info("MON", $sformatf("Observed DCR write: thread_count=%0d", txn.thread_count), UVM_HIGH)
            end
            if (vif.host_start) begin
                txn = gridx_host_seq_item::type_id::create("host_start_txn");
                txn.cmd_type = gridx_host_seq_item::CMD_START;
                ap_host_cmd.write(txn);
                `uvm_info("MON", "Observed kernel START", UVM_MEDIUM)
            end
        end
    endtask

    virtual task monitor_dmem_writes();
        gridx_mem_transaction txn;
        forever begin
            @(posedge vif.clk);
            if (vif.dmem_wr_en) begin
                txn = gridx_mem_transaction::type_id::create("dmem_wr_txn");
                txn.addr = vif.dmem_wr_addr;
                txn.data = vif.dmem_wr_data;
                txn.is_write = 1'b1;
                txn.cycle = cycle_count;
                ap_mem_write.write(txn);
            end
        end
    endtask

    virtual task monitor_dmem_reads();
        gridx_mem_transaction txn;
        forever begin
            @(posedge vif.clk);
            if (vif.dmem_rd_en) begin
                @(posedge vif.clk);
                txn = gridx_mem_transaction::type_id::create("dmem_rd_txn");
                txn.addr = vif.dmem_rd_addr;
                txn.data = vif.dmem_rd_data;
                txn.is_write = 1'b0;
                txn.cycle = cycle_count;
                ap_mem_read.write(txn);
            end
        end
    endtask
endclass


// Kernel status monitor
class gridx_kernel_monitor extends uvm_monitor;

    virtual gridx_kernel_status_if vif;

    uvm_analysis_port #(gridx_host_seq_item) ap_kernel_status;

    logic        prev_kernel_done;
    logic        prev_kernel_fault;
    int unsigned cycle_count;

    `uvm_component_utils(gridx_kernel_monitor)

    function new(string name = "gridx_kernel_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap_kernel_status = new("ap_kernel_status", this);

        if (!uvm_config_db#(virtual gridx_kernel_status_if)::get(this, "", "kernel_status_vif", vif))
            `uvm_fatal("NOVIF", "Could not get virtual interface 'kernel_status_vif'")
    endfunction

    virtual task run_phase(uvm_phase phase);
        prev_kernel_done  = 1'b0;
        prev_kernel_fault = 1'b0;
        cycle_count = 0;


        forever begin
            @(posedge vif.clk);
            cycle_count++;

            if (vif.kernel_done && !prev_kernel_done) begin
                gridx_host_seq_item status_txn;
                status_txn = gridx_host_seq_item::type_id::create("kernel_done_txn");
                status_txn.kernel_completed = 1'b1;
                status_txn.kernel_faulted   = 1'b0;
                status_txn.execution_cycles = vif.perf_cycle_count;
                ap_kernel_status.write(status_txn);

                `uvm_info("KMON", $sformatf(
                    "KERNEL DONE - cycles=%0d hbm_rd=%0d hbm_wr=%0d flits=%0d",
                    vif.perf_cycle_count,
                    vif.perf_hbm_reads,
                    vif.perf_hbm_writes,
                    vif.perf_total_flits), UVM_LOW)
            end

            if (vif.kernel_fault && !prev_kernel_fault) begin
                gridx_host_seq_item status_txn;
                status_txn = gridx_host_seq_item::type_id::create("kernel_fault_txn");
                status_txn.kernel_completed = 1'b0;
                status_txn.kernel_faulted   = 1'b1;
                status_txn.execution_cycles = vif.perf_cycle_count;
                ap_kernel_status.write(status_txn);

                `uvm_error("KMON", $sformatf(
                    "KERNEL FAULT at cycle %0d - state=%0d cores_done=0x%02h",
                    vif.perf_cycle_count,
                    vif.kernel_state,
                    vif.dbg_core_done_sample))
            end

            prev_kernel_done  = vif.kernel_done;
            prev_kernel_fault = vif.kernel_fault;
        end
    endtask
endclass

`endif // GRIDX_MONITOR_SV
