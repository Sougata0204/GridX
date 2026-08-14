open_project GridX.xpr
set_property source_mgmt_mode None [current_project]
set_property top gvf_2d [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -scripts_only
close_project
