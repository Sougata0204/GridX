
`default_nettype none
`timescale 1ns/1ns

import gridxPkg::*;
import gridx_mem_pkg::*;

module gridxPluginTop #(
    parameter CUBE_X = 2,
    parameter CUBE_Y = 2,
    parameter CUBE_Z = 2,
    parameter WARPS_PER_CORE = 1,
    parameter THREADS_PER_BLOCK = 4
) (
    input  wire clk,
    input  wire reset,
    input  wire start,
    output wire done,

    input  wire deviceControlWriteEnable,
    input  wire [15:0] deviceControlData,

    output wire [31:0] hbmReads,
    output wire [31:0] hbmWrites,
    output wire [31:0] totalFlitsForwarded
);

    localparam NUM_CORES = CUBE_X * CUBE_Y * CUBE_Z;
    localparam DATA_MEM_ADDR_BITS = 22;
    localparam DATA_MEM_DATA_BITS = 8;
    localparam PROGRAM_MEM_ADDR_BITS = 12;
    localparam PROGRAM_MEM_DATA_BITS = 16;
    localparam PROGRAM_MEM_NUM_CHANNELS = 16;

    wire [PROGRAM_MEM_NUM_CHANNELS-1:0] pmReadValid;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] pmReadAddress [PROGRAM_MEM_NUM_CHANNELS-1:0];
    reg  [PROGRAM_MEM_NUM_CHANNELS-1:0] pmReadReady;
    reg  [PROGRAM_MEM_DATA_BITS-1:0] pmReadData [PROGRAM_MEM_NUM_CHANNELS-1:0];

    wire [NUM_CORES-1:0] dmReadValid;
    wire [DATA_MEM_ADDR_BITS-1:0] dmReadAddress [NUM_CORES-1:0];
    wire [NUM_CORES-1:0] dmReadReady;
    wire [DATA_MEM_DATA_BITS-1:0] dmReadData [NUM_CORES-1:0];

    wire [NUM_CORES-1:0] dmWriteValid;
    wire [DATA_MEM_ADDR_BITS-1:0] dmWriteAddress [NUM_CORES-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] dmWriteData [NUM_CORES-1:0];
    wire [NUM_CORES-1:0] dmWriteReady;

    gpu #(
        .NUM_CORES(NUM_CORES),
        .CUBE_X(CUBE_X), .CUBE_Y(CUBE_Y), .CUBE_Z(CUBE_Z),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .WARPS_PER_CORE(WARPS_PER_CORE),
        .PROGRAM_MEM_NUM_CHANNELS(CUBE_X * CUBE_Y * CUBE_Z)
    ) uGpu (
        .clk(clk), .reset(reset), .start(start), .done(done),
        .deviceControlWriteEnable(deviceControlWriteEnable),
        .deviceControlData(deviceControlData),

        .programMemReadValid(pmReadValid),
        .programMemReadAddress(pmReadAddress),
        .programMemReadReady(pmReadReady),
        .programMemReadData(pmReadData),

        .coreMemReadValid(dmReadValid),
        .coreMemReadAddress(dmReadAddress),
        .coreMemReadReady(dmReadReady),
        .coreMemReadData(dmReadData),

        .coreMemWriteValid(dmWriteValid),
        .coreMemWriteAddress(dmWriteAddress),
        .coreMemWriteData(dmWriteData),
        .coreMemWriteReady(dmWriteReady)
    );

    integer pi;
    always @(posedge clk) begin
        pmReadReady <= 0;
        for (pi = 0; pi < CUBE_X * CUBE_Y * CUBE_Z; pi = pi + 1) begin
            if (pmReadValid[pi]) begin
                pmReadReady[pi] <= 1;
                if (pmReadAddress[pi] == 12'h005) pmReadData[pi] <= 16'hF000;
                else pmReadData[pi] <= 16'h0000;
            end
        end
    end

    flit_t   [gridx_mem_pkg::NUM_NODES-1:0] localFlitIn;
    logic    [gridx_mem_pkg::NUM_NODES-1:0] localFlitInValid;
    credit_t [gridx_mem_pkg::NUM_NODES-1:0] localCreditOut;

    flit_t   [gridx_mem_pkg::NUM_NODES-1:0] localFlitOut;
    logic    [gridx_mem_pkg::NUM_NODES-1:0] localFlitOutValid;
    credit_t [gridx_mem_pkg::NUM_NODES-1:0] localCreditIn;

    mem_mesh_top uMesh (
        .clk_layer(clk), .rst_n(~reset),
        .local_flit_in(localFlitIn), .local_flit_in_valid(localFlitInValid),
        .local_credit_out(localCreditOut),
        .local_flit_out(localFlitOut), .local_flit_out_valid(localFlitOutValid),
        .local_credit_in(localCreditIn)
    );

    localparam NUM_HBM_NODES = 2;
    localparam HBM_NODE_BASE = NUM_CORES - NUM_HBM_NODES;

    wire [NUM_CORES-1:0] isHbmNode;
    genvar hb;
    generate
        for (hb = 0; hb < NUM_CORES; hb = hb + 1) begin : hbmFlag
            assign isHbmNode[hb] = (hb >= HBM_NODE_BASE);
        end
    endgenerate

    genvar n;
    generate
        for (n = 0; n < HBM_NODE_BASE; n = n + 1) begin : coreBridges
            wire bridgeTxValid;
            wire [511:0] bridgeTxData;
            wire [1:0] bridgeTxFlitType;
            wire [1:0] bridgeTxVcId;

            wire bridgeRxValid;
            wire [511:0] bridgeRxData;
            wire [1:0] bridgeRxFlitType;
            wire [1:0] bridgeRxVcId;
            wire bridgeRxCreditValid;
            wire [1:0] bridgeRxCreditVcId;

            localparam [$clog2(CUBE_X+1)-1:0] myX = n % CUBE_X;
            localparam [$clog2(CUBE_Y+1)-1:0] myY = (n / CUBE_X) % CUBE_Y;
            localparam [$clog2(CUBE_Z+1)-1:0] myZ = n / (CUBE_X * CUBE_Y);

            memMeshBridge #(
                .NUM_GPU_CHANNELS(1),
                .ADDR_BITS(DATA_MEM_ADDR_BITS),
                .DATA_BITS(DATA_MEM_DATA_BITS),
                .MESH_COORD_W(4)
            ) uBridge (
                .clk(clk), .reset(reset),
                .gpuReadValid(dmReadValid[n]),
                .gpuReadAddress('{dmReadAddress[n]}),
                .gpuReadReady(dmReadReady[n]),
                .gpuReadData('{dmReadData[n]}),
                .gpuWriteValid(dmWriteValid[n]),
                .gpuWriteAddress('{dmWriteAddress[n]}),
                .gpuWriteData('{dmWriteData[n]}),
                .gpuWriteReady(dmWriteReady[n]),
                .meshTxValid(bridgeTxValid),
                .meshTxData(bridgeTxData),
                .meshTxFlitType(bridgeTxFlitType),
                .meshTxVcId(bridgeTxVcId),
                .meshTxCreditValid(localCreditOut[n].valid),
                .meshTxCreditVcId(localCreditOut[n].vc_id),
                .meshRxValid(bridgeRxValid),
                .meshRxData(bridgeRxData),
                .meshRxFlitType(bridgeRxFlitType),
                .meshRxVcId(bridgeRxVcId),
                .meshRxCreditValid(bridgeRxCreditValid),
                .meshRxCreditVcId(bridgeRxCreditVcId),
                .myX(myX), .myY(myY), .myZ(myZ),
                .outstandingCount(),
                .bridgeBusy()
            );

            assign localFlitInValid[n] = bridgeTxValid;
            assign localFlitIn[n].data = bridgeTxData;
            assign localFlitIn[n].flit_type = flit_type_e'(bridgeTxFlitType);
            assign localFlitIn[n].vc_id = bridgeTxVcId;

            assign bridgeRxValid = localFlitOutValid[n];
            assign bridgeRxData = localFlitOut[n].data;
            assign bridgeRxFlitType = localFlitOut[n].flit_type;
            assign bridgeRxVcId = localFlitOut[n].vc_id;

            assign localCreditIn[n].valid = bridgeRxCreditValid;
            assign localCreditIn[n].vc_id = bridgeRxCreditVcId;
        end
    endgenerate

    wire [31:0] hbmTotalReads [NUM_HBM_NODES-1:0];
    wire [31:0] hbmTotalWrites [NUM_HBM_NODES-1:0];

    genvar h;
    generate
        for (h = 0; h < NUM_HBM_NODES; h = h + 1) begin : hbmNodes
            localparam HN = HBM_NODE_BASE + h;

            wire [511:0] hbmRespData;
            wire [31:0] hbmRespAddr;
            wire hbmRespValid;
            wire hbmReady;

            wire [31:0] hbmReqAddr = localFlitOut[HN].data[31:0];
            wire [511:0] hbmReqWdata = localFlitOut[HN].data;
            wire hbmReqWrite = (localFlitOut[HN].vc_id == gridx_mem_pkg::VC_WRITE_REQ);

            hbm3Ctrl uHbm (
                .clk(clk), .reset(reset),
                .reqValid(localFlitOutValid[HN]),
                .reqAddr(hbmReqAddr),
                .reqWdata(hbmReqWdata),
                .reqWrite(hbmReqWrite),
                .reqReady(hbmReady),
                .respValid(hbmRespValid),
                .respData(hbmRespData),
                .respAddr(hbmRespAddr),
                .totalReads(hbmTotalReads[h]),
                .totalWrites(hbmTotalWrites[h]),
                .phyReadValid(~hbmReqWrite & localFlitOutValid[HN]),
                .phyReadData({512{1'b1}})
            );

            assign localCreditIn[HN].valid = hbmReady;
            assign localCreditIn[HN].vc_id = 2'd0;

            always @(posedge clk) begin
                if (hbmRespValid) begin
                    localFlitInValid[HN] <= 1;
                    localFlitIn[HN].data <= hbmRespData;
                    localFlitIn[HN].flit_type <= gridx_mem_pkg::FLIT_TAIL;
                    localFlitIn[HN].vc_id <= gridx_mem_pkg::VC_MEM_RESP;
                end else begin
                    localFlitInValid[HN] <= 0;
                end
            end
        end
    endgenerate

    reg [31:0] hbmReadsSum;
    reg [31:0] hbmWritesSum;
    integer si;
    always @(*) begin
        hbmReadsSum = 0;
        hbmWritesSum = 0;
        for (si = 0; si < NUM_HBM_NODES; si = si + 1) begin
            hbmReadsSum = hbmReadsSum + hbmTotalReads[si];
            hbmWritesSum = hbmWritesSum + hbmTotalWrites[si];
        end
    end
    assign hbmReads = hbmReadsSum;
    assign hbmWrites = hbmWritesSum;
    assign totalFlitsForwarded = hbmReads + hbmWrites;

endmodule
