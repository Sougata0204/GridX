// GridX3 UVM Environment
// Top-level container connecting all agents, scoreboard, and coverage.

`ifndef GRIDX_ENV_SV
`define GRIDX_ENV_SV

class gridx_env extends uvm_env;

    // Agents
    gridx_host_agent    m_host_agent;
    gridx_kernel_agent  m_kernel_agent;

    // Scoreboard
    gridx_scoreboard    m_scoreboard;

    // Coverage
    gridx_coverage      m_coverage;

    `uvm_component_utils(gridx_env)

    function new(string name = "gridx_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Build active host agent (driver + sequencer + monitor) — UVM_ACTIVE by default
        m_host_agent   = gridx_host_agent::type_id::create("m_host_agent", this);

        // Build passive kernel status agent (monitor only)
        m_kernel_agent = gridx_kernel_agent::type_id::create("m_kernel_agent", this);

        // Build scoreboard and coverage
        m_scoreboard   = gridx_scoreboard::type_id::create("m_scoreboard", this);
        m_coverage     = gridx_coverage::type_id::create("m_coverage", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Host monitor → Scoreboard (host commands)
        m_host_agent.m_monitor.ap_host_cmd.connect(m_scoreboard.imp_host_cmd);

        // Host monitor → Scoreboard (memory writes/reads for data checking)
        m_host_agent.m_monitor.ap_mem_write.connect(m_scoreboard.imp_mem_write);
        m_host_agent.m_monitor.ap_mem_read.connect(m_scoreboard.imp_mem_read);

        // Kernel monitor → Scoreboard (kernel done/fault events)
        m_kernel_agent.m_monitor.ap_kernel_status.connect(m_scoreboard.imp_kernel_status);

        // Host monitor → Coverage (command types)
        m_host_agent.m_monitor.ap_host_cmd.connect(m_coverage.analysis_export);

        // Kernel monitor → Coverage (completion/fault events)
        m_kernel_agent.m_monitor.ap_kernel_status.connect(m_coverage.analysis_export);
    endfunction

endclass

`endif // GRIDX_ENV_SV
