@echo off
xelab tb_uvm_top -s sim_saxpy -timescale 1ns/1ps -debug all -L uvm -generic_top "UVM_TESTNAME=gridx_saxpy_test"
xsim sim_saxpy --testplusarg UVM_TESTNAME=gridx_saxpy_test --testplusarg UVM_VERBOSITY=UVM_LOW --tclbatch run_saxpy_batch.tcl --log logs/saxpy_run.log
