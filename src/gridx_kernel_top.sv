`default_nettype none
`timescale 1ns/1ns

import gridxPkg::*;
import gridx_mem_pkg::*;

// GridX kernel top-level integrating 3D core mesh, NoC routers, HBM controllers, and memory subsystem into the full SoC.
module gridxKernelTop #(
    parameter CUBE_X               = 2,
    parameter CUBE_Y               = 2,
    parameter CUBE_Z               = 2,
    parameter NUM_CORES            = CUBE_X * CUBE_Y * CUBE_Z,

    parameter DATA_MEM_ADDR_BITS   = 22,
    parameter DATA_MEM_DATA_BITS   = 8,
    parameter PROG_MEM_ADDR_BITS   = 12,
    parameter PROG_MEM_DATA_BITS   = 16,
    parameter PROG_MEM_CHANNELS    = NUM_CORES,

    parameter THREADS_PER_BLOCK    = 32,
    parameter WARPS_PER_CORE       = 4,

    parameter NUM_HBM_NODES        = 2,

    parameter PMEM_DEPTH           = 4096,
    parameter DMEM_DEPTH           = 8192,

    parameter [DATA_MEM_ADDR_BITS-1:0] LOCAL_MEM_RANGE = 22'h008FFF,

    parameter SIM_TIMEOUT_CYCLES   = 500_000
) (
    input  wire         clkSys,
    input  wire [CUBE_Z-1:0] clkLayer,
    input  wire         rstN,

    input  wire        hostWrEn,
    input  wire [15:0] hostWrData,
    input  wire        hostStart,

    output wire        kernelDone,
    output wire        kernelFault,
    output wire [2:0]  kernelStateO,

    output wire [31:0] perfHbmReads,
    output wire [31:0] perfHbmWrites,
    output wire [31:0] perfTotalFlits,
    output wire [31:0] perfCycleCount,
    output wire [31:0] perfActiveCores,
    output wire [31:0] perfNoCStallCycles,

    output wire [7:0]  dbgCoreDoneSample,
    output wire        dbgMeshBusy,

    input  wire                          pmemWrEn,
    input  wire [PROG_MEM_ADDR_BITS-1:0] pmemWrAddr,
    input  wire [PROG_MEM_DATA_BITS-1:0] pmemWrData,

    input  wire                           dmemWrEn,
    input  wire [DATA_MEM_ADDR_BITS-1:0]  dmemWrAddr,
    input  wire [DATA_MEM_DATA_BITS-1:0]  dmemWrData,
    input  wire                           dmemRdEn,
    input  wire [DATA_MEM_ADDR_BITS-1:0]  dmemRdAddr,
    output reg  [DATA_MEM_DATA_BITS-1:0]  dmemRdData
);

    wire clk   = clkSys;
    wire reset  = ~rstN;

    wire [PROG_MEM_CHANNELS-1:0]      pmRdValid;
    wire [PROG_MEM_ADDR_BITS-1:0]     pmRdAddr [PROG_MEM_CHANNELS-1:0];
    reg  [PROG_MEM_CHANNELS-1:0]      pmRdReady;
    reg  [PROG_MEM_DATA_BITS-1:0]     pmRdData [PROG_MEM_CHANNELS-1:0];

    wire [NUM_CORES-1:0]              dmRdValid;
    wire [DATA_MEM_ADDR_BITS-1:0]     dmRdAddr  [NUM_CORES-1:0];
    reg  [NUM_CORES-1:0]              dmRdReady;
    wire [NUM_CORES-1:0]              dmRdRespValid;
    assign dmRdRespValid = dmRdReady;
    wire [DATA_MEM_DATA_BITS-1:0]     dmRdData  [NUM_CORES-1:0];
    wire [NUM_CORES-1:0]              dmWrValid;
    wire [DATA_MEM_ADDR_BITS-1:0]     dmWrAddr  [NUM_CORES-1:0];
    wire [DATA_MEM_DATA_BITS-1:0]     dmWrData  [NUM_CORES-1:0];
    reg  [NUM_CORES-1:0]              dmWrReady;

    reg [PROG_MEM_DATA_BITS-1:0] progMem [0:PMEM_DEPTH-1];

    always @(posedge clk)
        if (pmemWrEn) progMem[pmemWrAddr] <= pmemWrData;

    integer pi;
    always @(posedge clk) begin
        for (pi = 0; pi < PROG_MEM_CHANNELS; pi = pi + 1) begin
            if (pmRdValid[pi]) begin
                pmRdReady[pi] <= 1'b1;
                pmRdData[pi]  <= progMem[pmRdAddr[pi]];
            end else begin
                pmRdReady[pi] <= 1'b0;
            end
        end
    end

    reg [DATA_MEM_DATA_BITS-1:0] dataMem [0:DMEM_DEPTH-1];

    always @(posedge clk) begin
        if (reset)
            dmemRdData <= {DATA_MEM_DATA_BITS{1'b0}};
        else if (dmemRdEn)
            dmemRdData <= dataMem[dmemRdAddr[$clog2(DMEM_DEPTH)-1:0]];
    end

    wire [NUM_CORES-1:0]              localRdValid;
    wire [DATA_MEM_ADDR_BITS-1:0]     localRdAddr  [NUM_CORES-1:0];
    wire [NUM_CORES-1:0]              localRdReady;
    wire [DATA_MEM_DATA_BITS-1:0]     localRdData  [NUM_CORES-1:0];
    
    wire [NUM_CORES-1:0]              localWrValid;
    wire [DATA_MEM_ADDR_BITS-1:0]     localWrAddr  [NUM_CORES-1:0];
    wire [DATA_MEM_DATA_BITS-1:0]     localWrData  [NUM_CORES-1:0];
    wire [NUM_CORES-1:0]              localWrReady;

    wire [NUM_CORES-1:0]              meshBrRdValid;
    wire [DATA_MEM_ADDR_BITS-1:0]     meshBrRdAddr  [NUM_CORES-1:0];
    wire [NUM_CORES-1:0]              meshBrRdReady;
    wire [NUM_CORES-1:0]              meshBrRdReqReady;
    wire [DATA_MEM_DATA_BITS-1:0]     meshBrRdData  [NUM_CORES-1:0];
    wire [NUM_CORES-1:0]              meshBrWrValid;
    wire [DATA_MEM_ADDR_BITS-1:0]     meshBrWrAddr  [NUM_CORES-1:0];
    wire [DATA_MEM_DATA_BITS-1:0]     meshBrWrData  [NUM_CORES-1:0];
    wire [NUM_CORES-1:0]              meshBrWrReady;
    wire [NUM_CORES-1:0]              meshCreditsFull;
    wire [NUM_CORES-1:0]              coreCreditsFull;

    wire [NUM_CORES-1:0]              dmRdReqReady;

    smartMemController #(
        .NUM_CORES(NUM_CORES),
        .ADDR_WIDTH(DATA_MEM_ADDR_BITS),
        .DATA_WIDTH(DATA_MEM_DATA_BITS),
        .LOCAL_MEM_RANGE(LOCAL_MEM_RANGE),
        .SEGMENT_CTRL_ADDR(22'h00FFF0)
    ) uSmartMemCtrl (
        .clk(clk),
        .reset(reset),
        
        .coreRdValid(dmRdValid),
        .coreRdAddr (dmRdAddr),
        .coreRdReady(dmRdReady),
        .coreRdReqReady(dmRdReqReady),
        .coreRdData (dmRdData),
        
        .coreWrValid(dmWrValid),
        .coreWrAddr (dmWrAddr),
        .coreWrData (dmWrData),
        .coreWrReady(dmWrReady),
        
        .meshRdValid(meshBrRdValid),
        .meshRdAddr (meshBrRdAddr),
        .meshRdReady(meshBrRdReady),
        .meshRdReqReady(meshBrRdReqReady),
        .meshRdData (meshBrRdData),
        
        .meshWrValid(meshBrWrValid),
        .meshWrAddr (meshBrWrAddr),
        .meshWrData (meshBrWrData),
        .meshWrReady(meshBrWrReady),
        .meshCreditsFull(meshCreditsFull),
        .coreCreditsFull(coreCreditsFull),
        
        .localRdValid(localRdValid),
        .localRdAddr (localRdAddr),
        .localRdReady(localRdReady),
        .localRdData (localRdData),
        
        .localWrValid(localWrValid),
        .localWrAddr (localWrAddr),
        .localWrData (localWrData),
        .localWrReady(localWrReady)
    );

    localparam CORE_IDX_W = (NUM_CORES > 1) ? $clog2(NUM_CORES) : 1;
    reg [CORE_IDX_W-1:0] dmemArbPtr;
    
    reg [CORE_IDX_W-1:0] nextArbPtr;
    reg selectedWr;
    reg selectedRd;
    reg [CORE_IDX_W-1:0] selectedIdx;

    always @(*) begin
        selectedWr = 0;
        selectedRd = 0;
        selectedIdx = 0;
        nextArbPtr = dmemArbPtr;

        for (int c = 0; c < NUM_CORES; c++) begin
            automatic integer idx = (dmemArbPtr + c) % NUM_CORES;
            if (!selectedWr && !selectedRd) begin
                if (localWrValid[idx]) begin
                    selectedWr = 1;
                    selectedIdx = idx;
                    nextArbPtr = (idx + 1) % NUM_CORES;
                end else if (localRdValid[idx]) begin
                    selectedRd = 1;
                    selectedIdx = idx;
                    nextArbPtr = (idx + 1) % NUM_CORES;
                end
            end
        end
    end

    genvar li;
    generate
        for (li = 0; li < NUM_CORES; li++) begin : genBramReady
            assign localWrReady[li] = (selectedWr && (selectedIdx == li));
            assign localRdReady[li] = (selectedRd && (selectedIdx == li));
            assign localRdData[li]  = dataMem[localRdAddr[li][$clog2(DMEM_DEPTH)-1:0]];
        end
    endgenerate

    always @(posedge clk) begin
        if (reset) begin
            dmemArbPtr <= 0;
        end else begin
            if (selectedWr || selectedRd) dmemArbPtr <= nextArbPtr;
            
            if (dmemWrEn) begin
                dataMem[dmemWrAddr[$clog2(DMEM_DEPTH)-1:0]] <= dmemWrData;
            end else if (selectedWr) begin
                dataMem[localWrAddr[selectedIdx][$clog2(DMEM_DEPTH)-1:0]] <= localWrData[selectedIdx];
            end
        end
    end

    wire [NUM_CORES-1:0][5:0] coreFaceReqValid;
    wire [NUM_CORES-1:0][5:0] coreFaceReqWrite;
    wire [NUM_CORES-1:0][5:0][DATA_MEM_ADDR_BITS-1:0] coreFaceReqAddr;
    wire [NUM_CORES-1:0][5:0][DATA_MEM_DATA_BITS-1:0] coreFaceReqWdata;
    wire [NUM_CORES-1:0][5:0] coreFaceReqReady;

    wire [NUM_CORES-1:0][5:0] coreFaceRespValid;
    wire [NUM_CORES-1:0][5:0][DATA_MEM_DATA_BITS-1:0] coreFaceRespRdata;
    wire [NUM_CORES-1:0][5:0] coreFaceRespReady;

    `define coreId(x,y,z) ((z) * CUBE_Y * CUBE_X + (y) * CUBE_X + (x))

    genvar gx, gy, gz;
    generate
        for (gz = 0; gz < CUBE_Z; gz = gz + 1) begin : genZX
            for (gy = 0; gy < CUBE_Y; gy = gy + 1) begin : genYX
                for (gx = 0; gx < CUBE_X - 1; gx = gx + 1) begin : genXSheets
                    localparam CORE_A = `coreId(gx, gy, gz);
                    localparam CORE_B = `coreId(gx+1, gy, gz);
                    
                    memorySheet #(
                        .ADDR_WIDTH(DATA_MEM_ADDR_BITS),
                        .DATA_WIDTH(DATA_MEM_DATA_BITS)
                    ) msX (
                        .clk(clkSys), .reset(reset),
                        .sideAReqValid(coreFaceReqValid[CORE_A][0]),
                        .sideAReqWrite(coreFaceReqWrite[CORE_A][0]),
                        .sideAReqAddr(coreFaceReqAddr[CORE_A][0]),
                        .sideAReqWdata(coreFaceReqWdata[CORE_A][0]),
                        .sideAReqReady(coreFaceReqReady[CORE_A][0]),
                        .sideARespValid(coreFaceRespValid[CORE_A][0]),
                        .sideARespRdata(coreFaceRespRdata[CORE_A][0]),
                        .sideARespReady(coreFaceRespReady[CORE_A][0]),
                        .sideBReqValid(coreFaceReqValid[CORE_B][1]),
                        .sideBReqWrite(coreFaceReqWrite[CORE_B][1]),
                        .sideBReqAddr(coreFaceReqAddr[CORE_B][1]),
                        .sideBReqWdata(coreFaceReqWdata[CORE_B][1]),
                        .sideBReqReady(coreFaceReqReady[CORE_B][1]),
                        .sideBRespValid(coreFaceRespValid[CORE_B][1]),
                        .sideBRespRdata(coreFaceRespRdata[CORE_B][1]),
                        .sideBRespReady(coreFaceRespReady[CORE_B][1]),
                        .nocReqValid(1'b0), .nocReqWrite(1'b0), .nocReqAddr('0), .nocReqWdata('0),
                        .nocReqReady(), .nocRespValid(), .nocRespRdata(), .nocRespReady(1'b1),
                        .perfReads(), .perfWrites(), .perfBankConflicts(),
                        .perfSideAAccesses(), .perfSideBAccesses(), .perfNocAccesses(), .perfMerges()
                    );
                end
            end
        end

        for (gz = 0; gz < CUBE_Z; gz = gz + 1) begin : genZY
            for (gy = 0; gy < CUBE_Y - 1; gy = gy + 1) begin : genYSheets
                for (gx = 0; gx < CUBE_X; gx = gx + 1) begin : genXY
                    localparam CORE_A = `coreId(gx, gy, gz);
                    localparam CORE_B = `coreId(gx, gy+1, gz);
                    
                    memorySheet #(
                        .ADDR_WIDTH(DATA_MEM_ADDR_BITS),
                        .DATA_WIDTH(DATA_MEM_DATA_BITS)
                    ) msY (
                        .clk(clkSys), .reset(reset),
                        .sideAReqValid(coreFaceReqValid[CORE_A][2]),
                        .sideAReqWrite(coreFaceReqWrite[CORE_A][2]),
                        .sideAReqAddr(coreFaceReqAddr[CORE_A][2]),
                        .sideAReqWdata(coreFaceReqWdata[CORE_A][2]),
                        .sideAReqReady(coreFaceReqReady[CORE_A][2]),
                        .sideARespValid(coreFaceRespValid[CORE_A][2]),
                        .sideARespRdata(coreFaceRespRdata[CORE_A][2]),
                        .sideARespReady(coreFaceRespReady[CORE_A][2]),
                        .sideBReqValid(coreFaceReqValid[CORE_B][3]),
                        .sideBReqWrite(coreFaceReqWrite[CORE_B][3]),
                        .sideBReqAddr(coreFaceReqAddr[CORE_B][3]),
                        .sideBReqWdata(coreFaceReqWdata[CORE_B][3]),
                        .sideBReqReady(coreFaceReqReady[CORE_B][3]),
                        .sideBRespValid(coreFaceRespValid[CORE_B][3]),
                        .sideBRespRdata(coreFaceRespRdata[CORE_B][3]),
                        .sideBRespReady(coreFaceRespReady[CORE_B][3]),
                        .nocReqValid(1'b0), .nocReqWrite(1'b0), .nocReqAddr('0), .nocReqWdata('0),
                        .nocReqReady(), .nocRespValid(), .nocRespRdata(), .nocRespReady(1'b1),
                        .perfReads(), .perfWrites(), .perfBankConflicts(),
                        .perfSideAAccesses(), .perfSideBAccesses(), .perfNocAccesses(), .perfMerges()
                    );
                end
            end
        end

        for (gz = 0; gz < CUBE_Z - 1; gz = gz + 1) begin : genZSheets
            for (gy = 0; gy < CUBE_Y; gy = gy + 1) begin : genYZ
                for (gx = 0; gx < CUBE_X; gx = gx + 1) begin : genXZ
                    localparam CORE_A = `coreId(gx, gy, gz);
                    localparam CORE_B = `coreId(gx, gy, gz+1);
                    
                    memorySheet #(
                        .ADDR_WIDTH(DATA_MEM_ADDR_BITS),
                        .DATA_WIDTH(DATA_MEM_DATA_BITS)
                    ) msZ (
                        .clk(clkSys), .reset(reset),
                        .sideAReqValid(coreFaceReqValid[CORE_A][4]),
                        .sideAReqWrite(coreFaceReqWrite[CORE_A][4]),
                        .sideAReqAddr(coreFaceReqAddr[CORE_A][4]),
                        .sideAReqWdata(coreFaceReqWdata[CORE_A][4]),
                        .sideAReqReady(coreFaceReqReady[CORE_A][4]),
                        .sideARespValid(coreFaceRespValid[CORE_A][4]),
                        .sideARespRdata(coreFaceRespRdata[CORE_A][4]),
                        .sideARespReady(coreFaceRespReady[CORE_A][4]),
                        .sideBReqValid(coreFaceReqValid[CORE_B][5]),
                        .sideBReqWrite(coreFaceReqWrite[CORE_B][5]),
                        .sideBReqAddr(coreFaceReqAddr[CORE_B][5]),
                        .sideBReqWdata(coreFaceReqWdata[CORE_B][5]),
                        .sideBReqReady(coreFaceReqReady[CORE_B][5]),
                        .sideBRespValid(coreFaceRespValid[CORE_B][5]),
                        .sideBRespRdata(coreFaceRespRdata[CORE_B][5]),
                        .sideBRespReady(coreFaceRespReady[CORE_B][5]),
                        .nocReqValid(1'b0), .nocReqWrite(1'b0), .nocReqAddr('0), .nocReqWdata('0),
                        .nocReqReady(), .nocRespValid(), .nocRespRdata(), .nocRespReady(1'b1),
                        .perfReads(), .perfWrites(), .perfBankConflicts(),
                        .perfSideAAccesses(), .perfSideBAccesses(), .perfNocAccesses(), .perfMerges()
                    );
                end
            end
        end
    endgenerate

    generate
        for (gz = 0; gz < CUBE_Z; gz = gz + 1) begin : tieZ
            for (gy = 0; gy < CUBE_Y; gy = gy + 1) begin : tieY
                for (gx = 0; gx < CUBE_X; gx = gx + 1) begin : tieX
                    localparam CID = `coreId(gx, gy, gz);
                    if (gx == CUBE_X - 1) begin : tie_xp
                        assign coreFaceReqReady[CID][0] = 1'b0;
                        assign coreFaceRespValid[CID][0] = 1'b0;
                        assign coreFaceRespRdata[CID][0] = '0;
                    end
                    if (gx == 0) begin : tie_xn
                        assign coreFaceReqReady[CID][1] = 1'b0;
                        assign coreFaceRespValid[CID][1] = 1'b0;
                        assign coreFaceRespRdata[CID][1] = '0;
                    end
                    if (gy == CUBE_Y - 1) begin : tie_yp
                        assign coreFaceReqReady[CID][2] = 1'b0;
                        assign coreFaceRespValid[CID][2] = 1'b0;
                        assign coreFaceRespRdata[CID][2] = '0;
                    end
                    if (gy == 0) begin : tie_yn
                        assign coreFaceReqReady[CID][3] = 1'b0;
                        assign coreFaceRespValid[CID][3] = 1'b0;
                        assign coreFaceRespRdata[CID][3] = '0;
                    end
                    if (gz == CUBE_Z - 1) begin : tie_zp
                        assign coreFaceReqReady[CID][4] = 1'b0;
                        assign coreFaceRespValid[CID][4] = 1'b0;
                        assign coreFaceRespRdata[CID][4] = '0;
                    end
                    if (gz == 0) begin : tie_zn
                        assign coreFaceReqReady[CID][5] = 1'b0;
                        assign coreFaceRespValid[CID][5] = 1'b0;
                        assign coreFaceRespRdata[CID][5] = '0;
                    end
                end
            end
        end
    endgenerate

    wire gpuDone;
    wire [2:0] kernelState;

    gpu #(
        .NUM_CORES             (NUM_CORES),
        .CUBE_X                (CUBE_X),
        .CUBE_Y                (CUBE_Y),
        .CUBE_Z                (CUBE_Z),
        .DATA_MEM_ADDR_BITS    (DATA_MEM_ADDR_BITS),
        .DATA_MEM_DATA_BITS    (DATA_MEM_DATA_BITS),
        .PROGRAM_MEM_ADDR_BITS (PROG_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS (PROG_MEM_DATA_BITS),
        .PROGRAM_MEM_NUM_CHANNELS(PROG_MEM_CHANNELS),
        .THREADS_PER_BLOCK     (THREADS_PER_BLOCK),
        .WARPS_PER_CORE        (WARPS_PER_CORE)
    ) uGpu (
        .clk                        (clkSys),
        .reset                      (reset),
        .start                      (hostStart),
        .done                       (gpuDone),
        .deviceControlWriteEnable(hostWrEn),
        .deviceControlData        (hostWrData),
        .programMemReadValid     (pmRdValid),
        .programMemReadAddress   (pmRdAddr),
        .programMemReadReady     (pmRdReady),
        .programMemReadData      (pmRdData),
        .coreMemReadValid        (dmRdValid),
        .coreMemReadAddress      (dmRdAddr),
        .coreMemReadReady        (dmRdReady),
        .coreMemReadReqReady     (dmRdReqReady),
        .coreMemReadRespValid    (dmRdRespValid),
        .coreMemReadData         (dmRdData),
        .coreMemWriteValid       (dmWrValid),
        .coreMemWriteAddress     (dmWrAddr),
        .coreMemWriteData        (dmWrData),
        .coreMemWriteReady       (dmWrReady),
        .coreCreditsFull         (coreCreditsFull),
        .kernelStateO             (kernelState),
        .perfNoCStallCycles      (perfNoCStallCycles),
        
        .coreFaceReqValid        (coreFaceReqValid),
        .coreFaceReqWrite        (coreFaceReqWrite),
        .coreFaceReqAddr         (coreFaceReqAddr),
        .coreFaceReqWdata        (coreFaceReqWdata),
        .coreFaceReqReady        (coreFaceReqReady),
        .coreFaceRespValid       (coreFaceRespValid),
        .coreFaceRespRdata       (coreFaceRespRdata),
        .coreFaceRespReady       (coreFaceRespReady)
    );

    assign kernelDone     = gpuDone;
    assign kernelStateO  = kernelState;
    assign kernelFault    = uGpu.kernelFault;

    localparam HBM_NODE_BASE = NUM_CORES - NUM_HBM_NODES;
    localparam MESH_COORD_W_ACTUAL = (CUBE_X > CUBE_Y) ? ((CUBE_X > CUBE_Z) ? $clog2(CUBE_X+1) : $clog2(CUBE_Z+1)) : ((CUBE_Y > CUBE_Z) ? $clog2(CUBE_Y+1) : $clog2(CUBE_Z+1));

    flit_t   [gridx_mem_pkg::NUM_NODES-1:0] meshFlitIn;
    logic    [gridx_mem_pkg::NUM_NODES-1:0] meshFlitInValid;
    credit_t [gridx_mem_pkg::NUM_NODES-1:0] meshCreditOut;
    flit_t   [gridx_mem_pkg::NUM_NODES-1:0] meshFlitOut;
    logic    [gridx_mem_pkg::NUM_NODES-1:0] meshFlitOutValid;
    credit_t [gridx_mem_pkg::NUM_NODES-1:0] meshCreditIn;

    mem_mesh_top uMesh (
        .clk_layer           (clkLayer),
        .rst_n               (rstN),
        .local_flit_in       (meshFlitIn),
        .local_flit_in_valid (meshFlitInValid),
        .local_credit_out    (meshCreditOut),
        .local_flit_out      (meshFlitOut),
        .local_flit_out_valid(meshFlitOutValid),
        .local_credit_in     (meshCreditIn)
    );

    flit_t   [gridx_mem_pkg::NUM_NODES-1:0] preInjectFlit;
    logic    [gridx_mem_pkg::NUM_NODES-1:0] preInjectFlitValid;
    credit_t [gridx_mem_pkg::NUM_NODES-1:0] cdcCreditFromMesh;

    flit_t   [gridx_mem_pkg::NUM_NODES-1:0] cdcFlitFromMesh;
    logic    [gridx_mem_pkg::NUM_NODES-1:0] cdcFlitFromMeshValid;
    credit_t [gridx_mem_pkg::NUM_NODES-1:0] cdcCreditToMesh;

    wire        coreBrTxValid [NUM_CORES-1:0];
    flit_t      coreBrTxFlit  [NUM_CORES-1:0];

    genvar n;
    generate
        for (n = 0; n < NUM_CORES; n = n + 1) begin : coreBridges
            wire        brTxValid;
            wire [255:0] brTxData;
            wire [1:0]  brTxFlitType;
            wire [1:0]  brTxVcId;
            wire        brRxValid;
            wire [255:0] brRxData;
            wire [1:0]  brRxFlitType;
            wire [1:0]  brRxVcId;
            wire        brRxCreditValid;
            wire [1:0]  brRxCreditVcId;

            localparam [$clog2(CUBE_X+1)-1:0] myX = n % CUBE_X;
            localparam [$clog2(CUBE_Y+1)-1:0] myY = (n / CUBE_X) % CUBE_Y;
            localparam [$clog2(CUBE_Z+1)-1:0] myZ = n / (CUBE_X * CUBE_Y);

            memMeshBridge #(
                .NUM_GPU_CHANNELS(1),
                .ADDR_BITS       (DATA_MEM_ADDR_BITS),
                .DATA_BITS       (DATA_MEM_DATA_BITS),
                .MESH_COORD_W    (2),
                .NUM_HBM_NODES   (NUM_HBM_NODES),
                .HBM_BASE_NODE   (HBM_NODE_BASE),
                .MESH_X          (CUBE_X),
                .MESH_Y          (CUBE_Y)
            ) uBridge (
                .clk(clkSys), .reset(reset),
                .gpuReadValid   (meshBrRdValid[n]),
                .gpuReadAddress ('{meshBrRdAddr[n]}),
                .gpuReadReady   (meshBrRdReady[n]),
                .gpuReadReqReady('{meshBrRdReqReady[n]}),
                .gpuReadData    ('{meshBrRdData[n]}),
                .gpuWriteValid  (meshBrWrValid[n]),
                .gpuWriteAddress('{meshBrWrAddr[n]}),
                .gpuWriteData   ('{meshBrWrData[n]}),
                .gpuWriteReady  (meshBrWrReady[n]),
                .meshTxValid        (brTxValid),
                .meshTxData         (brTxData),
                .meshTxFlitType    (brTxFlitType),
                .meshTxVcId        (brTxVcId),
                .meshTxCreditValid (cdcCreditFromMesh[n].valid),
                .meshTxCreditVcId (cdcCreditFromMesh[n].vc_id),
                .meshRxValid        (brRxValid),
                .meshRxData         (brRxData),
                .meshRxFlitType    (brRxFlitType),
                .meshRxVcId        (brRxVcId),
                .meshRxCreditValid (brRxCreditValid),
                .meshRxCreditVcId (brRxCreditVcId),
                .myX(myX), .myY(myY), .myZ(myZ),
                .outstandingCount(), .bridgeBusy(),
                .bridgeCreditsFull(meshCreditsFull[n])
            );

            assign coreBrTxValid[n]   = brTxValid;
            assign coreBrTxFlit[n].valid     = brTxValid;
            assign coreBrTxFlit[n].data      = brTxData;
            assign coreBrTxFlit[n].flit_type = gridx_mem_pkg::flit_type_e'(brTxFlitType);
            assign coreBrTxFlit[n].vc_id     = brTxVcId;

            assign brRxValid     = cdcFlitFromMeshValid[n];
            assign brRxData      = cdcFlitFromMesh[n].data;
            assign brRxFlitType  = cdcFlitFromMesh[n].flit_type;
            assign brRxVcId     = cdcFlitFromMesh[n].vc_id;

            assign cdcCreditToMesh[n].valid = brRxCreditValid;
            assign cdcCreditToMesh[n].vc_id = brRxCreditVcId;
        end
    endgenerate

    generate
        for (n = 0; n < HBM_NODE_BASE; n = n + 1) begin : computeNodes
            assign preInjectFlitValid[n] = coreBrTxValid[n];
            assign preInjectFlit[n]      = coreBrTxFlit[n];
        end
    endgenerate

    wire [31:0] hbmRdCnt [NUM_HBM_NODES-1:0];
    wire [31:0] hbmWrCnt [NUM_HBM_NODES-1:0];
    wire [31:0] axiWrTxn [NUM_HBM_NODES-1:0];
    wire [31:0] axiRdTxn [NUM_HBM_NODES-1:0];

    genvar h;
    generate
        for (h = 0; h < NUM_HBM_NODES; h = h + 1) begin : hbmNodes
            localparam HN = HBM_NODE_BASE + h;

            wire        axiBrReqValid;
            wire [31:0] axiBrReqAddr;
            wire [511:0] axiBrReqWdata;
            wire        axiBrReqWrite;
            wire        axiBrReqReady;

            wire [511:0] hbmRespData;
            wire [31:0]  hbmRespAddr;
            wire         hbmRespValid;
            wire         hbmReady;

            wire [31:0]  meshReqAddr  = cdcFlitFromMesh[HN].data[31:0];
            wire [511:0] meshReqWdata = {504'd0, cdcFlitFromMesh[HN].data[39:32]};
            wire         meshReqWrite = (cdcFlitFromMesh[HN].vc_id == gridx_mem_pkg::VC_WRITE_REQ);
            wire         meshReqValid = cdcFlitFromMeshValid[HN] & (cdcFlitFromMesh[HN].flit_type == gridx_mem_pkg::FLIT_HEAD);

            wire [10:0]  axiBrRespId;

            axi4HbmBridge #(
                .ADDR_WIDTH(32),
                .DATA_WIDTH(512),
                .ID_WIDTH(11)
            ) uAxiBridge (
                .clk(clkSys),
                .reset(!rstN),
                .sAwid    ({cdcFlitFromMesh[HN].data[250:245], cdcFlitFromMesh[HN].data[125:121]}),
                .sAwaddr  (meshReqAddr),
                .sAwlen   (8'd0),
                .sAwsize  (3'b110),
                .sAwburst (2'b01),
                .sAwvalid (meshReqValid & meshReqWrite),
                .sAwready (),
                .sWdata   (meshReqWdata),
                .sWstrb   ({64{1'b1}}),
                .sWlast   (1'b1),
                .sWvalid  (meshReqValid & meshReqWrite),
                .sWready  (),
                .sBid     (),
                .sBresp   (),
                .sBvalid  (),
                .sBready  (1'b1),
                .sArid    ({cdcFlitFromMesh[HN].data[250:245], cdcFlitFromMesh[HN].data[125:121]}),
                .sAraddr  (meshReqAddr),
                .sArlen   (8'd0),
                .sArsize  (3'b110),
                .sArburst (2'b01),
                .sArvalid (meshReqValid & ~meshReqWrite),
                .sArready (),
                .sRid     (axiBrRespId),
                .sRdata   (),
                .sRresp   (),
                .sRlast   (),
                .sRvalid  (),
                .sRready  (1'b1),
                .hbmReqValid  (axiBrReqValid),
                .hbmReqAddr   (axiBrReqAddr),
                .hbmReqWdata  (axiBrReqWdata),
                .hbmReqWrite  (axiBrReqWrite),
                .hbmReqReady  (hbmReady),
                .hbmRespValid (hbmRespValid),
                .hbmRespData  (hbmRespData),
                .hbmRespAddr  (hbmRespAddr),
                .axiWrTxnCount (axiWrTxn[h]),
                .axiRdTxnCount (axiRdTxn[h])
            );

            hbm3Ctrl uHbm (
                .clk(clk), .reset(reset),
                .reqValid    (axiBrReqValid),
                .reqAddr     (axiBrReqAddr),
                .reqWdata    (axiBrReqWdata),
                .reqWrite    (axiBrReqWrite),
                .reqReady    (hbmReady),
                .respValid   (hbmRespValid),
                .respData    (hbmRespData),
                .respAddr    (hbmRespAddr),
                .totalReads  (hbmRdCnt[h]),
                .totalWrites (hbmWrCnt[h]),
                .phyReadValid(~axiBrReqWrite & axiBrReqValid),
                .phyReadData ({512{1'b1}}),
                .phyStackSel(),
                .phyChannelSel(),
                .phyRowAddr(),
                .phyColAddr(),
                .phyBankAddr(),
                .phyActivate(),
                .phyRead(),
                .phyWriteCmd(),
                .phyPrecharge(),
                .phyWriteData(),
                .rowHits(),
                .rowMisses(),
                .controllerBusy()
            );

            reg          hbmRespValid_d1;
            reg  [511:0] hbmRespData_d1;
            always @(posedge clkSys) begin
                if (reset) begin
                    hbmRespValid_d1 <= 1'b0;
                    hbmRespData_d1  <= 512'd0;
                end else begin
                    hbmRespValid_d1 <= hbmRespValid;
                    hbmRespData_d1  <= hbmRespData;
                end
            end

            reg hbmInjectValid;
            flit_t hbmInjectFlit;
            always @(posedge clkSys) begin
                if (hbmRespValid_d1) begin
                    hbmInjectValid <= 1'b1;
                    hbmInjectFlit.valid <= 1'b1;
                    hbmInjectFlit.flit_type <= gridx_mem_pkg::FLIT_HT;
                    hbmInjectFlit.vc_id <= gridx_mem_pkg::VC_MEM_RESP;
                    hbmInjectFlit.data <= 256'd0;
                    hbmInjectFlit.data[255:126] <= hbmRespData_d1[129:0];
                    hbmInjectFlit.data[125:121] <= axiBrRespId[4:0];
                    hbmInjectFlit.data[116:111] <= {axiBrRespId[6:5], axiBrRespId[8:7], axiBrRespId[10:9]};
                    hbmInjectFlit.data[110:0]   <= hbmRespData_d1[110:0];
                end else begin
                    hbmInjectValid <= 1'b0;
                    hbmInjectFlit.valid <= 1'b0;
                end
            end
            
            assign preInjectFlitValid[HN] = hbmInjectValid ? 1'b1 : coreBrTxValid[HN];
            assign preInjectFlit[HN]      = hbmInjectValid ? hbmInjectFlit : coreBrTxFlit[HN];
        end
    endgenerate

    genvar cdcI;
    generate
        for (cdcI = 0; cdcI < NUM_CORES; cdcI = cdcI + 1) begin : bridgeMeshCdc
            localparam int CDC_LAYER = cdcI / (CUBE_X * CUBE_Y);

            z_link_adapter_uni u_cdc_inject (
                .clk_a      (clkSys),
                .rst_a_n    (rstN),
                .flit_in    (preInjectFlit[cdcI]),
                .flit_in_valid(preInjectFlitValid[cdcI]),
                .credit_out (cdcCreditFromMesh[cdcI]),

                .clk_b      (clkLayer[CDC_LAYER]),
                .rst_b_n    (rstN),
                .flit_out   (meshFlitIn[cdcI]),
                .flit_out_valid(meshFlitInValid[cdcI]),
                .credit_in  (meshCreditOut[cdcI])
            );

            z_link_adapter_uni u_cdc_eject (
                .clk_a      (clkLayer[CDC_LAYER]),
                .rst_a_n    (rstN),
                .flit_in    (meshFlitOut[cdcI]),
                .flit_in_valid(meshFlitOutValid[cdcI]),
                .credit_out (meshCreditIn[cdcI]),

                .clk_b      (clkSys),
                .rst_b_n    (rstN),
                .flit_out   (cdcFlitFromMesh[cdcI]),
                .flit_out_valid(cdcFlitFromMeshValid[cdcI]),
                .credit_in  (cdcCreditToMesh[cdcI])
            );
        end
    endgenerate

    wire [NUM_CORES-1:0] vmcReqGrant;
    wire [DATA_MEM_DATA_BITS-1:0] vmcReqRdata [NUM_CORES-1:0];
    wire [NUM_CORES-1:0] vmcReqReady;
    wire vmcGlobalReqValid, vmcGlobalReqWrite;
    wire [DATA_MEM_ADDR_BITS-1:0] vmcGlobalReqAddr;
    wire [DATA_MEM_DATA_BITS-1:0] vmcGlobalReqData;

    wire [DATA_MEM_ADDR_BITS-1:0] vmcCoreAddr [NUM_CORES-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] vmcCoreData [NUM_CORES-1:0];
    genvar vi;
    generate
        for (vi = 0; vi < NUM_CORES; vi = vi + 1) begin : vmcTieoff
            assign vmcCoreAddr[vi] = {DATA_MEM_ADDR_BITS{1'b0}};
            assign vmcCoreData[vi] = {DATA_MEM_DATA_BITS{1'b0}};
        end
    endgenerate

    verticalMemoryController #(
        .NUM_CORES      (NUM_CORES),
        .ADDR_WIDTH     (DATA_MEM_ADDR_BITS),
        .DATA_WIDTH     (DATA_MEM_DATA_BITS)
    ) uTsvCtrl (
        .clk               (clk),
        .reset              (reset),
        .coreReqValid     ({NUM_CORES{1'b0}}),
        .coreReqWrite     ({NUM_CORES{1'b0}}),
        .coreReqAddr      (vmcCoreAddr),
        .coreReqData      (vmcCoreData),
        .coreReqGrant     (vmcReqGrant),
        .coreReqRdata     (vmcReqRdata),
        .coreReqReady     (vmcReqReady),
        .globalReqValid   (vmcGlobalReqValid),
        .globalReqWrite   (vmcGlobalReqWrite),
        .globalReqAddr    (vmcGlobalReqAddr),
        .globalReqData    (vmcGlobalReqData),
        .globalReqReady   (1'b1),
        .globalReqRdata   ({DATA_MEM_DATA_BITS{1'b0}})
    );

    dmaEngine #(
        .ADDR_BITS       (DATA_MEM_ADDR_BITS),
        .DATA_WIDTH      (64),
        .BURST_SIZE      (8),
        .SRAM_ADDR_BITS  (11)
    ) uDma (
        .clk               (clk),
        .reset              (reset),
        .cmdValid          (1'b0),
        .cmdDirection      (1'b0),
        .cmdExtAddr       ({DATA_MEM_ADDR_BITS{1'b0}}),
        .cmdSramAddr      (11'd0),
        .cmdLength         (8'd0),
        .cmdReady          (),
        .cmdDone           (),
        .cmdError          (),
        .extReadValid     (),
        .extReadAddress   (),
        .extReadReady     (1'b1),
        .extReadData      (64'd0),
        .extWriteValid    (),
        .extWriteAddress  (),
        .extWriteData     (),
        .extWriteReady    (1'b1),
        .sramReadValid    (),
        .sramReadAddress  (),
        .sramReadReady    (1'b1),
        .sramReadData     (64'd0),
        .sramWriteValid   (),
        .sramWriteAddress (),
        .sramWriteData    (),
        .sramWriteReady   (1'b1),
        .busy               (),
        .wordsTransferred  ()
    );

    localparam PWR_BANKS = NUM_CORES;
    wire [PWR_BANKS-1:0] pwrBankEnable;

    powerController #(
        .NUM_BANKS      (PWR_BANKS),
        .idleCycles    (16),
        .SLEEP_CYCLES   (256)
    ) uPwr (
        .clk               (clk),
        .reset              (reset),
        .bankActive        (~uGpu.coreDone & uGpu.coreStart),
        .forceEnable       ({PWR_BANKS{1'b0}}),
        .forceSleep        ({PWR_BANKS{1'b0}}),
        .bankPowerEnable  (pwrBankEnable),
        .bankPowerState   (),
        .bankNeedsReload  (),
        .totalActiveCycles(),
        .totalIdleCycles  (),
        .totalSleepCycles (),
        .stateTransitions  (),
        .bankWasActive    ()
    );

    localparam NUM_CLK_CLUSTERS = (NUM_CORES > 1) ? NUM_CORES : 2;
    wire [6:0] clusterTempArr [NUM_CLK_CLUSTERS-1:0];
    genvar ci;
    generate
        for (ci = 0; ci < NUM_CLK_CLUSTERS; ci = ci + 1) begin : clkTemp
            assign clusterTempArr[ci] = 7'd40;
        end
    endgenerate

    clkDomainCtrl #(
        .NUM_CLUSTERS      (NUM_CLK_CLUSTERS),
        .CORES_PER_CLUSTER (1),
        .SAMPLE_WINDOW     (1024)
    ) uClkCtrl (
        .clk                   (clk),
        .reset                 (reset),
        .clusterAluActive    (uGpu.corePerfAluActive[NUM_CLK_CLUSTERS-1:0]),
        .clusterTensorActive (uGpu.corePerfTensorActive[NUM_CLK_CLUSTERS-1:0]),
        .clusterStallMem     (uGpu.corePerfStallMem[NUM_CLK_CLUSTERS-1:0]),
        .clusterTemp          (clusterTempArr),
        .thermalLimit         (7'd95),
        .clusterPerfLevel    (),
        .clusterClockEnable  (),
        .clusterPowerGate    (),
        .clusterThrottled     (),
        .totalGatedCycles    ()
    );

    computeUtilization uUtil (
        .clk               (clk),
        .reset              (reset),
        .coreActive        (uGpu.kernelRunning),
        .aluEnable         (1'b1),
        .aluExecuting      (|uGpu.corePerfAluActive),
        .tensorBusy        (|uGpu.corePerfTensorActive),
        .tensorExecuting   (|uGpu.corePerfTensorActive),
        .aluActiveCycles  (),
        .aluIdleCycles    (),
        .tensorActiveCycles(),
        .tensorIdleCycles (),
        .aluActivePulse   (),
        .aluIdlePulse     (),
        .tensorActivePulse(),
        .tensorIdlePulse  ()
    );

    expressLink #(
        .DATA_WIDTH  (DATA_MEM_DATA_BITS),
        .ADDR_WIDTH  (DATA_MEM_ADDR_BITS),
        .LINK_LATENCY(2)
    ) uExpress (
        .clk        (clk),
        .reset      (reset),
        .aTxValid (1'b0),
        .aTxData  ({DATA_MEM_DATA_BITS{1'b0}}),
        .aTxAddr  ({DATA_MEM_ADDR_BITS{1'b0}}),
        .aTxWrite (1'b0),
        .aTxReady (),
        .aRxValid (),
        .aRxData  (),
        .aRxAddr  (),
        .aRxWrite (),
        .aRxReady (1'b1),
        .bTxValid (1'b0),
        .bTxData  ({DATA_MEM_DATA_BITS{1'b0}}),
        .bTxAddr  ({DATA_MEM_ADDR_BITS{1'b0}}),
        .bTxWrite (1'b0),
        .bTxReady (),
        .bRxValid (),
        .bRxData  (),
        .bRxAddr  (),
        .bRxWrite (),
        .bRxReady (1'b1)
    );

    multicastTree #(
        .NUM_GROUPS  (4),
        .MAX_TARGETS (NUM_CORES),
        .FLIT_WIDTH  (32)
    ) uMcast (
        .clk               (clk),
        .reset             (reset),
        .cfgValid         (1'b0),
        .cfgGroupId      (4'd0),
        .cfgTargetMask   ({NUM_CORES{1'b0}}),
        .cfgEnable        (1'b0),
        .flitInValid     (1'b0),
        .flitInData      (32'd0),
        .flitInGroupId  (4'd0),
        .flitInIsMulticast(1'b0),
        .flitOutValid    (),
        .flitOutData     (),
        .flitOutTargetId(),
        .flitOutReady    (1'b1),
        .busy              ()
    );

    creditManager #(
        .MAX_CREDITS  (16),
        .CREDIT_WIDTH (5)
    ) uCredits (
        .clk                (clk),
        .reset              (reset),
        .consume            (|meshFlitInValid),
        .releaseCredit     (|meshFlitOutValid),
        .available          (),
        .canIssue          (),
        .nearlyEmpty       (),
        .empty              (),
        .totalConsumed     (),
        .totalReleased     (),
        .minCreditsSeen   (),
        .maxOutstandingSeen()
    );

    memShellController #(
        .NUM_FACES   (6),
        .ADDR_WIDTH  (DATA_MEM_ADDR_BITS),
        .DATA_WIDTH  (DATA_MEM_DATA_BITS),
        .SHELL_SIZE_BYTES (256 * 1024)
    ) uShell (
        .clk               (clk),
        .reset             (reset),
        .faceReqValid    (6'd0),
        .faceReqWrite    (6'd0),
        .faceReqAddr     ('{default: '0}),
        .faceReqWdata    ('{default: '0}),
        .faceReqReady    (),
        .faceReqRdata    (),
        .faceCreditAvailable(),
        .sramReqValid    (),
        .sramReqWrite    (),
        .sramReqAddr     (),
        .sramReqWdata    (),
        .sramReqReady    (1'b1),
        .sramReqRdata    ({DATA_MEM_DATA_BITS{1'b0}})
    );

    prefetchEngine #(
        .ADDR_WIDTH (DATA_MEM_ADDR_BITS),
        .DATA_WIDTH (DATA_MEM_DATA_BITS),
        .NUM_ENTRIES(8),
        .PREFETCH_DIST (4)
    ) uPrefetch (
        .clk            (clk),
        .reset          (reset),
        .lsuLoadValid (1'b0),
        .lsuLoadAddr  ({DATA_MEM_ADDR_BITS{1'b0}}),
        .pfReqValid   (),
        .pfReqAddr    (),
        .pfReqReady   (1'b1),
        .activeStreams (),
        .pfIssuedCount(),
        .pfHitCount   ()
    );

    reg [31:0] cycleCounter;
    always @(posedge clk)
        if (reset) cycleCounter <= 32'd0;
        else       cycleCounter <= cycleCounter + 32'd1;

    assign perfCycleCount = cycleCounter;

    reg [31:0] hbmReadsSum, hbmWritesSum;
    integer si;
    always @(*) begin
        hbmReadsSum  = 32'd0;
        hbmWritesSum = 32'd0;
        for (si = 0; si < NUM_HBM_NODES; si = si + 1) begin
            hbmReadsSum  = hbmReadsSum  + hbmRdCnt[si];
            hbmWritesSum = hbmWritesSum + hbmWrCnt[si];
        end
    end
    assign perfHbmReads   = hbmReadsSum;
    assign perfHbmWrites  = hbmWritesSum;
    reg [31:0] flitCounter;
    always @(posedge clk) begin
        if (reset)
            flitCounter <= 32'd0;
        else begin
            begin : countFlits
                integer fi;
                reg [31:0] inc;
                inc = 32'd0;
                for (fi = 0; fi < gridx_mem_pkg::NUM_NODES; fi = fi + 1) begin
                    inc = inc + {31'd0, meshFlitInValid[fi]}
                              + {31'd0, meshFlitOutValid[fi]};
                end
                flitCounter <= flitCounter + inc;
            end
        end
    end
    assign perfTotalFlits = flitCounter;

    localparam DBG_SAMPLE_W = (NUM_CORES < 8) ? NUM_CORES : 8;
    assign dbgCoreDoneSample = uGpu.coreDone[DBG_SAMPLE_W-1:0];
    reg [31:0] activeCount;
    integer ai;
    always @(*) begin
        activeCount = 32'd0;
        for (ai = 0; ai < NUM_CORES; ai = ai + 1)
            activeCount = activeCount + {31'd0, ~uGpu.coreDone[ai] & uGpu.coreStart[ai]};
    end
    assign perfActiveCores = activeCount;
    assign dbgMeshBusy = |meshFlitInValid | |meshFlitOutValid;

    wire        chiReqAccepted;
    wire        chiRspValid;
    wire        chiSnpValid;
    wire        chiDatValid;
    wire        chiMemReqValid;
    wire [31:0] chiMemReqAddr;
    wire [511:0] chiMemReqWdata;
    wire        chiMemReqWrite;
    wire [3:0]  chiMemReqBurstLen;
    wire        chiControllerBusy;

    chiChannelController #(
        .NUM_CORES       (NUM_CORES),
        .ADDR_WIDTH      (32),
        .DATA_WIDTH      (512),
        .TXID_WIDTH      (8),
        .OTF_DEPTH       (16),
        .BURST_MAX_LEN   (16),
        .CREDIT_INIT     (8)
    ) uChiCtrl (
        .clk                (clk),
        .reset              (reset),
        .reqValid          (1'b0),
        .reqSrcId         ({$clog2(NUM_CORES){1'b0}}),
        .reqAddr           (32'd0),
        .reqData           (512'd0),
        .reqOpcode         (4'd0),
        .reqTxnId         (8'd0),
        .reqCreditAvail   (),
        .reqAccepted       (chiReqAccepted),
        .rspValid          (chiRspValid),
        .rspTgtId         (),
        .rspTxnId         (),
        .rspOpcode         (),
        .rspResp           (),
        .rspCreditReturn  (1'b1),
        .snpValid          (chiSnpValid),
        .snpTgtMask       (),
        .snpAddr           (),
        .snpOpcode         (),
        .snpRespValid     (1'b0),
        .snpRespSrcId    ({$clog2(NUM_CORES){1'b0}}),
        .snpRespData      (512'd0),
        .snpRespState     (2'b00),
        .datValid          (chiDatValid),
        .datTgtId         (),
        .datTxnId         (),
        .datData           (),
        .datByteEnable    (),
        .datCreditReturn  (1'b1),
        .memReqValid      (chiMemReqValid),
        .memReqAddr       (chiMemReqAddr),
        .memReqWdata      (chiMemReqWdata),
        .memReqWrite      (chiMemReqWrite),
        .memReqBurstLen  (chiMemReqBurstLen),
        .memReqReady      (1'b1),
        .memRespValid     (1'b0),
        .memRespData      (512'd0),
        .perfReqAccepted       (),
        .perfRspSent           (),
        .perfSnpIssued         (),
        .perfDatTransfers      (),
        .perfBurstCoalesced    (),
        .perfTotalLatencyCycles (),
        .perfMaxLatency        (),
        .perfAvgOtfDepth      (),
        .controllerBusy         (chiControllerBusy)
    );

    localparam AXI_NUM_MASTERS = (NUM_HBM_NODES > 1) ? NUM_HBM_NODES : 2;

    axi4BurstInterconnect #(
        .NUM_MASTERS      (AXI_NUM_MASTERS),
        .ADDR_WIDTH       (32),
        .DATA_WIDTH       (512),
        .ID_WIDTH         (6),
        .MAX_BURST_LEN    (16),
        .WRITE_BUF_DEPTH  (8),
        .READ_BUF_DEPTH   (8),
        .REORDER_DEPTH    (16)
    ) uAxi4Xbar (
        .clk              (clk),
        .reset            (reset),
        .mAwvalid        ({AXI_NUM_MASTERS{1'b0}}),
        .mAwid           ({AXI_NUM_MASTERS*6{1'b0}}),
        .mAwaddr         ({AXI_NUM_MASTERS*32{1'b0}}),
        .mAwlen          ({AXI_NUM_MASTERS*8{1'b0}}),
        .mAwsize         ({AXI_NUM_MASTERS*3{1'b0}}),
        .mAwburst        ({AXI_NUM_MASTERS*2{1'b0}}),
        .mAwqos          ({AXI_NUM_MASTERS*4{1'b0}}),
        .mAwready        (),
        .mWvalid         ({AXI_NUM_MASTERS{1'b0}}),
        .mWdata          ({AXI_NUM_MASTERS*512{1'b0}}),
        .mWstrb          ({AXI_NUM_MASTERS*64{1'b0}}),
        .mWlast          ({AXI_NUM_MASTERS{1'b0}}),
        .mWready         (),
        .mBvalid         (),
        .mBid            (),
        .mBresp          (),
        .mBready         ({AXI_NUM_MASTERS{1'b1}}),
        .mArvalid        ({AXI_NUM_MASTERS{1'b0}}),
        .mArid           ({AXI_NUM_MASTERS*6{1'b0}}),
        .mAraddr         ({AXI_NUM_MASTERS*32{1'b0}}),
        .mArlen          ({AXI_NUM_MASTERS*8{1'b0}}),
        .mArsize         ({AXI_NUM_MASTERS*3{1'b0}}),
        .mArburst        ({AXI_NUM_MASTERS*2{1'b0}}),
        .mArqos          ({AXI_NUM_MASTERS*4{1'b0}}),
        .mArready        (),
        .mRvalid         (),
        .mRid            (),
        .mRdata          (),
        .mRresp          (),
        .mRlast          (),
        .mRready         ({AXI_NUM_MASTERS{1'b1}}),
        .sAwvalid        (),
        .sAwid           (),
        .sAwaddr         (),
        .sAwlen          (),
        .sAwsize         (),
        .sAwburst        (),
        .sAwready        (1'b1),
        .sWvalid         (),
        .sWdata          (),
        .sWstrb          (),
        .sWlast          (),
        .sWready         (1'b1),
        .sBvalid         (1'b0),
        .sBid            (6'd0),
        .sBresp          (2'b00),
        .sBready         (),
        .sArvalid        (),
        .sArid           (),
        .sAraddr         (),
        .sArlen          (),
        .sArsize         (),
        .sArburst        (),
        .sArready        (1'b1),
        .sRvalid         (1'b0),
        .sRid            (6'd0),
        .sRdata          (512'd0),
        .sRresp          (2'b00),
        .sRlast          (1'b1),
        .sRready         (),
        .perfWrBursts          (),
        .perfRdBursts          (),
        .perfWrBeats           (),
        .perfRdBeats           (),
        .perfWrLatencyTotal   (),
        .perfRdLatencyTotal   (),
        .perfMaxWrLatency     (),
        .perfMaxRdLatency     (),
        .perfBwWriteBytes     (),
        .perfBwReadBytes      (),
        .perfBackpressureCycles(),
        .interconnectBusy       ()
    );

    wire [NUM_CORES-1:0][1:0] meshInjectVc;
    generate
        for (n = 0; n < NUM_CORES; n = n + 1) begin : genMeshInjectVc
            assign meshInjectVc[n] = meshFlitIn[n].vc_id;
        end
    endgenerate

    wire zPlusAnyTx = (uMesh.node_flit_tx_valid[0][0][0][gridx_mem_pkg::PORT_Z_POS] |
                       uMesh.node_flit_tx_valid[0][0][1][gridx_mem_pkg::PORT_Z_POS] |
                       uMesh.node_flit_tx_valid[0][1][0][gridx_mem_pkg::PORT_Z_POS] |
                       uMesh.node_flit_tx_valid[0][1][1][gridx_mem_pkg::PORT_Z_POS]);

    wire zMinusAnyTx = (uMesh.node_flit_tx_valid[1][0][0][gridx_mem_pkg::PORT_Z_NEG] |
                        uMesh.node_flit_tx_valid[1][0][1][gridx_mem_pkg::PORT_Z_NEG] |
                        uMesh.node_flit_tx_valid[1][1][0][gridx_mem_pkg::PORT_Z_NEG] |
                        uMesh.node_flit_tx_valid[1][1][1][gridx_mem_pkg::PORT_Z_NEG]);

    reg [31:0] latTimer;
    reg        latMeasuring;
    reg [31:0] latRetireCycles;
    reg        latRetirePulse;

    always @(posedge clk) begin
        if (reset) begin
            latTimer        <= 32'd0;
            latMeasuring    <= 1'b0;
            latRetireCycles <= 32'd0;
            latRetirePulse  <= 1'b0;
        end else begin
            latRetirePulse <= 1'b0;
            if (!latMeasuring && (meshBrWrValid[0] | meshBrRdValid[0])) begin
                latMeasuring <= 1'b1;
                latTimer     <= 32'd0;
            end else if (latMeasuring) begin
                latTimer <= latTimer + 32'd1;
                if (meshBrWrReady[0] | meshBrRdReady[0]) begin
                    latMeasuring    <= 1'b0;
                    latRetireCycles <= latTimer + 32'd1;
                    latRetirePulse  <= 1'b1;
                end
            end
        end
    end

    mem_mesh_telemetry #(
        .NUM_NODES        (NUM_CORES),
        .WINDOW_CYCLES    (1024),
        .LAT_BIN0_MAX     (16),
        .LAT_BIN1_MAX     (32),
        .LAT_BIN2_MAX     (64)
    ) uMeshTelemetry (
        .clk                   (clk),
        .rst_n                 (rstN),
        .node_inject_valid     (meshFlitInValid),
        .node_eject_valid      (meshFlitOutValid),
        .node_credits_blocked  (meshCreditsFull),
        .inject_vc_id          (meshInjectVc),
        .z_plus_valid          (zPlusAnyTx),
        .z_minus_valid         (zMinusAnyTx),
        .txn_issue_pulse       (meshBrWrValid[0] | meshBrRdValid[0]),
        .txn_retire_pulse      (latRetirePulse),
        .txn_latency_cycles    (latRetireCycles),
        .total_flits_injected  (),
        .total_flits_ejected   (),
        .total_z_plus_flits    (),
        .total_z_minus_flits   (),
        .total_congestion_cycles(),
        .vc0_read_flits        (),
        .vc1_write_flits       (),
        .vc2_resp_flits        (),
        .vc3_ctrl_flits        (),
        .per_node_inject       (),
        .per_node_eject        (),
        .lat_bin0_count        (),
        .lat_bin1_count        (),
        .lat_bin2_count        (),
        .lat_bin3_count        (),
        .min_latency           (),
        .max_latency           (),
        .total_latency_sum     (),
        .total_txns_measured   (),
        .rolling_window_flits  (),
        .peak_window_flits     ()
    );

    reg [31:0] simWd;
    always @(posedge clk) begin
        if (reset) simWd <= 0;
        else begin
            simWd <= simWd + 1;
            if (kernelDone && !$past(kernelDone)) begin
                $display("[KERNEL_TOP] COMPLETE ? cycles=%0d hbmRd=%0d hbmWr=%0d",
                         cycleCounter, perfHbmReads, perfHbmWrites);
                uMeshTelemetry.print_telemetry_report();
            end
            if (simWd >= SIM_TIMEOUT_CYCLES) begin
                $display("[KERNEL_TOP] TIMEOUT at %0d cycles", SIM_TIMEOUT_CYCLES);
                $finish;
            end
        end
    end

endmodule
