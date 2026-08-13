
`default_nettype none
`timescale 1ns/1ns

module memMeshBridge #(
    parameter NUM_GPU_CHANNELS  = 1,
    parameter ADDR_BITS         = 22,
    parameter DATA_BITS         = 8,
    parameter MESH_FLIT_WIDTH   = 256,
    parameter MESH_VC_ID_W      = 2,
    parameter MESH_COORD_W      = 2,
    parameter TX_TABLE_ENTRIES  = 4,
    parameter TX_ID_W           = 5,
    parameter NUM_HBM_NODES = 2,
    parameter HBM_BASE_NODE = 6,
    parameter MESH_X = 2,
    parameter MESH_Y = 2
) (
    input  wire clk,
    input  wire reset,

    input  wire [NUM_GPU_CHANNELS-1:0]  gpuReadValid,
    input  wire [ADDR_BITS-1:0]         gpuReadAddress  [NUM_GPU_CHANNELS-1:0],
    output reg  [NUM_GPU_CHANNELS-1:0]  gpuReadReady,
    output reg  [DATA_BITS-1:0]         gpuReadData     [NUM_GPU_CHANNELS-1:0],

    input  wire [NUM_GPU_CHANNELS-1:0]  gpuWriteValid,
    input  wire [ADDR_BITS-1:0]         gpuWriteAddress [NUM_GPU_CHANNELS-1:0],
    input  wire [DATA_BITS-1:0]         gpuWriteData    [NUM_GPU_CHANNELS-1:0],
    output wire [NUM_GPU_CHANNELS-1:0]  gpuWriteReady,

    output reg                          meshTxValid,
    output reg  [MESH_FLIT_WIDTH-1:0]   meshTxData,
    output reg  [1:0]                   meshTxFlitType,
    output reg  [MESH_VC_ID_W-1:0]      meshTxVcId,
    input  wire                         meshTxCreditValid,
    input  wire [MESH_VC_ID_W-1:0]      meshTxCreditVcId,

    input  wire                         meshRxValid,
    input  wire [MESH_FLIT_WIDTH-1:0]   meshRxData,
    input  wire [1:0]                   meshRxFlitType,
    input  wire [MESH_VC_ID_W-1:0]      meshRxVcId,
    output reg                          meshRxCreditValid,
    output reg  [MESH_VC_ID_W-1:0]      meshRxCreditVcId,

    input  wire [MESH_COORD_W-1:0]      myX,
    input  wire [MESH_COORD_W-1:0]      myY,
    input  wire [MESH_COORD_W-1:0]      myZ,

    output wire [6:0]                   outstandingCount,
    output wire                         bridgeBusy,
    output wire                         bridgeCreditsFull
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
    } txStateE;

    txStateE           txState;

    reg [TX_TABLE_ENTRIES-1:0]  txActive;
    reg [$clog2(NUM_GPU_CHANNELS)-1:0] txSrcChannel [TX_TABLE_ENTRIES-1:0];
    reg [TX_TABLE_ENTRIES-1:0]  txIsWrite;
    reg [6:0]                   txCount;
    reg [4:0]                   meshTxCredits [3:0];

    assign outstandingCount = txCount;
    assign bridgeBusy       = (txCount > 0) || (txState != TX_IDLE);
    // Assumes FLITS_PER_BUFFER = 8 for the VC
    assign bridgeCreditsFull = (meshTxCredits[VC_WRITE] == 5'd8);

    reg [$clog2(NUM_GPU_CHANNELS)-1:0] txWinner;
    reg                  txWinnerIsWrite;
    reg [ADDR_BITS-1:0]  txWinnerAddr;
    reg [DATA_BITS-1:0]  txWinnerWdata;
    reg [TX_ID_W-1:0]    txAllocId;

    reg [TX_ID_W-1:0]    freeTxId;
    reg                  txTableFull;

    always @(*) begin
        freeTxId    = 0;
        txTableFull = 1;
        for (integer t = 0; t < TX_TABLE_ENTRIES; t = t + 1) begin
            if (!txActive[t] && txTableFull) begin
                freeTxId    = t[TX_ID_W-1:0];
                txTableFull = 0;
            end
        end
    end

    reg [CH_ID_W-1:0] rrPtr;
    reg [CH_ID_W-1:0] arbWinner;
    reg                                arbFound;
    reg                                arbIsWrite;

    always @(*) begin
        arbFound    = 0;
        arbWinner   = 0;
        arbIsWrite = 0;
        for (integer ch = 0; ch < NUM_GPU_CHANNELS; ch = ch + 1) begin
            automatic integer idx = (rrPtr + ch) % NUM_GPU_CHANNELS;
            if (!arbFound) begin
                if (gpuWriteValid[idx]) begin
                    arbFound    = 1;
                    arbWinner   = idx[CH_ID_W-1:0];
                    arbIsWrite = 1;
                end else if (gpuReadValid[idx]) begin
                    arbFound    = 1;
                    arbWinner   = idx[CH_ID_W-1:0];
                    arbIsWrite = 0;
                end
            end
        end
    end

    reg [MESH_COORD_W-1:0] hbmDestX;
    reg [MESH_COORD_W-1:0] hbmDestY;
    reg [MESH_COORD_W-1:0] hbmDestZ;

    always @(*) begin
        automatic integer hbmSel = txWinnerAddr[6:5]; // Interleave across controllers
        automatic integer hbmNode = HBM_BASE_NODE + (hbmSel % NUM_HBM_NODES);
        hbmDestX = hbmNode % MESH_X;
        hbmDestY = (hbmNode / MESH_X) % MESH_Y;
        hbmDestZ = hbmNode / (MESH_X * MESH_Y);
    end

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            txState            <= TX_IDLE;
            meshTxValid       <= 0;
            meshTxData        <= 0;
            meshTxFlitType   <= 0;
            meshTxVcId       <= 0;
            gpuReadReady      <= 0;
            txActive           <= 0;
            txCount            <= 0;
            rrPtr              <= 0;
            for (i = 0; i < TX_TABLE_ENTRIES; i = i + 1) begin
                txSrcChannel[i] <= 0;
                txIsWrite[i]    <= 0;
            end
            for (i = 0; i < 4; i = i + 1) begin
                meshTxCredits[i] <= 5'd8;
            end
        end else begin
            automatic reg [4:0] nextCredits [3:0];

            gpuReadReady  <= 0;
            meshTxValid   <= 0;

            for (i=0; i<4; i=i+1) nextCredits[i] = meshTxCredits[i];

            if (meshTxCreditValid) begin
                nextCredits[meshTxCreditVcId] = nextCredits[meshTxCreditVcId] + 1;
            end

            case (txState)
                TX_IDLE: begin
                    if (arbFound && !txTableFull) begin
                        txWinner          <= arbWinner;
                        txWinnerIsWrite <= arbIsWrite;
                        txWinnerAddr     <= arbIsWrite ?
                                              gpuWriteAddress[arbWinner] :
                                              gpuReadAddress[arbWinner];
                        txWinnerWdata    <= arbIsWrite ?
                                              gpuWriteData[arbWinner] : 8'd0;
                        txAllocId        <= freeTxId;
                        txState           <= TX_SEND_HEAD;
                    end
                end

                TX_SEND_HEAD: begin
                    automatic reg [MESH_VC_ID_W-1:0] vc =
                        txWinnerIsWrite ? VC_WRITE : VC_READ;

                    if (nextCredits[vc] > 0) begin
                        meshTxValid     <= 1;
                        meshTxFlitType <= FLIT_HEAD;
                        meshTxVcId     <= vc;

                        begin
                            reg [MESH_FLIT_WIDTH-1:0] flitData;
                            flitData = 256'd0;
                            flitData[31:0]    = {10'd0, txWinnerAddr};
                            flitData[39:32]   = txWinnerWdata;
                            flitData[112:111] = hbmDestZ[1:0];
                            flitData[114:113] = hbmDestY[1:0];
                            flitData[116:115] = hbmDestX[1:0];
                            flitData[125:121] = txAllocId;
                            flitData[250:245] = {myZ[1:0], myY[1:0], myX[1:0]};
                            flitData[252:251] = vc;
                            flitData[255:253] = txWinnerIsWrite ? 3'b001 : 3'b000;
                            meshTxData <= flitData;
                        end

                        nextCredits[vc] = nextCredits[vc] - 1;

                        txActive[txAllocId]      <= 1;
                        txSrcChannel[txAllocId] <= txWinner;
                        txIsWrite[txAllocId]    <= txWinnerIsWrite;
                        txCount                    <= txCount + 1;

                        txState <= TX_SEND_TAIL;
                    end
                end

                TX_SEND_TAIL: begin
                    automatic reg [MESH_VC_ID_W-1:0] vc =
                        txWinnerIsWrite ? VC_WRITE : VC_READ;

                    if (nextCredits[vc] > 0) begin
                        meshTxValid     <= 1;
                        meshTxFlitType <= FLIT_TAIL;
                        meshTxVcId     <= vc;

                        begin
                            reg [MESH_FLIT_WIDTH-1:0] tailData;
                            tailData = 256'd0;
                            tailData[31:0]    = {10'd0, txWinnerAddr};
                            tailData[125:121] = txAllocId;
                            meshTxData <= tailData;
                        end

                        nextCredits[vc] = nextCredits[vc] - 1;

                        if (txWinnerIsWrite) begin
                            // gpuWriteReady is now driven combinatorially (see bottom of file)
                            txActive[txAllocId] <= 0;
                            txCount <= txCount - 1;
                        end else begin

                        end

                        rrPtr   <= (txWinner + 1) % NUM_GPU_CHANNELS;
                        txState <= TX_IDLE;
                    end
                end

                default: txState <= TX_IDLE;
            endcase

            for (i=0; i<4; i=i+1) meshTxCredits[i] <= nextCredits[i];
        end
    end

    reg [TX_ID_W-1:0] rxPendingTxId;

    always @(posedge clk) begin
        if (reset) begin
            meshRxCreditValid <= 0;
            meshRxCreditVcId <= 0;
            rxPendingTxId     <= 0;
        end else begin
            meshRxCreditValid <= 0;

            if (meshRxValid) begin

                meshRxCreditValid <= 1;
                meshRxCreditVcId <= meshRxVcId;

                if (meshRxFlitType == FLIT_HEAD) begin

                    rxPendingTxId <= meshRxData[125:121];
                end
                else if (meshRxFlitType == FLIT_TAIL) begin

                    automatic reg [TX_ID_W-1:0] tid = rxPendingTxId;
                    automatic integer srcCh = txSrcChannel[tid];

                    if (!txIsWrite[tid]) begin

                        gpuReadReady[srcCh] <= 1;
                        gpuReadData[srcCh]  <= meshRxData[DATA_BITS-1:0];
                    end

                    txActive[tid] <= 0;
                    txCount       <= txCount - 1;
                end
            end
        end
    end

`ifdef VERILATOR
    always @(posedge clk) begin
        if (!reset) begin
            if (txCount > TX_TABLE_ENTRIES) begin
                $display("ERROR: memMeshBridge TX overflow! count=%0d", txCount);
            end
        end
    end
`endif

    // Combinatorial assignment for gpuWriteReady
    reg [NUM_GPU_CHANNELS-1:0] gpuWriteReadyComb;
    always @(*) begin
        gpuWriteReadyComb = 0;
        if (txState == TX_SEND_TAIL) begin
            automatic reg [MESH_VC_ID_W-1:0] vc = txWinnerIsWrite ? VC_WRITE : VC_READ;
            if (meshTxCredits[vc] > 0) begin
                if (txWinnerIsWrite) begin
                    gpuWriteReadyComb[txWinner] = 1;
                end
            end
        end
    end
    assign gpuWriteReady = gpuWriteReadyComb;

endmodule
