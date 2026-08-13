# GridX³ — Vivado Elaboration + Synthesis Test (Minimal)
# Usage: vivado -mode batch -source scripts/test_synth.tcl

set SCRIPT_DIR   [file normalize [file dirname [info script]]]
set PROJECT_ROOT [file normalize [file join $SCRIPT_DIR ..]]

set TOP_MODULE   gridx_kernel_top
set PART         xcu30-fbvb900-2-e
set OUTPUT_DIR   [file join $PROJECT_ROOT vivado_output]

file mkdir $OUTPUT_DIR

set SRC_DIR      [file join $PROJECT_ROOT src]
set MESH_DIR     [file join $PROJECT_ROOT memory_mesh src]

set SRC_FILES [list \
    $MESH_DIR/gridx_mem_pkg.sv \
    $MESH_DIR/mem_mesh_arbiter.sv \
    $MESH_DIR/mem_mesh_endpoint_ni.sv \
    $MESH_DIR/mem_mesh_router.sv \
    $MESH_DIR/mem_mesh_top.sv \
    $SRC_DIR/gridx_pkg.sv \
    $SRC_DIR/gridx_defines.vh \
    $SRC_DIR/alu.sv \
    $SRC_DIR/async_fifo.sv \
    $SRC_DIR/async_load_tracker.sv \
    $SRC_DIR/bank_arbiter.sv \
    $SRC_DIR/channel_scheduler.sv \
    $SRC_DIR/clk_domain_ctrl.sv \
    $SRC_DIR/compute_utilization.sv \
    $SRC_DIR/controller.sv \
    $SRC_DIR/core.sv \
    $SRC_DIR/core_face_adapter.sv \
    $SRC_DIR/core_fin_router.sv \
    $SRC_DIR/core_local_memory.sv \
    $SRC_DIR/credit_manager.sv \
    $SRC_DIR/dcr.sv \
    $SRC_DIR/decoder.sv \
    $SRC_DIR/dispatch.sv \
    $SRC_DIR/dma_engine.sv \
    $SRC_DIR/dual_issue.sv \
    $SRC_DIR/express_link.sv \
    $SRC_DIR/fault_handler.sv \
    $SRC_DIR/fetcher.sv \
    $SRC_DIR/forward_progress.sv \
    $SRC_DIR/gc6_power_fsm.sv \
    $SRC_DIR/gpu.sv \
    $SRC_DIR/gpu_sram.sv \
    $SRC_DIR/hbm3_ctrl.sv \
    $SRC_DIR/instr_buffer.sv \
    $SRC_DIR/kernel_fsm.sv \
    $SRC_DIR/kernel_perf_model.sv \
    $SRC_DIR/l2_mesh_router.sv \
    $SRC_DIR/l2_slice.sv \
    $SRC_DIR/load_coalescer.sv \
    $SRC_DIR/lsu.sv \
    $SRC_DIR/lsu_arbiter.sv \
    $SRC_DIR/lsu_mshr.sv \
    $SRC_DIR/mem_coalescer.sv \
    $SRC_DIR/mem_fin.sv \
    $SRC_DIR/mem_mesh_bridge.sv \
    $SRC_DIR/mem_shell_controller.sv \
    $SRC_DIR/mshr.sv \
    $SRC_DIR/multicast_tree.sv \
    $SRC_DIR/pc.sv \
    $SRC_DIR/perf_boost_controller.sv \
    $SRC_DIR/performance_counters.sv \
    $SRC_DIR/power_controller.sv \
    $SRC_DIR/prefetch_engine.sv \
    $SRC_DIR/registers.sv \
    $SRC_DIR/response_buffer.sv \
    $SRC_DIR/rt_core.sv \
    $SRC_DIR/scheduler.sv \
    $SRC_DIR/scoreboard.sv \
    $SRC_DIR/shared_memory.sv \
    $SRC_DIR/simt_stack.sv \
    $SRC_DIR/sparse_mma.sv \
    $SRC_DIR/sram_bank.sv \
    $SRC_DIR/sram_controller.sv \
    $SRC_DIR/sram_tile_buffer.sv \
    $SRC_DIR/stall_tracker.sv \
    $SRC_DIR/store_combiner.sv \
    $SRC_DIR/tensor_controller.sv \
    $SRC_DIR/tensor_unit.sv \
    $SRC_DIR/tensor_unit_pipelined.sv \
    $SRC_DIR/tile_address_decoder.sv \
    $SRC_DIR/vertical_memory_controller.sv \
    $SRC_DIR/virtual_channel.sv \
    $SRC_DIR/warp_mem_unit.sv \
    $SRC_DIR/zero_skip_ctrl.sv \
    $SRC_DIR/gridx_kernel_top.sv \
]

puts " GridX³ — Vivado Synthesis Test"
puts " Top:  $TOP_MODULE"
puts " Part: $PART"
puts " Config: 2x2x2 = 8 cores, 1 warp, 4 threads"

read_verilog -sv $SRC_FILES
read_xdc [file join $PROJECT_ROOT constraints gridx_kernel_top.xdc]

puts "\n>>> Running Synthesis..."
synth_design -top $TOP_MODULE -part $PART \
    -flatten_hierarchy rebuilt \
    -directive AreaOptimized_high

write_checkpoint -force $OUTPUT_DIR/post_synth.dcp
report_utilization -file $OUTPUT_DIR/synth_utilization.rpt
report_timing_summary -file $OUTPUT_DIR/synth_timing.rpt

puts " SYNTHESIS COMPLETE"
puts " Checkpoint: $OUTPUT_DIR/post_synth.dcp"
puts " Utilization: $OUTPUT_DIR/synth_utilization.rpt"
