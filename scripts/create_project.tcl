# ============================================================================
# GridX3 -- Vivado Project Creation Script
# ============================================================================
# Usage: In Vivado Tcl Console:
#   cd D:/ML_DL_AI/GridX_Vivado/GridX/scripts
#   source create_project.tcl
# ============================================================================

set SCRIPT_DIR   [file normalize [file dirname [info script]]]
set PROJECT_ROOT [file normalize [file join $SCRIPT_DIR ..]]

set PROJ_NAME  GridX3
set PROJ_DIR   [file join $PROJECT_ROOT vivado_project]
set PART       xcu30-fbvb900-2-e       ;# Override with: vivado ... -tclargs <part>
set TOP_MODULE gridx_kernel_top

if {$argc > 0 && [lindex $argv 0] ne ""} {
    set PART [lindex $argv 0]
}

# ---- Create Project ----
create_project $PROJ_NAME $PROJ_DIR -part $PART -force
set_property target_language Verilog [current_project]

# ---- Add Design Sources ----
# Memory mesh package + modules (must compile first)
set MEMORY_MESH_SRC [file join $PROJECT_ROOT memory_mesh src]
if {[file exists $MEMORY_MESH_SRC]} {
    add_files -norecurse [glob [file join $MEMORY_MESH_SRC *.sv]]
}

# GridX RTL sources
add_files -norecurse [glob [file join $PROJECT_ROOT src *.sv]]
add_files -norecurse [glob [file join $PROJECT_ROOT src *.vh]]

# Set file type for header files
foreach f [get_files *.vh] {
    set_property file_type "Verilog Header" $f
}

# ---- Add Simulation Sources ----
add_files -fileset sim_1 -norecurse [glob [file join $PROJECT_ROOT sim *.sv]]
set MEMORY_MESH_SIM [file join $PROJECT_ROOT memory_mesh sim]
if {[file exists $MEMORY_MESH_SIM]} {
    add_files -fileset sim_1 -norecurse [glob [file join $MEMORY_MESH_SIM *.sv]]
}

# ---- Add Constraints ----
add_files -fileset constrs_1 -norecurse [glob [file join $PROJECT_ROOT constraints *.xdc]]

# ---- Set Top Module ----
set_property top $TOP_MODULE [current_fileset]

# ---- Compile Order: packages first ----
set_property source_mgmt_mode All [current_project]
reorder_files -front [get_files gridx_mem_pkg.sv]
reorder_files -after [get_files gridx_mem_pkg.sv] [get_files gridx_pkg.sv]

# ---- Simulation Top (unified testbench) ----
set_property top tb_gridx_top [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# ---- IMPORTANT: Do NOT add files from MemoryMesh_NoC/ ----
# GridX uses its own integrated memory_mesh/src/ modules.
# Adding MemoryMesh_NoC/ causes duplicate type definitions and errors.

puts ""
puts "============================================"
puts " GridX³ Vivado Project Created"
puts " Project: $PROJ_DIR/$PROJ_NAME.xpr"
puts " Top:     $TOP_MODULE"
puts " Part:    $PART"
puts " Cores:   2×2×2 = 8 (parameterized)"
puts "============================================"
puts ""
puts "Next steps:"
puts "  1. Open Elaborated Design  (RTL schematic)"
puts "  2. Run Synthesis           (gate-level netlist)"
puts "  3. Run Implementation      (place & route)"
puts ""
puts "NOTE: Do NOT add files from MemoryMesh_NoC/."
puts "      GridX uses its own memory_mesh/src/ modules."
puts ""

