`default_nettype none
`timescale 1ns/1ns

import gridx_config_pkg::*;

module tb_gridx_v2;

    // Simulation parameters
    parameter CLK_PERIOD = 2; // 500 MHz
    
    // Signals
    reg clk;
    reg reset;
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // VCD Control (Optional, controlled via tasks)
    wire vcd_dumping;
    reg force_dump_on = 0;
    reg force_dump_off = 0;
    
    vcd_ctrl #(
        .VCD_FILENAME("gridx_sim_v2.vcd"),
        .DUMP_START(0), // Start immediately to capture all traffic
        .DUMP_END(1000000),
        .DUMP_LEVEL(2)
    ) u_vcd (
        .clk(clk),
        .reset(reset),
        .enable(1'b1),
        .force_dump_on(force_dump_on),
        .force_dump_off(force_dump_off),
        .dumping(vcd_dumping)
    );
    
    // DPI-C Memory Model for System Memory (DRAM)
    wire sys_rd_valid, sys_wr_valid, sys_rd_ready, sys_wr_ready;
    wire [CFG_PHYSICAL_ADDR_BITS-1:0] sys_addr;
    wire [255:0] sys_wdata;
    wire [255:0] sys_rdata;
    
    wire dram_req_valid, dram_req_ready, dram_resp_valid;
    wire [2:0] dram_req_cmd;
    wire [39:0] dram_req_addr;
    wire [255:0] dram_req_wdata;
    wire [255:0] dram_resp_data;
    
    // Multiplexing for Testbench writes to DRAM
    reg sys_wr_valid_tb = 0;
    reg [CFG_PHYSICAL_ADDR_BITS-1:0] sys_addr_tb;
    reg [255:0] sys_wdata_tb;

    assign sys_rd_valid = dram_req_valid && (dram_req_cmd == 3'd2); // CMD_RD = 2
    assign sys_wr_valid = (dram_req_valid && (dram_req_cmd == 3'd3)) || sys_wr_valid_tb; // CMD_WR = 3
    assign sys_addr     = sys_wr_valid_tb ? sys_addr_tb : dram_req_addr;
    assign sys_wdata    = sys_wr_valid_tb ? sys_wdata_tb : dram_req_wdata;
    
    assign dram_req_ready = (dram_req_cmd == 3'd3) ? sys_wr_ready : sys_rd_ready;
    assign dram_resp_valid = sys_rd_ready;
    assign dram_resp_data = sys_rdata;

    gridx_mem_model #(
        .ADDR_WIDTH(CFG_PHYSICAL_ADDR_BITS),
        .DATA_WIDTH(256),
        .MEM_ID(0),
        .INIT_FILE(""), 
        .LATENCY(10) // DRAM read latency
    ) u_sys_mem (
        .clk(clk),
        .reset(reset),
        .rd_valid(sys_rd_valid),
        .rd_addr(sys_addr),
        .rd_ready(sys_rd_ready),
        .rd_data(sys_rdata),
        .wr_valid(sys_wr_valid),
        .wr_addr(sys_addr),
        .wr_data(sys_wdata),
        .wr_ready(sys_wr_ready),
        .total_reads(),
        .total_writes(),
        .pages_allocated()
    );
    
    // DPI-C Memory Models for HBM stacks (NMC access)
    wire [CFG_NUM_HBM_NODES-1:0] nmc_mem_read_valid;
    wire [31:0] nmc_mem_read_addr [CFG_NUM_HBM_NODES-1:0];
    wire [CFG_NUM_HBM_NODES-1:0] nmc_mem_read_ready;
    wire [255:0] nmc_mem_read_data [CFG_NUM_HBM_NODES-1:0];
    wire [CFG_NUM_HBM_NODES-1:0] nmc_mem_write_valid;
    wire [31:0] nmc_mem_write_addr [CFG_NUM_HBM_NODES-1:0];
    wire [255:0] nmc_mem_write_data [CFG_NUM_HBM_NODES-1:0];
    wire [CFG_NUM_HBM_NODES-1:0] nmc_mem_write_ready;

    // HBM Stack 0 (Memory ID 1)
    wire hbm0_rd_valid, hbm0_wr_valid, hbm0_rd_ready, hbm0_wr_ready;
    wire [31:0] hbm0_addr;
    wire [255:0] hbm0_wdata, hbm0_rdata;
    
    reg hbm0_wr_valid_tb = 0;
    reg [31:0] hbm0_addr_tb;
    reg [255:0] hbm0_wdata_tb;
    
    assign hbm0_rd_valid = nmc_mem_read_valid[0];
    assign hbm0_addr     = hbm0_wr_valid_tb ? hbm0_addr_tb : (nmc_mem_read_valid[0] ? nmc_mem_read_addr[0] : nmc_mem_write_addr[0]);
    assign hbm0_wr_valid = nmc_mem_write_valid[0] || hbm0_wr_valid_tb;
    assign hbm0_wdata    = hbm0_wr_valid_tb ? hbm0_wdata_tb : nmc_mem_write_data[0];
    
    assign nmc_mem_read_ready[0]  = hbm0_rd_ready;
    assign nmc_mem_read_data[0]   = hbm0_rdata;
    assign nmc_mem_write_ready[0] = hbm0_wr_ready;

    gridx_mem_model #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(256),
        .MEM_ID(1),
        .INIT_FILE(""),
        .LATENCY(5) // Lower latency for HBM
    ) u_hbm_stack0 (
        .clk(clk),
        .reset(reset),
        .rd_valid(hbm0_rd_valid),
        .rd_addr(hbm0_addr),
        .rd_ready(hbm0_rd_ready),
        .rd_data(hbm0_rdata),
        .wr_valid(hbm0_wr_valid),
        .wr_addr(hbm0_addr),
        .wr_data(hbm0_wdata),
        .wr_ready(hbm0_wr_ready),
        .total_reads(),
        .total_writes(),
        .pages_allocated()
    );

    // HBM Stack 1 (Memory ID 2)
    wire hbm1_rd_valid, hbm1_wr_valid, hbm1_rd_ready, hbm1_wr_ready;
    wire [31:0] hbm1_addr;
    wire [255:0] hbm1_wdata, hbm1_rdata;
    
    reg hbm1_wr_valid_tb = 0;
    reg [31:0] hbm1_addr_tb;
    reg [255:0] hbm1_wdata_tb;
    
    assign hbm1_rd_valid = nmc_mem_read_valid[1];
    assign hbm1_addr     = hbm1_wr_valid_tb ? hbm1_addr_tb : (nmc_mem_read_valid[1] ? nmc_mem_read_addr[1] : nmc_mem_write_addr[1]);
    assign hbm1_wr_valid = nmc_mem_write_valid[1] || hbm1_wr_valid_tb;
    assign hbm1_wdata    = hbm1_wr_valid_tb ? hbm1_wdata_tb : nmc_mem_write_data[1];
    
    assign nmc_mem_read_ready[1]  = hbm1_rd_ready;
    assign nmc_mem_read_data[1]   = hbm1_rdata;
    assign nmc_mem_write_ready[1] = hbm1_wr_ready;

    gridx_mem_model #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(256),
        .MEM_ID(2),
        .INIT_FILE(""),
        .LATENCY(5)
    ) u_hbm_stack1 (
        .clk(clk),
        .reset(reset),
        .rd_valid(hbm1_rd_valid),
        .rd_addr(hbm1_addr),
        .rd_ready(hbm1_rd_ready),
        .rd_data(hbm1_rdata),
        .wr_valid(hbm1_wr_valid),
        .wr_addr(hbm1_addr),
        .wr_data(hbm1_wdata),
        .wr_ready(hbm1_wr_ready),
        .total_reads(),
        .total_writes(),
        .pages_allocated()
    );

    // Device Under Test: Active Base Die
    
    // TSV Interface
    wire [CFG_NUM_CORES-1:0] tsv_rx_valid, tsv_tx_valid;
    wire [CFG_TSV_DATA_WIDTH-1:0] tsv_rx_data [CFG_NUM_CORES-1:0];
    wire [CFG_TSV_DATA_WIDTH-1:0] tsv_tx_data [CFG_NUM_CORES-1:0];
    
    // Loopback TSVs for base die testing
    genvar t;
    generate
        for (t = 0; t < CFG_NUM_CORES; t = t + 1) begin : loopback
            assign tsv_rx_valid[t] = tsv_tx_valid[t];
            assign tsv_rx_data[t]  = tsv_tx_data[t];
        end
    endgenerate

    reg host_cmd_valid = 0;
    reg [127:0] host_cmd_data = 0;
    wire host_cmd_ready;
    
    // MMU Translation Ports
    reg translate_valid = 0;
    reg [CFG_VIRTUAL_ADDR_BITS-1:0] translate_vaddr;
    reg [7:0] translate_asid;
    reg translate_write;
    wire translate_ready;
    wire [CFG_PHYSICAL_ADDR_BITS-1:0] translate_paddr;
    wire translate_fault;
    reg [CFG_PHYSICAL_ADDR_BITS-1:0] page_table_base;
    reg tlb_invalidate_all = 0;

    // NMC Command Ports
    reg [CFG_NUM_HBM_NODES-1:0] nmc_cmd_valid = 0;
    reg [3:0] nmc_cmd_opcode [CFG_NUM_HBM_NODES-1:0];
    reg [31:0] nmc_cmd_addr [CFG_NUM_HBM_NODES-1:0];
    reg [15:0] nmc_cmd_length [CFG_NUM_HBM_NODES-1:0];
    wire [CFG_NUM_HBM_NODES-1:0] nmc_cmd_ready;
    wire [CFG_NUM_HBM_NODES-1:0] nmc_result_valid;
    wire [255:0] nmc_result_data [CFG_NUM_HBM_NODES-1:0];
    wire [CFG_NUM_HBM_NODES-1:0] nmc_busy;

    // HCP Launch / Complete Ports
    wire hcp_launch_valid;
    wire [4:0] hcp_launch_task_id;
    wire [CFG_HCP_CMD_WIDTH-1:0] hcp_launch_cmd;
    reg hcp_launch_ack = 0;
    reg hcp_complete_valid = 0;
    reg [4:0] hcp_complete_task_id = 0;

    wire [CFG_NUM_HBM_NODES-1:0] hbm_phy_active;
    wire base_die_ready, hcp_busy, hcp_graph_done;
    wire [31:0] nmc_ops_completed;

    active_base_die #(
        .NUM_COMPUTE_DIES(CFG_CUBE_Z),
        .CORES_PER_DIE(CFG_CUBE_X * CFG_CUBE_Y),
        .TOTAL_CORES(CFG_NUM_CORES),
        .ADDR_WIDTH(CFG_DATA_MEM_ADDR_BITS),
        .DATA_WIDTH(CFG_DATA_MEM_DATA_BITS),
        .TSV_DATA_WIDTH(CFG_TSV_DATA_WIDTH),
        .NUM_HBM_NODES(CFG_NUM_HBM_NODES)
    ) dut_base_die (
        .clk(clk),
        .reset(reset),
        
        .tsv_rx_valid(tsv_rx_valid),
        .tsv_rx_data(tsv_rx_data),
        .tsv_tx_valid(tsv_tx_valid),
        .tsv_tx_data(tsv_tx_data),
        
        .host_cmd_valid(host_cmd_valid),
        .host_cmd_data(host_cmd_data),
        .host_cmd_ready(host_cmd_ready),

        .translate_valid(translate_valid),
        .translate_vaddr(translate_vaddr),
        .translate_asid(translate_asid),
        .translate_write(translate_write),
        .translate_ready(translate_ready),
        .translate_paddr(translate_paddr),
        .translate_fault(translate_fault),
        .page_table_base(page_table_base),
        .tlb_invalidate_all(tlb_invalidate_all),

        .nmc_cmd_valid(nmc_cmd_valid),
        .nmc_cmd_opcode(nmc_cmd_opcode),
        .nmc_cmd_addr(nmc_cmd_addr),
        .nmc_cmd_length(nmc_cmd_length),
        .nmc_cmd_ready(nmc_cmd_ready),
        .nmc_result_valid(nmc_result_valid),
        .nmc_result_data(nmc_result_data),
        .nmc_busy(nmc_busy),

        .nmc_mem_read_valid(nmc_mem_read_valid),
        .nmc_mem_read_addr(nmc_mem_read_addr),
        .nmc_mem_read_ready(nmc_mem_read_ready),
        .nmc_mem_read_data(nmc_mem_read_data),
        .nmc_mem_write_valid(nmc_mem_write_valid),
        .nmc_mem_write_addr(nmc_mem_write_addr),
        .nmc_mem_write_data(nmc_mem_write_data),
        .nmc_mem_write_ready(nmc_mem_write_ready),

        .hcp_launch_valid(hcp_launch_valid),
        .hcp_launch_task_id(hcp_launch_task_id),
        .hcp_launch_cmd(hcp_launch_cmd),
        .hcp_launch_ack(hcp_launch_ack),
        .hcp_complete_valid(hcp_complete_valid),
        .hcp_complete_task_id(hcp_complete_task_id),
        
        .hbm_phy_active(hbm_phy_active),
        .hbm_total_reads(),
        .hbm_total_writes(),
        
        .dram_req_valid(dram_req_valid),
        .dram_req_addr(dram_req_addr),
        .dram_req_wdata(dram_req_wdata),
        .dram_req_cmd(dram_req_cmd),
        .dram_req_ready(dram_req_ready),
        .dram_resp_valid(dram_resp_valid),
        .dram_resp_data(dram_resp_data),
        
        .base_die_ready(base_die_ready),
        .nmc_ops_completed(nmc_ops_completed),
        .hcp_busy(hcp_busy),
        .hcp_graph_done(hcp_graph_done)
    );

    // Testbench Helper Tasks
    task sys_mem_write_64(input [39:0] addr, input [63:0] data);
        reg [39:0] aligned_addr;
        reg [255:0] wdata;
        integer offset;
        begin
            aligned_addr = addr & ~40'h1f;
            offset = addr & 40'h1f;
            wdata = 256'd0;
            if (offset == 0)  wdata[63:0]    = data;
            if (offset == 8)  wdata[127:64]   = data;
            if (offset == 16) wdata[191:128]  = data;
            if (offset == 24) wdata[255:192]  = data;
            
            @(posedge clk);
            sys_wr_valid_tb = 1;
            sys_addr_tb = aligned_addr;
            sys_wdata_tb = wdata;
            @(posedge clk);
            sys_wr_valid_tb = 0;
            // Simple wait logic for DRAM write cycles
            #20;
        end
    endtask

    task hbm0_write_256(input [31:0] addr, input [255:0] data);
        begin
            @(posedge clk);
            hbm0_wr_valid_tb = 1;
            hbm0_addr_tb = addr;
            hbm0_wdata_tb = data;
            @(posedge clk);
            hbm0_wr_valid_tb = 0;
            #10;
        end
    endtask

    task hbm1_write_256(input [31:0] addr, input [255:0] data);
        begin
            @(posedge clk);
            hbm1_wr_valid_tb = 1;
            hbm1_addr_tb = addr;
            hbm1_wdata_tb = data;
            @(posedge clk);
            hbm1_wr_valid_tb = 0;
            #10;
        end
    endtask

    // Test Sequence
    initial begin
        $display("[TB_GRIDX_V2] GridX3 V2 Closed-Loop Testbench Started");
        
        reset = 1;
        host_cmd_valid = 0;
        host_cmd_data = 0;
        page_table_base = 40'h0000_10000;
        
        #100;
        reset = 0;
        
        // Wait for base die to be ready
        wait(base_die_ready);
        $display("[%0t] Base Die Ready.", $time);
        
        // TEST PHASE 1: MMU / TLB / DRAM Verification
        $display("\n[TEST] Phase 1: Setting up page tables in System DRAM...");
        
        // VPN parts for vaddr = 48'h0000_1234_5678:
        // VPN 0 = 0, VPN 1 = 0, VPN 2 = 145 (9'h091), VPN 3 = 325 (9'h145)
        // Level 0 table at 40'h10000
        // PTE at 40'h10000 + 0*8 = 40'h10000 points to next table at 40'h20000.
        // PPN = 40'h20, Valid=1, Perms=7 (RWX) -> PTE = 64'h0000_0002_000f
        sys_mem_write_64(40'h10000, 64'h0000_0002_000f);
        
        // Level 1 table at 40'h20000
        // PTE at 40'h20000 + 0*8 = 40'h20000 points to next table at 40'h30000.
        // PPN = 40'h30, Valid=1, Perms=7 -> PTE = 64'h0000_0003_000f
        sys_mem_write_64(40'h20000, 64'h0000_0003_000f);
        
        // Level 2 table at 40'h30000
        // PTE at 40'h30000 + 145*8 = 40'h30488 points to next table at 40'h40000.
        // PPN = 40'h40, Valid=1, Perms=7 -> PTE = 64'h0000_0004_000f
        sys_mem_write_64(40'h30488, 64'h0000_0004_000f);
        
        // Level 3 table at 40'h40000
        // PTE at 40'h40000 + 325*8 = 40'h40a28 points to physical page PPN = 40'h0000_9abcd.
        // PPN = 40'h9abcd, Valid=1, Perms=7 -> PTE = 64'h0000_9abc_d00f
        sys_mem_write_64(40'h40a28, 64'h0000_9abc_d00f);
        
        $display("[TEST] Page tables populated. Issuing virtual translation request...");
        
        @(posedge clk);
        translate_valid = 1;
        translate_vaddr = 48'h0000_1234_5678;
        translate_asid = 8'h01;
        translate_write = 0;
        
        @(posedge clk);
        translate_valid = 0;
        
        // Wait for translation completion
        wait(translate_ready);
        $display("[%0t] Translation Completed.", $time);
        $display("  Vaddr:  48'h0000_1234_5678");
        $display("  Paddr:  40'h%h (Expected: 40'h0000_9abc_d678)", translate_paddr);
        $display("  Fault:  %0b (Expected: 0)", translate_fault);
        
        if (translate_paddr == 40'h0000_9abc_d678 && !translate_fault) begin
            $display("✓ Phase 1 MMU Translation Walk PASSED.");
        end else begin
            $display("✗ Phase 1 MMU Translation Walk FAILED.");
            $finish;
        end
        
        // Run it again to check TLB Hit (should complete immediately)
        $display("\n[TEST] Issuing same virtual translation request to test TLB cache...");
        @(posedge clk);
        translate_valid = 1;
        @(posedge clk);
        translate_valid = 0;
        
        // Since it is cached in the TLB, it should complete in the next cycle
        @(posedge clk);
        if (translate_ready) begin
            $display("[%0t] TLB Translation completed in 1 cycle (Hit).", $time);
            $display("  Paddr:  40'h%h (Expected: 40'h0000_9abc_d678)", translate_paddr);
            $display("✓ Phase 1 TLB Hit test PASSED.");
        end else begin
            $display("✗ Phase 1 TLB Hit test FAILED (missed or took multiple cycles).");
            $finish;
        end
        
        // TEST PHASE 2: NMC Verification
        $display("\n[TEST] Phase 2: Populating HBM memory for NMC reduction...");
        // Initialize HBM stack 0 at address 32'h1000
        // We write 8 integers representing 1 to 8:
        // Word 0: integers 1 to 4 -> 32'h0000_0004, 32'h0000_0003, 32'h0000_0002, 32'h0000_0001
        // Word 1: integers 5 to 8 -> 32'h0000_0008, 32'h0000_0007, 32'h0000_0006, 32'h0000_0005
        hbm0_write_256(32'h1000, 256'h0000_0004_0000_0003_0000_0002_0000_0001);
        hbm0_write_256(32'h1020, 256'h0000_0008_0000_0007_0000_0006_0000_0005);
        
        $display("[TEST] Triggering NMC SUM reduction...");
        @(posedge clk);
        nmc_cmd_valid[0] = 1;
        nmc_cmd_opcode[0] = 4'd0; // OP_SUM
        nmc_cmd_addr[0] = 32'h1000;
        nmc_cmd_length[0] = 16'd2; // 2 256-bit words
        
        @(posedge clk);
        wait(nmc_cmd_ready[0] == 0);
        nmc_cmd_valid[0] = 0;
        
        // Wait for reduction result
        wait(nmc_result_valid[0]);
        $display("[%0t] NMC Reduction Complete.", $time);
        $display("  Result: 256'h%h", nmc_result_data[0]);
        
        // Word 0 + Word 1 = {12, 10, 8, 6} in 64-bit bounds or simple 256-bit addition
        // 256'h0000_0004_0000_0003_0000_0002_0000_0001 + 256'h0000_0008_0000_0007_0000_0006_0000_0005
        // 256'h0000_000c_0000_000a_0000_0008_0000_0006
        if (nmc_result_data[0] == 256'h0000_000c_0000_000a_0000_0008_0000_0006) begin
            $display("✓ Phase 2 NMC Reduction PASSED.");
        end else begin
            $display("✗ Phase 2 NMC Reduction FAILED.");
            $finish;
        end
        
        // TEST PHASE 3: HCP Dependency Graph Execution
        $display("\n[TEST] Phase 3: Launching HCP dependency graph execution...");
        
        // We will submit a dependency graph of 3 tasks:
        // Task 1 (ID=1): Init / Config. No dependencies.
        // Task 2 (ID=2): NMC Run. Depends on Task 1.
        // Task 3 (ID=3): MMU Walk. Depends on Task 2.
        
        // Task 1:
        wait(host_cmd_ready);
        host_cmd_valid = 1;
        // submit_task_id = 5'd1
        // submit_dep_count = 3'd0
        // submit_dep_ids = 20'd0
        // cmd = 128'h00000000_00000000_00000000_00000011 (Task type 1)
        host_cmd_data = 128'h00000000_00000000_00000000_00000011 | (3'd0 << 5) | (5'd1);
        @(posedge clk);
        host_cmd_valid = 0;
        $display("[HCP] Submitted Task 1 (ID=1, no deps)");
        
        // Task 2:
        #10;
        wait(host_cmd_ready);
        host_cmd_valid = 1;
        // submit_task_id = 5'd2
        // submit_dep_count = 3'd1
        // submit_dep_ids = task 1 (5'd1) -> placed at bits [12:8] of host_cmd_data
        // cmd = 128'h00000000_00000000_00000000_00000022
        host_cmd_data = 128'h00000000_00000000_00000000_00000022 | (20'd1 << 8) | (3'd1 << 5) | (5'd2);
        @(posedge clk);
        host_cmd_valid = 0;
        $display("[HCP] Submitted Task 2 (ID=2, depends on Task 1)");
        
        // Task 3:
        #10;
        wait(host_cmd_ready);
        host_cmd_valid = 1;
        // submit_task_id = 5'd3
        // submit_dep_count = 3'd1
        // submit_dep_ids = task 2 (5'd2) -> placed at bits [12:8] of host_cmd_data
        // cmd = 128'h00000000_00000000_00000000_00000033
        host_cmd_data = 128'h00000000_00000000_00000000_00000033 | (20'd2 << 8) | (3'd1 << 5) | (5'd3);
        @(posedge clk);
        host_cmd_valid = 0;
        $display("[HCP] Submitted Task 3 (ID=3, depends on Task 2)");
        
        // Wait for HCP to execute Task 1 (since it has no dependencies)
        wait(hcp_launch_valid && hcp_launch_task_id == 5'd1);
        $display("[%0t] HCP Launched Task 1 (ID=1). Acknowledging and completing...", $time);
        @(posedge clk);
        hcp_launch_ack = 1;
        @(posedge clk);
        hcp_launch_ack = 0;
        
        // Simulate some execution delay, then complete Task 1
        #100;
        @(posedge clk);
        hcp_complete_valid = 1;
        hcp_complete_task_id = 5'd1;
        @(posedge clk);
        hcp_complete_valid = 0;
        $display("[%0t] Task 1 Completed.", $time);
        
        // Now, HCP should automatically launch Task 2 because its dependency (Task 1) is resolved
        wait(hcp_launch_valid && hcp_launch_task_id == 5'd2);
        $display("[%0t] HCP Launched Task 2 (ID=2). Acknowledging and completing NMC...", $time);
        @(posedge clk);
        hcp_launch_ack = 1;
        @(posedge clk);
        hcp_launch_ack = 0;
        
        // Run NMC reduction in loop as Task 2 workload
        #100;
        @(posedge clk);
        hcp_complete_valid = 1;
        hcp_complete_task_id = 5'd2;
        @(posedge clk);
        hcp_complete_valid = 0;
        $display("[%0t] Task 2 Completed.", $time);
        
        // Now, HCP should automatically launch Task 3
        wait(hcp_launch_valid && hcp_launch_task_id == 5'd3);
        $display("[%0t] HCP Launched Task 3 (ID=3). Acknowledging and completing MMU walk...", $time);
        @(posedge clk);
        hcp_launch_ack = 1;
        @(posedge clk);
        hcp_launch_ack = 0;
        
        #100;
        @(posedge clk);
        hcp_complete_valid = 1;
        hcp_complete_task_id = 5'd3;
        @(posedge clk);
        hcp_complete_valid = 0;
        $display("[%0t] Task 3 Completed.", $time);
        
        // Wait for graph completion
        wait(hcp_graph_done);
        $display("[%0t] HCP Task Graph Finished successfully.", $time);
        $display("✓ Phase 3 HCP Task Graph PASSED.");
        
        $display("[TB_GRIDX_V2] RESULT: ALL TESTS PASSED SUCCESSFULLY!");
        #100;
        $finish;
    end

    // Watchdog timer to prevent infinite hangs
    initial begin
        #50000;
        $display("[WATCHDOG] Simulation timeout reached.");
        $finish;
    end

endmodule
