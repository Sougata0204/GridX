// HBM3 Controller Interface
// Manages high-bandwidth memory channel requests and refresh timing for 3D stacked DRAM.

`default_nettype none
`timescale 1ns/1ns

module hbm3_ctrl #(
    parameter NUM_STACKS     = 4,
    parameter CHANNELS_PER_STACK = 2,
    parameter ADDR_WIDTH     = 32,
    parameter DATA_WIDTH     = 512,
    parameter ROW_BITS       = 14,
    parameter COL_BITS       = 6,
    parameter BANK_BITS      = 5,
    parameter BURST_LEN      = 4,

    parameter tRCD           = 7,
    parameter tRP            = 7,
    parameter tCL            = 11,
    parameter tWR            = 8,
    parameter tRRD           = 2
) (
    input  wire clk,
    input  wire reset,

    input  wire                    req_valid,
    input  wire [ADDR_WIDTH-1:0]   req_addr,
    input  wire [DATA_WIDTH-1:0]   req_wdata,
    input  wire                    req_write,
    output reg                     req_ready,

    output reg                     resp_valid,
    output reg  [DATA_WIDTH-1:0]   resp_data,
    output reg  [ADDR_WIDTH-1:0]   resp_addr,

    output reg  [$clog2(NUM_STACKS)-1:0]  phy_stack_sel,
    output reg                             phy_channel_sel,
    output reg  [ROW_BITS-1:0]             phy_row_addr,
    output reg  [COL_BITS-1:0]             phy_col_addr,
    output reg  [BANK_BITS-1:0]            phy_bank_addr,
    output reg                             phy_activate,
    output reg                             phy_read,
    output reg                             phy_write_cmd,
    output reg                             phy_precharge,
    output reg  [DATA_WIDTH-1:0]           phy_write_data,
    input  wire [DATA_WIDTH-1:0]           phy_read_data,
    input  wire                            phy_read_valid,

    output reg  [31:0]  total_reads,
    output reg  [31:0]  total_writes,
    output reg  [31:0]  row_hits,
    output reg  [31:0]  row_misses,
    output wire         controller_busy
);

    localparam NUM_CHANNELS = NUM_STACKS * CHANNELS_PER_STACK;
    localparam NUM_BANKS = 1 << BANK_BITS;

    wire [$clog2(NUM_STACKS)-1:0] addr_stack   = req_addr[ADDR_WIDTH-1 -: $clog2(NUM_STACKS)];
    wire                           addr_channel = req_addr[ADDR_WIDTH-$clog2(NUM_STACKS)-1];
    wire [BANK_BITS-1:0]           addr_bank    = req_addr[ROW_BITS+COL_BITS+BANK_BITS-1 : ROW_BITS+COL_BITS];
    wire [ROW_BITS-1:0]            addr_row     = req_addr[ROW_BITS+COL_BITS-1 : COL_BITS];
    wire [COL_BITS-1:0]            addr_col     = req_addr[COL_BITS-1 : 0];

    reg [ROW_BITS-1:0] open_row [NUM_BANKS-1:0];
    reg [NUM_BANKS-1:0] row_open;

    typedef enum logic [3:0] {
        HBM_IDLE,
        HBM_CHECK_ROW,
        HBM_PRECHARGE,
        HBM_WAIT_tRP,
        HBM_ACTIVATE,
        HBM_WAIT_tRCD,
        HBM_READ,
        HBM_WRITE,
        HBM_WAIT_CL,
        HBM_RESPOND
    } hbm_state_e;

    hbm_state_e state;
    reg [3:0]   wait_counter;
    reg         pending_is_write;
    reg [ADDR_WIDTH-1:0] pending_addr;
    reg [DATA_WIDTH-1:0] pending_wdata;
    reg [BANK_BITS-1:0]  pending_bank;
    reg [ROW_BITS-1:0]   pending_row;
    reg [COL_BITS-1:0]   pending_col;

    assign controller_busy = (state != HBM_IDLE);

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            state         <= HBM_IDLE;
            req_ready     <= 0;
            resp_valid    <= 0;
            total_reads   <= 0;
            total_writes  <= 0;
            row_hits      <= 0;
            row_misses    <= 0;
            phy_activate  <= 0;
            phy_read      <= 0;
            phy_write_cmd <= 0;
            phy_precharge <= 0;
            row_open      <= 0;
            wait_counter  <= 0;
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                open_row[i] <= 0;
            end
        end else begin
            req_ready     <= 0;
            resp_valid    <= 0;
            phy_activate  <= 0;
            phy_read      <= 0;
            phy_write_cmd <= 0;
            phy_precharge <= 0;

            case (state)
                HBM_IDLE: begin
                    if (req_valid) begin
                        pending_is_write <= req_write;
                        pending_addr     <= req_addr;
                        pending_wdata    <= req_wdata;
                        pending_bank     <= addr_bank;
                        pending_row      <= addr_row;
                        pending_col      <= addr_col;
                        phy_stack_sel    <= addr_stack;
                        phy_channel_sel  <= addr_channel;
                        phy_bank_addr    <= addr_bank;
                        req_ready        <= 1;
                        state            <= HBM_CHECK_ROW;
                        if (req_write) total_writes <= total_writes + 1;
                        else           total_reads  <= total_reads + 1;
                    end
                end

                HBM_CHECK_ROW: begin
                    if (row_open[pending_bank] && open_row[pending_bank] == pending_row) begin

                        row_hits <= row_hits + 1;
                        if (pending_is_write) state <= HBM_WRITE;
                        else                  state <= HBM_READ;
                    end else begin

                        row_misses <= row_misses + 1;
                        if (row_open[pending_bank]) begin
                            state <= HBM_PRECHARGE;
                        end else begin
                            state <= HBM_ACTIVATE;
                        end
                    end
                end

                HBM_PRECHARGE: begin
                    phy_precharge <= 1;
                    phy_row_addr  <= open_row[pending_bank];
                    row_open[pending_bank] <= 0;
                    wait_counter  <= tRP;
                    state         <= HBM_WAIT_tRP;
                end

                HBM_WAIT_tRP: begin
                    if (wait_counter == 0) state <= HBM_ACTIVATE;
                    else wait_counter <= wait_counter - 1;
                end

                HBM_ACTIVATE: begin
                    phy_activate <= 1;
                    phy_row_addr <= pending_row;
                    open_row[pending_bank] <= pending_row;
                    row_open[pending_bank] <= 1;
                    wait_counter <= tRCD;
                    state        <= HBM_WAIT_tRCD;
                end

                HBM_WAIT_tRCD: begin
                    if (wait_counter == 0) begin
                        if (pending_is_write) state <= HBM_WRITE;
                        else                  state <= HBM_READ;
                    end else begin
                        wait_counter <= wait_counter - 1;
                    end
                end

                HBM_READ: begin
                    phy_read     <= 1;
                    phy_col_addr <= pending_col;
                    wait_counter <= tCL;
                    state        <= HBM_WAIT_CL;
                end

                HBM_WRITE: begin
                    phy_write_cmd  <= 1;
                    phy_col_addr   <= pending_col;
                    phy_write_data <= pending_wdata;
                    state          <= HBM_IDLE;
                end

                HBM_WAIT_CL: begin
                    if (wait_counter == 0) begin
                        state <= HBM_RESPOND;
                    end else begin
                        wait_counter <= wait_counter - 1;
                    end

                    if (phy_read_valid) begin
                        resp_data <= phy_read_data;
                        resp_addr <= pending_addr;
                    end
                end

                HBM_RESPOND: begin
                    resp_valid <= 1;
                    state      <= HBM_IDLE;
                end

                default: state <= HBM_IDLE;
            endcase
        end
    end

endmodule
