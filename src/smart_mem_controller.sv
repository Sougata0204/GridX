`default_nettype none
`timescale 1ns/1ns

module smartMemController #(
    parameter NUM_CORES = 64,
    parameter ADDR_WIDTH = 22,
    parameter DATA_WIDTH = 8,
    parameter LOCAL_MEM_RANGE = 22'h07FFFF,
    parameter SEGMENT_CTRL_ADDR = 22'h00FFF0
)(
    input  wire clk,
    input  wire reset,

    // Core Memory Interfaces (Raw 16-bit physical from LSU, extended to 22 by LSU zero padding)
    input  wire [NUM_CORES-1:0]                  coreRdValid,
    input  wire [ADDR_WIDTH-1:0]                 coreRdAddr [NUM_CORES-1:0],
    output wire [NUM_CORES-1:0]                  coreRdReady,
    output wire [DATA_WIDTH-1:0]                 coreRdData [NUM_CORES-1:0],

    input  wire [NUM_CORES-1:0]                  coreWrValid,
    input  wire [ADDR_WIDTH-1:0]                 coreWrAddr [NUM_CORES-1:0],
    input  wire [DATA_WIDTH-1:0]                 coreWrData [NUM_CORES-1:0],
    output wire [NUM_CORES-1:0]                  coreWrReady,

    // Mesh Bridge Interfaces (Translated, HBM bounds)
    output wire [NUM_CORES-1:0]                  meshRdValid,
    output wire [ADDR_WIDTH-1:0]                 meshRdAddr [NUM_CORES-1:0],
    input  wire [NUM_CORES-1:0]                  meshRdReady,
    input  wire [DATA_WIDTH-1:0]                 meshRdData [NUM_CORES-1:0],

    output wire [NUM_CORES-1:0]                  meshWrValid,
    output wire [ADDR_WIDTH-1:0]                 meshWrAddr [NUM_CORES-1:0],
    output wire [DATA_WIDTH-1:0]                 meshWrData [NUM_CORES-1:0],
    input  wire [NUM_CORES-1:0]                  meshWrReady,
    input  wire [NUM_CORES-1:0]                  meshCreditsFull,
    output wire [NUM_CORES-1:0]                  coreCreditsFull,

    // Local BRAM Arbiter Interface
    output wire [NUM_CORES-1:0]                  localRdValid,
    output wire [ADDR_WIDTH-1:0]                 localRdAddr [NUM_CORES-1:0],
    input  wire [NUM_CORES-1:0]                  localRdReady,
    input  wire [DATA_WIDTH-1:0]                 localRdData [NUM_CORES-1:0],

    output wire [NUM_CORES-1:0]                  localWrValid,
    output wire [ADDR_WIDTH-1:0]                 localWrAddr [NUM_CORES-1:0],
    output wire [DATA_WIDTH-1:0]                 localWrData [NUM_CORES-1:0],
    input  wire [NUM_CORES-1:0]                  localWrReady
);

    // Segment Registers for each core
    reg [ADDR_WIDTH-1:0] segmentBase [0:NUM_CORES-1];

    genvar i;
    generate
        for (i = 0; i < NUM_CORES; i = i + 1) begin : coreRouting
            // Segment base control logic
            wire isCtrlWr = coreWrValid[i] && (coreWrAddr[i] == SEGMENT_CTRL_ADDR);
            
            always @(posedge clk) begin
                if (reset) begin
                    segmentBase[i] <= 0;
                end else if (isCtrlWr) begin
                    // Simple shift to load upper bits (e.g., writing 0x10 sets base to 0x100000)
                    segmentBase[i] <= {coreWrData[i][7:0], 14'h0};
                end
            end

            // Address Translation
            wire [ADDR_WIDTH-1:0] mappedRdAddr = coreRdAddr[i] + segmentBase[i];
            wire [ADDR_WIDTH-1:0] mappedWrAddr = coreWrAddr[i] + segmentBase[i];

            // Routing Logic
            wire routeRdMesh  = !isCtrlWr && (mappedRdAddr > LOCAL_MEM_RANGE);
            wire routeRdLocal = !isCtrlWr && (mappedRdAddr <= LOCAL_MEM_RANGE);
            wire routeWrMesh  = !isCtrlWr && (mappedWrAddr > LOCAL_MEM_RANGE);
            wire routeWrLocal = !isCtrlWr && (mappedWrAddr <= LOCAL_MEM_RANGE);

            // Output Valid Signals
            assign meshRdValid[i]  = coreRdValid[i] & routeRdMesh;
            assign localRdValid[i] = coreRdValid[i] & routeRdLocal;
            assign meshWrValid[i]  = coreWrValid[i] & routeWrMesh;
            assign localWrValid[i] = coreWrValid[i] & routeWrLocal;

            // Output Address/Data
            assign meshRdAddr[i]  = mappedRdAddr;
            assign localRdAddr[i] = mappedRdAddr;
            
            assign meshWrAddr[i]  = mappedWrAddr;
            assign localWrAddr[i] = mappedWrAddr;
            
            assign meshWrData[i]  = coreWrData[i];
            assign localWrData[i] = coreWrData[i];

            // Combinatorial Ready Signals
            // If writing to the control register, ready is immediate (combinatorial)
            assign coreRdReady[i] = (meshRdReady[i] & routeRdMesh) | 
                                      (localRdReady[i] & routeRdLocal);
                                      
            assign coreWrReady[i] = isCtrlWr | 
                                      (meshWrReady[i] & routeWrMesh) | 
                                      (localWrReady[i] & routeWrLocal);

            assign coreCreditsFull[i] = meshCreditsFull[i];

            // Read Data Mux
            assign coreRdData[i]  = routeRdMesh ? meshRdData[i] : localRdData[i];
            
            // synthesis translateOff
            if (i == 0) begin
                always @(posedge clk) begin
                    if (coreWrValid[0] && !reset && !isCtrlWr) begin
                        $display("[ADDR_DECODE_WAVE] Cycle %0t | LSU_Valid=1 | Base=0x%0x | CoreAddr=0x%0x | MappedAddr=0x%0x | LocalRange=0x%0x | routeMesh=%b | routeLocal=%b | meshWrValid=%b",
                            $time, segmentBase[0], coreWrAddr[0], mappedWrAddr, LOCAL_MEM_RANGE, routeWrMesh, routeWrLocal, meshWrValid[0]);
                    end
                end
            end
            // synthesis translateOn
        end
    endgenerate

endmodule
