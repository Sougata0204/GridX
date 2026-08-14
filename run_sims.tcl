open_project GridX.xpr
set_property source_mgmt_mode None [current_project]
remove_files -fileset sim_1 {../../../../../uvm_sim_work/gridx3_uvm.sim/sim_1/behav/xsim/glbl.v}

set_property top gvf_2d [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation
run 50us
close_sim

set_property top gvf_3d_full [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation
run 50us
close_sim
