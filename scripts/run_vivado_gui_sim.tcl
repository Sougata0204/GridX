# GridX 2x2x2 Full Chip — Compile, Elaborate, Simulate with Full Waveform Dump
# 
# USAGE: From Vivado Tcl Console:
#   source d:/ML_DL_AI/GridX_Vivado/GridX/scripts/run_vivado_gui_sim.tcl

set PROJECT_ROOT "d:/ML_DL_AI/GridX_Vivado/GridX"
set WORK_DIR     "$PROJECT_ROOT/xsim_work"
set SRC_DIR      "$PROJECT_ROOT/src"
set MESH_SRC_DIR "$PROJECT_ROOT/memory_mesh/src"
set SIM_DIR      "$PROJECT_ROOT/sim"

puts ""
puts "   GridX 2x2x2 Full Chip — Compile + Elaborate + Simulate          "

file mkdir $WORK_DIR
cd $WORK_DIR

# ── Step 1: Build ordered file list ──
set files [list]
lappend files "$MESH_SRC_DIR/gridx_mem_pkg.sv"
lappend files "$SRC_DIR/gridx_pkg.sv"
lappend files "$SRC_DIR/gridx_config_pkg.sv"

foreach f [lsort [glob -nocomplain "$MESH_SRC_DIR/*.sv"]] {
    set norm [file normalize $f]
    if {[lsearch -exact $files $norm] < 0} { lappend files $norm }
}

foreach f [lsort [glob -nocomplain "$SRC_DIR/*.sv"]] {
    set tail [file tail $f]
    if {$tail in {sample_gpu.sv sample_gpu_top.sv sample_gpu_top_rejected.sv}} continue
    set norm [file normalize $f]
    if {[lsearch -exact $files $norm] < 0} { lappend files $norm }
}

lappend files "$SIM_DIR/tb_fullchip_no_mesh.sv"

# ── Step 2: Compile all files ──
puts "\n--> Compiling [llength $files] SystemVerilog files..."
set errCount 0
foreach f $files {
    if {[catch {exec xvlog -sv -work xil_defaultlib -i $SRC_DIR -i $MESH_SRC_DIR $f 2>@1} result]} {
        puts "  ERROR in [file tail $f]"
        incr errCount
    }
}
if {$errCount > 0} {
    puts "COMPILE FAILED: $errCount errors"
    return
}
puts "  All files compiled successfully."

# ── Step 3: Elaborate with -debug all for full signal visibility ──
puts "\n--> Elaborating with -debug all (full waveform access)..."
if {[catch {exec xelab -debug all xil_defaultlib.tb_fullchip_no_mesh -snapshot tb_fullchip_no_mesh_dbg 2>@1} result]} {
    puts "ELABORATION FAILED:\n$result"
    return
}
puts "  Elaboration OK."

# ── Step 4: Create the run-and-dump Tcl batch script ──
set runscript "$WORK_DIR/run_with_waves.tcl"
set fd [open $runscript w]
puts $fd "# Auto-generated: log all signals then run"
puts $fd "log_wave -recursive /tb_fullchip_no_mesh/*"
puts $fd "run all"
close $fd
puts "  Created $runscript"

# ── Step 5: Launch xsim in GUI mode ──
puts "\n--> Launching xsim GUI with waveform logging..."
puts "    Snapshot: tb_fullchip_no_mesh_dbg"
puts ""
puts "  IMPORTANT: Once the GUI opens, click Run All (or type 'run all')."
puts "  All signals are pre-logged to the waveform database."
puts ""

exec xsim tb_fullchip_no_mesh_dbg -gui -tclbatch $runscript -wdb "$WORK_DIR/tb_fullchip_no_mesh.wdb" -view "$WORK_DIR/tb_fullchip_no_mesh.wcfg" &
