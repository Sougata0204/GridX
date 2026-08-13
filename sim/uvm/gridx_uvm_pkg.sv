// GridX3 UVM Master Package
// Imports UVM 1.2 base and includes all GridX³ UVM components in dependency order.

`ifndef GRIDX_UVM_PKG_SV
`define GRIDX_UVM_PKG_SV

`timescale 1ns/1ps

import gridx_mem_pkg::*;

package gridx_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // VIP Modules
    `include "axi4_uvm_vip.sv"
    `include "mem_mesh_uvm_vip.sv"

    // Sequence Items (transactions)
    `include "gridx_seq_item.sv"
    `include "noc_synthetic_seq.sv"
    `include "gridx_saxpy_seq.sv"

    // Driver
    `include "gridx_driver.sv"

    // Monitors
    `include "gridx_monitor.sv"

    // Agents
    `include "gridx_agent.sv"

    // Scoreboard
    `include "gridx_scoreboard.sv"

    // Coverage
    `include "gridx_coverage.sv"

    // Environment
    `include "gridx_env.sv"

    // Test Library
    `include "gridx_test_lib.sv"

endpackage

`endif // GRIDX_UVM_PKG_SV

