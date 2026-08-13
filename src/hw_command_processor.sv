// Hardware Command Processor
// Autonomous task graph execution engine that tracks task dependencies and dispatches ready tasks.

`default_nettype none
`timescale 1ns/1ns

module hwCommandProcessor #(
    parameter MAX_TASKS = 32,
    parameter MAX_DEPS = 4,
    parameter CMD_WIDTH = 128,
    parameter TASK_ID_WIDTH = 5
) (
    input  wire clk,
    input  wire reset,
    
    // Host Submission Interface
    input  wire submitValid,
    input  wire [TASK_ID_WIDTH-1:0] submitTaskId,
    input  wire [CMD_WIDTH-1:0] submitCmd,
    input  wire [2:0] submitDepCount,
    input  wire [(MAX_DEPS*TASK_ID_WIDTH)-1:0] submitDepIds,
    output reg  submitReady,
    
    // Command Launch Interface (to Cores/NMC)
    output reg  launchValid,
    output reg  [TASK_ID_WIDTH-1:0] launchTaskId,
    output reg  [CMD_WIDTH-1:0] launchCmd,
    input  wire launchAck,
    
    // Completion Interface (from Cores/NMC)
    input  wire completeValid,
    input  wire [TASK_ID_WIDTH-1:0] completeTaskId,
    
    // Status
    output wire busy,
    output wire [31:0] tasksPending,
    output wire [31:0] tasksCompleted,
    output wire graphDone
);

    reg validTask [MAX_TASKS-1:0];
    reg [CMD_WIDTH-1:0] cmdArray [MAX_TASKS-1:0];
    reg [MAX_TASKS-1:0] depMatrix [MAX_TASKS-1:0]; // depMatrix[i][j] = 1 means task i depends on task j
    reg [MAX_TASKS-1:0] completedMask; // 1 means task is complete
    reg [MAX_TASKS-1:0] launchedMask;  // 1 means task has been sent for execution
    
    reg [31:0] pendingCnt;
    reg [31:0] compCnt;
    
    assign tasksPending = pendingCnt;
    assign tasksCompleted = compCnt;
    assign busy = (pendingCnt > 0);
    assign graphDone = (pendingCnt == 0 && compCnt > 0);
    
    integer i, j;
    
    // Find ready tasks
    reg [MAX_TASKS-1:0] readyMask;
    always @(*) begin
        readyMask = 0;
        for (i = 0; i < MAX_TASKS; i = i + 1) begin
            if (validTask[i] && !launchedMask[i] && !completedMask[i]) begin
                // A task is ready if all its dependencies are met (i.e. all dependencies are 1 in completedMask or 0 in depMatrix)
                if ((depMatrix[i] & ~completedMask) == 0) begin
                    readyMask[i] = 1;
                end
            end
        end
    end
    
    // Arbitrate among ready tasks
    reg [$clog2(MAX_TASKS)-1:0] nextLaunchId;
    reg nextLaunchValid;
    
    always @(*) begin
        nextLaunchId = 0;
        nextLaunchValid = 0;
        for (i = 0; i < MAX_TASKS; i = i + 1) begin
            if (readyMask[i] && !nextLaunchValid) begin
                nextLaunchValid = 1;
                nextLaunchId = i;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < MAX_TASKS; i = i + 1) begin
                validTask[i] <= 0;
                depMatrix[i] <= 0;
            end
            completedMask <= 0;
            launchedMask <= 0;
            pendingCnt <= 0;
            compCnt <= 0;
            
            submitReady <= 1;
            launchValid <= 0;
            launchTaskId <= 0;
            launchCmd <= 0;
        end else begin
            submitReady <= 1; // Can always submit if there are open slots (simplified)
            
            // 1. Process Submission
            if (submitValid) begin
                validTask[submitTaskId] <= 1;
                cmdArray[submitTaskId] <= submitCmd;
                
                // Build dependency mask
                for (j = 0; j < MAX_TASKS; j = j + 1) depMatrix[submitTaskId][j] <= 0;
                
                for (j = 0; j < MAX_DEPS; j = j + 1) begin
                    if (j < submitDepCount) begin
                        depMatrix[submitTaskId][ submitDepIds[(j*TASK_ID_WIDTH) +: TASK_ID_WIDTH] ] <= 1;
                    end
                end
                
                completedMask[submitTaskId] <= 0;
                launchedMask[submitTaskId] <= 0;
                pendingCnt <= pendingCnt + 1;
            end
            
            // 2. Process Completion
            if (completeValid) begin
                completedMask[completeTaskId] <= 1;
                pendingCnt <= pendingCnt - 1;
                compCnt <= compCnt + 1;
                validTask[completeTaskId] <= 0; // Free slot
            end
            
            // 3. Launching
            if (launchValid && launchAck) begin
                launchValid <= 0; // Launched
                launchedMask[launchTaskId] <= 1;
            end else if (!launchValid && nextLaunchValid) begin
                launchValid <= 1;
                launchTaskId <= nextLaunchId;
                launchCmd <= cmdArray[nextLaunchId];
            end
        end
    end

endmodule
