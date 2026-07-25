// Hardware Command Processor
// Autonomous task graph execution engine that tracks task dependencies and dispatches ready tasks.

`default_nettype none
`timescale 1ns/1ns

module hw_command_processor #(
    parameter MAX_TASKS = 32,
    parameter MAX_DEPS = 4,
    parameter CMD_WIDTH = 128,
    parameter TASK_ID_WIDTH = 5
) (
    input  wire clk,
    input  wire reset,
    
    // Host Submission Interface
    input  wire submit_valid,
    input  wire [TASK_ID_WIDTH-1:0] submit_task_id,
    input  wire [CMD_WIDTH-1:0] submit_cmd,
    input  wire [2:0] submit_dep_count,
    input  wire [(MAX_DEPS*TASK_ID_WIDTH)-1:0] submit_dep_ids,
    output reg  submit_ready,
    
    // Command Launch Interface (to Cores/NMC)
    output reg  launch_valid,
    output reg  [TASK_ID_WIDTH-1:0] launch_task_id,
    output reg  [CMD_WIDTH-1:0] launch_cmd,
    input  wire launch_ack,
    
    // Completion Interface (from Cores/NMC)
    input  wire complete_valid,
    input  wire [TASK_ID_WIDTH-1:0] complete_task_id,
    
    // Status
    output wire busy,
    output wire [31:0] tasks_pending,
    output wire [31:0] tasks_completed,
    output wire graph_done
);

    reg valid_task [MAX_TASKS-1:0];
    reg [CMD_WIDTH-1:0] cmd_array [MAX_TASKS-1:0];
    reg [MAX_TASKS-1:0] dep_matrix [MAX_TASKS-1:0]; // dep_matrix[i][j] = 1 means task i depends on task j
    reg [MAX_TASKS-1:0] completed_mask; // 1 means task is complete
    reg [MAX_TASKS-1:0] launched_mask;  // 1 means task has been sent for execution
    
    reg [31:0] pending_cnt;
    reg [31:0] comp_cnt;
    
    assign tasks_pending = pending_cnt;
    assign tasks_completed = comp_cnt;
    assign busy = (pending_cnt > 0);
    assign graph_done = (pending_cnt == 0 && comp_cnt > 0);
    
    integer i, j;
    
    // Find ready tasks
    reg [MAX_TASKS-1:0] ready_mask;
    always @(*) begin
        ready_mask = 0;
        for (i = 0; i < MAX_TASKS; i = i + 1) begin
            if (valid_task[i] && !launched_mask[i] && !completed_mask[i]) begin
                // A task is ready if all its dependencies are met (i.e. all dependencies are 1 in completed_mask or 0 in dep_matrix)
                if ((dep_matrix[i] & ~completed_mask) == 0) begin
                    ready_mask[i] = 1;
                end
            end
        end
    end
    
    // Arbitrate among ready tasks
    reg [$clog2(MAX_TASKS)-1:0] next_launch_id;
    reg next_launch_valid;
    
    always @(*) begin
        next_launch_id = 0;
        next_launch_valid = 0;
        for (i = 0; i < MAX_TASKS; i = i + 1) begin
            if (ready_mask[i] && !next_launch_valid) begin
                next_launch_valid = 1;
                next_launch_id = i;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < MAX_TASKS; i = i + 1) begin
                valid_task[i] <= 0;
                dep_matrix[i] <= 0;
            end
            completed_mask <= 0;
            launched_mask <= 0;
            pending_cnt <= 0;
            comp_cnt <= 0;
            
            submit_ready <= 1;
            launch_valid <= 0;
            launch_task_id <= 0;
            launch_cmd <= 0;
        end else begin
            submit_ready <= 1; // Can always submit if there are open slots (simplified)
            
            // 1. Process Submission
            if (submit_valid) begin
                valid_task[submit_task_id] <= 1;
                cmd_array[submit_task_id] <= submit_cmd;
                
                // Build dependency mask
                for (j = 0; j < MAX_TASKS; j = j + 1) dep_matrix[submit_task_id][j] <= 0;
                
                for (j = 0; j < MAX_DEPS; j = j + 1) begin
                    if (j < submit_dep_count) begin
                        dep_matrix[submit_task_id][ submit_dep_ids[(j*TASK_ID_WIDTH) +: TASK_ID_WIDTH] ] <= 1;
                    end
                end
                
                completed_mask[submit_task_id] <= 0;
                launched_mask[submit_task_id] <= 0;
                pending_cnt <= pending_cnt + 1;
            end
            
            // 2. Process Completion
            if (complete_valid) begin
                completed_mask[complete_task_id] <= 1;
                pending_cnt <= pending_cnt - 1;
                comp_cnt <= comp_cnt + 1;
                valid_task[complete_task_id] <= 0; // Free slot
            end
            
            // 3. Launching
            if (launch_valid && launch_ack) begin
                launch_valid <= 0; // Launched
                launched_mask[launch_task_id] <= 1;
            end else if (!launch_valid && next_launch_valid) begin
                launch_valid <= 1;
                launch_task_id <= next_launch_id;
                launch_cmd <= cmd_array[next_launch_id];
            end
        end
    end

endmodule
