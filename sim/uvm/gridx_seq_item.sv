// GridX3 UVM Sequence Items
// Transaction objects for host commands and memory operations.

`ifndef GRIDX_SEQ_ITEM_SV
`define GRIDX_SEQ_ITEM_SV

// Host command transaction
class gridx_host_seq_item extends uvm_sequence_item;

    typedef enum logic [2:0] {
        CMD_RESET       = 3'b000,
        CMD_LOAD_PROG   = 3'b001,
        CMD_WRITE_DMEM  = 3'b010,
        CMD_READ_DMEM   = 3'b011,
        CMD_CONFIGURE   = 3'b100,
        CMD_START       = 3'b101
    } cmd_type_e;

    // Transaction fields
    rand cmd_type_e              cmd_type;
    rand logic [15:0]            thread_count;
    rand logic [11:0]            prog_addr;
    rand logic [15:0]            prog_data;
    rand logic [21:0]            mem_addr;
    rand logic [7:0]             mem_data;

    // Program binary payload (for bulk program load)
    rand logic [15:0]            program_binary[];

    // Response fields (filled by driver/monitor after execution)
    logic [7:0]                  read_data;
    logic                        kernel_completed;
    logic                        kernel_faulted;
    logic [31:0]                 execution_cycles;

    // Constraints
    constraint c_thread_count {
        thread_count inside {[1:32]};
    }

    constraint c_prog_binary_size {
        program_binary.size() inside {[4:256]};
    }

    constraint c_prog_addr {
        prog_addr < 4096;
    }

    constraint c_mem_addr {
        mem_addr < 22'h100000; // Keep within addressable range
    }

    `uvm_object_utils_begin(gridx_host_seq_item)
        `uvm_field_enum(cmd_type_e, cmd_type, UVM_ALL_ON)
        `uvm_field_int(thread_count, UVM_ALL_ON)
        `uvm_field_int(prog_addr, UVM_ALL_ON)
        `uvm_field_int(prog_data, UVM_ALL_ON)
        `uvm_field_int(mem_addr, UVM_ALL_ON)
        `uvm_field_int(mem_data, UVM_ALL_ON)
        `uvm_field_array_int(program_binary, UVM_ALL_ON)
        `uvm_field_int(read_data, UVM_ALL_ON | UVM_NOCOMPARE)
        `uvm_field_int(kernel_completed, UVM_ALL_ON | UVM_NOCOMPARE)
        `uvm_field_int(kernel_faulted, UVM_ALL_ON | UVM_NOCOMPARE)
        `uvm_field_int(execution_cycles, UVM_ALL_ON | UVM_NOCOMPARE)
    `uvm_object_utils_end

    function new(string name = "gridx_host_seq_item");
        super.new(name);
    endfunction

    virtual function string convert2string();
        return $sformatf("CMD=%s thread_count=%0d prog_addr=0x%03h mem_addr=0x%06h",
                         cmd_type.name(), thread_count, prog_addr, mem_addr);
    endfunction
endclass


// Memory scoreboard entry — used by scoreboard to track expected vs actual
class gridx_mem_transaction extends uvm_sequence_item;

    logic [21:0] addr;
    logic [7:0]  data;
    logic        is_write;
    int unsigned cycle;

    `uvm_object_utils_begin(gridx_mem_transaction)
        `uvm_field_int(addr, UVM_ALL_ON)
        `uvm_field_int(data, UVM_ALL_ON)
        `uvm_field_int(is_write, UVM_ALL_ON)
        `uvm_field_int(cycle, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "gridx_mem_transaction");
        super.new(name);
    endfunction
endclass

`endif // GRIDX_SEQ_ITEM_SV
