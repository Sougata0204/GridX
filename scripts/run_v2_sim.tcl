# ============================================================================
# GridX³ — V2 Simulation Script
# ============================================================================
# Compiles DPI-C memory backend, elaborates the design, and runs simulation.
# Note: Memory efficient execution flow.
# ============================================================================

set PROJECT_DIR "d:/ML_DL_AI/GridX_Vivado/GridX"
set SRC_DIR "$PROJECT_DIR/src"
set SIM_DIR "$PROJECT_DIR/sim"

# 1. Compile DPI-C shared library using Vivado's xsc
puts "\[SIM\] Compiling DPI-C Memory Backend using xsc..."
set cmd "xsc $SRC_DIR/gridx_mem_model.c"
if {[catch {exec {*}$cmd} result]} {
    puts "\[SIM\] WARNING: DPI-C compilation failed. Falling back to SV memory arrays."
    puts $result
    set USE_DPI 0
} else {
    puts "\[SIM\] DPI-C backend compiled successfully."
    set USE_DPI 1
}

# 2. Compile SystemVerilog Files
puts "\[SIM\] Parsing SystemVerilog files..."

# Ensure xsim.dir exists
file mkdir xsim.dir/work

# Use xvlog to compile
set xvlog_cmd [list xvlog -sv -work work]
if {$USE_DPI} {
    lappend xvlog_cmd "-d" "GRIDX_USE_DPI_C"
}

# Add files in dependency order
lappend xvlog_cmd "$SRC_DIR/gridx_config_pkg.sv"
lappend xvlog_cmd "$SRC_DIR/vcd_ctrl.sv"
lappend xvlog_cmd "$SRC_DIR/gridx_mem_model.sv"
lappend xvlog_cmd "$SRC_DIR/tlb.sv"
lappend xvlog_cmd "$SRC_DIR/page_table_walker.sv"
lappend xvlog_cmd "$SRC_DIR/mmu.sv"
lappend xvlog_cmd "$SRC_DIR/tsv_bridge.sv"
lappend xvlog_cmd "$SRC_DIR/nmc_engine.sv"
lappend xvlog_cmd "$SRC_DIR/hw_command_processor.sv"
lappend xvlog_cmd "$SRC_DIR/dram_ctrl.sv"
lappend xvlog_cmd "$SRC_DIR/directory_controller.sv"
lappend xvlog_cmd "$SRC_DIR/snoop_filter.sv"
lappend xvlog_cmd "$SRC_DIR/tensor_unit_mx.sv"
lappend xvlog_cmd "$SRC_DIR/sparse_decompressor.sv"
lappend xvlog_cmd "$SRC_DIR/scheduler_v2.sv"
lappend xvlog_cmd "$SRC_DIR/active_base_die.sv"
lappend xvlog_cmd "$SIM_DIR/tb_gridx_v2.sv"

puts "Executing: $xvlog_cmd"
if {[catch {exec {*}$xvlog_cmd} result]} {
    puts "\[SIM\] ERROR: Compilation Failed!"
    puts $result
    exit 1
}

# 3. Elaborate
puts "\[SIM\] Elaborating Design..."
set xelab_cmd [list xelab -debug typical -top tb_gridx_v2 -snapshot tb_gridx_v2_snap]
if {$USE_DPI} {
    lappend xelab_cmd "-sv_lib" "dpi"
}

puts "Executing: $xelab_cmd"
if {[catch {exec {*}$xelab_cmd} result]} {
    puts "\[SIM\] ERROR: Elaboration Failed!"
    puts $result
    exit 1
}

# 4. Run Simulation
puts "\[SIM\] Running Simulation..."
set xsim_cmd [list xsim tb_gridx_v2_snap -R]
if {[catch {exec {*}$xsim_cmd} result]} {
    puts "\[SIM\] Simulation completed with errors/warnings."
    puts $result
} else {
    puts "\[SIM\] Simulation completed successfully."
    puts $result
}

puts "\[SIM\] Done."
