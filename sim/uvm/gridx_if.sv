// SystemVerilog virtual interface bundle defining signal connections between DUT and UVM components.
`ifndef GRIDX_IF_SV
`define GRIDX_IF_SV

`include "../../src/axi4_if.sv"

interface gridx_host_if #(
    parameter PROG_ADDR_BITS = 12,
    parameter PROG_DATA_BITS = 16,
    parameter DATA_ADDR_BITS = 22,
    parameter DATA_DATA_BITS = 8
) (
    input wire clk,
    input wire rst_n
);
    logic        host_wr_en;
    logic [15:0] host_wr_data;
    logic        host_start;

    logic                       pmem_wr_en;
    logic [PROG_ADDR_BITS-1:0]  pmem_wr_addr;
    logic [PROG_DATA_BITS-1:0]  pmem_wr_data;

    logic                       dmem_wr_en;
    logic [DATA_ADDR_BITS-1:0]  dmem_wr_addr;
    logic [DATA_DATA_BITS-1:0]  dmem_wr_data;

    logic                       dmem_rd_en;
    logic [DATA_ADDR_BITS-1:0]  dmem_rd_addr;
    logic [DATA_DATA_BITS-1:0]  dmem_rd_data;

    clocking drv_cb @(posedge clk);
        default input #1step output #1;
        output host_wr_en, host_wr_data, host_start;
        output pmem_wr_en, pmem_wr_addr, pmem_wr_data;
        output dmem_wr_en, dmem_wr_addr, dmem_wr_data;
        output dmem_rd_en, dmem_rd_addr;
        input  dmem_rd_data;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input host_wr_en, host_wr_data, host_start;
        input pmem_wr_en, pmem_wr_addr, pmem_wr_data;
        input dmem_wr_en, dmem_wr_addr, dmem_wr_data;
        input dmem_rd_en, dmem_rd_addr, dmem_rd_data;
    endclocking

    modport DRIVER  (clocking drv_cb, input clk, input rst_n);
    modport MONITOR (clocking mon_cb, input clk, input rst_n);

    function logic [7:0] backdoor_read_hbm(logic [31:0] addr);
`ifndef SYNTHESIS
        if (tb_uvm_top.dut.hbmNodes[0].uHbm.sim_hbm_mem.exists(addr)) begin
            return tb_uvm_top.dut.hbmNodes[0].uHbm.sim_hbm_mem[addr][7:0];
        end else if (tb_uvm_top.dut.hbmNodes[1].uHbm.sim_hbm_mem.exists(addr)) begin
            return tb_uvm_top.dut.hbmNodes[1].uHbm.sim_hbm_mem[addr][7:0];
        end else begin
            return 8'hxx;
        end
`else
        return 8'h00;
`endif
    endfunction

    function void backdoor_write_hbm(logic [31:0] addr, logic [7:0] data);
`ifndef SYNTHESIS
        tb_uvm_top.dut.hbmNodes[0].uHbm.sim_hbm_mem[addr] = data;
        tb_uvm_top.dut.hbmNodes[1].uHbm.sim_hbm_mem[addr] = data;
`endif
    endfunction

endinterface

interface gridx_kernel_status_if (
    input wire clk,
    input wire rst_n
);
    logic        kernel_done;
    logic        kernel_fault;
    logic [2:0]  kernel_state;

    logic [31:0] perf_hbm_reads;
    logic [31:0] perf_hbm_writes;
    logic [31:0] perf_total_flits;
    logic [31:0] perf_cycle_count;
    logic [31:0] perf_active_cores;

    logic [31:0] trace_z_plus;
    logic [31:0] trace_z_minus;
    logic [31:0] trace_lsu_req;
    logic [31:0] trace_mesh_wr;
    logic [31:0] trace_local_wr;

    logic [7:0]  dbg_core_done_sample;
    logic        dbg_mesh_busy;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input kernel_done, kernel_fault, kernel_state;
        input perf_hbm_reads, perf_hbm_writes, perf_total_flits;
        input perf_cycle_count, perf_active_cores;
        input dbg_core_done_sample, dbg_mesh_busy;
    endclocking

    modport MONITOR (clocking mon_cb, input clk, input rst_n);
endinterface

`endif
