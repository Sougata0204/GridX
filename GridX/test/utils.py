"""
Cocotb 2.0 Signal Utility Functions
====================================
Canonical signal value handling for cocotb 2.0 API compatibility.

All signal value comparisons MUST use these helpers:
  - sig_to_int(signal) -> int
  - sig_to_bool(signal) -> bool

FORBIDDEN patterns (cocotb 2.0 breaking changes):
  - dut.sig.value == 1           # LogicArray comparison fails
  - dut.sig.value.integer == 1   # BinaryValue deprecated
  - int(dut.sig.value) == 1      # Uncentralized, error-prone

REQUIRED patterns:
  - sig_to_int(dut.sig) == 1
  - sig_to_bool(dut.valid) is True
"""

from cocotb.types import LogicArray


def sig_to_int(signal) -> int:
    """
    Convert a cocotb signal to integer.
    
    Handles LogicArray (cocotb 2.0) safely.
    Returns 0 if signal contains X or Z values.
    
    Args:
        signal: A cocotb signal handle (dut.signal_name)
    
    Returns:
        int: Integer value of the signal
    """
    try:
        val = signal.value
        # Handle LogicArray with potential X/Z
        if isinstance(val, LogicArray):
            # Check for X/Z values
            str_val = str(val)
            if 'x' in str_val.lower() or 'z' in str_val.lower():
                return 0
            return int(val)
        return int(val)
    except (ValueError, TypeError):
        return 0


def sig_to_bool(signal) -> bool:
    """
    Convert a cocotb signal to boolean.
    
    Returns True if signal is non-zero.
    Returns False if signal is 0, X, or Z.
    
    Args:
        signal: A cocotb signal handle (dut.signal_name)
    
    Returns:
        bool: Boolean value of the signal
    """
    return sig_to_int(signal) != 0


def sig_to_str(signal) -> str:
    """
    Convert a cocotb signal to binary string.
    
    Safely handles LogicArray and returns raw binary representation
    including X/Z values if present.
    
    Args:
        signal: A cocotb signal handle (dut.signal_name)
    
    Returns:
        str: Binary string representation
    """
    try:
        return str(signal.value)
    except (ValueError, TypeError):
        return "X"


def sig_slice_to_int(signal, start: int, end: int) -> int:
    """
    Extract a bit slice from signal and convert to integer.
    
    Args:
        signal: A cocotb signal handle
        start: Start bit (inclusive, 0-indexed from MSB in string)
        end: End bit (exclusive)
    
    Returns:
        int: Integer value of the slice
    """
    try:
        str_val = str(signal.value)
        slice_str = str_val[start:end]
        if 'x' in slice_str.lower() or 'z' in slice_str.lower():
            return 0
        return int(slice_str, 2)
    except (ValueError, TypeError, IndexError):
        return 0


# Clock configuration constants
CLOCK_PERIOD_NS = 10
CLOCK_UNIT = "ns"
