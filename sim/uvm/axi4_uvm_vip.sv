// GridX3 AXI4 UVM VIP
// UVM Agent, Sequence Item, Driver, and Monitor for 512-bit AXI4 memory channel interfaces.

`ifndef AXI4_UVM_VIP_SV
`define AXI4_UVM_VIP_SV

`timescale 1ns/1ps

class axi4_seq_item extends uvm_sequence_item;
    rand logic [3:0]   id;
    rand logic [31:0]  addr;
    rand logic [7:0]   len;
    rand logic [2:0]   size;
    rand logic [1:0]   burst;
    rand logic         is_write;
    rand logic [511:0] data[];
    logic [1:0]        resp;

    `uvm_object_utils_begin(axi4_seq_item)
        `uvm_field_int(id, UVM_ALL_ON)
        `uvm_field_int(addr, UVM_ALL_ON)
        `uvm_field_int(len, UVM_ALL_ON)
        `uvm_field_int(size, UVM_ALL_ON)
        `uvm_field_int(burst, UVM_ALL_ON)
        `uvm_field_int(is_write, UVM_ALL_ON)
        `uvm_field_array_int(data, UVM_ALL_ON)
        `uvm_field_int(resp, UVM_ALL_ON | UVM_NOCOMPARE)
    `uvm_object_utils_end

    function new(string name = "axi4_seq_item");
        super.new(name);
    endfunction
endclass

class axi4_monitor extends uvm_monitor;
    virtual axi4_if vif;
    uvm_analysis_port #(axi4_seq_item) ap;

    `uvm_component_utils(axi4_monitor)

    function new(string name = "axi4_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi4_if)::get(this, "", "axi4_vif", vif))
            `uvm_fatal("NOVIF", "Could not get virtual interface 'axi4_vif'")
    endfunction

    virtual task run_phase(uvm_phase phase);
        axi4_seq_item item;
        forever begin
            @(posedge vif.clk);
            if (vif.arvalid && vif.arready) begin
                item = axi4_seq_item::type_id::create("axi4_ar_item");
                item.id       = vif.arid;
                item.addr     = vif.araddr;
                item.len      = vif.arlen;
                item.is_write = 1'b0;
                ap.write(item);
            end
            if (vif.awvalid && vif.awready) begin
                item = axi4_seq_item::type_id::create("axi4_aw_item");
                item.id       = vif.awid;
                item.addr     = vif.awaddr;
                item.len      = vif.awlen;
                item.is_write = 1'b1;
                ap.write(item);
            end
        end
    endtask
endclass

class axi4_agent extends uvm_agent;
    axi4_monitor m_monitor;

    `uvm_component_utils(axi4_agent)

    function new(string name = "axi4_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_monitor = axi4_monitor::type_id::create("m_monitor", this);
    endfunction
endclass

`endif // AXI4_UVM_VIP_SV
