
`default_nettype none
`timescale 1ns/1ns

module mem_mesh_bridge #(
    parameter NUM_GPU_CHANNELS  = 1,
    parameter ADDR_BITS         = 22,
    parameter DATA_BITS         = 8,
    parameter MESH_FLIT_WIDTH   = 512,
    parameter MESH_VC_ID_W      = 2,
    parameter MESH_COORD_W      = 2,
    parameter TX_TABLE_ENTRIES  = 4,
    parameter TX_ID_W           = 5
) (
    input  wire clk,
    input  wire reset,

    input  wire [NUM_GPU_CHANNELS-1:0]  gpu_read_valid,
    input  wire [ADDR_BITS-1:0]         gpu_read_address  [NUM_GPU_CHANNELS-1:0],
    output reg  [NUM_GPU_CHANNELS-1:0]  gpu_read_ready,
    output reg  [DATA_BITS-1:0]         gpu_read_data     [NUM_GPU_CHANNELS-1:0],

    input  wire [NUM_GPU_CHANNELS-1:0]  gpu_write_valid,
    input  wire [ADDR_BITS-1:0]         gpu_write_address [NUM_GPU_CHANNELS-1:0],
    input  wire [DATA_BITS-1:0]         gpu_write_data    [NUM_GPU_CHANNELS-1:0],
    output reg  [NUM_GPU_CHANNELS-1:0]  gpu_write_ready,

    output reg                          mesh_tx_valid,
    output reg  [MESH_FLIT_WIDTH-1:0]   mesh_tx_data,
    output reg  [1:0]                   mesh_tx_flit_type,
    output reg  [MESH_VC_ID_W-1:0]      mesh_tx_vc_id,
    input  wire                         mesh_tx_credit_valid,
    input  wire [MESH_VC_ID_W-1:0]      mesh_tx_credit_vc_id,

    input  wire                         mesh_rx_valid,
    input  wire [MESH_FLIT_WIDTH-1:0]   mesh_rx_data,
    input  wire [1:0]                   mesh_rx_flit_type,
    input  wire [MESH_VC_ID_W-1:0]      mesh_rx_vc_id,
    output reg                          mesh_rx_credit_valid,
    output reg  [MESH_VC_ID_W-1:0]      mesh_rx_credit_vc_id,

    input  wire [MESH_COORD_W-1:0]      my_x,
    input  wire [MESH_COORD_W-1:0]      my_y,
    input  wire [MESH_COORD_W-1:0]      my_z,

    output wire [6:0]                   outstanding_count,
    output wire                         bridge_busy
);

    localparam CH_ID_W = (NUM_GPU_CHANNELS > 1) ? $clog2(NUM_GPU_CHANNELS) : 1;

    localparam [1:0] FLIT_HEAD = 2'b01;
    localparam [1:0] FLIT_BODY = 2'b10;
    localparam [1:0] FLIT_TAIL = 2'b11;

    localparam [MESH_VC_ID_W-1:0] VC_READ  = 2'd0;
    localparam [MESH_VC_ID_W-1:0] VC_WRITE = 2'd1;
    localparam [MESH_VC_ID_W-1:0] VC_RESP  = 2'd2;


    typedef enum logic [2:0] {
        TX_IDLE,
        TX_ARBITRATE,
        TX_SEND_HEAD,
        TX_SEND_TAIL,
        TX_WAIT_CREDIT
    } tx_state_e;

    tx_state_e           tx_state;

    reg [TX_TABLE_ENTRIES-1:0]  tx_active;
    reg [$clog2(NUM_GPU_CHANNELS)-1:0] tx_src_channel [TX_TABLE_ENTRIES-1:0];
    reg [TX_TABLE_ENTRIES-1:0]  tx_is_write;
    reg [6:0]                   tx_count;

    assign outstanding_count = tx_count;
    assign bridge_busy       = (tx_count > 0) || (tx_state != TX_IDLE);
    reg [$clog2(NUM_GPU_CHANNELS)-1:0] tx_winner;
    reg                  tx_winner_is_write;
    reg [ADDR_BITS-1:0]  tx_winner_addr;
    reg [DATA_BITS-1:0]  tx_winner_wdata;
    reg [TX_ID_W-1:0]    tx_alloc_id;

    reg [4:0] mesh_tx_credits [3:0];

    reg [TX_ID_W-1:0]    free_tx_id;
    reg                  tx_table_full;

    always @(*) begin
        free_tx_id    = 0;
        tx_table_full = 1;
        for (integer t = 0; t < TX_TABLE_ENTRIES; t = t + 1) begin
            if (!tx_active[t] && tx_table_full) begin
                free_tx_id    = t[TX_ID_W-1:0];
                tx_table_full = 0;
            end
        end
    end

    reg [CH_ID_W-1:0] rr_ptr;
    reg [CH_ID_W-1:0] arb_winner;
    reg                                arb_found;
    reg                                arb_is_write;

    always @(*) begin
        arb_found    = 0;
        arb_winner   = 0;
        arb_is_write = 0;
        for (integer ch = 0; ch < NUM_GPU_CHANNELS; ch = ch + 1) begin
            automatic integer idx = (rr_ptr + ch) % NUM_GPU_CHANNELS;
            if (!arb_found) begin
                if (gpu_write_valid[idx]) begin
                    arb_found    = 1;
                    arb_winner   = idx[CH_ID_W-1:0];
                    arb_is_write = 1;
                end else if (gpu_read_valid[idx]) begin
                    arb_found    = 1;
                    arb_winner   = idx[CH_ID_W-1:0];
                    arb_is_write = 0;
                end
            end
        end
    end

    localparam NUM_HBM_NODES = 8;
    localparam MESH_DIM = (1 << MESH_COORD_W);  // 2^MESH_COORD_W (e.g. 4-bit coord -> 16, but actual mesh is 8)
    localparam TOTAL_NODES = MESH_DIM * MESH_DIM * MESH_DIM;
    localparam HBM_BASE_NODE = TOTAL_NODES - NUM_HBM_NODES;

    reg [MESH_COORD_W-1:0] hbm_dest_x;
    reg [MESH_COORD_W-1:0] hbm_dest_y;
    reg [MESH_COORD_W-1:0] hbm_dest_z;

    always @(*) begin
        automatic integer hbm_sel = tx_winner_addr[4:2];
        automatic integer hbm_node = HBM_BASE_NODE + hbm_sel;
        hbm_dest_x = hbm_node % MESH_DIM;
        hbm_dest_y = (hbm_node / MESH_DIM) % MESH_DIM;
        hbm_dest_z = hbm_node / (MESH_DIM * MESH_DIM);
    end

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            tx_state            <= TX_IDLE;
            mesh_tx_valid       <= 0;
            mesh_tx_data        <= 0;
            mesh_tx_flit_type   <= 0;
            mesh_tx_vc_id       <= 0;
            gpu_read_ready      <= 0;
            gpu_write_ready     <= 0;
            tx_active           <= 0;
            tx_count            <= 0;
            rr_ptr              <= 0;
            for (i = 0; i < TX_TABLE_ENTRIES; i = i + 1) begin
                tx_src_channel[i] <= 0;
                tx_is_write[i]    <= 0;
            end
            for (i = 0; i < 4; i = i + 1) begin
                mesh_tx_credits[i] <= 5'd8;
            end
        end else begin

            gpu_read_ready  <= 0;
            gpu_write_ready <= 0;
            mesh_tx_valid   <= 0;

            if (mesh_tx_credit_valid) begin
                mesh_tx_credits[mesh_tx_credit_vc_id] <=
                    mesh_tx_credits[mesh_tx_credit_vc_id] + 1;
            end

            case (tx_state)
                TX_IDLE: begin
                    if (arb_found && !tx_table_full) begin
                        tx_winner          <= arb_winner;
                        tx_winner_is_write <= arb_is_write;
                        tx_winner_addr     <= arb_is_write ?
                                              gpu_write_address[arb_winner] :
                                              gpu_read_address[arb_winner];
                        tx_winner_wdata    <= arb_is_write ?
                                              gpu_write_data[arb_winner] : 8'd0;
                        tx_alloc_id        <= free_tx_id;
                        tx_state           <= TX_SEND_HEAD;
                    end
                end

                TX_SEND_HEAD: begin
                    automatic reg [MESH_VC_ID_W-1:0] vc =
                        tx_winner_is_write ? VC_WRITE : VC_READ;

                    if (mesh_tx_credits[vc] > 0) begin
                        mesh_tx_valid     <= 1;
                        mesh_tx_flit_type <= FLIT_HEAD;
                        mesh_tx_vc_id     <= vc;
                        mesh_tx_data      <= {
                            tx_winner_is_write ? 3'b001 : 3'b000,
                            vc,
                            my_x, my_y, my_z,
                            hbm_dest_x, hbm_dest_y, hbm_dest_z,
                            tx_alloc_id,
                            4'b0000,
                            4'b0000,
                            2'b00,
                            tx_winner_addr,
                            tx_winner_wdata,
                            438'd0
                        };

                        mesh_tx_credits[vc] <= mesh_tx_credits[vc] - 1;

                        tx_active[tx_alloc_id]      <= 1;
                        tx_src_channel[tx_alloc_id] <= tx_winner;
                        tx_is_write[tx_alloc_id]    <= tx_winner_is_write;
                        tx_count                    <= tx_count + 1;

                        tx_state <= TX_SEND_TAIL;
                    end

                end

                TX_SEND_TAIL: begin
                    automatic reg [MESH_VC_ID_W-1:0] vc =
                        tx_winner_is_write ? VC_WRITE : VC_READ;

                    if (mesh_tx_credits[vc] > 0) begin
                        mesh_tx_valid     <= 1;
                        mesh_tx_flit_type <= FLIT_TAIL;
                        mesh_tx_vc_id     <= vc;
                        mesh_tx_data      <= {
                            tx_alloc_id,
                            tx_winner_addr,
                            {(MESH_FLIT_WIDTH-27){1'b0}}
                        };

                        mesh_tx_credits[vc] <= mesh_tx_credits[vc] - 1;

                        if (tx_winner_is_write) begin
                            gpu_write_ready[tx_winner] <= 1;
                        end else begin

                        end

                        rr_ptr   <= (tx_winner + 1) % NUM_GPU_CHANNELS;
                        tx_state <= TX_IDLE;
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    reg [TX_ID_W-1:0] rx_pending_tx_id;

    always @(posedge clk) begin
        if (reset) begin
            mesh_rx_credit_valid <= 0;
            mesh_rx_credit_vc_id <= 0;
            rx_pending_tx_id     <= 0;
        end else begin
            mesh_rx_credit_valid <= 0;

            if (mesh_rx_valid) begin

                mesh_rx_credit_valid <= 1;
                mesh_rx_credit_vc_id <= mesh_rx_vc_id;

                if (mesh_rx_flit_type == FLIT_HEAD) begin

                    rx_pending_tx_id <= mesh_rx_data[494:490];
                end
                else if (mesh_rx_flit_type == FLIT_TAIL) begin

                    automatic reg [TX_ID_W-1:0] tid = rx_pending_tx_id;
                    automatic integer src_ch = tx_src_channel[tid];

                    if (!tx_is_write[tid]) begin

                        gpu_read_ready[src_ch] <= 1;
                        gpu_read_data[src_ch]  <= mesh_rx_data[DATA_BITS-1:0];
                    end

                    tx_active[tid] <= 0;
                    tx_count       <= tx_count - 1;
                end
            end
        end
    end

`ifdef VERILATOR
    always @(posedge clk) begin
        if (!reset) begin
            if (tx_count > TX_TABLE_ENTRIES) begin
                $display("ERROR: mem_mesh_bridge TX overflow! count=%0d", tx_count);
            end
        end
    end
`endif

endmodule
