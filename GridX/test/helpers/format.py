from typing import List, Optional
from .logger import logger
from .utils_compat import sig_to_int, sig_to_str

def format_register(register: int) -> str:
    if register < 13:
        return f"R{register}"
    if register == 13:
        return f"%blockIdx"
    if register == 14:
        return f"%blockDim"
    if register == 15:
        return f"%threadIdx"
    return f"R{register}"
    
def format_instruction(instruction: str) -> str:
    # Handle X/Z values
    if 'x' in instruction.lower() or 'z' in instruction.lower():
        return "UNKNOWN (X/Z)"
    
    opcode = instruction[0:4]
    rd = format_register(int(instruction[4:8], 2))
    rs = format_register(int(instruction[8:12], 2))
    rt = format_register(int(instruction[12:16], 2))
    n = "N" if instruction[4] == '1' else ""
    z = "Z" if instruction[5] == '1' else ""
    p = "P" if instruction[6] == '1' else ""
    imm = f"#{int(instruction[8:16], 2)}"

    if opcode == "0000":
        return "NOP"
    elif opcode == "0001":
        return f"BRnzp {n}{z}{p}, {imm}"
    elif opcode == "0010":
        return f"CMP {rs}, {rt}"
    elif opcode == "0011":
        return f"ADD {rd}, {rs}, {rt}"
    elif opcode == "0100":
        return f"SUB {rd}, {rs}, {rt}"
    elif opcode == "0101":
        return f"MUL {rd}, {rs}, {rt}"
    elif opcode == "0110":
        return f"DIV {rd}, {rs}, {rt}"
    elif opcode == "0111":
        return f"LDR {rd}, {rs}"
    elif opcode == "1000":
        return f"STR {rs}, {rt}"
    elif opcode == "1001":
        return f"CONST {rd}, {imm}"
    elif opcode == "1010":
        return f"TILE_LD {rd}, {rs}"
    elif opcode == "1011":
        return f"TILE_ST {rs}, {rt}"
    elif opcode == "1100":
        return "DMA_SYNC"
    elif opcode == "1101":
        return "TILE_FENCE"
    elif opcode == "1111":
        return "RET"
    return "UNKNOWN"

def format_core_state(core_state: str) -> str:
    core_state_map = {
        "000": "IDLE",
        "001": "FETCH",
        "010": "DECODE",
        "011": "REQUEST",
        "100": "WAIT",
        "101": "EXECUTE",
        "110": "UPDATE",
        "111": "DONE"
    }
    return core_state_map.get(core_state, "UNKNOWN")

def format_fetcher_state(fetcher_state: str) -> str:
    fetcher_state_map = {
        "000": "IDLE",
        "001": "FETCHING",
        "010": "FETCHED"
    }
    return fetcher_state_map.get(fetcher_state, "UNKNOWN")

def format_lsu_state(lsu_state: str) -> str:
    lsu_state_map = {
        "00": "IDLE",
        "01": "REQUESTING",
        "10": "WAITING",
        "11": "DONE"
    }
    return lsu_state_map.get(lsu_state, "UNKNOWN")

def format_memory_controller_state(controller_state: str) -> str:
    controller_state_map = {
        "000": "IDLE",
        "001": "READING",
        "010": "WRITING"
    }
    return controller_state_map.get(controller_state, "UNKNOWN")

def format_registers(registers: List[str]) -> str:
    formatted_registers = []
    for i, reg_value in enumerate(registers):
        if 'x' in reg_value.lower() or 'z' in reg_value.lower():
            decimal_value = 0
        else:
            decimal_value = int(reg_value, 2)
        reg_idx = 15 - i
        formatted_registers.append(f"{format_register(reg_idx)} = {decimal_value}")
    formatted_registers.reverse()
    return ', '.join(formatted_registers)

def format_cycle(dut, cycle_id: int, thread_id: Optional[int] = None):
    """Format cycle information - cocotb 2.0 compatible"""
    logger.debug(f"\n================================== Cycle {cycle_id} ==================================")

    try:
        for core in dut.cores:
            # Use sig_to_int for all signal comparisons
            thread_count_val = sig_to_int(dut.thread_count)
            core_idx = sig_to_int(core.i)
            threads_per_block = sig_to_int(dut.THREADS_PER_BLOCK)
            
            if threads_per_block > 0 and thread_count_val <= core_idx * threads_per_block:
                continue

            logger.debug(f"\n+--------------------- Core {core_idx} ---------------------+")

            instruction = sig_to_str(core.core_instance.instruction)
            
            for thread in core.core_instance.threads:
                thread_i = sig_to_int(thread.i)
                core_thread_count = sig_to_int(core.core_instance.thread_count)
                
                if thread_i < core_thread_count:
                    block_idx = sig_to_int(core.core_instance.block_id)
                    block_dim = sig_to_int(core.core_instance.THREADS_PER_BLOCK)
                    thread_idx = sig_to_int(thread.register_instance.THREAD_ID)
                    idx = block_idx * block_dim + thread_idx

                    rs = sig_to_int(thread.register_instance.rs)
                    rt = sig_to_int(thread.register_instance.rt)

                    reg_input_mux = sig_to_int(core.core_instance.decoded_reg_input_mux)
                    alu_out = sig_to_int(thread.alu_instance.alu_out)
                    lsu_out = sig_to_int(thread.lsu_instance.lsu_out)
                    constant = sig_to_int(core.core_instance.decoded_immediate)

                    if thread_id is None or thread_id == idx:
                        logger.debug(f"\n+-------- Thread {idx} --------+")

                        logger.debug("PC:", sig_to_int(core.core_instance.current_pc))
                        logger.debug("Instruction:", format_instruction(instruction))
                        logger.debug("Core State:", format_core_state(sig_to_str(core.core_instance.core_state)))
                        logger.debug("Fetcher State:", format_fetcher_state(sig_to_str(core.core_instance.fetcher_state)))
                        logger.debug("LSU State:", format_lsu_state(sig_to_str(thread.lsu_instance.lsu_state)))
                        logger.debug("Registers:", format_registers([sig_to_str(item) for item in thread.register_instance.registers]))
                        logger.debug(f"RS = {rs}, RT = {rt}")

                        if reg_input_mux == 0:
                            logger.debug("ALU Out:", alu_out)
                        if reg_input_mux == 1:
                            logger.debug("LSU Out:", lsu_out)
                        if reg_input_mux == 2:
                            logger.debug("Constant:", constant)

            logger.debug("Core Done:", sig_to_str(core.core_instance.done))
    except Exception as e:
        # Gracefully handle missing signals during format
        logger.debug(f"Format error (may be normal during early cycles): {e}")