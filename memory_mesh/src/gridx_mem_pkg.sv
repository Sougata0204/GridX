// `default_nettype none  -- removed: package uses `logic` types
`timescale 1ps/1ps

package gridx_mem_pkg;

    localparam int MESH_X     = 2;
    localparam int MESH_Y     = 2;
    localparam int MESH_Z     = 2;
    localparam int NUM_NODES  = MESH_X * MESH_Y * MESH_Z;

    localparam int COORD_X_W  = (MESH_X > 1) ? $clog2(MESH_X) : 1;
    localparam int COORD_Y_W  = (MESH_Y > 1) ? $clog2(MESH_Y) : 1;
    localparam int COORD_Z_W  = (MESH_Z > 1) ? $clog2(MESH_Z) : 1;

    localparam int NUM_PORTS  = 7;

    localparam int NOC_FREQ_MHZ       = 1000;
    localparam int NOC_CLOCK_PERIOD_PS = 1000000 / NOC_FREQ_MHZ;

    localparam int LINK_BW_GBPS       = 256;
    localparam int BISECTION_BW_GBPS  = 1024;

    localparam int FLIT_WIDTH        = 256;
    localparam int NUM_VCS           = 4;
    localparam int VC_ID_W           = 2;
    localparam int FLITS_PER_BUFFER  = 8;
    localparam int CREDIT_WIDTH      = $clog2(FLITS_PER_BUFFER + 1);

    typedef enum logic [VC_ID_W-1:0] {
        VC_READ_REQ  = 2'd0,
        VC_WRITE_REQ = 2'd1,
        VC_MEM_RESP  = 2'd2,
        VC_CTRL_COH  = 2'd3
    } vc_id_e;

    typedef enum logic [1:0] {
        FLIT_HEAD = 2'b01,
        FLIT_BODY = 2'b10,
        FLIT_TAIL = 2'b11
    } flit_type_e;

    typedef enum logic [2:0] {
        PKT_READ_REQ  = 3'b000,
        PKT_WRITE_REQ = 3'b001,
        PKT_MEM_RESP  = 3'b010,
        PKT_COHERENCE = 3'b011
    } pkt_type_e;

    typedef enum logic [2:0] {
        PORT_LOCAL = 3'd0,
        PORT_X_POS = 3'd1,
        PORT_X_NEG = 3'd2,
        PORT_Y_POS = 3'd3,
        PORT_Y_NEG = 3'd4,
        PORT_Z_POS = 3'd5,
        PORT_Z_NEG = 3'd6
    } router_port_e;

    typedef struct packed {
        logic [COORD_X_W-1:0] x;
        logic [COORD_Y_W-1:0] y;
        logic [COORD_Z_W-1:0] z;
    } coord_t;

    typedef struct packed {
        pkt_type_e              pkt_type;
        logic [VC_ID_W-1:0]     vc_id;
        coord_t                 src_coord;
        coord_t                 dest_coord;
        logic [4:0]             tx_id;
        logic [3:0]             ctrl_flags;
        logic [3:0]             mcast_grp;
        logic [1:0]             pf_hint;
        logic [479:0]           metadata;
    } head_flit_t;

    typedef struct packed {
        logic                   valid;
        flit_type_e             flit_type;
        logic [VC_ID_W-1:0]    vc_id;
        logic [FLIT_WIDTH-1:0] data;
    } flit_t;

    typedef struct packed {
        logic                   valid;
        logic [VC_ID_W-1:0]    vc_id;
    } credit_t;

    localparam int TX_TABLE_ENTRIES = 32;
    localparam int TX_ID_W          = 5;
    localparam int DATA_WIDTH       = 256;
    localparam int ADDR_WIDTH       = 32;
    localparam int CACHE_LINE_BYTES = 64;
    localparam int FLITS_PER_LINE   = (CACHE_LINE_BYTES * 8) / FLIT_WIDTH;

    function automatic logic is_at_boundary_x_pos(coord_t c);
        is_at_boundary_x_pos = (c.x == COORD_X_W'(MESH_X - 1));
    endfunction

    function automatic logic is_at_boundary_x_neg(coord_t c);
        is_at_boundary_x_neg = (c.x == 0);
    endfunction

    function automatic logic is_at_boundary_y_pos(coord_t c);
        is_at_boundary_y_pos = (c.y == COORD_Y_W'(MESH_Y - 1));
    endfunction

    function automatic logic is_at_boundary_y_neg(coord_t c);
        is_at_boundary_y_neg = (c.y == 0);
    endfunction

    function automatic logic is_at_boundary_z_pos(coord_t c);
        is_at_boundary_z_pos = (c.z == COORD_Z_W'(MESH_Z - 1));
    endfunction

    function automatic logic is_at_boundary_z_neg(coord_t c);
        is_at_boundary_z_neg = (c.z == 0);
    endfunction

endpackage

