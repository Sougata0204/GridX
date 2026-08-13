// Memory Management Unit
// Integrates TLB and Page Table Walker for virtual memory translation and page fault detection.

`default_nettype none
`timescale 1ns/1ns

module mmu #(
    parameter VIRTUAL_ADDR_BITS = 48,
    parameter PHYSICAL_ADDR_BITS = 40,
    parameter PAGE_OFFSET_BITS = 12,
    parameter TLB_ENTRIES = 64,
    parameter ASID_BITS = 8
) (
    input  wire clk,
    input  wire reset,
    
    // Core Interface
    input  wire translateValid,
    input  wire [VIRTUAL_ADDR_BITS-1:0] translateVaddr,
    input  wire [ASID_BITS-1:0] translateAsid,
    input  wire translateWrite,
    output reg  translateReady,
    output reg  [PHYSICAL_ADDR_BITS-1:0] translatePaddr,
    output reg  translateFault,
    
    // Memory Interface (for Page Table Walker)
    output wire ptwMemReadValid,
    output wire [PHYSICAL_ADDR_BITS-1:0] ptwMemReadAddr,
    input  wire ptwMemReadReady,
    input  wire [63:0] ptwMemReadData,
    
    // System Config
    input  wire [PHYSICAL_ADDR_BITS-1:0] pageTableBase,
    input  wire tlbInvalidateAll,
    
    // Performance
    output reg  [31:0] perfTlbHits,
    output reg  [31:0] perfTlbMisses,
    output reg  [31:0] perfPageFaults
);

    // TLB Signals
    wire tlbLookupHit;
    wire [PHYSICAL_ADDR_BITS-1:0] tlbLookupPaddr;
    wire [2:0] tlbLookupPermissions;
    reg tlbLookupValid;
    
    reg tlbWriteValid;
    reg [VIRTUAL_ADDR_BITS-1:0] tlbWriteVaddr;
    reg [PHYSICAL_ADDR_BITS-1:0] tlbWritePaddr;
    reg [ASID_BITS-1:0] tlbWriteAsid;
    reg [2:0] tlbWritePermissions;
    
    tlb #(
        .NUM_ENTRIES(TLB_ENTRIES),
        .VIRTUAL_ADDR_BITS(VIRTUAL_ADDR_BITS),
        .PHYSICAL_ADDR_BITS(PHYSICAL_ADDR_BITS),
        .PAGE_OFFSET_BITS(PAGE_OFFSET_BITS),
        .ASID_BITS(ASID_BITS)
    ) uTlb (
        .clk(clk),
        .reset(reset),
        .lookupValid(tlbLookupValid),
        .lookupVaddr(translateVaddr),
        .lookupAsid(translateAsid),
        .lookupHit(tlbLookupHit),
        .lookupPaddr(tlbLookupPaddr),
        .lookupPermissions(tlbLookupPermissions),
        .writeValid(tlbWriteValid),
        .writeVaddr(tlbWriteVaddr),
        .writePaddr(tlbWritePaddr),
        .writeAsid(tlbWriteAsid),
        .writePermissions(tlbWritePermissions),
        .invalidateAll(tlbInvalidateAll),
        .invalidateAsidValid(1'b0),
        .invalidateAsid(8'd0),
        .perfHits(),     // Managed internally
        .perfMisses()
    );

    // Page Table Walker Signals
    reg ptwRequestValid;
    wire ptwDone;
    wire ptwFault;
    wire [PHYSICAL_ADDR_BITS-1:0] ptwPaddr;
    wire [2:0] ptwPermissions;
    wire ptwBusy;

    pageTableWalker #(
        .VIRTUAL_ADDR_BITS(VIRTUAL_ADDR_BITS),
        .PHYSICAL_ADDR_BITS(PHYSICAL_ADDR_BITS),
        .PAGE_OFFSET_BITS(PAGE_OFFSET_BITS),
        .PAGE_TABLE_LEVELS(4),
        .DATA_WIDTH(64)
    ) uPtw (
        .clk(clk),
        .reset(reset),
        .walkRequestValid(ptwRequestValid),
        .walkVaddr(translateVaddr),
        .walkAsid(translateAsid),
        .walkDone(ptwDone),
        .walkFault(ptwFault),
        .walkPaddr(ptwPaddr),
        .walkPermissions(ptwPermissions),
        .memReadValid(ptwMemReadValid),
        .memReadAddr(ptwMemReadAddr),
        .memReadReady(ptwMemReadReady),
        .memReadData(ptwMemReadData),
        .pageTableBaseAddr(pageTableBase),
        .busy(ptwBusy)
    );

    typedef enum logic [1:0] {
        IDLE,
        TLB_LOOKUP,
        PTW_WAIT
    } stateE;
    
    stateE state;
    
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            translateReady <= 0;
            translatePaddr <= 0;
            translateFault <= 0;
            tlbLookupValid <= 0;
            tlbWriteValid <= 0;
            ptwRequestValid <= 0;
            perfTlbHits <= 0;
            perfTlbMisses <= 0;
            perfPageFaults <= 0;
        end else begin
            translateReady <= 0;
            translateFault <= 0;
            tlbLookupValid <= 0;
            tlbWriteValid <= 0;
            ptwRequestValid <= 0;
            
            case (state)
                IDLE: begin
                    if (translateValid) begin
                        tlbLookupValid <= 1;
                        state <= TLB_LOOKUP;
                    end
                end
                
                TLB_LOOKUP: begin
                    // TLB takes 1 cycle
                    if (tlbLookupHit) begin
                        // Check permissions
                        if (translateWrite && !tlbLookupPermissions[1]) begin // [1] is write permission
                            translateFault <= 1;
                            translateReady <= 1;
                            perfPageFaults <= perfPageFaults + 1;
                        end else begin
                            translatePaddr <= tlbLookupPaddr;
                            translateReady <= 1;
                            perfTlbHits <= perfTlbHits + 1;
                        end
                        state <= IDLE;
                    end else begin
                        perfTlbMisses <= perfTlbMisses + 1;
                        ptwRequestValid <= 1;
                        state <= PTW_WAIT;
                    end
                end
                
                PTW_WAIT: begin
                    if (ptwDone) begin
                        if (ptwFault) begin
                            translateFault <= 1;
                            translateReady <= 1;
                            perfPageFaults <= perfPageFaults + 1;
                            state <= IDLE;
                        end else begin
                            // Fill TLB
                            tlbWriteValid <= 1;
                            tlbWriteVaddr <= translateVaddr;
                            tlbWritePaddr <= ptwPaddr;
                            tlbWriteAsid <= translateAsid;
                            tlbWritePermissions <= ptwPermissions;
                            
                            // Check permissions
                            if (translateWrite && !ptwPermissions[1]) begin
                                translateFault <= 1;
                                translateReady <= 1;
                                perfPageFaults <= perfPageFaults + 1;
                            end else begin
                                translatePaddr <= {ptwPaddr[PHYSICAL_ADDR_BITS-1:PAGE_OFFSET_BITS], translateVaddr[PAGE_OFFSET_BITS-1:0]};
                                translateReady <= 1;
                            end
                            state <= IDLE;
                        end
                    end
                end
                
            endcase
        end
        
        // Debug prints (simulation only)
        // synthesis translateOff
        if (!reset) begin
            if (translateValid)
                $display("[%0t] [MMU] translateValid=1, vaddr=%h, asid=%h", $time, translateVaddr, translateAsid);
            if (state != IDLE)
                $display("[%0t] [MMU] state=%s, tlbHit=%0b, ptwReq=%0b", $time, state.name(), tlbLookupHit, ptwRequestValid);
        end
        // synthesis translateOn
    end

endmodule
