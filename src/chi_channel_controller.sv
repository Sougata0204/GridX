// CHI-Compliant Multi-Channel Burst Controller
// Implements AMBA CHI REQ/RSP/SNP/DAT channel architecture with
// high-throughput burst transfers, credit-based flow control,
// and deep outstanding transaction queues for low-latency operation.
//
// Key Features:
//   - 4 independent CHI channels: REQ, RSP, SNP, DAT
//   - Deep outstanding transaction queue (configurable depth)
//   - Credit-based flow control per channel
//   - Burst coalescing for sequential address patterns
//   - Back-pressure propagation to NoC fabric
//   - Latency analysis counters per channel

`default_nettype none
`timescale 1ns/1ns

module chiChannelController #(
    parameter NUM_CORES        = 8,
    parameter ADDR_WIDTH       = 32,
    parameter DATA_WIDTH       = 512,
    parameter TXID_WIDTH       = 8,
    parameter CORE_ID_WIDTH    = $clog2(NUM_CORES),
    parameter OTF_DEPTH        = 16,   // Outstanding Transaction FIFO depth
    parameter BURST_MAX_LEN    = 16,   // Maximum burst coalescing length
    parameter CREDIT_INIT      = 8     // Initial credits per channel
) (
    input  wire clk,
    input  wire reset,

    input  wire                     reqValid,
    input  wire [CORE_ID_WIDTH-1:0] reqSrcId,
    input  wire [ADDR_WIDTH-1:0]    reqAddr,
    input  wire [DATA_WIDTH-1:0]    reqData,
    input  wire [3:0]               reqOpcode,  // CHI opcodes: ReadShared, ReadUnique, WriteBackFull, etc.
    input  wire [TXID_WIDTH-1:0]    reqTxnId,
    output reg                      reqCreditAvail,
    output reg                      reqAccepted,

    output reg                      rspValid,
    output reg  [CORE_ID_WIDTH-1:0] rspTgtId,
    output reg  [TXID_WIDTH-1:0]    rspTxnId,
    output reg  [2:0]               rspOpcode,  // CompAck, RetryAck, CompDBID, etc.
    output reg  [1:0]               rspResp,    // 00=OK, 01=ExOK, 10=DataErr
    input  wire                     rspCreditReturn,

    output reg                      snpValid,
    output reg  [NUM_CORES-1:0]     snpTgtMask,
    output reg  [ADDR_WIDTH-1:0]    snpAddr,
    output reg  [2:0]               snpOpcode,  // SnpShared, SnpCleanInvalid, SnpUnique
    input  wire                     snpRespValid,
    input  wire [CORE_ID_WIDTH-1:0] snpRespSrcId,
    input  wire [DATA_WIDTH-1:0]    snpRespData,
    input  wire [1:0]               snpRespState, // 00=I, 01=SC, 10=SD, 11=UC

    output reg                      datValid,
    output reg  [CORE_ID_WIDTH-1:0] datTgtId,
    output reg  [TXID_WIDTH-1:0]    datTxnId,
    output reg  [DATA_WIDTH-1:0]    datData,
    output reg  [DATA_WIDTH/8-1:0]  datByteEnable,
    input  wire                     datCreditReturn,

    output reg                      memReqValid,
    output reg  [ADDR_WIDTH-1:0]    memReqAddr,
    output reg  [DATA_WIDTH-1:0]    memReqWdata,
    output reg                      memReqWrite,
    output reg  [3:0]               memReqBurstLen,
    input  wire                     memReqReady,
    input  wire                     memRespValid,
    input  wire [DATA_WIDTH-1:0]    memRespData,

    output reg  [31:0]  perfReqAccepted,
    output reg  [31:0]  perfRspSent,
    output reg  [31:0]  perfSnpIssued,
    output reg  [31:0]  perfDatTransfers,
    output reg  [31:0]  perfBurstCoalesced,
    output reg  [31:0]  perfTotalLatencyCycles,
    output reg  [31:0]  perfMaxLatency,
    output reg  [31:0]  perfAvgOtfDepth,
    output wire         controllerBusy
);

    localparam [3:0] CHI_READ_SHARED     = 4'h0;
    localparam [3:0] CHI_READ_UNIQUE     = 4'h1;
    localparam [3:0] CHI_READ_ONCE       = 4'h2;
    localparam [3:0] CHI_WRITE_BACK_FULL = 4'h3;
    localparam [3:0] CHI_WRITE_CLEAN     = 4'h4;
    localparam [3:0] CHI_WRITE_UNIQUE    = 4'h5;
    localparam [3:0] CHI_MAKE_INVALID    = 4'h6;
    localparam [3:0] CHI_EVICT           = 4'h7;

    localparam [2:0] CHI_RSP_COMP       = 3'h0;
    localparam [2:0] CHI_RSP_COMP_DBID  = 3'h1;
    localparam [2:0] CHI_RSP_RETRY_ACK  = 3'h2;
    localparam [2:0] CHI_RSP_COMP_ACK   = 3'h3;

    localparam [2:0] CHI_SNP_SHARED     = 3'h0;
    localparam [2:0] CHI_SNP_CLEAN_INV  = 3'h1;
    localparam [2:0] CHI_SNP_UNIQUE     = 3'h2;

    reg                      otfValid     [OTF_DEPTH-1:0];
    reg [CORE_ID_WIDTH-1:0]  otfSrcId    [OTF_DEPTH-1:0];
    reg [ADDR_WIDTH-1:0]     otfAddr      [OTF_DEPTH-1:0];
    reg [DATA_WIDTH-1:0]     otfData      [OTF_DEPTH-1:0];
    reg [3:0]                otfOpcode    [OTF_DEPTH-1:0];
    reg [TXID_WIDTH-1:0]     otfTxnId    [OTF_DEPTH-1:0];
    reg [31:0]               otfEnqueueCycle [OTF_DEPTH-1:0];
    reg [$clog2(OTF_DEPTH):0] otfWrPtr, otfRdPtr, otfCount;

    reg [7:0] creditReq;
    reg [7:0] creditRsp;
    reg [7:0] creditDat;

    reg                      burstActive;
    reg [ADDR_WIDTH-1:0]     burstBaseAddr;
    reg [3:0]                burstLen;
    reg [CORE_ID_WIDTH-1:0]  burstSrcId;
    reg [TXID_WIDTH-1:0]     burstTxnId;
    reg                      burstIsWrite;

    typedef enum logic [3:0] {
        FSM_IDLE,
        FSM_ACCEPT_REQ,
        FSM_CHECK_COALESCE,
        FSM_ISSUE_SNP,
        FSM_WAIT_SNP,
        FSM_MEM_REQ,
        FSM_MEM_BURST,
        FSM_WAIT_MEM,
        FSM_SEND_DAT,
        FSM_SEND_RSP,
        FSM_WRITEBACK
    } fsmStateE;

    fsmStateE state;

    // Current transaction being processed
    reg [CORE_ID_WIDTH-1:0]  curSrcId;
    reg [ADDR_WIDTH-1:0]     curAddr;
    reg [DATA_WIDTH-1:0]     curData;
    reg [3:0]                curOpcode;
    reg [TXID_WIDTH-1:0]     curTxnId;
    reg [31:0]               curStartCycle;
    reg [3:0]                curBurstBeat;

    // Snoop tracking
    reg [4:0]  snpExpected;
    reg [4:0]  snpReceived;
    reg [8:0]  snpTimeout;
    reg [DATA_WIDTH-1:0] snpFetchedData;

    // Cycle counter for latency tracking
    reg [31:0] cycleCounter;
    reg [31:0] otfDepthAccum;
    reg [31:0] otfSampleCount;

    wire otfFull  = (otfCount >= OTF_DEPTH);
    wire otfEmpty = (otfCount == 0);

    assign controllerBusy = (state != FSM_IDLE) || !otfEmpty;

    // Determine if address is sequential (for burst coalescing)
    wire addrSequential = burstActive &&
                           (curAddr == burstBaseAddr + ((burstLen + 1) * (DATA_WIDTH / 8))) &&
                           (burstLen < BURST_MAX_LEN - 1);

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            state             <= FSM_IDLE;
            otfWrPtr        <= 0;
            otfRdPtr        <= 0;
            otfCount         <= 0;
            creditReq        <= CREDIT_INIT;
            creditRsp        <= CREDIT_INIT;
            creditDat        <= CREDIT_INIT;
            reqCreditAvail  <= 1;
            reqAccepted      <= 0;
            rspValid         <= 0;
            snpValid         <= 0;
            datValid         <= 0;
            memReqValid     <= 0;
            burstActive      <= 0;
            burstLen         <= 0;
            cycleCounter     <= 0;
            otfDepthAccum   <= 0;
            otfSampleCount  <= 0;

            perfReqAccepted       <= 0;
            perfRspSent           <= 0;
            perfSnpIssued         <= 0;
            perfDatTransfers      <= 0;
            perfBurstCoalesced    <= 0;
            perfTotalLatencyCycles <= 0;
            perfMaxLatency        <= 0;
            perfAvgOtfDepth      <= 0;

            for (i = 0; i < OTF_DEPTH; i = i + 1) begin
                otfValid[i] <= 0;
            end
        end else begin
            // Default pulse signals
            reqAccepted  <= 0;
            rspValid     <= 0;
            snpValid     <= 0;
            datValid     <= 0;
            memReqValid <= 0;

            cycleCounter <= cycleCounter + 1;

            // Credit management
            reqCreditAvail <= !otfFull && (creditReq > 0);

            if (rspCreditReturn && creditRsp < CREDIT_INIT)
                creditRsp <= creditRsp + 1;
            if (datCreditReturn && creditDat < CREDIT_INIT)
                creditDat <= creditDat + 1;

            // OTF depth sampling for average calculation
            otfDepthAccum  <= otfDepthAccum + otfCount;
            otfSampleCount <= otfSampleCount + 1;
            if (otfSampleCount > 0)
                perfAvgOtfDepth <= otfDepthAccum / otfSampleCount;

            if (reqValid && !otfFull && creditReq > 0) begin
                otfValid[otfWrPtr]         <= 1;
                otfSrcId[otfWrPtr]        <= reqSrcId;
                otfAddr[otfWrPtr]          <= reqAddr;
                otfData[otfWrPtr]          <= reqData;
                otfOpcode[otfWrPtr]        <= reqOpcode;
                otfTxnId[otfWrPtr]        <= reqTxnId;
                otfEnqueueCycle[otfWrPtr] <= cycleCounter;
                otfWrPtr <= (otfWrPtr + 1) % OTF_DEPTH;
                otfCount  <= otfCount + 1;
                creditReq <= creditReq - 1;
                reqAccepted <= 1;
                perfReqAccepted <= perfReqAccepted + 1;
            end

            case (state)
                FSM_IDLE: begin
                    if (!otfEmpty) begin
                        // Dequeue oldest transaction
                        curSrcId      <= otfSrcId[otfRdPtr];
                        curAddr        <= otfAddr[otfRdPtr];
                        curData        <= otfData[otfRdPtr];
                        curOpcode      <= otfOpcode[otfRdPtr];
                        curTxnId      <= otfTxnId[otfRdPtr];
                        curStartCycle <= otfEnqueueCycle[otfRdPtr];
                        curBurstBeat  <= 0;
                        otfValid[otfRdPtr] <= 0;
                        otfRdPtr <= (otfRdPtr + 1) % OTF_DEPTH;
                        otfCount  <= otfCount - 1;
                        state      <= FSM_CHECK_COALESCE;
                    end
                end

                FSM_CHECK_COALESCE: begin
                    // Check if we can coalesce with burst
                    if (addrSequential && (curOpcode == CHI_WRITE_BACK_FULL ||
                                            curOpcode == CHI_READ_SHARED ||
                                            curOpcode == CHI_READ_ONCE)) begin
                        burstLen <= burstLen + 1;
                        perfBurstCoalesced <= perfBurstCoalesced + 1;
                        state <= FSM_MEM_BURST;
                    end else begin
                        // Start new burst context
                        burstActive    <= 1;
                        burstBaseAddr <= curAddr;
                        burstLen       <= 0;
                        burstSrcId    <= curSrcId;
                        burstTxnId    <= curTxnId;
                        burstIsWrite  <= (curOpcode == CHI_WRITE_BACK_FULL ||
                                           curOpcode == CHI_WRITE_CLEAN ||
                                           curOpcode == CHI_WRITE_UNIQUE);

                        // Route based on opcode
                        case (curOpcode)
                            CHI_READ_SHARED,
                            CHI_READ_UNIQUE: state <= FSM_ISSUE_SNP;
                            CHI_READ_ONCE:   state <= FSM_MEM_REQ;
                            CHI_WRITE_BACK_FULL,
                            CHI_WRITE_CLEAN: state <= FSM_WRITEBACK;
                            CHI_WRITE_UNIQUE: state <= FSM_ISSUE_SNP;
                            CHI_MAKE_INVALID: state <= FSM_ISSUE_SNP;
                            CHI_EVICT:       state <= FSM_SEND_RSP;
                            default:         state <= FSM_SEND_RSP;
                        endcase
                    end
                end

                FSM_ISSUE_SNP: begin
                    snpValid    <= 1;
                    snpTgtMask <= {NUM_CORES{1'b1}} & ~(1 << curSrcId);
                    snpAddr     <= curAddr;
                    snpExpected <= 0;
                    snpReceived <= 0;
                    snpTimeout  <= 0;

                    case (curOpcode)
                        CHI_READ_SHARED:  snpOpcode <= CHI_SNP_SHARED;
                        CHI_READ_UNIQUE,
                        CHI_WRITE_UNIQUE,
                        CHI_MAKE_INVALID: snpOpcode <= CHI_SNP_CLEAN_INV;
                        default:          snpOpcode <= CHI_SNP_SHARED;
                    endcase

                    // Count expected snoop responses
                    begin : countSnoopees
                        integer c;
                        reg [4:0] cnt;
                        cnt = 0;
                        for (c = 0; c < NUM_CORES; c = c + 1)
                            if (c != curSrcId) cnt = cnt + 1;
                        snpExpected <= cnt;
                    end

                    perfSnpIssued <= perfSnpIssued + 1;
                    state <= FSM_WAIT_SNP;
                end

                FSM_WAIT_SNP: begin
                    snpTimeout <= snpTimeout + 1;
                    if (snpRespValid) begin
                        snpReceived <= snpReceived + 1;
                        snpFetchedData <= snpRespData;

                        if (snpReceived + 1 >= snpExpected || snpTimeout >= 256) begin
                            if (curOpcode == CHI_READ_SHARED || curOpcode == CHI_READ_UNIQUE)
                                state <= FSM_MEM_REQ;
                            else
                                state <= FSM_SEND_RSP;
                        end
                    end else if (snpTimeout >= 256) begin
                        // Timeout: proceed with memory
                        if (curOpcode == CHI_READ_SHARED || curOpcode == CHI_READ_UNIQUE)
                            state <= FSM_MEM_REQ;
                        else
                            state <= FSM_SEND_RSP;
                    end
                end

                FSM_MEM_REQ: begin
                    if (memReqReady) begin
                        memReqValid     <= 1;
                        memReqAddr      <= curAddr;
                        memReqWdata     <= curData;
                        memReqWrite     <= 0;
                        memReqBurstLen <= burstLen + 1;
                        state             <= FSM_WAIT_MEM;
                    end
                end

                FSM_MEM_BURST: begin
                    // Continue burst beats
                    if (memReqReady) begin
                        memReqValid     <= 1;
                        memReqAddr      <= curAddr;
                        memReqWdata     <= curData;
                        memReqWrite     <= burstIsWrite;
                        memReqBurstLen <= 1;
                        curBurstBeat    <= curBurstBeat + 1;
                        state             <= FSM_WAIT_MEM;
                    end
                end

                FSM_WAIT_MEM: begin
                    if (memRespValid) begin
                        state <= FSM_SEND_DAT;
                    end
                end

                FSM_SEND_DAT: begin
                    if (creditDat > 0) begin
                        datValid       <= 1;
                        datTgtId      <= curSrcId;
                        datTxnId      <= curTxnId;
                        datData        <= memRespData;
                        datByteEnable <= {(DATA_WIDTH/8){1'b1}};
                        creditDat      <= creditDat - 1;
                        perfDatTransfers <= perfDatTransfers + 1;
                        state           <= FSM_SEND_RSP;
                    end
                end

                FSM_SEND_RSP: begin
                    if (creditRsp > 0) begin
                        rspValid   <= 1;
                        rspTgtId  <= curSrcId;
                        rspTxnId  <= curTxnId;
                        rspOpcode  <= CHI_RSP_COMP;
                        rspResp    <= 2'b00; // OK
                        creditRsp  <= creditRsp - 1;
                        perfRspSent <= perfRspSent + 1;

                        // Return credit to REQ channel
                        if (creditReq < CREDIT_INIT) creditReq <= creditReq + 1;

                        // Latency tracking
                        begin : latencyCalc
                            reg [31:0] lat;
                            lat = cycleCounter - curStartCycle;
                            perfTotalLatencyCycles <= perfTotalLatencyCycles + lat;
                            if (lat > perfMaxLatency)
                                perfMaxLatency <= lat;
                        end

                        burstActive <= 0;
                        state <= FSM_IDLE;
                    end
                end

                FSM_WRITEBACK: begin
                    // Write data to memory backend
                    if (memReqReady) begin
                        memReqValid     <= 1;
                        memReqAddr      <= curAddr;
                        memReqWdata     <= curData;
                        memReqWrite     <= 1;
                        memReqBurstLen <= 1;
                        state             <= FSM_SEND_RSP;
                    end
                end

                default: state <= FSM_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
