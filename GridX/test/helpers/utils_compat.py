"""
Cocotb 2.0 Compatibility Helpers (for test/helpers module)
============================================================
Re-exports from test.utils for use within helpers package.
"""

import sys
import os

# Add parent test directory to path for utils import
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from utils import sig_to_int, sig_to_bool, sig_to_str, sig_slice_to_int, CLOCK_PERIOD_NS, CLOCK_UNIT

__all__ = ['sig_to_int', 'sig_to_bool', 'sig_to_str', 'sig_slice_to_int', 'CLOCK_PERIOD_NS', 'CLOCK_UNIT']
