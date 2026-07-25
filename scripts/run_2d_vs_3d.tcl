# ============================================================================
# GridX³ 2D vs 3D Controlled Comparison Runner
# ============================================================================
# Runs gvf.sv (3D baseline, CUBE_Z=2) and gvf_2d.sv (2D slice, CUBE_Z=1)
# sequentially, captures logs, then invokes Python analysis.
#
# Usage from project root:
#   vivado -mode batch -source scripts/run_2d_vs_3d.tcl
# ============================================================================

set SCRIPT_DIR   [file normalize [file dirname [info script]]]
set PROJECT_ROOT [file normalize [file join $SCRIPT_DIR ..]]
set WORK_DIR     [file join $PROJECT_ROOT xsim_work]
set SRC_DIR      [file join $PROJECT_ROOT src]
set MESH_SRC_DIR [file join $PROJECT_ROOT memory_mesh src]
set SIM_DIR      [file join $PROJECT_ROOT sim]

set LOG_3D [file join $WORK_DIR gvf_3d.log]
set LOG_2D [file join $WORK_DIR gvf_2d.log]

# --- Shared file-list builder (same as compile_xsim.tcl) ---
proc add_unique {var_name file_name} {
    upvar 1 $var_name files
    set normalized [file normalize $file_name]
    if {[lsearch -exact $files $normalized] < 0} {
        lappend files $normalized
    }
}

proc build_file_list {src_dir mesh_src_dir sim_dir top_module} {
    set files [list]
    add_unique files [file join $mesh_src_dir gridx_mem_pkg.sv]
    add_unique files [file join $src_dir gridx_pkg.sv]
    add_unique files [file join $src_dir gridx_config_pkg.sv]

    foreach opt_file [list gridx_sim_config.sv gridx_fabric_pkg.sv] {
        set opt_path [file join $src_dir $opt_file]
        if {[file exists $opt_path]} {
            add_unique files $opt_path
        }
    }

    foreach file_name [lsort [glob -nocomplain [file join $mesh_src_dir *.sv]]] {
        add_unique files $file_name
    }

    foreach file_name [lsort [glob -nocomplain [file join $src_dir *.sv]]] {
        set tail [file tail $file_name]
        if {$tail in {sample_gpu.sv sample_gpu_top.sv sample_gpu_top_rejected.sv}} {
            continue
        }
        add_unique files $file_name
    }

    set top_tb [file join $sim_dir ${top_module}.sv]
    if {[file exists $top_tb]} {
        add_unique files $top_tb
    }

    return $files
}

proc compile_and_run {top_module src_dir mesh_src_dir sim_dir work_dir log_file label} {
    puts ""
    puts "╔══════════════════════════════════════════════════════════════╗"
    puts "║  Compiling: $label"
    puts "║  Top:       $top_module"
    puts "║  Log:       $log_file"
    puts "╚══════════════════════════════════════════════════════════════╝"

    file mkdir $work_dir
    cd $work_dir

    set files [build_file_list $src_dir $mesh_src_dir $sim_dir $top_module]
    puts "  Files: [llength $files]"

    # Compile
    set xvlog_base [list xvlog -sv -work xil_defaultlib -d DEBUG -i $src_dir -i $mesh_src_dir]
    foreach file_name $files {
        set xvlog_cmd $xvlog_base
        lappend xvlog_cmd $file_name
        if {[catch {exec {*}$xvlog_cmd 2>@1} result]} {
            puts "COMPILE ERROR in [file tail $file_name]:"
            puts $result
            return 0
        }
    }
    puts "  Compilation OK."

    # Elaborate
    set xelab_cmd [list xelab -debug off xil_defaultlib.$top_module -snapshot $top_module]
    if {[catch {exec {*}$xelab_cmd 2>@1} result]} {
        puts "ELABORATE ERROR:"
        puts $result
        return 0
    }
    puts "  Elaboration OK."

    # Simulate
    puts "  Running simulation..."
    set xsim_cmd [list xsim $top_module -R]
    if {[catch {exec {*}$xsim_cmd 2>@1} result]} {
        # xsim may return non-zero due to $finish — check if we got output
        if {[string length $result] > 100} {
            puts "  Simulation completed (with \$finish)."
        } else {
            puts "SIMULATION ERROR:"
            puts $result
            return 0
        }
    } else {
        puts "  Simulation completed."
    }

    # Write log
    set fp [open $log_file w]
    puts $fp $result
    close $fp
    puts "  Log saved: $log_file"
    return 1
}


# ============================================================================
# MAIN
# ============================================================================
puts ""
puts "╔══════════════════════════════════════════════════════════════════╗"
puts "║   GridX³ 2D vs 3D Controlled A/B Comparison                   ║"
puts "║   Config A: CUBE_X=2, CUBE_Y=2, CUBE_Z=1  (2D, 4 cores)      ║"
puts "║   Config B: CUBE_X=2, CUBE_Y=2, CUBE_Z=2  (3D, 8 cores)      ║"
puts "╚══════════════════════════════════════════════════════════════════╝"

# --- Run 3D baseline (gvf.sv) ---
set ok_3d [compile_and_run "gvf" $SRC_DIR $MESH_SRC_DIR $SIM_DIR $WORK_DIR $LOG_3D \
    "3D-BASELINE (2x2x2, 8 cores)"]

if {!$ok_3d} {
    puts "\n[ERROR] 3D simulation failed. Aborting comparison."
    exit 1
}

# --- Run 2D slice (gvf_2d.sv) ---
set ok_2d [compile_and_run "gvf_2d" $SRC_DIR $MESH_SRC_DIR $SIM_DIR $WORK_DIR $LOG_2D \
    "2D-SLICE (2x2x1, 4 cores)"]

if {!$ok_2d} {
    puts "\n[ERROR] 2D simulation failed. Aborting comparison."
    exit 1
}

# --- Run analysis ---
puts ""
puts "╔══════════════════════════════════════════════════════════════════╗"
puts "║   Running Analysis                                             ║"
puts "╚══════════════════════════════════════════════════════════════════╝"

set analysis_script [file join $SCRIPT_DIR analyze_2d_vs_3d.py]
if {[file exists $analysis_script]} {
    if {[catch {exec python $analysis_script $LOG_3D $LOG_2D 2>@1} result]} {
        puts $result
    } else {
        puts $result
    }
} else {
    puts "  Analysis script not found: $analysis_script"
    puts "  Run manually: python scripts/analyze_2d_vs_3d.py $LOG_3D $LOG_2D"
}

puts ""
puts "╔══════════════════════════════════════════════════════════════════╗"
puts "║   2D vs 3D Comparison Complete                                 ║"
puts "║   Logs: $LOG_3D"
puts "║         $LOG_2D"
puts "╚══════════════════════════════════════════════════════════════════╝"
