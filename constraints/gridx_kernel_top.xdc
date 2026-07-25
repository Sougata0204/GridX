## ============================================================================
## GridX³ Kernel Top — Xilinx Vivado Constraints (XDC)
## Target: Any Xilinx UltraScale+ / Alveo / Kintex / Artix
## ============================================================================

## ---- Primary Clock (adjust period for your board) ----
create_clock -period 5.000 -name clk_sys [get_ports clk_sys]
set_property IOSTANDARD LVCMOS33 [get_ports clk_sys]

## ---- Reset ----
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

## ---- False paths for async status outputs ----
set_false_path -from [get_pins -hierarchical *perf_cycle_count*]
set_false_path -from [get_pins -hierarchical *perf_hbm_reads*]
set_false_path -from [get_pins -hierarchical *perf_hbm_writes*]
set_false_path -from [get_pins -hierarchical *perf_total_flits*]
set_false_path -from [get_pins -hierarchical *perf_active_cores*]

## ---- Kernel state outputs ----
set_false_path -to [get_ports kernel_done]
set_false_path -to [get_ports kernel_fault]
set_false_path -to [get_ports kernel_state*]

## ---- Multicycle for debug probes ----
set_false_path -to [get_ports dbg_core_done*]
set_false_path -to [get_ports dbg_mesh_busy]

## ---- Max delay for host interface ----
set_input_delay  -clock clk_sys -max 2.0 [get_ports {host_wr_en host_wr_data* host_start}]
set_input_delay  -clock clk_sys -max 2.0 [get_ports {pmem_wr_en pmem_wr_addr* pmem_wr_data*}]
set_input_delay  -clock clk_sys -max 2.0 [get_ports {dmem_wr_en dmem_wr_addr* dmem_wr_data*}]
set_input_delay  -clock clk_sys -max 2.0 [get_ports {dmem_rd_en dmem_rd_addr*}]
set_output_delay -clock clk_sys -max 2.0 [get_ports {dmem_rd_data*}]

## ---- Area / Power Optimization ----
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE ExploreWithRemap [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraTimingOpt  [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
