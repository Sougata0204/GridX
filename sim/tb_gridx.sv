`timescale 1ns/1ns

module tb_gridx;
    parameter DATA_MEM_ADDR_BITS = 22;
    parameter DATA_MEM_DATA_BITS = 8;
    parameter DATA_MEM_NUM_CHANNELS = 64;
    parameter PROGRAM_MEM_ADDR_BITS = 12;
    parameter PROGRAM_MEM_DATA_BITS = 16;
    parameter PROGRAM_MEM_NUM_CHANNELS = 16;
    parameter NUM_CORES = 1;
    parameter THREADS_PER_BLOCK = 64;
    parameter WARPS_PER_CORE = 4;
    parameter THREAD_COUNT = 64;
    parameter MAX_SIM_CYCLES = 5000;
    parameter MIN_CYCLES = 100;

    reg clk;
    reg reset;
    reg start;
    wire done;
    reg device_control_write_enable;
    reg [15:0] device_control_data;
    wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_valid;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address [0:PROGRAM_MEM_NUM_CHANNELS-1];
    reg [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_ready;
    reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data [0:PROGRAM_MEM_NUM_CHANNELS-1];
    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [0:DATA_MEM_NUM_CHANNELS-1];
    reg [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_ready;
    reg [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [0:DATA_MEM_NUM_CHANNELS-1];
    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [0:DATA_MEM_NUM_CHANNELS-1];
    wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [0:DATA_MEM_NUM_CHANNELS-1];
    reg [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_ready;

    reg [PROGRAM_MEM_DATA_BITS-1:0] program_memory [0:255];
    reg [DATA_MEM_DATA_BITS-1:0] data_memory [0:65535];

    gpu #(
        .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
        .DATA_MEM_NUM_CHANNELS(DATA_MEM_NUM_CHANNELS),
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .PROGRAM_MEM_NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS),
        .NUM_CORES(NUM_CORES),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .WARPS_PER_CORE(WARPS_PER_CORE),
        .CUBE_X(1),
        .CUBE_Y(1),
        .CUBE_Z(1),
        .MESH_X(1),
        .MESH_Y(1)
    ) dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .done(done),
        .device_control_write_enable(device_control_write_enable),
        .device_control_data(device_control_data),
        .program_mem_read_valid(program_mem_read_valid),
        .program_mem_read_address(program_mem_read_address),
        .program_mem_read_ready(program_mem_read_ready),
        .program_mem_read_data(program_mem_read_data),
        .data_mem_read_valid(data_mem_read_valid),
        .data_mem_read_address(data_mem_read_address),
        .data_mem_read_ready(data_mem_read_ready),
        .data_mem_read_data(data_mem_read_data),
        .data_mem_write_valid(data_mem_write_valid),
        .data_mem_write_address(data_mem_write_address),
        .data_mem_write_data(data_mem_write_data),
        .data_mem_write_ready(data_mem_write_ready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer cycle_count;
    integer done_cycle;
    reg done_seen;
    integer ch;

    initial begin
        program_memory[0] = 16'h0000;
        program_memory[1] = 16'h0000;
        program_memory[2] = 16'h0000;
        program_memory[3] = 16'h0000;
        program_memory[4] = 16'h0000;
        program_memory[5] = 16'hF000;
    end

    always @(posedge clk) begin
        program_mem_read_ready = 0;
        for (ch = 0; ch < PROGRAM_MEM_NUM_CHANNELS; ch = ch + 1) begin
            if (program_mem_read_valid[ch]) begin
                program_mem_read_data[ch] = program_memory[program_mem_read_address[ch][7:0]];
                program_mem_read_ready[ch] = 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        data_mem_read_ready = 0;
        data_mem_write_ready = 0;
        for (ch = 0; ch < DATA_MEM_NUM_CHANNELS; ch = ch + 1) begin
            if (data_mem_read_valid[ch]) begin
                data_mem_read_data[ch] = data_memory[data_mem_read_address[ch][15:0]];
                data_mem_read_ready[ch] = 1'b1;
            end
            if (data_mem_write_valid[ch]) begin
                data_memory[data_mem_write_address[ch][15:0]] = data_mem_write_data[ch];
                data_mem_write_ready[ch] = 1'b1;
            end
        end
    end

    initial begin
        $dumpfile("wave/tb_gridx.vcd");
        $dumpvars(0, tb_gridx);
        $display("================================================================");
        $display(" GridX EXECUTION SANITY TESTBENCH (iverilog)");
        $display("================================================================");
        $display("  Thread Count:  %0d", THREAD_COUNT);
        $display("  Max Cycles:    %0d", MAX_SIM_CYCLES);

        cycle_count = 0;
        done_cycle = -1;
        done_seen = 0;
        reset = 1;
        start = 0;
        device_control_write_enable = 0;
        device_control_data = 0;

        repeat(10) @(posedge clk);
        cycle_count = 10;
        reset = 0;
        $display("[INFO] Reset released at cycle %0d", cycle_count);

        @(posedge clk);
        cycle_count = cycle_count + 1;
        device_control_write_enable = 1;
        device_control_data = THREAD_COUNT;
        @(posedge clk);
        cycle_count = cycle_count + 1;
        device_control_write_enable = 0;
        $display("[INFO] DCR configured at cycle %0d", cycle_count);

        @(posedge clk);
        cycle_count = cycle_count + 1;
        start = 1;
        @(posedge clk);
        cycle_count = cycle_count + 1;
        $display("[INFO] Kernel start at cycle %0d", cycle_count);

        while (cycle_count < MAX_SIM_CYCLES) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            if (done && !done_seen) begin
                done_seen = 1;
                done_cycle = cycle_count;
                $display("[INFO] done asserted at cycle %0d", done_cycle);
            end
            if (done && done_seen && (cycle_count - done_cycle >= MIN_CYCLES)) begin
                $display("[INFO] Kernel completed after %0d additional cycles", cycle_count - done_cycle);
            end
            if (cycle_count % 5000 == 0) begin
                $display("[HEARTBEAT] Cycle %0d - done=%b", cycle_count, done);
            end
        end

        $display("");
        $display("================================================================");
        $display("                   EXECUTION RESULTS");
        $display("================================================================");
        $display("  Total cycles:  %0d", cycle_count);
        $display("  Done seen:     %s", done_seen ? "YES" : "NO");
        $display("  Done cycle:    %0d", done_cycle);

        if (done_seen && (done_cycle > 10) && (cycle_count > 0)) begin
            $display("  [PASS] Execution Sanity Test PASSED");
        end else begin
            $display("  [FAIL] Execution Sanity Test FAILED");
            if (!done_seen) $display("    - Done never asserted (timeout)");
            if (done_cycle <= 10) $display("    - Done during/after reset");
        end
        $display("================================================================");
        $finish;
    end
endmodule
