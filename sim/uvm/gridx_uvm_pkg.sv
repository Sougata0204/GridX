// Master UVM package importing UVM 1.2 base and compiling all GridX verification components.
`ifndef GRIDX_UVM_PKG_SV
`define GRIDX_UVM_PKG_SV

`timescale 1ns/1ps

package gridx_uvm_pkg;

    import gridx_mem_pkg::*;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "axi4_uvm_vip.sv"
    `include "mem_mesh_uvm_vip.sv"

    `include "gridx_seq_item.sv"
    `include "noc_synthetic_seq.sv"
    `include "gridx_saxpy_seq.sv"
    `include "gridx_multicore_perf_seq.sv"
    `include "gridx_multiclock_dv_seq.sv"
    `include "gridx_congestion_dv_seq.sv"
    `include "gridx_mixed_stress_seq.sv"

    `include "gridx_driver.sv"

    `include "gridx_monitor.sv"

    `include "gridx_agent.sv"

    `include "gridx_scoreboard.sv"

    `include "gridx_coverage.sv"

    `include "gridx_env.sv"

    `include "gridx_test_lib.sv"

endpackage

`endif
