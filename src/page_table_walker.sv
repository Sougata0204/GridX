// Hardware Page Table Walker
// FSM that walks 4-level page tables to resolve virtual-to-physical address translation on TLB misses.

`default_nettype none
`timescale 1ns/1ns

module page_table_walker #(
    parameter VIRTUAL_ADDR_BITS = 48,
    parameter PHYSICAL_ADDR_BITS = 40,
    parameter PAGE_OFFSET_BITS = 12,
    parameter PAGE_TABLE_LEVELS = 4,
    parameter DATA_WIDTH = 64
) (
    input  wire clk,
    input  wire reset,
    
    // Walk Request
    input  wire walk_request_valid,
    input  wire [VIRTUAL_ADDR_BITS-1:0] walk_vaddr,
    input  wire [7:0] walk_asid,
    
    // Walk Result
    output reg  walk_done,
    output reg  walk_fault,
    output reg  [PHYSICAL_ADDR_BITS-1:0] walk_paddr,
    output reg  [2:0] walk_permissions,
    
    // Memory Interface
    output reg  mem_read_valid,
    output reg  [PHYSICAL_ADDR_BITS-1:0] mem_read_addr,
    input  wire mem_read_ready,
    input  wire [DATA_WIDTH-1:0] mem_read_data,
    
    // System Config
    input  wire [PHYSICAL_ADDR_BITS-1:0] page_table_base_addr,
    
    output reg  busy
);

    typedef enum logic [2:0] {
        IDLE,
        REQ_MEM,
        WAIT_MEM,
        EVAL_PTE,
        DONE_OK,
        DONE_FAULT
    } state_e;
    
    state_e state;
    
    reg [2:0] current_level;
    reg [PHYSICAL_ADDR_BITS-1:0] current_base;
    reg [VIRTUAL_ADDR_BITS-1:0] vaddr_latched;
    
    // The virtual address is split into 9-bit chunks for 4 levels (48-12 = 36 bits).
    // Assuming level 0 is top (L4), level 3 is leaf (L1)
    wire [8:0] vpn_parts [0:3];
    assign vpn_parts[0] = vaddr_latched[47:39];
    assign vpn_parts[1] = vaddr_latched[38:30];
    assign vpn_parts[2] = vaddr_latched[29:21];
    assign vpn_parts[3] = vaddr_latched[20:12];

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            walk_done <= 0;
            walk_fault <= 0;
            walk_paddr <= 0;
            walk_permissions <= 0;
            mem_read_valid <= 0;
            mem_read_addr <= 0;
            busy <= 0;
        end else begin
            walk_done <= 0;
            walk_fault <= 0;
            
            case (state)
                IDLE: begin
                    if (walk_request_valid) begin
                        busy <= 1;
                        vaddr_latched <= walk_vaddr;
                        current_level <= 0;
                        current_base <= page_table_base_addr;
                        state <= REQ_MEM;
                    end else begin
                        busy <= 0;
                    end
                end
                
                REQ_MEM: begin
                    mem_read_valid <= 1;
                    // Address = Base + VPN_part * 8
                    mem_read_addr <= current_base + {28'd0, vpn_parts[current_level], 3'b000};
                    state <= WAIT_MEM;
                end
                
                WAIT_MEM: begin
                    if (mem_read_ready) begin
                        mem_read_valid <= 0;
                        state <= EVAL_PTE;
                    end
                end
                
                EVAL_PTE: begin
                    // Simple PTE format:
                    // [0] Valid bit
                    // [3:1] Permissions (RWX)
                    // [39:12] PPN
                    if (!mem_read_data[0]) begin
                        state <= DONE_FAULT;
                    end else begin
                        if (current_level == (PAGE_TABLE_LEVELS - 1)) begin
                            // Leaf level
                            walk_paddr <= {mem_read_data[39:12], 12'd0}; // PPN aligned
                            walk_permissions <= mem_read_data[3:1];
                            state <= DONE_OK;
                        end else begin
                            // Next level
                            current_base <= {mem_read_data[39:12], 12'd0};
                            current_level <= current_level + 1;
                            state <= REQ_MEM;
                        end
                    end
                end
                
                DONE_OK: begin
                    walk_done <= 1;
                    walk_fault <= 0;
                    busy <= 0;
                    state <= IDLE;
                end
                
                DONE_FAULT: begin
                    walk_done <= 1;
                    walk_fault <= 1;
                    busy <= 0;
                    state <= IDLE;
                end
                
            endcase
        end
        
        // Debug prints (simulation only)
        // synthesis translate_off
        if (!reset) begin
            if (walk_request_valid)
                $display("[%0t] [PTW] walk_request_valid=1, vaddr=%h, level=%0d, base=%h", $time, walk_vaddr, current_level, page_table_base_addr);
            if (state != IDLE)
                $display("[%0t] [PTW] state=%s, level=%0d, mem_rd_val=%0b, mem_rd_addr=%h, mem_rd_ready=%0b, data=%h", 
                         $time, state.name(), current_level, mem_read_valid, mem_read_addr, mem_read_ready, mem_read_data);
        end
        // synthesis translate_on
    end

endmodule
