// GridX3 UVM Functional Coverage Collector

`ifndef GRIDX_COVERAGE_SV
`define GRIDX_COVERAGE_SV

class gridx_coverage extends uvm_subscriber #(gridx_host_seq_item);

    // Sampled transaction
    gridx_host_seq_item m_txn;

    // Kernel configuration coverage
    covergroup cg_kernel_config;
        cp_thread_count: coverpoint m_txn.thread_count {
            bins single_thread = {1};
            bins few_threads   = {[2:4]};
            bins mid_threads   = {[5:16]};
            bins many_threads  = {[17:32]};
        }

        cp_cmd_type: coverpoint m_txn.cmd_type {
            bins configure = {gridx_host_seq_item::CMD_CONFIGURE};
            bins start     = {gridx_host_seq_item::CMD_START};
            bins load_prog = {gridx_host_seq_item::CMD_LOAD_PROG};
            bins write_mem = {gridx_host_seq_item::CMD_WRITE_DMEM};
            bins read_mem  = {gridx_host_seq_item::CMD_READ_DMEM};
            bins reset_cmd = {gridx_host_seq_item::CMD_RESET};
        }

        cp_mem_region: coverpoint m_txn.mem_addr {
            bins l1_region = {[22'h000000:22'h07FFFF]};
            bins l2_region = {[22'h080000:22'h1FFFFF]};
            bins l3_region = {[22'h200000:22'h3FFFFF]};
        }
    endgroup

    // Kernel completion coverage
    covergroup cg_kernel_result;
        cp_completed: coverpoint m_txn.kernel_completed {
            bins pass = {1'b1};
            bins no   = {1'b0};
        }

        cp_faulted: coverpoint m_txn.kernel_faulted {
            bins fault = {1'b1};
            bins clean = {1'b0};
        }

        cx_result: cross cp_completed, cp_faulted {
            bins normal_completion = binsof(cp_completed.pass) && binsof(cp_faulted.clean);
            bins fault_detected    = binsof(cp_completed.no)   && binsof(cp_faulted.fault);
        }
    endgroup

    `uvm_component_utils(gridx_coverage)

    function new(string name = "gridx_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_kernel_config = new();
        cg_kernel_result = new();
    endfunction

    virtual function void write(gridx_host_seq_item t);
        m_txn = t;

        case (t.cmd_type)
            gridx_host_seq_item::CMD_CONFIGURE,
            gridx_host_seq_item::CMD_START,
            gridx_host_seq_item::CMD_LOAD_PROG,
            gridx_host_seq_item::CMD_WRITE_DMEM,
            gridx_host_seq_item::CMD_READ_DMEM,
            gridx_host_seq_item::CMD_RESET: begin
                cg_kernel_config.sample();
            end
            default: ;
        endcase

        if (t.kernel_completed || t.kernel_faulted) begin
            cg_kernel_result.sample();
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("COV", $sformatf("Kernel Config Coverage: %.1f%%", cg_kernel_config.get_coverage()), UVM_NONE)
        `uvm_info("COV", $sformatf("Kernel Result Coverage: %.1f%%", cg_kernel_result.get_coverage()), UVM_NONE)
    endfunction

endclass

`endif // GRIDX_COVERAGE_SV

