// HBM3 Controller Interface
// Manages high-bandwidth memory channel requests and refresh timing for 3D stacked DRAM.

`default_nettype none
`timescale 1ns/1ns

module hbm3Ctrl #(
    parameter NUM_STACKS     = 4,
    parameter CHANNELS_PER_STACK = 2,
    parameter ADDR_WIDTH     = 32,
    parameter DATA_WIDTH     = 512,
    parameter ROW_BITS       = 14,
    parameter COL_BITS       = 6,
    parameter BANK_BITS      = 5,
    parameter burstLen      = 4,

    parameter tRCD           = 7,
    parameter tRP            = 7,
    parameter tCL            = 11,
    parameter tWR            = 8,
    parameter tRRD           = 2
) (
    input  wire clk,
    input  wire reset,

    input  wire                    reqValid,
    input  wire [ADDR_WIDTH-1:0]   reqAddr,
    input  wire [DATA_WIDTH-1:0]   reqWdata,
    input  wire                    reqWrite,
    output reg                     reqReady,

    output reg                     respValid,
    output reg  [DATA_WIDTH-1:0]   respData,
    output reg  [ADDR_WIDTH-1:0]   respAddr,

    output reg  [$clog2(NUM_STACKS)-1:0]  phyStackSel,
    output reg                             phyChannelSel,
    output reg  [ROW_BITS-1:0]             phyRowAddr,
    output reg  [COL_BITS-1:0]             phyColAddr,
    output reg  [BANK_BITS-1:0]            phyBankAddr,
    output reg                             phyActivate,
    output reg                             phyRead,
    output reg                             phyWriteCmd,
    output reg                             phyPrecharge,
    output reg  [DATA_WIDTH-1:0]           phyWriteData,
    input  wire [DATA_WIDTH-1:0]           phyReadData,
    input  wire                            phyReadValid,

    output reg  [31:0]  totalReads,
    output reg  [31:0]  totalWrites,
    output reg  [31:0]  rowHits,
    output reg  [31:0]  rowMisses,
    output wire         controllerBusy
);

    localparam NUM_CHANNELS = NUM_STACKS * CHANNELS_PER_STACK;
    localparam NUM_BANKS = 1 << BANK_BITS;

    wire [$clog2(NUM_STACKS)-1:0] addrStack   = reqAddr[ADDR_WIDTH-1 -: $clog2(NUM_STACKS)];
    wire                           addrChannel = reqAddr[ADDR_WIDTH-$clog2(NUM_STACKS)-1];
    wire [BANK_BITS-1:0]           addrBank    = reqAddr[ROW_BITS+COL_BITS+BANK_BITS-1 : ROW_BITS+COL_BITS];
    wire [ROW_BITS-1:0]            addrRow     = reqAddr[ROW_BITS+COL_BITS-1 : COL_BITS];
    wire [COL_BITS-1:0]            addrCol     = reqAddr[COL_BITS-1 : 0];

    reg [ROW_BITS-1:0] openRow [NUM_BANKS-1:0];
    reg [NUM_BANKS-1:0] rowOpen;

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
    } hbmStateE;

    hbmStateE state;
    reg [3:0]   waitCounter;
    reg         pendingIsWrite;
    reg [ADDR_WIDTH-1:0] pendingAddr;
    reg [DATA_WIDTH-1:0] pendingWdata;
    reg [BANK_BITS-1:0]  pendingBank;
    reg [ROW_BITS-1:0]   pendingRow;
    reg [COL_BITS-1:0]   pendingCol;

    assign controllerBusy = (state != HBM_IDLE);

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            state         <= HBM_IDLE;
            reqReady     <= 0;
            respValid    <= 0;
            totalReads   <= 0;
            totalWrites  <= 0;
            rowHits      <= 0;
            rowMisses    <= 0;
            phyActivate  <= 0;
            phyRead      <= 0;
            phyWriteCmd <= 0;
            phyPrecharge <= 0;
            rowOpen      <= 0;
            waitCounter  <= 0;
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                openRow[i] <= 0;
            end
        end else begin
            reqReady     <= 0;
            respValid    <= 0;
            phyActivate  <= 0;
            phyRead      <= 0;
            phyWriteCmd <= 0;
            phyPrecharge <= 0;

            case (state)
                HBM_IDLE: begin
                    if (reqValid) begin
                        pendingIsWrite <= reqWrite;
                        pendingAddr     <= reqAddr;
                        pendingWdata    <= reqWdata;
                        pendingBank     <= addrBank;
                        pendingRow      <= addrRow;
                        pendingCol      <= addrCol;
                        phyStackSel    <= addrStack;
                        phyChannelSel  <= addrChannel;
                        phyBankAddr    <= addrBank;
                        reqReady        <= 1;
                        state            <= HBM_CHECK_ROW;
                        if (reqWrite) totalWrites <= totalWrites + 1;
                        else           totalReads  <= totalReads + 1;
                    end
                end

                HBM_CHECK_ROW: begin
                    if (rowOpen[pendingBank] && openRow[pendingBank] == pendingRow) begin

                        rowHits <= rowHits + 1;
                        if (pendingIsWrite) state <= HBM_WRITE;
                        else                  state <= HBM_READ;
                    end else begin

                        rowMisses <= rowMisses + 1;
                        if (rowOpen[pendingBank]) begin
                            state <= HBM_PRECHARGE;
                        end else begin
                            state <= HBM_ACTIVATE;
                        end
                    end
                end

                HBM_PRECHARGE: begin
                    phyPrecharge <= 1;
                    phyRowAddr  <= openRow[pendingBank];
                    rowOpen[pendingBank] <= 0;
                    waitCounter  <= tRP;
                    state         <= HBM_WAIT_tRP;
                end

                HBM_WAIT_tRP: begin
                    if (waitCounter == 0) state <= HBM_ACTIVATE;
                    else waitCounter <= waitCounter - 1;
                end

                HBM_ACTIVATE: begin
                    phyActivate <= 1;
                    phyRowAddr <= pendingRow;
                    openRow[pendingBank] <= pendingRow;
                    rowOpen[pendingBank] <= 1;
                    waitCounter <= tRCD;
                    state        <= HBM_WAIT_tRCD;
                end

                HBM_WAIT_tRCD: begin
                    if (waitCounter == 0) begin
                        if (pendingIsWrite) state <= HBM_WRITE;
                        else                  state <= HBM_READ;
                    end else begin
                        waitCounter <= waitCounter - 1;
                    end
                end

                HBM_READ: begin
                    phyRead     <= 1;
                    phyColAddr <= pendingCol;
                    waitCounter <= tCL;
                    state        <= HBM_WAIT_CL;
                end

                HBM_WRITE: begin
                    phyWriteCmd  <= 1;
                    phyColAddr   <= pendingCol;
                    phyWriteData <= pendingWdata;
                    state          <= HBM_IDLE;
                end

                HBM_WAIT_CL: begin
                    if (waitCounter == 0) begin
                        state <= HBM_RESPOND;
                    end else begin
                        waitCounter <= waitCounter - 1;
                    end

                    if (phyReadValid) begin
                        respData <= phyReadData;
                        respAddr <= pendingAddr;
                    end
                end

                HBM_RESPOND: begin
                    respValid <= 1;
                    state      <= HBM_IDLE;
                end

                default: state <= HBM_IDLE;
            endcase
        end
    end

endmodule
