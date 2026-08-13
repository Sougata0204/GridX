// GridX3 UVM Scoreboard
// Golden reference model and data integrity checker.

`ifndef GRIDX_SCOREBOARD_SV
`define GRIDX_SCOREBOARD_SV

// Declare analysis imp suffixes BEFORE the class (required by UVM macro)
`uvm_analysis_imp_decl(_host_cmd)
`uvm_analysis_imp_decl(_kernel_status)
`uvm_analysis_imp_decl(_mem_write)
`uvm_analysis_imp_decl(_mem_read)

class gridx_scoreboard extends uvm_scoreboard;

    // Analysis implementation ports
    uvm_analysis_imp_host_cmd      #(gridx_host_seq_item,   gridx_scoreboard) imp_host_cmd;
    uvm_analysis_imp_kernel_status #(gridx_host_seq_item,   gridx_scoreboard) imp_kernel_status;
    uvm_analysis_imp_mem_write     #(gridx_mem_transaction, gridx_scoreboard) imp_mem_write;
    uvm_analysis_imp_mem_read      #(gridx_mem_transaction, gridx_scoreboard) imp_mem_read;

    // Reference memory model (associative array for sparse tracking)
    logic [7:0] ref_dmem [int];

    // Tracking counters
    int unsigned num_kernels_launched;
    int unsigned num_kernels_completed;
    int unsigned num_kernels_faulted;
    int unsigned num_mem_writes;
    int unsigned num_mem_reads;
    int unsigned num_data_errors;
    int unsigned num_checks;

    int unsigned current_thread_count;
    logic kernel_active;

    `uvm_component_utils(gridx_scoreboard)

    function new(string name = "gridx_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        imp_host_cmd      = new("imp_host_cmd", this);
        imp_kernel_status = new("imp_kernel_status", this);
        imp_mem_write     = new("imp_mem_write", this);
        imp_mem_read      = new("imp_mem_read", this);
    endfunction

    virtual function void start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);
        num_kernels_launched  = 0;
        num_kernels_completed = 0;
        num_kernels_faulted   = 0;
        num_mem_writes        = 0;
        num_mem_reads         = 0;
        num_data_errors       = 0;
        num_checks            = 0;
        current_thread_count  = 0;
        kernel_active         = 0;
    endfunction

    // Handle host commands
    virtual function void write_host_cmd(gridx_host_seq_item txn);
        case (txn.cmd_type)
            gridx_host_seq_item::CMD_CONFIGURE: begin
                current_thread_count = txn.thread_count;
                `uvm_info("SCB", $sformatf("Kernel configured: %0d threads", current_thread_count), UVM_MEDIUM)
            end
            gridx_host_seq_item::CMD_START: begin
                num_kernels_launched++;
                kernel_active = 1;
                `uvm_info("SCB", $sformatf("Kernel #%0d launched", num_kernels_launched), UVM_MEDIUM)
            end
            default: ;
        endcase
    endfunction

    // Handle kernel completion/fault
    virtual function void write_kernel_status(gridx_host_seq_item txn);
        if (txn.kernel_completed) begin
            num_kernels_completed++;
            kernel_active = 0;
            `uvm_info("SCB", $sformatf("Kernel #%0d completed in %0d cycles",
                num_kernels_completed, txn.execution_cycles), UVM_LOW)
        end
        if (txn.kernel_faulted) begin
            num_kernels_faulted++;
            kernel_active = 0;
            `uvm_error("SCB", $sformatf("Kernel #%0d FAULTED at cycle %0d",
                num_kernels_launched, txn.execution_cycles))
        end
    endfunction

    // Track memory writes
    virtual function void write_mem_write(gridx_mem_transaction txn);
        num_mem_writes++;
        ref_dmem[txn.addr] = txn.data;
    endfunction

    // Check memory reads against reference
    virtual function void write_mem_read(gridx_mem_transaction txn);
        num_mem_reads++;
        num_checks++;

        if (ref_dmem.exists(txn.addr)) begin
            if (txn.data !== ref_dmem[txn.addr]) begin
                num_data_errors++;
                `uvm_error("SCB", $sformatf(
                    "DATA MISMATCH at addr 0x%06h: expected=0x%02h actual=0x%02h (cycle %0d)",
                    txn.addr, ref_dmem[txn.addr], txn.data, txn.cycle))
            end else begin
                `uvm_info("SCB", $sformatf(
                    "Data match at addr 0x%06h: 0x%02h", txn.addr, txn.data), UVM_HIGH)
            end
        end
    endfunction

    // Final report
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCB", "   GRIDX3 SCOREBOARD FINAL REPORT",      UVM_NONE)
        `uvm_info("SCB", $sformatf("  Kernels Launched:   %0d", num_kernels_launched),  UVM_NONE)
        `uvm_info("SCB", $sformatf("  Kernels Completed:  %0d", num_kernels_completed), UVM_NONE)
        `uvm_info("SCB", $sformatf("  Kernels Faulted:    %0d", num_kernels_faulted),   UVM_NONE)
        `uvm_info("SCB", $sformatf("  Memory Writes:      %0d", num_mem_writes),        UVM_NONE)
        `uvm_info("SCB", $sformatf("  Memory Reads:       %0d", num_mem_reads),         UVM_NONE)
        `uvm_info("SCB", $sformatf("  Data Checks:        %0d", num_checks),            UVM_NONE)
        `uvm_info("SCB", $sformatf("  Data Errors:        %0d", num_data_errors),       UVM_NONE)

        if (num_data_errors == 0 && num_kernels_faulted == 0)
            `uvm_info("SCB", "  RESULT: ALL CHECKS PASSED", UVM_NONE)
        else
            `uvm_error("SCB", $sformatf("  RESULT: %0d ERRORS DETECTED", num_data_errors + num_kernels_faulted))
    endfunction

    function int get_errors();
        return num_data_errors + num_kernels_faulted;
    endfunction

endclass

`endif // GRIDX_SCOREBOARD_SV
