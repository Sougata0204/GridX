# GridX3 — Full 3D Integration Simulation (2x2x2 + MemoryMesh + HBM + 250MHz)
# Run: vivado -mode batch -source scripts/run_3d_full.tcl
set SCRIPT_DIR   [file normalize [file dirname [info script]]]
set PROJECT_ROOT [file normalize [file join $SCRIPT_DIR ..]]
set WORK_DIR     [file join $PROJECT_ROOT xsim_work]
set SRC_DIR      [file join $PROJECT_ROOT src]
set MESH_SRC_DIR [file join $PROJECT_ROOT memory_mesh src]
set SIM_DIR      [file join $PROJECT_ROOT sim]
set LOG_FILE     [file join $WORK_DIR gvf_3d_full.log]

puts ""
puts "╔══════════════════════════════════════════════════════════════════╗"
puts "║   GridX3 Full 3D Integration Verification                      ║"
puts "║   Config: CUBE_X=2, CUBE_Y=2, CUBE_Z=2 (8 cores)              ║"
puts "║   MemoryMesh NoC + HBM3 + Per-Layer 250MHz Clocks              ║"
puts "╚══════════════════════════════════════════════════════════════════╝"

proc add_unique {var_name file_name} {
    upvar 1 $var_name files
    set normalized [file normalize $file_name]
    if {[lsearch -exact $files $normalized] < 0} {
        lappend files $normalized
    }
}

file mkdir $WORK_DIR
cd $WORK_DIR

# Build ordered file list
set files [list]

# 1. Packages first (dependency order)
add_unique files [file join $MESH_SRC_DIR gridx_mem_pkg.sv]
add_unique files [file join $SRC_DIR gridx_pkg.sv]
add_unique files [file join $SRC_DIR gridx_config_pkg.sv]

# 2. Memory mesh modules
foreach f [lsort [glob -nocomplain [file join $MESH_SRC_DIR *.sv]]] {
    add_unique files $f
}

# 3. All src modules
foreach f [lsort [glob -nocomplain [file join $SRC_DIR *.sv]]] {
    set tail [file tail $f]
    if {$tail in {sample_gpu.sv sample_gpu_top.sv sample_gpu_top_rejected.sv}} continue
    add_unique files $f
}

# 4. Testbench
add_unique files [file join $SIM_DIR gvf_3d_full.sv]

puts "  Files: [llength $files]"

puts ""
set xvlog_base [list xvlog -sv -work xil_defaultlib -d DEBUG -i $SRC_DIR -i $MESH_SRC_DIR]
foreach f $files {
    set cmd $xvlog_base
    lappend cmd $f
    if {[catch {exec {*}$cmd 2>@1} result]} {
        puts "COMPILE ERROR in [file tail $f]:"
        puts $result
        exit 1
    }
}
puts "  Compilation OK."

puts ""
set xelab_cmd [list xelab -debug off xil_defaultlib.gvf_3d_full -snapshot gvf_3d_full]
if {[catch {exec {*}$xelab_cmd 2>@1} result]} {
    puts "ELABORATE ERROR:"
    puts $result
    exit 1
}
puts "  Elaboration OK."

puts ""
set xsim_cmd [list xsim gvf_3d_full -R]
if {[catch {exec {*}$xsim_cmd 2>@1} result]} {
    if {[string length $result] > 100} {
        puts "  Simulation completed (with \$finish)."
    } else {
        puts "SIMULATION ERROR:"
        puts $result
        exit 1
    }
} else {
    puts "  Simulation completed."
}

# Save log
set fp [open $LOG_FILE w]
puts $fp $result
close $fp
puts "  Log saved: $LOG_FILE"

# Check results
if {[string match "*ALL TESTS PASSED*" $result]} {
    puts ""
    puts "╔══════════════════════════════════════════════════════════════════╗"
    puts "║  RESULT: ALL TESTS PASSED ✅                                   ║"
    puts "╚══════════════════════════════════════════════════════════════════╝"
} elseif {[string match "*FAILURES*" $result]} {
    puts ""
    puts "╔══════════════════════════════════════════════════════════════════╗"
    puts "║  RESULT: FAILURES DETECTED ❌                                  ║"
    puts "╚══════════════════════════════════════════════════════════════════╝"
}

puts ""
puts "Log: $LOG_FILE"
