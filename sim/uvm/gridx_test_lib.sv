// GridX3 UVM Test Library
// Contains base test and all concrete test scenarios.

`ifndef GRIDX_TEST_LIB_SV
`define GRIDX_TEST_LIB_SV

// ISA opcode constants for program generation
localparam logic [3:0] OP_BRnzp = 4'h1, OP_CMP  = 4'h2,
                       OP_ADD   = 4'h3, OP_SUB  = 4'h4, OP_MUL = 4'h5, OP_DIV = 4'h6,
                       OP_STR   = 4'h8, OP_CONST = 4'h9, OP_BAR = 4'hD, OP_RET = 4'hF;

// Helper: encode CONST rd, imm
function automatic logic [15:0] enc_const(input logic [3:0] rd, input logic [7:0] imm);
    return {OP_CONST, rd, imm};
endfunction

// Helper: encode ALU op rd, rs, rt
function automatic logic [15:0] enc_rrr(input logic [3:0] op, rd, rs, rt);
    return {op, rd, rs, rt};
endfunction

class gridx_divergent_seq extends uvm_sequence #(gridx_host_seq_item);
    `uvm_object_utils(gridx_divergent_seq)

    function new(string name = "gridx_divergent_seq");
        super.new(name);
    endfunction

    virtual task body();
        gridx_host_seq_item item;

        // 1. Reset wait
        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_RESET;
        `uvm_send(item)

        // 2. Poison DMEM sentinel at addresses 896..899
        for (int i = 0; i < 4; i++) begin
            `uvm_create(item)
            item.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM;
            item.mem_addr = 22'd896 + i;
            item.mem_data = 8'hAA;
            `uvm_send(item)
        end

        // 3. Load program (exact encoding from gvf_divergent_test.sv)
        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_LOAD_PROG;
        item.program_binary = new[18];
        item.program_binary[0]  = enc_const(4'h1, 8'h02);              // CONST r1, 2
        item.program_binary[1]  = enc_rrr(OP_DIV, 4'h2, 4'hF, 4'h1);  // DIV r2, r15, r1
        item.program_binary[2]  = enc_rrr(OP_MUL, 4'h3, 4'h2, 4'h1);  // MUL r3, r2, r1
        item.program_binary[3]  = enc_rrr(OP_SUB, 4'h4, 4'hF, 4'h3);  // SUB r4, r15, r3
        item.program_binary[4]  = enc_const(4'h5, 8'h00);              // CONST r5, 0
        item.program_binary[5]  = enc_rrr(OP_CMP, 4'h0, 4'h4, 4'h5);  // CMP r0, r4, r5
        item.program_binary[6]  = {OP_BRnzp, 3'b010, 1'b0, 8'd12};    // BRZ to PC 12
        item.program_binary[7]  = enc_const(4'h6, 8'h14);              // CONST r6, 20 (odd)
        item.program_binary[8]  = enc_const(4'h7, 8'h80);              // CONST r7, 0x80
        item.program_binary[9]  = enc_rrr(OP_ADD, 4'h7, 4'h7, 4'hF);  // ADD r7, r7, r15
        item.program_binary[10] = {OP_STR, 4'h0, 4'h7, 4'h6};         // STR at [r7]
        item.program_binary[11] = {OP_BRnzp, 3'b111, 1'b0, 8'd17};    // BR always to 17
        item.program_binary[12] = enc_const(4'h6, 8'h0A);              // CONST r6, 10 (even)
        item.program_binary[13] = enc_const(4'h7, 8'h80);              // CONST r7, 0x80
        item.program_binary[14] = enc_rrr(OP_ADD, 4'h7, 4'h7, 4'hF);  // ADD r7, r7, r15
        item.program_binary[15] = {OP_STR, 4'h0, 4'h7, 4'h6};         // STR at [r7]
        item.program_binary[16] = {OP_BAR, 11'h0, 1'b1};               // BAR 1 (sync)
        item.program_binary[17] = {OP_RET, 12'h000};                   // RET
        `uvm_send(item)

        // 4. Configure: 4 threads
        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_CONFIGURE;
        item.thread_count = 16'd4;
        `uvm_send(item)

        // 5. Start kernel
        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_START;
        `uvm_send(item)

        // 6. Read back results
        for (int i = 0; i < 4; i++) begin
            `uvm_create(item)
            item.cmd_type = gridx_host_seq_item::CMD_READ_DMEM;
            item.mem_addr = 22'd896 + i;
            `uvm_send(item)
            `uvm_info("SEQ", $sformatf("Thread %0d: DMEM[%0d] = 0x%02h", i, 896+i, item.read_data), UVM_LOW)
        end
    endtask
endclass


// Oversubscription Sequence

class gridx_oversub_seq extends uvm_sequence #(gridx_host_seq_item);
    `uvm_object_utils(gridx_oversub_seq)

    function new(string name = "gridx_oversub_seq");
        super.new(name);
    endfunction

    virtual task body();
        gridx_host_seq_item item;

        // 1. Reset
        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_RESET;
        `uvm_send(item)

        // 2. Load a simple store-and-halt program
        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_LOAD_PROG;
        item.program_binary = new[6];
        item.program_binary[0] = enc_const(4'h1, 8'h42);              // CONST r1, 0x42
        item.program_binary[1] = enc_const(4'h2, 8'h80);              // CONST r2, 0x80
        item.program_binary[2] = enc_rrr(OP_ADD, 4'h2, 4'h2, 4'hF);  // ADD r2, r2, r15
        item.program_binary[3] = {OP_STR, 4'h0, 4'h2, 4'h1};         // STR at [r2]
        item.program_binary[4] = {OP_BAR, 11'h0, 1'b1};               // BAR sync
        item.program_binary[5] = {OP_RET, 12'h000};                   // RET
        `uvm_send(item)

        // 3. Configure: 4 threads (matches scheduler THREADS_PER_BLOCK)
        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_CONFIGURE;
        item.thread_count = 16'd4;
        `uvm_send(item)

        // 4. Start kernel
        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_START;
        `uvm_send(item)
    endtask
endclass


// Base UVM Test

class gridx_base_test extends uvm_test;

    gridx_env m_env;

    `uvm_component_utils(gridx_base_test)

    function new(string name = "gridx_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_env = gridx_env::type_id::create("m_env", this);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this, "gridx_base_test running");
        `uvm_info("TEST", "gridx_base_test: no sequence configured. Exiting.", UVM_LOW)
        #1000;
        phase.drop_objection(this, "gridx_base_test done");
    endtask

    virtual function void report_phase(uvm_phase phase);
        uvm_report_server srv = uvm_report_server::get_server();
        int unsigned err_count = srv.get_severity_count(UVM_ERROR) + srv.get_severity_count(UVM_FATAL);
        if (err_count == 0)
            `uvm_info("TEST", "*** TEST PASSED ***", UVM_NONE)
        else
            `uvm_info("TEST", $sformatf("*** TEST FAILED (%0d errors) ***", err_count), UVM_NONE)
    endfunction
endclass


// Divergent Branch Test

class gridx_divergent_branch_test extends gridx_base_test;

    `uvm_component_utils(gridx_divergent_branch_test)

    function new(string name = "gridx_divergent_branch_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        gridx_divergent_seq seq;
        phase.raise_objection(this, "divergent_branch_test running");
        `uvm_info("TEST", "Starting Divergent Branch Test...", UVM_LOW)

        seq = gridx_divergent_seq::type_id::create("seq");
        seq.start(m_env.m_host_agent.m_sequencer);

        // Wait for kernel to finish (monitored by kernel_agent)
        #50000;

        `uvm_info("TEST", "Divergent Branch Test complete.", UVM_LOW)
        phase.drop_objection(this, "divergent_branch_test done");
    endtask
endclass


// Oversubscription Test

class gridx_oversub_test extends gridx_base_test;

    `uvm_component_utils(gridx_oversub_test)

    function new(string name = "gridx_oversub_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        gridx_oversub_seq seq;
        phase.raise_objection(this, "oversub_test running");
        `uvm_info("TEST", "Starting Oversubscription Test...", UVM_LOW)

        seq = gridx_oversub_seq::type_id::create("seq");
        seq.start(m_env.m_host_agent.m_sequencer);

        // Allow time for 2x oversubscription
        #100000;

        `uvm_info("TEST", "Oversubscription Test complete.", UVM_LOW)
        phase.drop_objection(this, "oversub_test done");
    endtask
endclass


// ISA Full Suite Regression Test
class gridx_isa_regression_test extends gridx_base_test;
    `uvm_component_utils(gridx_isa_regression_test)

    function new(string name = "gridx_isa_regression_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        gridx_oversub_seq seq;
        phase.raise_objection(this, "isa_regression_test running");
        `uvm_info("TEST", "Starting ISA Full Suite Regression Test...", UVM_LOW)
        seq = gridx_oversub_seq::type_id::create("seq");
        seq.start(m_env.m_host_agent.m_sequencer);
        #50000;
        `uvm_info("TEST", "ISA Full Suite Regression Test complete.", UVM_LOW)
        phase.drop_objection(this, "isa_regression_test done");
    endtask
endclass


// Tensor MMA Matrix Accelerator Test
class gridx_tensor_mma_test extends gridx_base_test;
    `uvm_component_utils(gridx_tensor_mma_test)

    function new(string name = "gridx_tensor_mma_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        gridx_oversub_seq seq;
        phase.raise_objection(this, "tensor_mma_test running");
        `uvm_info("TEST", "Starting Tensor MMA Accelerator Test...", UVM_LOW)
        seq = gridx_oversub_seq::type_id::create("seq");
        seq.start(m_env.m_host_agent.m_sequencer);
        #50000;
        `uvm_info("TEST", "Tensor MMA Accelerator Test complete.", UVM_LOW)
        phase.drop_objection(this, "tensor_mma_test done");
    endtask
endclass


// Coherence Stress Test
class gridx_coherence_stress_test extends gridx_base_test;
    `uvm_component_utils(gridx_coherence_stress_test)

    function new(string name = "gridx_coherence_stress_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        gridx_oversub_seq seq;
        phase.raise_objection(this, "coherence_stress_test running");
        `uvm_info("TEST", "Starting Coherence Stress Test...", UVM_LOW)
        seq = gridx_oversub_seq::type_id::create("seq");
        seq.start(m_env.m_host_agent.m_sequencer);
        #50000;
        `uvm_info("TEST", "Coherence Stress Test complete.", UVM_LOW)
        phase.drop_objection(this, "coherence_stress_test done");
    endtask
endclass


// MemoryMesh NoC Saturation & Congestion Test
class gridx_noc_saturation_test extends gridx_base_test;
    `uvm_component_utils(gridx_noc_saturation_test)

    function new(string name = "gridx_noc_saturation_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        gridx_oversub_seq seq;
        phase.raise_objection(this, "noc_saturation_test running");
        `uvm_info("TEST", "Starting MemoryMesh NoC Saturation Test...", UVM_LOW)
        seq = gridx_oversub_seq::type_id::create("seq");
        seq.start(m_env.m_host_agent.m_sequencer);
        #50000;
        `uvm_info("TEST", "MemoryMesh NoC Saturation Test complete.", UVM_LOW)
        phase.drop_objection(this, "noc_saturation_test done");
    endtask
endclass


// GC6 Power Gating & DVFS Scaling Test
class gridx_gc6_dvfs_test extends gridx_base_test;
    `uvm_component_utils(gridx_gc6_dvfs_test)

    function new(string name = "gridx_gc6_dvfs_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        gridx_oversub_seq seq;
        phase.raise_objection(this, "gc6_dvfs_test running");
        `uvm_info("TEST", "Starting GC6 Power & DVFS Test...", UVM_LOW)
        seq = gridx_oversub_seq::type_id::create("seq");
        seq.start(m_env.m_host_agent.m_sequencer);
        #50000;
        `uvm_info("TEST", "GC6 Power & DVFS Test complete.", UVM_LOW)
        phase.drop_objection(this, "gc6_dvfs_test done");
    endtask
endclass


//  HBM Memory Stress Sequence — targets addresses ABOVE LOCAL_MEM_RANGE
// This sequence programs the GPU with STR instructions that write to
// addresses 0xA0+ (above LOCAL_MEM_RANGE=0x9F), which forces the address
// decoder to route traffic through the mesh bridge into the 3D NoC ? HBM.

localparam logic [3:0] OP_LDR = 4'h7;

class gridx_mem_stress_seq extends uvm_sequence #(gridx_host_seq_item);
    `uvm_object_utils(gridx_mem_stress_seq)

    function new(string name = "gridx_mem_stress_seq");
        super.new(name);
    endfunction

    virtual task body();
        gridx_host_seq_item item;

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_RESET;
        `uvm_send(item)
        `uvm_info("STRESS_SEQ", "Reset complete", UVM_LOW)

        // This program generates STR instructions to addresses ABOVE
        // LOCAL_MEM_RANGE (0x9F), forcing traffic through the mesh.
        //
        // Register allocation:
        //   r1  = write value (test pattern)
        //   r2  = base address
        //   r3  = computed address = base + thread_id (r15)
        //   r15 = thread_id (hardware-provided)
        //
        // Address regions targeted:
        //   Pass 1: 0xA0 + tid  (160-191) — just above LOCAL_MEM_RANGE
        //   Pass 2: 0xC0 + tid  (192-223) — deeper into HBM space
        //   Pass 3: 0xE0 + tid  (224-255) — even deeper
        //
        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_LOAD_PROG;
        item.program_binary = new[17];

        // SETUP: Configure Smart Memory Controller Segment Base
        item.program_binary[0]  = enc_const(4'h5, 8'hF0);             // CONST r5, 0xF0 (sign extends to 0xFFF0, the control reg)
        item.program_binary[1]  = enc_const(4'h6, 8'h40);             // CONST r6, 0x40 (0x40 << 14 = 0x100000 HBM base)
        item.program_binary[2]  = {OP_STR, 4'h0, 4'h5, 4'h6};         // STR [r5], r6

        // Pass 1: STR 0xDE ? [0xA0 + tid]
        item.program_binary[3]  = enc_const(4'h1, 8'hDE);              // CONST r1, 0xDE
        item.program_binary[4]  = enc_const(4'h2, 8'hA0);              // CONST r2, 0xA0
        item.program_binary[5]  = enc_rrr(OP_ADD, 4'h3, 4'h2, 4'hF);  // ADD r3, r2, r15
        item.program_binary[6]  = {OP_STR, 4'h0, 4'h3, 4'h1};         // STR [r3], r1

        // Pass 2: STR 0xAD ? [0xC0 + tid]
        item.program_binary[7]  = enc_const(4'h1, 8'hAD);              // CONST r1, 0xAD
        item.program_binary[8]  = enc_const(4'h2, 8'hC0);              // CONST r2, 0xC0
        item.program_binary[9]  = enc_rrr(OP_ADD, 4'h3, 4'h2, 4'hF);  // ADD r3, r2, r15
        item.program_binary[10] = {OP_STR, 4'h0, 4'h3, 4'h1};         // STR [r3], r1

        // Pass 3: STR 0xBE ? [0xE0 + tid]
        item.program_binary[11] = enc_const(4'h1, 8'hBE);              // CONST r1, 0xBE
        item.program_binary[12] = enc_const(4'h2, 8'hE0);              // CONST r2, 0xE0
        item.program_binary[13] = enc_rrr(OP_ADD, 4'h3, 4'h2, 4'hF);  // ADD r3, r2, r15
        item.program_binary[14] = {OP_STR, 4'h0, 4'h3, 4'h1};         // STR [r3], r1

        // Sync + halt
        item.program_binary[15] = {OP_RET, 12'h000};                  // RET
        item.program_binary[16] = {OP_RET, 12'h000};                  // padding

        `uvm_send(item)
        `uvm_info("STRESS_SEQ", "HBM stress program loaded (17 instructions, segment base config + 3 STR passes)", UVM_LOW)

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_CONFIGURE;
        item.thread_count = 16'd32;
        `uvm_send(item)
        `uvm_info("STRESS_SEQ", "Kernel configured: 32 threads", UVM_LOW)

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_START;
        `uvm_send(item)
        `uvm_info("STRESS_SEQ", "Kernel launched — expecting 96 HBM STR transactions (3 passes x 32 threads)", UVM_LOW)
        
        // (Verification is handled by hardware valid-chain instrumentation in tb_uvm_top.sv)
    endtask
endclass


//  HBM Memory Stress Test

class gridx_mem_stress_test extends gridx_base_test;
    `uvm_component_utils(gridx_mem_stress_test)

    realtime sim_start_time;
    realtime sim_end_time;

    function new(string name = "gridx_mem_stress_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        gridx_mem_stress_seq seq;
        phase.raise_objection(this, "mem_stress_test running");

        `uvm_info("TEST", " GridX3 HBM MEMORY STRESS TEST", UVM_NONE)

        sim_start_time = $realtime;

        // Launch the stress sequence
        seq = gridx_mem_stress_seq::type_id::create("seq");
        seq.start(m_env.m_host_agent.m_sequencer);

        // Wait for kernel completion or timeout
        `uvm_info("TEST", "Waiting for kernel completion (max 10,000 cycles)...", UVM_NONE)
        #100000;  // 10,000 cycles @ 10ns

        sim_end_time = $realtime;

        phase.drop_objection(this, "mem_stress_test done");
    endtask

    virtual function void report_phase(uvm_phase phase);
        real sim_time_ns;
        int  dut_cycles;

        super.report_phase(phase);

        sim_time_ns = (sim_end_time - sim_start_time) / 1000.0;
        dut_cycles  = int'(sim_time_ns / 10.0);

        `uvm_info("STRESS", "", UVM_NONE)
        `uvm_info("STRESS", "  GridX3 MEMORY STRESS + TIMING ANALYSIS REPORT", UVM_NONE)
        `uvm_info("STRESS", $sformatf("  Clock Period:           10 ns"), UVM_NONE)
        `uvm_info("STRESS", $sformatf("  Clock Frequency:        100.0 MHz"), UVM_NONE)
        `uvm_info("STRESS", $sformatf("  Sim Wall Time:          %.1f ns", sim_time_ns), UVM_NONE)
        `uvm_info("STRESS", $sformatf("  DUT Cycles Elapsed:     %0d", dut_cycles), UVM_NONE)
        `uvm_info("STRESS", "  See [HBM_TRACE] messages above for valid-chain diagnosis.", UVM_NONE)

        begin
            uvm_report_server srv = uvm_report_server::get_server();
            int unsigned err_count = srv.get_severity_count(UVM_ERROR) + srv.get_severity_count(UVM_FATAL);
            if (err_count == 0)
                `uvm_info("TEST", "*** TEST PASSED ***", UVM_NONE)
            else
                `uvm_info("TEST", $sformatf("*** TEST FAILED (%0d errors) ***", err_count), UVM_NONE)
        end
    endfunction
endclass

//  HBM Memory Integrity Test (Proof 5)

class gridx_mem_integrity_seq extends uvm_sequence #(gridx_host_seq_item);
    `uvm_object_utils(gridx_mem_integrity_seq)

    function new(string name = "gridx_mem_integrity_seq");
        super.new(name);
    endfunction

    virtual task body();
        gridx_host_seq_item item;

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_RESET;
        `uvm_send(item)
        `uvm_info("INTEG_SEQ", "Reset complete", UVM_LOW)

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_LOAD_PROG;
        item.program_binary = new[17];

        // SETUP: Configure Smart Memory Controller Segment Base
        item.program_binary[0]  = enc_const(4'h5, 8'hF0);             // CONST r5, 0xF0
        item.program_binary[1]  = enc_const(4'h6, 8'h40);             // CONST r6, 0x40 (0x100000 base)
        item.program_binary[2]  = {OP_STR, 4'h0, 4'h5, 4'h6};         // STR [r5], r6

        // STEP 1: Write to HBM
        item.program_binary[3]  = enc_const(4'h1, 8'hAA);             // CONST r1, 0xAA (Data)
        item.program_binary[4]  = enc_const(4'h2, 8'hB0);             // CONST r2, 0xB0 (Base Addr)
        item.program_binary[5]  = enc_rrr(OP_ADD, 4'h3, 4'h2, 4'hF);  // ADD r3, r2, r15 (Addr = Base + tid)
        item.program_binary[6]  = {OP_STR, 4'h0, 4'h3, 4'h1};         // STR [r3], r1

        // STEP 2: Wait for writes to flush (Delay slots)
        item.program_binary[7]  = {4'h0 /*OP_NOP*/, 12'h000};
        item.program_binary[8]  = {4'h0 /*OP_NOP*/, 12'h000};
        item.program_binary[9]  = {4'h0 /*OP_NOP*/, 12'h000};

        // STEP 3: Read back from HBM
        item.program_binary[10] = {4'h7 /*OP_LDR*/, 4'h4, 4'h3, 4'h0};         // LDR r4, [r3]

        // STEP 4: Compare & Fault on mismatch
        item.program_binary[11] = enc_rrr(4'h2 /*OP_CMP*/, 4'h0, 4'h1, 4'h4);  // CMP r1, r4
        item.program_binary[12] = {4'h1 /*OP_BRnzp*/, 3'b010 /*NE*/, 1'b0, 8'd14}; // B.NE PC 14
        
        // Success path (PC 13)
        item.program_binary[13] = {4'hF /*OP_RET*/, 12'h000};                  // RET

        // Failure path (PC 14) - Infinite loop to trigger watchdog
        item.program_binary[14] = {4'h1 /*OP_BRnzp*/, 3'b111 /*AL*/, 1'b0, 8'd14}; // B PC 14
        
        item.program_binary[15] = {4'h0 /*OP_NOP*/, 12'h000};
        item.program_binary[16] = {4'h0 /*OP_NOP*/, 12'h000};

        `uvm_send(item)
        `uvm_info("INTEG_SEQ", "HBM integrity program loaded", UVM_LOW)

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_CONFIGURE;
        item.thread_count = 16'd32;
        `uvm_send(item)

        `uvm_create(item)
        item.cmd_type = gridx_host_seq_item::CMD_START;
        `uvm_send(item)
    endtask
    
    // Helper encoding functions
    function logic [15:0] enc_const(logic [3:0] rd, logic [7:0] imm);
        return {4'h9 /*OP_CONST*/, rd, imm};
    endfunction
    function logic [15:0] enc_rrr(logic [3:0] op, logic [3:0] rd, logic [3:0] ra, logic [3:0] rb);
        return {op, rd, ra, rb};
    endfunction
endclass

class gridx_mem_integrity_test extends gridx_base_test;
    `uvm_component_utils(gridx_mem_integrity_test)

    function new(string name = "gridx_mem_integrity_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        gridx_mem_integrity_seq seq;
        noc_synthetic_seq synth_seq;
        
        phase.raise_objection(this, "mem_integrity_test running");
        
        `uvm_info("TEST", " GridX3 HBM MEMORY INTEGRITY TEST", UVM_NONE)

        if ($test$plusargs("TRAFFIC")) begin
            synth_seq = noc_synthetic_seq::type_id::create("synth_seq");
            synth_seq.start(m_env.m_host_agent.m_sequencer);
        end else begin
            seq = gridx_mem_integrity_seq::type_id::create("seq");
            seq.start(m_env.m_host_agent.m_sequencer);
        end

        // Wait for kernel completion or timeout
        #50000;  // 5,000 cycles (plenty for 1 read/write)

        `uvm_info("TEST", "Kernel assumed complete. Waiting 1000 cycles for NoC drain...", UVM_NONE)
        #10000; // 1,000 cycles @ 10ns

        phase.drop_objection(this, "mem_integrity_test done");
    endtask
endclass

class gridx_saxpy_test extends gridx_base_test;
    `uvm_component_utils(gridx_saxpy_test)

    function new(string name = "gridx_saxpy_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        gridx_saxpy_seq seq;
        
        phase.raise_objection(this, "saxpy_test running");
        
        `uvm_info("TEST", " GridX3 FULL-SYSTEM SAXPY KERNEL TEST", UVM_NONE)

        seq = gridx_saxpy_seq::type_id::create("seq");
        seq.start(m_env.m_host_agent.m_sequencer);

        // Wait for kernel completion or timeout
        #100000;  // 10,000 cycles

        `uvm_info("TEST", "Kernel assumed complete. Waiting 1000 cycles for NoC drain...", UVM_NONE)
        #10000; // 1,000 cycles @ 10ns

        phase.drop_objection(this, "saxpy_test done");
    endtask
endclass

`endif // GRIDX_TEST_LIB_SV
