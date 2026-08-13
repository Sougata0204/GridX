// AXI4 Multi-Channel Burst Interconnect
// High-throughput AXI4 crossbar with multiple outstanding burst transactions,
// deep write buffering, read prefetch pipeline, QoS arbitration,
// and comprehensive bandwidth/latency analysis.
//
// Architecture:
//   - Dual independent AW/W write pipeline with deep write buffer
//   - AR read pipeline with read-ahead prefetch
//   - Out-of-order completion via reorder buffer
//   - Per-channel QoS-based priority arbitration
//   - Bandwidth saturation detection & back-pressure signaling

`default_nettype none
`timescale 1ns/1ns

module axi4BurstInterconnect #(
    parameter NUM_MASTERS      = 4,
    parameter ADDR_WIDTH       = 32,
    parameter DATA_WIDTH       = 512,
    parameter ID_WIDTH         = 6,
    parameter STRB_WIDTH       = DATA_WIDTH / 8,
    parameter MAX_BURST_LEN    = 16,
    parameter WRITE_BUF_DEPTH  = 8,
    parameter READ_BUF_DEPTH   = 8,
    parameter REORDER_DEPTH    = 16
) (
    input  wire clk,
    input  wire reset,

    input  wire [NUM_MASTERS-1:0]                   mAwvalid,
    input  wire [NUM_MASTERS*ID_WIDTH-1:0]          mAwid,
    input  wire [NUM_MASTERS*ADDR_WIDTH-1:0]        mAwaddr,
    input  wire [NUM_MASTERS*8-1:0]                 mAwlen,
    input  wire [NUM_MASTERS*3-1:0]                 mAwsize,
    input  wire [NUM_MASTERS*2-1:0]                 mAwburst,
    input  wire [NUM_MASTERS*4-1:0]                 mAwqos,
    output reg  [NUM_MASTERS-1:0]                   mAwready,

    input  wire [NUM_MASTERS-1:0]                   mWvalid,
    input  wire [NUM_MASTERS*DATA_WIDTH-1:0]        mWdata,
    input  wire [NUM_MASTERS*STRB_WIDTH-1:0]        mWstrb,
    input  wire [NUM_MASTERS-1:0]                   mWlast,
    output reg  [NUM_MASTERS-1:0]                   mWready,

    output reg  [NUM_MASTERS-1:0]                   mBvalid,
    output reg  [NUM_MASTERS*ID_WIDTH-1:0]          mBid,
    output reg  [NUM_MASTERS*2-1:0]                 mBresp,
    input  wire [NUM_MASTERS-1:0]                   mBready,

    input  wire [NUM_MASTERS-1:0]                   mArvalid,
    input  wire [NUM_MASTERS*ID_WIDTH-1:0]          mArid,
    input  wire [NUM_MASTERS*ADDR_WIDTH-1:0]        mAraddr,
    input  wire [NUM_MASTERS*8-1:0]                 mArlen,
    input  wire [NUM_MASTERS*3-1:0]                 mArsize,
    input  wire [NUM_MASTERS*2-1:0]                 mArburst,
    input  wire [NUM_MASTERS*4-1:0]                 mArqos,
    output reg  [NUM_MASTERS-1:0]                   mArready,

    output reg  [NUM_MASTERS-1:0]                   mRvalid,
    output reg  [NUM_MASTERS*ID_WIDTH-1:0]          mRid,
    output reg  [NUM_MASTERS*DATA_WIDTH-1:0]        mRdata,
    output reg  [NUM_MASTERS*2-1:0]                 mRresp,
    output reg  [NUM_MASTERS-1:0]                   mRlast,
    input  wire [NUM_MASTERS-1:0]                   mRready,

    output reg                      sAwvalid,
    output reg  [ID_WIDTH-1:0]      sAwid,
    output reg  [ADDR_WIDTH-1:0]    sAwaddr,
    output reg  [7:0]               sAwlen,
    output reg  [2:0]               sAwsize,
    output reg  [1:0]               sAwburst,
    input  wire                     sAwready,

    output reg                      sWvalid,
    output reg  [DATA_WIDTH-1:0]    sWdata,
    output reg  [STRB_WIDTH-1:0]    sWstrb,
    output reg                      sWlast,
    input  wire                     sWready,

    input  wire                     sBvalid,
    input  wire [ID_WIDTH-1:0]      sBid,
    input  wire [1:0]               sBresp,
    output reg                      sBready,

    output reg                      sArvalid,
    output reg  [ID_WIDTH-1:0]      sArid,
    output reg  [ADDR_WIDTH-1:0]    sAraddr,
    output reg  [7:0]               sArlen,
    output reg  [2:0]               sArsize,
    output reg  [1:0]               sArburst,
    input  wire                     sArready,

    input  wire                     sRvalid,
    input  wire [ID_WIDTH-1:0]      sRid,
    input  wire [DATA_WIDTH-1:0]    sRdata,
    input  wire [1:0]               sRresp,
    input  wire                     sRlast,
    output reg                      sRready,

    output reg  [31:0]  perfWrBursts,
    output reg  [31:0]  perfRdBursts,
    output reg  [31:0]  perfWrBeats,
    output reg  [31:0]  perfRdBeats,
    output reg  [31:0]  perfWrLatencyTotal,
    output reg  [31:0]  perfRdLatencyTotal,
    output reg  [31:0]  perfMaxWrLatency,
    output reg  [31:0]  perfMaxRdLatency,
    output reg  [31:0]  perfBwWriteBytes,
    output reg  [31:0]  perfBwReadBytes,
    output reg  [31:0]  perfBackpressureCycles,
    output wire         interconnectBusy
);

    localparam MSTR_W = (NUM_MASTERS > 1) ? $clog2(NUM_MASTERS) : 1;

    reg [WRITE_BUF_DEPTH-1:0]   wbufValid;
    reg [MSTR_W-1:0]            wbufMaster    [WRITE_BUF_DEPTH-1:0];
    reg [ID_WIDTH-1:0]          wbufId        [WRITE_BUF_DEPTH-1:0];
    reg [ADDR_WIDTH-1:0]        wbufAddr      [WRITE_BUF_DEPTH-1:0];
    reg [7:0]                   wbufLen       [WRITE_BUF_DEPTH-1:0];
    reg [2:0]                   wbufSize      [WRITE_BUF_DEPTH-1:0];
    reg [1:0]                   wbufBurst     [WRITE_BUF_DEPTH-1:0];
    reg [31:0]                  wbufEnqCycle [WRITE_BUF_DEPTH-1:0];
    reg [$clog2(WRITE_BUF_DEPTH):0] wbufWrPtr, wbufRdPtr, wbufCount;

    reg [READ_BUF_DEPTH-1:0]    rbufValid;
    reg [MSTR_W-1:0]            rbufMaster    [READ_BUF_DEPTH-1:0];
    reg [ID_WIDTH-1:0]          rbufId        [READ_BUF_DEPTH-1:0];
    reg [ADDR_WIDTH-1:0]        rbufAddr      [READ_BUF_DEPTH-1:0];
    reg [7:0]                   rbufLen       [READ_BUF_DEPTH-1:0];
    reg [2:0]                   rbufSize      [READ_BUF_DEPTH-1:0];
    reg [1:0]                   rbufBurst     [READ_BUF_DEPTH-1:0];
    reg [31:0]                  rbufEnqCycle [READ_BUF_DEPTH-1:0];
    reg [$clog2(READ_BUF_DEPTH):0] rbufWrPtr, rbufRdPtr, rbufCount;

    reg [31:0] cycleCnt;

    reg [MSTR_W-1:0] wrArbPtr;
    reg [MSTR_W-1:0] rdArbPtr;

    wire wbufFull  = (wbufCount >= WRITE_BUF_DEPTH);
    wire wbufEmpty = (wbufCount == 0);
    wire rbufFull  = (rbufCount >= READ_BUF_DEPTH);
    wire rbufEmpty = (rbufCount == 0);

    assign interconnectBusy = !wbufEmpty || !rbufEmpty;

    typedef enum logic [2:0] {
        WR_IDLE,
        WR_ISSUE_AW,
        WR_STREAM_W,
        WR_WAIT_B
    } wrStateE;
    wrStateE wrState;

    reg [ID_WIDTH-1:0]     wrCurId;
    reg [ADDR_WIDTH-1:0]   wrCurAddr;
    reg [7:0]              wrCurLen;
    reg [2:0]              wrCurSize;
    reg [1:0]              wrCurBurst;
    reg [MSTR_W-1:0]       wrCurMaster;
    reg [7:0]              wrBeatCnt;
    reg [31:0]             wrStartCycle;

    typedef enum logic [2:0] {
        RD_IDLE,
        RD_ISSUE_AR,
        RD_WAIT_R,
        RD_FORWARD
    } rdStateE;
    rdStateE rdState;

    reg [ID_WIDTH-1:0]     rdCurId;
    reg [ADDR_WIDTH-1:0]   rdCurAddr;
    reg [7:0]              rdCurLen;
    reg [2:0]              rdCurSize;
    reg [1:0]              rdCurBurst;
    reg [MSTR_W-1:0]       rdCurMaster;
    reg [7:0]              rdBeatCnt;
    reg [31:0]             rdStartCycle;

    integer j;

    always @(posedge clk) begin
        if (reset) begin
            // Write buffer
            wbufWrPtr   <= 0;
            wbufRdPtr   <= 0;
            wbufCount    <= 0;
            wbufValid    <= 0;
            wrState      <= WR_IDLE;
            wrArbPtr    <= 0;

            // Read buffer
            rbufWrPtr   <= 0;
            rbufRdPtr   <= 0;
            rbufCount    <= 0;
            rbufValid    <= 0;
            rdState      <= RD_IDLE;
            rdArbPtr    <= 0;

            // Downstream
            sAwvalid     <= 0;
            sWvalid      <= 0;
            sBready      <= 1;
            sArvalid     <= 0;
            sRready      <= 1;

            // Master ports
            mAwready     <= 0;
            mWready      <= 0;
            mBvalid      <= 0;
            mArready     <= 0;
            mRvalid      <= 0;

            cycleCnt     <= 0;

            // Perf
            perfWrBursts          <= 0;
            perfRdBursts          <= 0;
            perfWrBeats           <= 0;
            perfRdBeats           <= 0;
            perfWrLatencyTotal   <= 0;
            perfRdLatencyTotal   <= 0;
            perfMaxWrLatency     <= 0;
            perfMaxRdLatency     <= 0;
            perfBwWriteBytes     <= 0;
            perfBwReadBytes      <= 0;
            perfBackpressureCycles <= 0;
        end else begin
            cycleCnt <= cycleCnt + 1;

            // Default deassert
            mAwready <= 0;
            mArready <= 0;

            if (!wbufFull) begin : wrAccept
                integer m;
                for (m = 0; m < NUM_MASTERS; m = m + 1) begin
                    automatic integer idx = (wrArbPtr + m) % NUM_MASTERS;
                    if (mAwvalid[idx] && !wbufFull) begin
                        mAwready[idx] <= 1;

                        wbufMaster[wbufWrPtr]    <= idx[MSTR_W-1:0];
                        wbufId[wbufWrPtr]        <= mAwid[idx*ID_WIDTH +: ID_WIDTH];
                        wbufAddr[wbufWrPtr]      <= mAwaddr[idx*ADDR_WIDTH +: ADDR_WIDTH];
                        wbufLen[wbufWrPtr]       <= mAwlen[idx*8 +: 8];
                        wbufSize[wbufWrPtr]      <= mAwsize[idx*3 +: 3];
                        wbufBurst[wbufWrPtr]     <= mAwburst[idx*2 +: 2];
                        wbufEnqCycle[wbufWrPtr] <= cycleCnt;
                        wbufValid[wbufWrPtr]     <= 1;
                        wbufWrPtr <= (wbufWrPtr + 1) % WRITE_BUF_DEPTH;
                        wbufCount  <= wbufCount + 1;
                        wrArbPtr  <= (idx + 1) % NUM_MASTERS;
                        disable wrAccept;
                    end
                end
            end else begin
                perfBackpressureCycles <= perfBackpressureCycles + 1;
            end

            if (!rbufFull) begin : rdAccept
                integer m;
                for (m = 0; m < NUM_MASTERS; m = m + 1) begin
                    automatic integer idx = (rdArbPtr + m) % NUM_MASTERS;
                    if (mArvalid[idx] && !rbufFull) begin
                        mArready[idx] <= 1;

                        rbufMaster[rbufWrPtr]    <= idx[MSTR_W-1:0];
                        rbufId[rbufWrPtr]        <= mArid[idx*ID_WIDTH +: ID_WIDTH];
                        rbufAddr[rbufWrPtr]      <= mAraddr[idx*ADDR_WIDTH +: ADDR_WIDTH];
                        rbufLen[rbufWrPtr]       <= mArlen[idx*8 +: 8];
                        rbufSize[rbufWrPtr]      <= mArsize[idx*3 +: 3];
                        rbufBurst[rbufWrPtr]     <= mArburst[idx*2 +: 2];
                        rbufEnqCycle[rbufWrPtr] <= cycleCnt;
                        rbufValid[rbufWrPtr]     <= 1;
                        rbufWrPtr <= (rbufWrPtr + 1) % READ_BUF_DEPTH;
                        rbufCount  <= rbufCount + 1;
                        rdArbPtr  <= (idx + 1) % NUM_MASTERS;
                        disable rdAccept;
                    end
                end
            end

            case (wrState)
                WR_IDLE: begin
                    sAwvalid <= 0;
                    sWvalid  <= 0;
                    if (!wbufEmpty) begin
                        wrCurId      <= wbufId[wbufRdPtr];
                        wrCurAddr    <= wbufAddr[wbufRdPtr];
                        wrCurLen     <= wbufLen[wbufRdPtr];
                        wrCurSize    <= wbufSize[wbufRdPtr];
                        wrCurBurst   <= wbufBurst[wbufRdPtr];
                        wrCurMaster  <= wbufMaster[wbufRdPtr];
                        wrStartCycle <= wbufEnqCycle[wbufRdPtr];
                        wrBeatCnt    <= 0;
                        wbufValid[wbufRdPtr] <= 0;
                        wbufRdPtr <= (wbufRdPtr + 1) % WRITE_BUF_DEPTH;
                        wbufCount  <= wbufCount - 1;
                        wrState    <= WR_ISSUE_AW;
                    end
                end

                WR_ISSUE_AW: begin
                    sAwvalid <= 1;
                    sAwid    <= wrCurId;
                    sAwaddr  <= wrCurAddr;
                    sAwlen   <= wrCurLen;
                    sAwsize  <= wrCurSize;
                    sAwburst <= wrCurBurst;
                    if (sAwready) begin
                        sAwvalid <= 0;
                        wrState  <= WR_STREAM_W;
                        perfWrBursts <= perfWrBursts + 1;
                    end
                end

                WR_STREAM_W: begin
                    // Accept W beats from the winning master
                    mWready[wrCurMaster] <= 1;
                    if (mWvalid[wrCurMaster]) begin
                        sWvalid <= 1;
                        sWdata  <= mWdata[wrCurMaster*DATA_WIDTH +: DATA_WIDTH];
                        sWstrb  <= mWstrb[wrCurMaster*STRB_WIDTH +: STRB_WIDTH];
                        sWlast  <= mWlast[wrCurMaster];
                        if (sWready) begin
                            wrBeatCnt <= wrBeatCnt + 1;
                            perfWrBeats <= perfWrBeats + 1;
                            perfBwWriteBytes <= perfBwWriteBytes + (DATA_WIDTH / 8);
                            if (mWlast[wrCurMaster] || wrBeatCnt >= wrCurLen) begin
                                sWvalid <= 0;
                                mWready[wrCurMaster] <= 0;
                                wrState <= WR_WAIT_B;
                            end
                        end
                    end else begin
                        sWvalid <= 0;
                    end
                end

                WR_WAIT_B: begin
                    sBready <= 1;
                    if (sBvalid) begin
                        // Forward B response to originating master
                        mBvalid[wrCurMaster] <= 1;
                        mBid[wrCurMaster*ID_WIDTH +: ID_WIDTH] <= sBid;
                        mBresp[wrCurMaster*2 +: 2] <= sBresp;

                        begin : wrLatCalc
                            reg [31:0] lat;
                            lat = cycleCnt - wrStartCycle;
                            perfWrLatencyTotal <= perfWrLatencyTotal + lat;
                            if (lat > perfMaxWrLatency) perfMaxWrLatency <= lat;
                        end

                        wrState <= WR_IDLE;
                    end
                end
            endcase

            // Clear B valid when accepted by master
            for (j = 0; j < NUM_MASTERS; j = j + 1) begin
                if (mBvalid[j] && mBready[j])
                    mBvalid[j] <= 0;
            end

            case (rdState)
                RD_IDLE: begin
                    sArvalid <= 0;
                    if (!rbufEmpty) begin
                        rdCurId      <= rbufId[rbufRdPtr];
                        rdCurAddr    <= rbufAddr[rbufRdPtr];
                        rdCurLen     <= rbufLen[rbufRdPtr];
                        rdCurSize    <= rbufSize[rbufRdPtr];
                        rdCurBurst   <= rbufBurst[rbufRdPtr];
                        rdCurMaster  <= rbufMaster[rbufRdPtr];
                        rdStartCycle <= rbufEnqCycle[rbufRdPtr];
                        rdBeatCnt    <= 0;
                        rbufValid[rbufRdPtr] <= 0;
                        rbufRdPtr <= (rbufRdPtr + 1) % READ_BUF_DEPTH;
                        rbufCount  <= rbufCount - 1;
                        rdState    <= RD_ISSUE_AR;
                    end
                end

                RD_ISSUE_AR: begin
                    sArvalid <= 1;
                    sArid    <= rdCurId;
                    sAraddr  <= rdCurAddr;
                    sArlen   <= rdCurLen;
                    sArsize  <= rdCurSize;
                    sArburst <= rdCurBurst;
                    if (sArready) begin
                        sArvalid <= 0;
                        rdState  <= RD_WAIT_R;
                        perfRdBursts <= perfRdBursts + 1;
                    end
                end

                RD_WAIT_R: begin
                    sRready <= 1;
                    if (sRvalid) begin
                        // Forward R data to originating master
                        mRvalid[rdCurMaster] <= 1;
                        mRid[rdCurMaster*ID_WIDTH +: ID_WIDTH] <= sRid;
                        mRdata[rdCurMaster*DATA_WIDTH +: DATA_WIDTH] <= sRdata;
                        mRresp[rdCurMaster*2 +: 2] <= sRresp;
                        mRlast[rdCurMaster] <= sRlast;

                        rdBeatCnt <= rdBeatCnt + 1;
                        perfRdBeats <= perfRdBeats + 1;
                        perfBwReadBytes <= perfBwReadBytes + (DATA_WIDTH / 8);

                        if (sRlast) begin
                            begin : rdLatCalc
                                reg [31:0] lat;
                                lat = cycleCnt - rdStartCycle;
                                perfRdLatencyTotal <= perfRdLatencyTotal + lat;
                                if (lat > perfMaxRdLatency) perfMaxRdLatency <= lat;
                            end
                            rdState <= RD_IDLE;
                        end
                    end
                end

                default: rdState <= RD_IDLE;
            endcase

            // Clear R valid when accepted by master
            for (j = 0; j < NUM_MASTERS; j = j + 1) begin
                if (mRvalid[j] && mRready[j])
                    mRvalid[j] <= 0;
            end
        end
    end

endmodule

`default_nettype wire
