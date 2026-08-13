# GridX3 -- Vivado/XSim compile and run flow
# Usage:
#   vivado -mode batch -source scripts/compile_xsim.tcl
#   vivado -mode batch -source scripts/compile_xsim.tcl -tclargs <top> [run]

set SCRIPT_DIR   [file normalize [file dirname [info script]]]
set PROJECT_ROOT [file normalize [file join $SCRIPT_DIR ..]]
set WORK_DIR     [file join $PROJECT_ROOT xsim_work]

set TOP_MODULE tb_gridx_kernel_top
set RUN_SIM 0
set RUN_TIME 5us

if {$argc > 0 && [lindex $argv 0] ne ""} {
    set TOP_MODULE [lindex $argv 0]
}

if {$argc > 1 && [string equal -nocase [lindex $argv 1] "run"]} {
    set RUN_SIM 1
}

if {$argc > 2 && [lindex $argv 2] ne ""} {
    set PROJECT_ROOT [file normalize [lindex $argv 2]]
}

if {$argc > 3 && [lindex $argv 3] ne ""} {
    set RUN_TIME [lindex $argv 3]
}

set SRC_DIR      [file join $PROJECT_ROOT src]
set MESH_SRC_DIR [file join $PROJECT_ROOT memory_mesh src]
set SIM_DIR      [file join $PROJECT_ROOT sim]
set MESH_SIM_DIRS [list \
    [file join $PROJECT_ROOT memory_mesh sim] \
    [file join $PROJECT_ROOT memory_mesh tb] \
]
set UVM_SIM_DIR [file join $SIM_DIR uvm]
set WORK_DIR [file join $PROJECT_ROOT xsim_work]

# Detect UVM mode based on top module name
set UVM_MODE 0
if {[string match "*uvm*" $TOP_MODULE]} {
    set UVM_MODE 1
}

proc add_unique {var_name file_name} {
    upvar 1 $var_name files
    set normalized [file normalize $file_name]
    if {[lsearch -exact $files $normalized] < 0} {
        lappend files $normalized
    }
}

file mkdir $WORK_DIR
cd $WORK_DIR

set files [list]

# Packages first, then the rest of the design and simulation sources.
add_unique files [file join $MESH_SRC_DIR gridx_mem_pkg.sv]
add_unique files [file join $SRC_DIR gridx_pkg.sv]
add_unique files [file join $SRC_DIR gridx_config_pkg.sv]

# Add optional package files if they exist
foreach opt_file [list gridx_sim_config.sv gridx_fabric_pkg.sv] {
    set opt_path [file join $SRC_DIR $opt_file]
    if {[file exists $opt_path]} {
        add_unique files $opt_path
    }
}

foreach file_name [lsort [glob -nocomplain [file join $MESH_SRC_DIR *.sv]]] {
    add_unique files $file_name
}

foreach file_name [lsort [glob -nocomplain [file join $SRC_DIR *.sv]]] {
    set tail [file tail $file_name]
    if {$tail in {
        sample_gpu.sv
        sample_gpu_top.sv
        sample_gpu_top_rejected.sv
    }} {
        continue
    }
    add_unique files $file_name
}

set top_tb [file join $SIM_DIR ${TOP_MODULE}.sv]
if {[file exists $top_tb]} {
    add_unique files $top_tb
} else {
    foreach mesh_sim_dir $MESH_SIM_DIRS {
        set mesh_top_tb [file join $mesh_sim_dir ${TOP_MODULE}.sv]
        if {[file exists $mesh_top_tb]} {
            add_unique files $mesh_top_tb
        }
    }
}

# For UVM mode, add UVM source files
if {$UVM_MODE} {
    # Add UVM interfaces first (not inside package)
    # gridx_if.sv is included by tb_uvm_top.sv, so we add the package and TB
    add_unique files [file join $UVM_SIM_DIR gridx_uvm_pkg.sv]
    add_unique files [file join $UVM_SIM_DIR tb_uvm_top.sv]
}

puts " GridX3 Vivado/XSim Compile"
puts " Root: $PROJECT_ROOT"
puts " Work: $WORK_DIR"
puts " Top:  $TOP_MODULE"
puts " Files: [llength $files]"

puts "\n>>> Running xvlog..."
set xvlog_base [list xvlog -sv -work xil_defaultlib -d DEBUG -i $SRC_DIR -i $MESH_SRC_DIR -i $UVM_SIM_DIR]
if {$UVM_MODE} {
    lappend xvlog_base -L uvm
}
foreach file_name $files {
    puts "xvlog: $file_name"
    set xvlog_cmd $xvlog_base
    lappend xvlog_cmd $file_name
    if {[catch {exec {*}$xvlog_cmd 2>@1} result]} {
        puts $result
        exit 1
    }
    puts $result
}

puts "\n>>> Running xelab..."
set debug_level "off"
if {[info exists ::env(XILINX_DEBUG_LEVEL)]} {
    set debug_level $::env(XILINX_DEBUG_LEVEL)
}
set xelab_cmd [list xelab -debug $debug_level xil_defaultlib.$TOP_MODULE -snapshot $TOP_MODULE]
if {$UVM_MODE} {
    lappend xelab_cmd -L uvm
}
if {[catch {exec {*}$xelab_cmd 2>@1} result]} {
    puts $result
    exit 1
}
puts $result

if {$RUN_SIM} {
    puts "\n>>> Running xsim..."
    if {[string equal -nocase $RUN_TIME "all"]} {
        set xsim_cmd [list xsim $TOP_MODULE -R]
    } else {
        set run_script [file join $WORK_DIR run_${TOP_MODULE}.tcl]
        set fp [open $run_script w]
        puts $fp "run $RUN_TIME"
        puts $fp "quit"
        close $fp
        set xsim_cmd [list xsim $TOP_MODULE -tclbatch $run_script]
        if {$UVM_MODE && $argc > 4 && [lindex $argv 4] ne ""} {
            lappend xsim_cmd --testplusarg "UVM_TESTNAME=[lindex $argv 4]"
        }
    }
    if {[catch {exec {*}$xsim_cmd 2>@1} result]} {
        puts $result
        exit 1
    }
    puts $result
}

puts " XSIM FLOW COMPLETE"
puts " Snapshot: $TOP_MODULE"
