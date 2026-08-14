open_project GridX.xpr
set sim_sets [get_filesets *sim*]
puts "SIM_SETS: $sim_sets"
foreach sim_set $sim_sets {
    puts "SIM_SET $sim_set TOP: [get_property top [get_filesets $sim_set]]"
}
