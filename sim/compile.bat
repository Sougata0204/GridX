@echo off
echo sv work uvm/gridx_if.sv >> files.prj
echo sv work uvm/gridx_uvm_pkg.sv >> files.prj
echo sv work uvm/tb_uvm_top.sv >> files.prj
xvlog -prj files.prj -i uvm -L uvm
if %errorlevel% neq 0 exit /b %errorlevel%
xelab tb_uvm_top -s sim_uvm -timescale 1ns/1ps -debug all -L uvm
if %errorlevel% neq 0 exit /b %errorlevel%
xsim -f saxpy.args
