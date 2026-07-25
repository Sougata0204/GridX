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
    input  wire translate_valid,
    input  wire [VIRTUAL_ADDR_BITS-1:0] translate_vaddr,
    input  wire [ASID_BITS-1:0] translate_asid,
    input  wire translate_write,
    output reg  translate_ready,
    output reg  [PHYSICAL_ADDR_BITS-1:0] translate_paddr,
    output reg  translate_fault,
    
    // Memory Interface (for Page Table Walker)
    output wire ptw_mem_read_valid,
    output wire [PHYSICAL_ADDR_BITS-1:0] ptw_mem_read_addr,
    input  wire ptw_mem_read_ready,
    input  wire [63:0] ptw_mem_read_data,
    
    // System Config
    input  wire [PHYSICAL_ADDR_BITS-1:0] page_table_base,
    input  wire tlb_invalidate_all,
    
    // Performance
    output reg  [31:0] perf_tlb_hits,
    output reg  [31:0] perf_tlb_misses,
    output reg  [31:0] perf_page_faults
);

    // TLB Signals
    wire tlb_lookup_hit;
    wire [PHYSICAL_ADDR_BITS-1:0] tlb_lookup_paddr;
    wire [2:0] tlb_lookup_permissions;
    reg tlb_lookup_valid;
    
    reg tlb_write_valid;
    reg [VIRTUAL_ADDR_BITS-1:0] tlb_write_vaddr;
    reg [PHYSICAL_ADDR_BITS-1:0] tlb_write_paddr;
    reg [ASID_BITS-1:0] tlb_write_asid;
    reg [2:0] tlb_write_permissions;
    
    tlb #(
        .NUM_ENTRIES(TLB_ENTRIES),
        .VIRTUAL_ADDR_BITS(VIRTUAL_ADDR_BITS),
        .PHYSICAL_ADDR_BITS(PHYSICAL_ADDR_BITS),
        .PAGE_OFFSET_BITS(PAGE_OFFSET_BITS),
        .ASID_BITS(ASID_BITS)
    ) u_tlb (
        .clk(clk),
        .reset(reset),
        .lookup_valid(tlb_lookup_valid),
        .lookup_vaddr(translate_vaddr),
        .lookup_asid(translate_asid),
        .lookup_hit(tlb_lookup_hit),
        .lookup_paddr(tlb_lookup_paddr),
        .lookup_permissions(tlb_lookup_permissions),
        .write_valid(tlb_write_valid),
        .write_vaddr(tlb_write_vaddr),
        .write_paddr(tlb_write_paddr),
        .write_asid(tlb_write_asid),
        .write_permissions(tlb_write_permissions),
        .invalidate_all(tlb_invalidate_all),
        .invalidate_asid_valid(1'b0),
        .invalidate_asid(8'd0),
        .perf_hits(),     // Managed internally
        .perf_misses()
    );

    // Page Table Walker Signals
    reg ptw_request_valid;
    wire ptw_done;
    wire ptw_fault;
    wire [PHYSICAL_ADDR_BITS-1:0] ptw_paddr;
    wire [2:0] ptw_permissions;
    wire ptw_busy;

    page_table_walker #(
        .VIRTUAL_ADDR_BITS(VIRTUAL_ADDR_BITS),
        .PHYSICAL_ADDR_BITS(PHYSICAL_ADDR_BITS),
        .PAGE_OFFSET_BITS(PAGE_OFFSET_BITS),
        .PAGE_TABLE_LEVELS(4),
        .DATA_WIDTH(64)
    ) u_ptw (
        .clk(clk),
        .reset(reset),
        .walk_request_valid(ptw_request_valid),
        .walk_vaddr(translate_vaddr),
        .walk_asid(translate_asid),
        .walk_done(ptw_done),
        .walk_fault(ptw_fault),
        .walk_paddr(ptw_paddr),
        .walk_permissions(ptw_permissions),
        .mem_read_valid(ptw_mem_read_valid),
        .mem_read_addr(ptw_mem_read_addr),
        .mem_read_ready(ptw_mem_read_ready),
        .mem_read_data(ptw_mem_read_data),
        .page_table_base_addr(page_table_base),
        .busy(ptw_busy)
    );

    typedef enum logic [1:0] {
        IDLE,
        TLB_LOOKUP,
        PTW_WAIT
    } state_e;
    
    state_e state;
    
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            translate_ready <= 0;
            translate_paddr <= 0;
            translate_fault <= 0;
            tlb_lookup_valid <= 0;
            tlb_write_valid <= 0;
            ptw_request_valid <= 0;
            perf_tlb_hits <= 0;
            perf_tlb_misses <= 0;
            perf_page_faults <= 0;
        end else begin
            translate_ready <= 0;
            translate_fault <= 0;
            tlb_lookup_valid <= 0;
            tlb_write_valid <= 0;
            ptw_request_valid <= 0;
            
            case (state)
                IDLE: begin
                    if (translate_valid) begin
                        tlb_lookup_valid <= 1;
                        state <= TLB_LOOKUP;
                    end
                end
                
                TLB_LOOKUP: begin
                    // TLB takes 1 cycle
                    if (tlb_lookup_hit) begin
                        // Check permissions
                        if (translate_write && !tlb_lookup_permissions[1]) begin // [1] is write permission
                            translate_fault <= 1;
                            translate_ready <= 1;
                            perf_page_faults <= perf_page_faults + 1;
                        end else begin
                            translate_paddr <= tlb_lookup_paddr;
                            translate_ready <= 1;
                            perf_tlb_hits <= perf_tlb_hits + 1;
                        end
                        state <= IDLE;
                    end else begin
                        perf_tlb_misses <= perf_tlb_misses + 1;
                        ptw_request_valid <= 1;
                        state <= PTW_WAIT;
                    end
                end
                
                PTW_WAIT: begin
                    if (ptw_done) begin
                        if (ptw_fault) begin
                            translate_fault <= 1;
                            translate_ready <= 1;
                            perf_page_faults <= perf_page_faults + 1;
                            state <= IDLE;
                        end else begin
                            // Fill TLB
                            tlb_write_valid <= 1;
                            tlb_write_vaddr <= translate_vaddr;
                            tlb_write_paddr <= ptw_paddr;
                            tlb_write_asid <= translate_asid;
                            tlb_write_permissions <= ptw_permissions;
                            
                            // Check permissions
                            if (translate_write && !ptw_permissions[1]) begin
                                translate_fault <= 1;
                                translate_ready <= 1;
                                perf_page_faults <= perf_page_faults + 1;
                            end else begin
                                translate_paddr <= {ptw_paddr[PHYSICAL_ADDR_BITS-1:PAGE_OFFSET_BITS], translate_vaddr[PAGE_OFFSET_BITS-1:0]};
                                translate_ready <= 1;
                            end
                            state <= IDLE;
                        end
                    end
                end
                
            endcase
        end
        
        // Debug prints (simulation only)
        // synthesis translate_off
        if (!reset) begin
            if (translate_valid)
                $display("[%0t] [MMU] translate_valid=1, vaddr=%h, asid=%h", $time, translate_vaddr, translate_asid);
            if (state != IDLE)
                $display("[%0t] [MMU] state=%s, tlb_hit=%0b, ptw_req=%0b", $time, state.name(), tlb_lookup_hit, ptw_request_valid);
        end
        // synthesis translate_on
    end

endmodule
