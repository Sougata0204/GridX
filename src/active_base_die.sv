
`default_nettype none
`timescale 1ns/1ns

import gridxConfigPkg::*;

module activeBaseDie #(
    parameter NUM_COMPUTE_DIES = CFG_CUBE_Z,
    parameter CORES_PER_DIE    = CFG_CUBE_X * CFG_CUBE_Y,
    parameter TOTAL_CORES      = CFG_NUM_CORES,
    parameter ADDR_WIDTH       = CFG_DATA_MEM_ADDR_BITS,
    parameter DATA_WIDTH       = CFG_DATA_MEM_DATA_BITS,
    parameter TSV_DATA_WIDTH   = CFG_TSV_DATA_WIDTH,
    parameter NUM_HBM_NODES    = CFG_NUM_HBM_NODES,
    parameter NUM_NMC_ENGINES  = NUM_HBM_NODES
) (
    input  wire        clk,
    input  wire        reset,

    // TSV Interface (to/from compute dies above)
    input  wire [TOTAL_CORES-1:0]              tsvRxValid,
    input  wire [TSV_DATA_WIDTH-1:0]           tsvRxData  [TOTAL_CORES-1:0],
    output wire [TOTAL_CORES-1:0]              tsvTxValid,
    output wire [TSV_DATA_WIDTH-1:0]           tsvTxData  [TOTAL_CORES-1:0],

    // Host Interface
    input  wire                                hostCmdValid,
    input  wire [127:0]                        hostCmdData,
    output wire                                hostCmdReady,

    // MMU Translation Interface
    input  wire                                translateValid,
    input  wire [CFG_VIRTUAL_ADDR_BITS-1:0]    translateVaddr,
    input  wire [7:0]                          translateAsid,
    input  wire                                translateWrite,
    output wire                                translateReady,
    output wire [CFG_PHYSICAL_ADDR_BITS-1:0]   translatePaddr,
    output wire                                translateFault,
    input  wire [CFG_PHYSICAL_ADDR_BITS-1:0]   pageTableBase,
    input  wire                                tlbInvalidateAll,

    // NMC Command & Status Interfaces
    input  wire [NUM_NMC_ENGINES-1:0]          nmcCmdValid,
    input  wire [3:0]                          nmcCmdOpcode [NUM_NMC_ENGINES-1:0],
    input  wire [31:0]                         nmcCmdAddr   [NUM_NMC_ENGINES-1:0],
    input  wire [15:0]                         nmcCmdLength [NUM_NMC_ENGINES-1:0],
    output wire [NUM_NMC_ENGINES-1:0]          nmcCmdReady,
    output wire [NUM_NMC_ENGINES-1:0]          nmcResultValid,
    output wire [255:0]                        nmcResultData [NUM_NMC_ENGINES-1:0],
    output wire [NUM_NMC_ENGINES-1:0]          nmcBusy,

    // NMC Memory Access Ports (to HBM stacks)
    output wire [NUM_NMC_ENGINES-1:0]          nmcMemReadValid,
    output wire [31:0]                         nmcMemReadAddr  [NUM_NMC_ENGINES-1:0],
    input  wire [NUM_NMC_ENGINES-1:0]          nmcMemReadReady,
    input  wire [255:0]                        nmcMemReadData  [NUM_NMC_ENGINES-1:0],
    output wire [NUM_NMC_ENGINES-1:0]          nmcMemWriteValid,
    output wire [31:0]                         nmcMemWriteAddr [NUM_NMC_ENGINES-1:0],
    output wire [255:0]                        nmcMemWriteData [NUM_NMC_ENGINES-1:0],
    input  wire [NUM_NMC_ENGINES-1:0]          nmcMemWriteReady,

    // HCP Launch / Complete Interface
    output wire                                hcpLaunchValid,
    output wire [4:0]                          hcpLaunchTaskId,
    output wire [CFG_HCP_CMD_WIDTH-1:0]        hcpLaunchCmd,
    input  wire                                hcpLaunchAck,
    input  wire                                hcpCompleteValid,
    input  wire [4:0]                          hcpCompleteTaskId,

    // HBM PHY Interface (to package)
    output wire [NUM_HBM_NODES-1:0]            hbmPhyActive,
    output wire [31:0]                         hbmTotalReads,
    output wire [31:0]                         hbmTotalWrites,

    // External DRAM Interface
    output wire                                dramReqValid,
    output wire [39:0]                         dramReqAddr,
    output wire [255:0]                        dramReqWdata,
    output wire [2:0]                          dramReqCmd,
    input  wire                                dramReqReady,
    input  wire                                dramRespValid,
    input  wire [255:0]                        dramRespData,

    // Status
    output wire                                baseDieReady,
    output wire [31:0]                         nmcOpsCompleted,
    output wire                                hcpBusy,
    output wire                                hcpGraphDone
);

    // TSV BRIDGE ARRAY
    genvar t;
    generate
        for (t = 0; t < TOTAL_CORES; t = t + 1) begin : tsvBridges
            tsvBridge #(
                .DATA_WIDTH     (TSV_DATA_WIDTH),
                .LATENCY_CYCLES (CFG_TSV_LATENCY_CYCLES),
                .BUFFER_DEPTH   (4)
            ) uTsv (
                .clk            (clk),
                .reset          (reset),
                // Transmit path (base -> compute)
                .txValid       (tsvTxValid[t]),
                .txData        (tsvTxData[t]),
                .txReady       (),
                // Receive path (compute -> base)
                .rxValid       (),
                .rxData        (),
                .rxReady       (1'b1),
                // TSV physical pins
                .tsvOutValid  (),
                .tsvOutData   (),
                .tsvInValid   (tsvRxValid[t]),
                .tsvInData    (tsvRxData[t]),
                // Perf
                .perfTxCount  (),
                .perfRxCount  (),
                .perfStallCycles(),
                .linkUp        ()
            );
        end
    endgenerate

    // MMU / TLB
    wire        ptwMemReadValid;
    wire [39:0] ptwMemReadAddr;
    wire        ptwMemReadReady;
    wire [63:0] ptwMemReadData;

    mmu #(
        .VIRTUAL_ADDR_BITS  (CFG_VIRTUAL_ADDR_BITS),
        .PHYSICAL_ADDR_BITS (CFG_PHYSICAL_ADDR_BITS),
        .PAGE_OFFSET_BITS   (CFG_PAGE_OFFSET_BITS),
        .TLB_ENTRIES        (CFG_TLB_ENTRIES),
        .ASID_BITS          (8)
    ) uMmu (
        .clk                (clk),
        .reset              (reset),
        .translateValid    (translateValid),
        .translateVaddr    (translateVaddr),
        .translateAsid     (translateAsid),
        .translateWrite    (translateWrite),
        .translateReady    (translateReady),
        .translatePaddr    (translatePaddr),
        .translateFault    (translateFault),
        .ptwMemReadValid (ptwMemReadValid),
        .ptwMemReadAddr  (ptwMemReadAddr),
        .ptwMemReadReady (ptwMemReadReady),
        .ptwMemReadData  (ptwMemReadData),
        .pageTableBase    (pageTableBase),
        .tlbInvalidateAll (tlbInvalidateAll),
        .perfTlbHits      (),
        .perfTlbMisses    (),
        .perfPageFaults   ()
    );

    // NEAR-MEMORY COMPUTE ENGINES (one per HBM node)
    wire [31:0] nmcOps [NUM_NMC_ENGINES-1:0];

    genvar nm;
    generate
        for (nm = 0; nm < NUM_NMC_ENGINES; nm = nm + 1) begin : nmcEngines
            nmcEngine #(
                .DATA_WIDTH      (256),
                .REDUCTION_WIDTH (32),
                .QUEUE_DEPTH     (CFG_NMC_QUEUE_DEPTH),
                .NUM_ALUS        (CFG_NMC_ALU_COUNT)
            ) uNmc (
                .clk              (clk),
                .reset            (reset),
                .cmdValid        (nmcCmdValid[nm]),
                .cmdOpcode       (nmcCmdOpcode[nm]),
                .cmdAddr         (nmcCmdAddr[nm]),
                .cmdLength       (nmcCmdLength[nm]),
                .cmdReady        (nmcCmdReady[nm]),
                .resultValid     (nmcResultValid[nm]),
                .resultData      (nmcResultData[nm]),
                .memReadValid   (nmcMemReadValid[nm]),
                .memReadAddr    (nmcMemReadAddr[nm]),
                .memReadReady   (nmcMemReadReady[nm]),
                .memReadData    (nmcMemReadData[nm]),
                .memWriteValid  (nmcMemWriteValid[nm]),
                .memWriteAddr   (nmcMemWriteAddr[nm]),
                .memWriteData   (nmcMemWriteData[nm]),
                .memWriteReady  (nmcMemWriteReady[nm]),
                .busy             (nmcBusy[nm]),
                .perfOpsCompleted(nmcOps[nm])
            );
        end
    endgenerate

    // Aggregate NMC ops
    reg [31:0] nmcOpsSum;
    integer nmi;
    always @(*) begin
        nmcOpsSum = 32'd0;
        for (nmi = 0; nmi < NUM_NMC_ENGINES; nmi = nmi + 1)
            nmcOpsSum = nmcOpsSum + nmcOps[nmi];
    end
    assign nmcOpsCompleted = nmcOpsSum;

    // HARDWARE COMMAND PROCESSOR
    hwCommandProcessor #(
        .MAX_TASKS     (CFG_HCP_MAX_TASKS),
        .MAX_DEPS      (CFG_HCP_MAX_DEPS),
        .CMD_WIDTH     (CFG_HCP_CMD_WIDTH),
        .TASK_ID_WIDTH (5)
    ) uHcp (
        .clk              (clk),
        .reset            (reset),
        .submitValid     (hostCmdValid),
        .submitTaskId   (hostCmdData[4:0]),
        .submitCmd       (hostCmdData[127:0]),
        .submitDepCount (hostCmdData[7:5]),
        .submitDepIds   (hostCmdData[27:8]),
        .submitReady     (hostCmdReady),
        .launchValid     (hcpLaunchValid),
        .launchTaskId   (hcpLaunchTaskId),
        .launchCmd       (hcpLaunchCmd),
        .launchAck       (hcpLaunchAck),
        .completeValid   (hcpCompleteValid),
        .completeTaskId (hcpCompleteTaskId),
        .busy             (hcpBusy),
        .tasksPending    (),
        .tasksCompleted  (),
        .graphDone       (hcpGraphDone)
    );

    // EXTERNAL DRAM CONTROLLER
    wire [255:0] dramRespData256;
    assign ptwMemReadData = dramRespData256[63:0];

    wire [2:0] dramPhyCmd;
    assign dramReqCmd = dramPhyCmd;

    dramCtrl #(
        .ADDR_WIDTH    (40),
        .DATA_WIDTH    (256),
        .BURST_LENGTH  (8),
        .NUM_RANKS     (2)
    ) uDram (
        .clk            (clk),
        .reset          (reset),
        .reqValid      (ptwMemReadValid),
        .reqAddr       (ptwMemReadAddr),
        .reqWdata      (256'd0),
        .reqWrite      (1'b0),
        .reqReady      (),
        .respValid     (ptwMemReadReady),
        .respData      (dramRespData256),
        .respAddr      (),
        .phyCmdValid  (dramReqValid),
        .phyCmd        (dramPhyCmd),
        .phyAddr       (dramReqAddr),
        .phyWdata      (dramReqWdata),
        .phyRdata      (dramRespData),
        .phyRdataValid(dramRespValid),
        .busy           (),
        .totalReads    (),
        .totalWrites   (),
        .rowHits       (),
        .rowMisses     ()
    );

    // STATUS
    assign baseDieReady  = ~reset;
    assign hbmPhyActive  = {NUM_HBM_NODES{1'b1}};
    assign hbmTotalReads = 32'd0;
    assign hbmTotalWrites = 32'd0;

endmodule
