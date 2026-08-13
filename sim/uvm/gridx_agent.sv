// GridX3 UVM Agents
// Packages driver, sequencer, and monitor into reusable verification components.

`ifndef GRIDX_AGENT_SV
`define GRIDX_AGENT_SV

// Host Agent — active agent with driver + sequencer + monitor
class gridx_host_agent extends uvm_agent;

    gridx_host_driver                        m_driver;
    uvm_sequencer #(gridx_host_seq_item)     m_sequencer;
    gridx_host_monitor                       m_monitor;

    `uvm_component_utils(gridx_host_agent)

    function new(string name = "gridx_host_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        m_monitor = gridx_host_monitor::type_id::create("m_monitor", this);

        if (get_is_active() == UVM_ACTIVE) begin
            m_driver    = gridx_host_driver::type_id::create("m_driver", this);
            m_sequencer = uvm_sequencer#(gridx_host_seq_item)::type_id::create("m_sequencer", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            m_driver.seq_item_port.connect(m_sequencer.seq_item_export);
        end
    endfunction
endclass


// Kernel Status Agent — passive agent (monitor only, no driver)
class gridx_kernel_agent extends uvm_agent;

    gridx_kernel_monitor m_monitor;

    `uvm_component_utils(gridx_kernel_agent)

    function new(string name = "gridx_kernel_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // Always passive — kernel status is read-only
        m_monitor = gridx_kernel_monitor::type_id::create("m_monitor", this);
    endfunction
endclass

`endif // GRIDX_AGENT_SV
