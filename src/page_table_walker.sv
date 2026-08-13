// Hardware Page Table Walker
// FSM that walks 4-level page tables to resolve virtual-to-physical address translation on TLB misses.

`default_nettype none
`timescale 1ns/1ns

module pageTableWalker #(
    parameter VIRTUAL_ADDR_BITS = 48,
    parameter PHYSICAL_ADDR_BITS = 40,
    parameter PAGE_OFFSET_BITS = 12,
    parameter PAGE_TABLE_LEVELS = 4,
    parameter DATA_WIDTH = 64
) (
    input  wire clk,
    input  wire reset,
    
    // Walk Request
    input  wire walkRequestValid,
    input  wire [VIRTUAL_ADDR_BITS-1:0] walkVaddr,
    input  wire [7:0] walkAsid,
    
    // Walk Result
    output reg  walkDone,
    output reg  walkFault,
    output reg  [PHYSICAL_ADDR_BITS-1:0] walkPaddr,
    output reg  [2:0] walkPermissions,
    
    // Memory Interface
    output reg  memReadValid,
    output reg  [PHYSICAL_ADDR_BITS-1:0] memReadAddr,
    input  wire memReadReady,
    input  wire [DATA_WIDTH-1:0] memReadData,
    
    // System Config
    input  wire [PHYSICAL_ADDR_BITS-1:0] pageTableBaseAddr,
    
    output reg  busy
);

    typedef enum logic [2:0] {
        IDLE,
        reqMem,
        WAIT_MEM,
        EVAL_PTE,
        DONE_OK,
        DONE_FAULT
    } stateE;
    
    stateE state;
    
    reg [2:0] currentLevel;
    reg [PHYSICAL_ADDR_BITS-1:0] currentBase;
    reg [VIRTUAL_ADDR_BITS-1:0] vaddrLatched;
    
    // The virtual address is split into 9-bit chunks for 4 levels (48-12 = 36 bits).
    // Assuming level 0 is top (L4), level 3 is leaf (L1)
    wire [8:0] vpnParts [0:3];
    assign vpnParts[0] = vaddrLatched[47:39];
    assign vpnParts[1] = vaddrLatched[38:30];
    assign vpnParts[2] = vaddrLatched[29:21];
    assign vpnParts[3] = vaddrLatched[20:12];

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            walkDone <= 0;
            walkFault <= 0;
            walkPaddr <= 0;
            walkPermissions <= 0;
            memReadValid <= 0;
            memReadAddr <= 0;
            busy <= 0;
        end else begin
            walkDone <= 0;
            walkFault <= 0;
            
            case (state)
                IDLE: begin
                    if (walkRequestValid) begin
                        busy <= 1;
                        vaddrLatched <= walkVaddr;
                        currentLevel <= 0;
                        currentBase <= pageTableBaseAddr;
                        state <= reqMem;
                    end else begin
                        busy <= 0;
                    end
                end
                
                reqMem: begin
                    memReadValid <= 1;
                    // Address = Base + VPN_part * 8
                    memReadAddr <= currentBase + {28'd0, vpnParts[currentLevel], 3'b000};
                    state <= WAIT_MEM;
                end
                
                WAIT_MEM: begin
                    if (memReadReady) begin
                        memReadValid <= 0;
                        state <= EVAL_PTE;
                    end
                end
                
                EVAL_PTE: begin
                    // Simple PTE format:
                    // [0] Valid bit
                    // [3:1] Permissions (RWX)
                    // [39:12] PPN
                    if (!memReadData[0]) begin
                        state <= DONE_FAULT;
                    end else begin
                        if (currentLevel == (PAGE_TABLE_LEVELS - 1)) begin
                            // Leaf level
                            walkPaddr <= {memReadData[39:12], 12'd0}; // PPN aligned
                            walkPermissions <= memReadData[3:1];
                            state <= DONE_OK;
                        end else begin
                            // Next level
                            currentBase <= {memReadData[39:12], 12'd0};
                            currentLevel <= currentLevel + 1;
                            state <= reqMem;
                        end
                    end
                end
                
                DONE_OK: begin
                    walkDone <= 1;
                    walkFault <= 0;
                    busy <= 0;
                    state <= IDLE;
                end
                
                DONE_FAULT: begin
                    walkDone <= 1;
                    walkFault <= 1;
                    busy <= 0;
                    state <= IDLE;
                end
                
            endcase
        end
        
        // Debug prints (simulation only)
        // synthesis translateOff
        if (!reset) begin
            if (walkRequestValid)
                $display("[%0t] [PTW] walkRequestValid=1, vaddr=%h, level=%0d, base=%h", $time, walkVaddr, currentLevel, pageTableBaseAddr);
            if (state != IDLE)
                $display("[%0t] [PTW] state=%s, level=%0d, memRdVal=%0b, memRdAddr=%h, memRdReady=%0b, data=%h", 
                         $time, state.name(), currentLevel, memReadValid, memReadAddr, memReadReady, memReadData);
        end
        // synthesis translateOn
    end

endmodule
