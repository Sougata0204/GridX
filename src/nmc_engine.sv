
`default_nettype none
`timescale 1ns/1ns

module nmc_engine #(
    parameter DATA_WIDTH = 256,
    parameter REDUCTION_WIDTH = 32,
    parameter QUEUE_DEPTH = 8,
    parameter NUM_ALUS = 4
) (
    input  wire clk,
    input  wire reset,
    
    // Command Interface
    input  wire cmd_valid,
    input  wire [3:0] cmd_opcode,
    input  wire [31:0] cmd_addr,
    input  wire [15:0] cmd_length,
    output reg  cmd_ready,
    
    // Result Interface
    output reg  result_valid,
    output reg  [DATA_WIDTH-1:0] result_data,
    
    // Memory Interface
    output reg  mem_read_valid,
    output reg  [31:0] mem_read_addr,
    input  wire mem_read_ready,
    input  wire [DATA_WIDTH-1:0] mem_read_data,
    
    output reg  mem_write_valid,
    output reg  [31:0] mem_write_addr,
    output reg  [DATA_WIDTH-1:0] mem_write_data,
    input  wire mem_write_ready,
    
    output reg  busy,
    output reg  [31:0] perf_ops_completed
);

    localparam OP_SUM  = 4'd0;
    localparam OP_MAX  = 4'd1;
    localparam OP_MIN  = 4'd2;
    localparam OP_ABS  = 4'd3;
    localparam OP_RELU = 4'd4;
    
    typedef enum logic [2:0] {
        IDLE,
        READ_MEM,
        PROCESS,
        WRITE_MEM,
        DONE
    } state_e;
    
    state_e state;
    
    reg [3:0] cur_opcode;
    reg [31:0] cur_addr;
    reg [15:0] cur_length;
    reg [15:0] elements_processed;
    
    reg [DATA_WIDTH-1:0] acc_data;
    
    integer i;
    
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            cmd_ready <= 1;
            result_valid <= 0;
            mem_read_valid <= 0;
            mem_write_valid <= 0;
            busy <= 0;
            perf_ops_completed <= 0;
        end else begin
            result_valid <= 0;
            
            case (state)
                IDLE: begin
                    if (cmd_valid) begin
                        cur_opcode <= cmd_opcode;
                        cur_addr <= cmd_addr;
                        cur_length <= cmd_length;
                        elements_processed <= 0;
                        cmd_ready <= 0;
                        busy <= 1;
                        if (cmd_opcode == OP_MAX) acc_data <= {DATA_WIDTH{1'b0}}; // Should be min val
                        else if (cmd_opcode == OP_MIN) acc_data <= {DATA_WIDTH{1'b1}}; // Should be max val
                        else acc_data <= 0;
                        
                        state <= READ_MEM;
                    end else begin
                        cmd_ready <= 1;
                        busy <= 0;
                    end
                end
                
                READ_MEM: begin
                    if (elements_processed < cur_length) begin
                        mem_read_valid <= 1;
                        mem_read_addr <= cur_addr + (elements_processed * (DATA_WIDTH/8));
                        if (mem_read_ready && mem_read_valid) begin
                            mem_read_valid <= 0;
                            state <= PROCESS;
                        end
                    end else begin
                        state <= DONE;
                    end
                end
                
                PROCESS: begin
                    // Simple ALU (in reality, NUM_ALUS parallel paths)
                    // For now, doing a simple wide operation for demo
                    case (cur_opcode)
                        OP_SUM:  acc_data <= acc_data + mem_read_data;
                        OP_MAX:  acc_data <= (mem_read_data > acc_data) ? mem_read_data : acc_data;
                        OP_MIN:  acc_data <= (mem_read_data < acc_data) ? mem_read_data : acc_data;
                        OP_ABS: begin
                            for (i = 0; i < DATA_WIDTH/32; i = i + 1) begin
                                if (mem_read_data[i*32 + 31]) begin
                                    acc_data[i*32 +: 32] <= -mem_read_data[i*32 +: 32];
                                end else begin
                                    acc_data[i*32 +: 32] <= mem_read_data[i*32 +: 32];
                                end
                            end
                        end
                        OP_RELU: begin
                            for (i = 0; i < DATA_WIDTH/32; i = i + 1) begin
                                if (mem_read_data[i*32 + 31]) begin
                                    acc_data[i*32 +: 32] <= 32'd0;
                                end else begin
                                    acc_data[i*32 +: 32] <= mem_read_data[i*32 +: 32];
                                end
                            end
                        end
                        default: acc_data <= mem_read_data;
                    endcase
                    
                    elements_processed <= elements_processed + 1;
                    
                    // If element-wise, write back immediately
                    if (cur_opcode == OP_ABS || cur_opcode == OP_RELU) begin
                        state <= WRITE_MEM;
                    end else begin
                        state <= READ_MEM;
                    end
                end
                
                WRITE_MEM: begin
                    mem_write_valid <= 1;
                    mem_write_addr <= cur_addr + ((elements_processed - 1) * (DATA_WIDTH/8));
                    mem_write_data <= acc_data;
                    if (mem_write_ready && mem_write_valid) begin
                        mem_write_valid <= 0;
                        state <= READ_MEM;
                    end
                end
                
                DONE: begin
                    result_valid <= 1;
                    result_data <= acc_data;
                    perf_ops_completed <= perf_ops_completed + 1;
                    cmd_ready <= 1;
                    busy <= 0;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
