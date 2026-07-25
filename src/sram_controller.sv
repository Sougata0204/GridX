
`default_nettype none
`timescale 1ns/1ns

module sram_controller #(
    parameter NUM_CORES = 2,
    parameter THREADS_PER_BLOCK = 4,
    parameter NUM_BANKS = 8,
    parameter BANK_DEPTH = 256,
    parameter DATA_WIDTH = 64,
    parameter ADDR_BITS = 8,
    parameter NUM_REQUESTERS = NUM_CORES * THREADS_PER_BLOCK,
    parameter NUM_TILES = 4
) (
    input wire clk,
    input wire reset,
    input wire [ADDR_BITS-1:0] sram_base_reg,
    input wire [ADDR_BITS-1:0] sram_limit_reg,
    input wire [NUM_REQUESTERS-1:0] core_read_valid,
    input wire [ADDR_BITS-1:0] core_read_address [NUM_REQUESTERS-1:0],
    output wire [NUM_REQUESTERS-1:0] core_read_ready,
    output wire [DATA_WIDTH-1:0] core_read_data [NUM_REQUESTERS-1:0],
    input wire [NUM_REQUESTERS-1:0] core_write_valid,
    input wire [ADDR_BITS-1:0] core_write_address [NUM_REQUESTERS-1:0],
    input wire [DATA_WIDTH-1:0] core_write_data [NUM_REQUESTERS-1:0],
    output wire [NUM_REQUESTERS-1:0] core_write_ready,
    output wire [NUM_REQUESTERS-1:0] core_bank_conflict,
    input wire tile_ld_valid,
    input wire [$clog2(NUM_TILES)-1:0] tile_ld_id,
    input wire tile_st_valid,
    input wire [$clog2(NUM_TILES)-1:0] tile_st_id,
    input wire tile_fence_valid,
    input wire [$clog2(NUM_TILES)-1:0] tile_fence_id,
    output wire tile_fence_done,
    output wire [NUM_REQUESTERS-1:0] lsu_must_stall,
    output wire [NUM_REQUESTERS-1:0] ext_read_valid,
    output wire [ADDR_BITS-1:0] ext_read_address [NUM_REQUESTERS-1:0],
    input wire [NUM_REQUESTERS-1:0] ext_read_ready,
    input wire [DATA_WIDTH-1:0] ext_read_data [NUM_REQUESTERS-1:0],
    output wire [NUM_REQUESTERS-1:0] ext_write_valid,
    output wire [ADDR_BITS-1:0] ext_write_address [NUM_REQUESTERS-1:0],
    output wire [DATA_WIDTH-1:0] ext_write_data [NUM_REQUESTERS-1:0],
    input wire [NUM_REQUESTERS-1:0] ext_write_ready,
    input wire dma_read_valid,
    input wire [ADDR_BITS-1:0] dma_read_address,
    output reg dma_read_ready,
    output reg [DATA_WIDTH-1:0] dma_read_data,
    input wire dma_write_valid,
    input wire [ADDR_BITS-1:0] dma_write_address,
    input wire [DATA_WIDTH-1:0] dma_write_data,
    output reg dma_write_ready,
    input wire dma_write_done,
    input wire dma_read_done,
    input wire [NUM_BANKS-1:0] force_bank_enable,
    input wire [NUM_BANKS-1:0] force_bank_sleep,
    output wire [NUM_BANKS-1:0] bank_active,
    output wire [1:0] bank_power_state [NUM_BANKS-1:0],
    output wire [NUM_BANKS-1:0] bank_needs_reload,
    output wire [2:0] tile_state [NUM_TILES-1:0]
);
    localparam TILE_IDLE     = 3'b000;
    localparam TILE_LOADING  = 3'b001;
    localparam TILE_READY    = 3'b010;
    localparam TILE_IN_USE   = 3'b011;
    localparam TILE_EVICTING = 3'b100;
    reg [2:0] tile_state_reg [NUM_TILES-1:0];
    reg [NUM_TILES-1:0] tile_first_read_seen;
    genvar t;
    generate
        for (t = 0; t < NUM_TILES; t = t + 1) begin : tile_state_output
            assign tile_state[t] = tile_state_reg[t];
        end
    endgenerate

    function [$clog2(NUM_TILES)-1:0] get_tile_id;
        input [ADDR_BITS-1:0] addr;
        reg [ADDR_BITS-1:0] tile_size;
        begin
            tile_size = (sram_limit_reg - sram_base_reg + 1) / NUM_TILES;
            if (tile_size > 0)
                get_tile_id = (addr - sram_base_reg) / tile_size;
            else
                get_tile_id = 0;
        end
    endfunction
    wire [NUM_TILES-1:0] tile_readable;
    generate
        for (t = 0; t < NUM_TILES; t = t + 1) begin : readable_check
            assign tile_readable[t] = (tile_state_reg[t] == TILE_READY) ||
                                      (tile_state_reg[t] == TILE_IN_USE);
        end
    endgenerate
    wire [NUM_TILES-1:0] tile_dma_write_allowed;
    generate
        for (t = 0; t < NUM_TILES; t = t + 1) begin : dma_write_check
            assign tile_dma_write_allowed[t] = (tile_state_reg[t] == TILE_IDLE);
        end
    endgenerate
    wire [NUM_TILES-1:0] tile_dma_read_allowed;
    generate
        for (t = 0; t < NUM_TILES; t = t + 1) begin : dma_read_check
            assign tile_dma_read_allowed[t] = (tile_state_reg[t] == TILE_READY);
        end
    endgenerate
    assign tile_fence_done = tile_fence_valid &&
                             (tile_state_reg[tile_fence_id] == TILE_READY);
    reg [NUM_REQUESTERS-1:0] lsu_stall_reg;
    integer r;
    always @(*) begin
        for (r = 0; r < NUM_REQUESTERS; r = r + 1) begin
            if (core_read_valid[r]) begin
                if (core_read_address[r] >= sram_base_reg &&
                    core_read_address[r] <= sram_limit_reg) begin
                    lsu_stall_reg[r] = ~tile_readable[get_tile_id(core_read_address[r])];
                end else begin
                    lsu_stall_reg[r] = 1'b0;
                end
            end else begin
                lsu_stall_reg[r] = 1'b0;
            end
        end
    end
    assign lsu_must_stall = lsu_stall_reg;
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < NUM_TILES; i = i + 1) begin
                tile_state_reg[i] <= TILE_IDLE;
                tile_first_read_seen[i] <= 1'b0;
            end
        end else begin
            for (i = 0; i < NUM_TILES; i = i + 1) begin
                case (tile_state_reg[i])
                    TILE_IDLE: begin
                        if (tile_ld_valid && (tile_ld_id == i)) begin
                            tile_state_reg[i] <= TILE_LOADING;
                        end
                    end
                    TILE_LOADING: begin
                        if (dma_write_done) begin
                            tile_state_reg[i] <= TILE_READY;
                            tile_first_read_seen[i] <= 1'b0;
                        end
                    end
                    TILE_READY: begin
                        if (!tile_first_read_seen[i]) begin
                            for (r = 0; r < NUM_REQUESTERS; r = r + 1) begin
                                if (core_read_valid[r] &&
                                    core_read_address[r] >= sram_base_reg &&
                                    core_read_address[r] <= sram_limit_reg &&
                                    get_tile_id(core_read_address[r]) == i) begin
                                    tile_state_reg[i] <= TILE_IN_USE;
                                    tile_first_read_seen[i] <= 1'b1;
                                end
                            end
                        end
                        if (tile_st_valid && (tile_st_id == i)) begin
                            tile_state_reg[i] <= TILE_EVICTING;
                        end
                    end
                    TILE_IN_USE: begin
                        if (tile_fence_valid && (tile_fence_id == i)) begin
                            tile_state_reg[i] <= TILE_READY;
                            tile_first_read_seen[i] <= 1'b0;
                        end
                    end
                    TILE_EVICTING: begin
                        if (dma_read_done) begin
                            tile_state_reg[i] <= TILE_IDLE;
                            tile_first_read_seen[i] <= 1'b0;
                        end
                    end
                    default: begin
                        tile_state_reg[i] <= TILE_IDLE;
                    end
                endcase
            end
        end
    end
    `ifdef FORMAL
    genvar a;
    generate
        for (a = 0; a < NUM_REQUESTERS; a = a + 1) begin : assert_lsu_read
            always @(posedge clk) begin
                if (!reset && core_read_valid[a]) begin
                    if (core_read_address[a] >= sram_base_reg &&
                        core_read_address[a] <= sram_limit_reg) begin
                        assert(tile_readable[get_tile_id(core_read_address[a])])
                            else $error("ILLEGAL: LSU read when tile not READY/IN_USE");
                    end
                end
            end
        end
    endgenerate
    always @(posedge clk) begin
        if (!reset && dma_write_valid && tile_ld_valid) begin
            assert(tile_dma_write_allowed[tile_ld_id])
                else $error("ILLEGAL: DMA write when tile != IDLE");
        end
    end
    always @(posedge clk) begin
        if (!reset && dma_read_valid && tile_st_valid) begin
            assert(tile_state_reg[tile_st_id] != TILE_IN_USE)
                else $error("ILLEGAL: DMA read when tile == IN_USE");
        end
    end
    `endif
    wire [NUM_BANKS-1:0] bank_tile_active;
    generate
        for (t = 0; t < NUM_BANKS && t < NUM_TILES; t = t + 1) begin : bank_tile_map
            assign bank_tile_active[t] = (tile_state_reg[t] != TILE_IDLE);
        end
        for (t = NUM_TILES; t < NUM_BANKS; t = t + 1) begin : bank_unused
            assign bank_tile_active[t] = 1'b0;
        end
    endgenerate
    wire [NUM_BANKS-1:0] bank_power_enable;
    wire [NUM_REQUESTERS-1:0] sram_read_ready;
    wire [DATA_WIDTH-1:0] sram_read_data [NUM_REQUESTERS-1:0];
    wire [NUM_REQUESTERS-1:0] sram_write_ready;
    wire [NUM_REQUESTERS-1:0] tile_ext_read_valid;
    wire [ADDR_BITS-1:0] tile_ext_read_address [NUM_REQUESTERS-1:0];
    wire [NUM_REQUESTERS-1:0] tile_ext_write_valid;
    wire [ADDR_BITS-1:0] tile_ext_write_address [NUM_REQUESTERS-1:0];
    wire [DATA_WIDTH-1:0] tile_ext_write_data [NUM_REQUESTERS-1:0];
    wire [NUM_REQUESTERS-1:0] gated_read_valid;
    assign gated_read_valid = core_read_valid & ~lsu_must_stall;
    sram_tile_buffer #(
        .NUM_BANKS(NUM_BANKS),
        .BANK_DEPTH(BANK_DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_REQUESTERS(NUM_REQUESTERS),
        .ADDR_BITS(ADDR_BITS)
    ) tile_buffer_inst (
        .clk(clk),
        .reset(reset),
        .sram_base(sram_base_reg),
        .sram_limit(sram_limit_reg),
        .read_valid(gated_read_valid),
        .read_address(core_read_address),
        .read_ready(sram_read_ready),
        .read_data(sram_read_data),
        .write_valid(core_write_valid),
        .write_address(core_write_address),
        .write_data(core_write_data),
        .write_ready(sram_write_ready),
        .bank_conflict(core_bank_conflict),
        .bank_power_enable(bank_power_enable | bank_tile_active),
        .bank_active(bank_active),
        .external_read_valid(tile_ext_read_valid),
        .external_read_address(tile_ext_read_address),
        .external_write_valid(tile_ext_write_valid),
        .external_write_address(tile_ext_write_address),
        .external_write_data(tile_ext_write_data)
    );
    power_controller #(
        .NUM_BANKS(NUM_BANKS),
        .IDLE_CYCLES(16),
        .SLEEP_CYCLES(256)
    ) power_ctrl_inst (
        .clk(clk),
        .reset(reset),
        .bank_active(bank_active | bank_tile_active),
        .force_enable(force_bank_enable | bank_tile_active),
        .force_sleep(force_bank_sleep & ~bank_tile_active),
        .bank_power_enable(bank_power_enable),
        .bank_power_state(bank_power_state),
        .bank_needs_reload(bank_needs_reload),
        .total_idle_cycles(),
        .total_sleep_cycles(),
        .state_transitions(),
        .bank_was_active()
    );
    assign ext_read_valid = tile_ext_read_valid;
    assign ext_read_address = tile_ext_read_address;
    assign ext_write_valid = tile_ext_write_valid;
    assign ext_write_address = tile_ext_write_address;
    assign ext_write_data = tile_ext_write_data;
    genvar m;
    generate
        for (m = 0; m < NUM_REQUESTERS; m = m + 1) begin : response_mux
            assign core_read_ready[m] = sram_read_ready[m] | ext_read_ready[m];
            assign core_read_data[m] = sram_read_ready[m] ? sram_read_data[m] : ext_read_data[m];
            assign core_write_ready[m] = sram_write_ready[m] | ext_write_ready[m];
        end
    endgenerate
    always @(posedge clk) begin
        if (reset) begin
            dma_read_ready <= 1'b0;
            dma_read_data <= {DATA_WIDTH{1'b0}};
            dma_write_ready <= 1'b0;
        end else begin
            dma_read_ready <= dma_read_valid;
            dma_write_ready <= dma_write_valid;
        end
    end
endmodule
