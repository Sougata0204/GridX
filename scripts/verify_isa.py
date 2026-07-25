# ============================================================================
# GridX³ — Python Golden Model and Verification Script
# ============================================================================

import os
import sys

def main():
    print("=================================================")
    print(" GridX³ ISA Program Python Golden Model")
    print("=================================================")

    # Input arrays
    A = [2, 3, 5, 7]
    B = [11, 13, 17, 19]

    print(f"Inputs:")
    print(f"  Vector A: {A}")
    print(f"  Vector B: {B}")

    # 1. Vector Add Golden Model
    golden_C = [a + b for a, b in zip(A, B)]
    
    # 2. Matrix Multiply Golden Model (tensor unit behavior)
    # The tensor unit multiplies RS (first element A[0]) by RT (B[0..3])
    golden_D = [A[0] * b for b in B]

    # 3. Reduction Golden Model
    golden_sum = sum(golden_D)

    print("\nGolden Model Reference Outputs:")
    print(f"  Vector Add:       C = {golden_C}")
    print(f"  Matrix Multiply:  D = {golden_D}")
    print(f"  Reduction Sum:    {golden_sum}")

    # Check if simulation outputs are present
    sim_file = "xsim_work/sim_results.txt"
    if not os.path.exists(sim_file):
        # Check current directory too
        sim_file = "sim_results.txt"
        if not os.path.exists(sim_file):
            print(f"\n[INFO] Simulation results file 'sim_results.txt' not found yet.")
            print(f"       Run the simulation first using Vivado batch mode.")
            return

    print(f"\nLoading simulation outputs from '{sim_file}'...")
    try:
        with open(sim_file, "r") as f:
            lines = [line.strip() for line in f if line.strip()]
        
        if len(lines) < 5:
            print(f"[ERROR] Simulation results file has only {len(lines)} lines; expected at least 5.")
            sys.exit(1)
        
        sim_C = [int(x) for x in lines[0:4]]
        sim_sum = int(lines[4])

        print("\nSimulation Results:")
        print(f"  Vector Add C:    {sim_C}")
        print(f"  Reduction Sum:   {sim_sum}")

        # Verification
        print("\nComparing Results...")
        errors = 0

        # Vector Add compare
        if sim_C == golden_C:
            print("✓ Vector Add: MATCH")
        else:
            print(f"✗ Vector Add: MISMATCH! Expected {golden_C}, got {sim_C}")
            errors += 1

        # Reduction sum compare
        if sim_sum == golden_sum:
            print("✓ Reduction Sum: MATCH")
        else:
            print(f"✗ Reduction Sum: MISMATCH! Expected {golden_sum}, got {sim_sum}")
            errors += 1

        print("=================================================")
        if errors == 0:
            print(" VERIFICATION SUCCESSFUL! GridX results match Golden Model.")
            print("=================================================")
            sys.exit(0)
        else:
            print(f" VERIFICATION FAILED! {errors} mismatch(es) found.")
            print("=================================================")
            sys.exit(1)

    except Exception as e:
        print(f"[ERROR] Failed to process simulation results: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
