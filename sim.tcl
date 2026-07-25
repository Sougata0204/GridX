# ==============================================================================
# GridX³ Vivado XSIM Simulation Script
# ==============================================================================
# Usage:
#   vivado -mode batch -source sim.tcl
# ==============================================================================

# Create a physical project to allow launch_simulation
create_project sim_project ./sim_project -force

# Set project properties for SystemVerilog
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# Add source files
read_verilog -sv [glob -nocomplain src/*.vh]
read_verilog -sv [glob -nocomplain src/*.sv]
read_verilog -sv [glob -nocomplain memory_mesh/src/*.sv]
read_verilog -sv [glob -nocomplain sim/*.sv]

# Set the top module
set_property top tb_isa_program [get_filesets sim_1]

# Launch the simulator
launch_simulation -step compile
launch_simulation -step elaborate
launch_simulation -step simulate -simset sim_1 -mode behavioral

# Exit Vivado
exit
