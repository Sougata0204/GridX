# ============================================================================
# GridX³ — Vivado Project Cleanup Script
# ============================================================================
# Run this in Vivado Tcl Console to remove stale MemoryMesh_NoC files
# that were accidentally added to the project.
#
# Usage: source scripts/cleanup_project.tcl
# ============================================================================

puts "Cleaning up stale MemoryMesh_NoC files from project..."

# List of external files that should NOT be in this project
set stale_patterns {
    "*MemoryMesh_NoC*"
    "*mesh_noc_pkg*"
    "*mesh_noc_router*"
    "*mesh_noc_arbiter*"
    "*mesh_noc_endpoint_ni*"
    "*mesh_noc_top*"
    "*tb_mesh_noc*"
}

set removed 0
foreach pat $stale_patterns {
    set matches [get_files -quiet $pat]
    foreach f $matches {
        puts "  Removing: $f"
        remove_files $f
        incr removed
    }
}

if {$removed > 0} {
    puts "\nRemoved $removed stale file(s)."
    puts "The project now uses only GridX/memory_mesh/src/ modules."
} else {
    puts "\nNo stale files found. Project is clean."
}

puts ""
puts "To verify, check that the hierarchy shows:"
puts "  gridx_kernel_top → u_mesh : mem_mesh_top (from memory_mesh/src/)"
puts "  NOT mesh_noc_top (from MemoryMesh_NoC/)"
puts ""
