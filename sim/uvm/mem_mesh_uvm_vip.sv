// GridX3 MemoryMesh NoC UVM VIP
// UVM Monitor, Sequence Item, and Agent for MemoryMesh NoC 256-bit flit inspection.

`ifndef MEM_MESH_UVM_VIP_SV
`define MEM_MESH_UVM_VIP_SV

`timescale 1ps/1ps
import gridx_mem_pkg::*;

class mem_mesh_seq_item extends uvm_sequence_item;
    rand flit_type_e flit_type;
    rand logic [1:0] vc_id;
    rand logic [255:0] data;
    rand logic [3:0] src_x, src_y, src_z;
    rand logic [3:0] dest_x, dest_y, dest_z;

    `uvm_object_utils_begin(mem_mesh_seq_item)
        `uvm_field_enum(flit_type_e, flit_type, UVM_ALL_ON)
        `uvm_field_int(vc_id, UVM_ALL_ON)
        `uvm_field_int(data, UVM_ALL_ON)
        `uvm_field_int(src_x, UVM_ALL_ON)
        `uvm_field_int(src_y, UVM_ALL_ON)
        `uvm_field_int(src_z, UVM_ALL_ON)
        `uvm_field_int(dest_x, UVM_ALL_ON)
        `uvm_field_int(dest_y, UVM_ALL_ON)
        `uvm_field_int(dest_z, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "mem_mesh_seq_item");
        super.new(name);
    endfunction
endclass

class mem_mesh_agent extends uvm_agent;
    uvm_analysis_port #(mem_mesh_seq_item) ap;

    `uvm_component_utils(mem_mesh_agent)

    function new(string name = "mem_mesh_agent", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction
endclass

`endif // MEM_MESH_UVM_VIP_SV
