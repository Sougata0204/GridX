# GridX³ — Vivado Simulation Script (xsim)
# Usage: vivado -mode batch -source scripts/run_sim.tcl

set SCRIPT_DIR   [file normalize [file dirname [info script]]]
set PROJECT_ROOT [file normalize [file join $SCRIPT_DIR ..]]

set TOP_TB       tb_gridx_top
set OUTPUT_DIR   [file join $PROJECT_ROOT vivado_output]

file mkdir $OUTPUT_DIR

set SRC_DIR      [file join $PROJECT_ROOT src]
set MESH_DIR     [file join $PROJECT_ROOT memory_mesh src]
set SIM_DIR      [file join $PROJECT_ROOT sim]

puts " GridX³ — Vivado Simulation (xsim)"
puts " Testbench: $TOP_TB"

puts "\n>>> Compiling design + testbench..."

set compile_cmd "xvlog -sv --nolog"

# Memory mesh package + modules
append compile_cmd " $MESH_DIR/gridx_mem_pkg.sv"
append compile_cmd " $MESH_DIR/mem_mesh_arbiter.sv"
append compile_cmd " $MESH_DIR/mem_mesh_endpoint_ni.sv"
append compile_cmd " $MESH_DIR/mem_mesh_router.sv"
append compile_cmd " $MESH_DIR/mem_mesh_top.sv"

# Design source files
# Compile packages first to ensure types and parameters are available to other modules
append compile_cmd " $SRC_DIR/gridx_pkg.sv"
append compile_cmd " $SRC_DIR/gridx_defines.vh"

foreach f [lsort [glob -directory $SRC_DIR *.sv *.vh]] {
    set tail [file tail $f]
    if {$tail in {gridx_pkg.sv gridx_defines.vh}} {
        continue
    }
    append compile_cmd " $f"
}

# Testbench
append compile_cmd " $SIM_DIR/$TOP_TB.sv"

if {[catch {exec {*}[split $compile_cmd] 2>@1} result]} {
    puts $result
    exit 1
}
puts $result

puts "\n>>> Elaborating..."
set debug_level "off"
if {[info exists ::env(XILINX_DEBUG_LEVEL)]} {
    set debug_level $::env(XILINX_DEBUG_LEVEL)
}
if {[catch {exec xelab $TOP_TB -timescale 1ns/1ns -debug $debug_level --nolog -s ${TOP_TB}_sim 2>@1} result]} {
    puts $result
    exit 1
}
puts $result

puts "\n>>> Running simulation..."
if {[catch {exec xsim ${TOP_TB}_sim -runall --nolog 2>@1} result]} {
    puts $result
    exit 1
}
puts $result

puts " SIMULATION COMPLETE"
