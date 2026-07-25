
`default_nettype none
`timescale 1ns/1ns

module dram_ctrl #(
    parameter ADDR_WIDTH = 40,
    parameter DATA_WIDTH = 256,
    parameter BURST_LENGTH = 8,
    parameter NUM_RANKS = 2
) (
    input  wire clk,
    input  wire reset,
    
    // Core Interface
    input  wire req_valid,
    input  wire [ADDR_WIDTH-1:0] req_addr,
    input  wire [DATA_WIDTH-1:0] req_wdata,
    input  wire req_write,
    output reg  req_ready,
    
    output reg  resp_valid,
    output reg  [DATA_WIDTH-1:0] resp_data,
    output reg  [ADDR_WIDTH-1:0] resp_addr,
    
    // PHY Interface
    output reg  phy_cmd_valid,
    output reg  [2:0] phy_cmd, // 0: ACT, 1: PRE, 2: RD, 3: WR
    output reg  [ADDR_WIDTH-1:0] phy_addr,
    output reg  [DATA_WIDTH-1:0] phy_wdata,
    input  wire [DATA_WIDTH-1:0] phy_rdata,
    input  wire phy_rdata_valid,
    
    output reg  busy,
    output reg  [31:0] total_reads,
    output reg  [31:0] total_writes,
    output reg  [31:0] row_hits,
    output reg  [31:0] row_misses
);

    localparam CMD_ACT = 3'd0;
    localparam CMD_PRE = 3'd1;
    localparam CMD_RD  = 3'd2;
    localparam CMD_WR  = 3'd3;
    
    // Simplified Memory Organization
    // Assume Row is bits [39:16], Bank is bits [15:13], Col is bits [12:5], Byte is [4:0]
    
    // Open Row Table
    reg valid_row [7:0];
    reg [23:0] open_row [7:0]; // 8 banks
    
    typedef enum logic [2:0] {
        IDLE,
        PRECHARGE,
        ACTIVATE,
        ACCESS,
        WAIT_PHY
    } state_e;
    
    state_e state;
    
    reg [ADDR_WIDTH-1:0] latched_addr;
    reg [DATA_WIDTH-1:0] latched_wdata;
    reg latched_write;
    
    wire [2:0] cur_bank = latched_addr[15:13];
    wire [23:0] cur_row = latched_addr[39:16];
    
    wire row_hit = valid_row[cur_bank] && (open_row[cur_bank] == cur_row);
    
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            req_ready <= 1;
            resp_valid <= 0;
            phy_cmd_valid <= 0;
            busy <= 0;
            
            for (i = 0; i < 8; i = i + 1) begin
                valid_row[i] <= 0;
            end
            
            total_reads <= 0;
            total_writes <= 0;
            row_hits <= 0;
            row_misses <= 0;
        end else begin
            resp_valid <= 0;
            phy_cmd_valid <= 0;
            
            // Forward PHY read data
            if (phy_rdata_valid) begin
                resp_valid <= 1;
                resp_data <= phy_rdata;
                resp_addr <= latched_addr;
            end
            
            case (state)
                IDLE: begin
                    if (req_valid) begin
                        latched_addr <= req_addr;
                        latched_wdata <= req_wdata;
                        latched_write <= req_write;
                        req_ready <= 0;
                        busy <= 1;
                        
                        // Check open page table
                        if (valid_row[req_addr[15:13]] && open_row[req_addr[15:13]] == req_addr[39:16]) begin
                            // Row hit
                            state <= ACCESS;
                            row_hits <= row_hits + 1;
                        end else if (valid_row[req_addr[15:13]]) begin
                            // Row miss, page open -> Precharge needed
                            state <= PRECHARGE;
                            row_misses <= row_misses + 1;
                        end else begin
                            // Row miss, page closed -> Activate needed
                            state <= ACTIVATE;
                            row_misses <= row_misses + 1;
                        end
                    end else begin
                        busy <= 0;
                        req_ready <= 1;
                    end
                end
                
                PRECHARGE: begin
                    phy_cmd_valid <= 1;
                    phy_cmd <= CMD_PRE;
                    phy_addr <= latched_addr; // Bank is in the address
                    valid_row[cur_bank] <= 0;
                    state <= ACTIVATE;
                end
                
                ACTIVATE: begin
                    phy_cmd_valid <= 1;
                    phy_cmd <= CMD_ACT;
                    phy_addr <= latched_addr;
                    valid_row[cur_bank] <= 1;
                    open_row[cur_bank] <= cur_row;
                    state <= ACCESS;
                end
                
                ACCESS: begin
                    phy_cmd_valid <= 1;
                    phy_cmd <= latched_write ? CMD_WR : CMD_RD;
                    phy_addr <= latched_addr;
                    phy_wdata <= latched_wdata;
                    
                    if (latched_write) begin
                        total_writes <= total_writes + 1;
                        // For writes, we can ACK immediately after sending to PHY
                        resp_valid <= 1;
                        resp_addr <= latched_addr;
                        state <= IDLE;
                        req_ready <= 1;
                    end else begin
                        total_reads <= total_reads + 1;
                        state <= WAIT_PHY;
                    end
                end
                
                WAIT_PHY: begin
                    if (phy_rdata_valid) begin // Assuming PHY asserts this for 1 cycle when data returns
                        state <= IDLE;
                        req_ready <= 1;
                    end
                end
                
            endcase
        end
        
        // Debug prints (simulation only)
        // synthesis translate_off
        if (!reset) begin
            if (req_valid)
                $display("[%0t] [DRAM] req_valid=1, addr=%h, write=%b, ready=%0b", $time, req_addr, req_write, req_ready);
            if (state != IDLE)
                $display("[%0t] [DRAM] state=%s, bank=%0d, row=%h", $time, state.name(), cur_bank, cur_row);
        end
        // synthesis translate_on
    end

endmodule
