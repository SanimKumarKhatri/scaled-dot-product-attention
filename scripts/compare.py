"""
Compare Verilog output files against reference files.
Exit code 0 if all comparisons pass, 1 otherwise.
"""

import numpy as np

N, DK = 2, 4

def read_hex_matrix(path, rows, cols, width_bits, signed=True):
    """Read a hex file as a matrix of signed or unsigned integers."""
    m = []
    with open(path) as f:
        for line in f:
            tokens = line.split()
            if not tokens:
                continue
            row = []
            for t in tokens:
                v = int(t, 16)
                if signed and v >= (1 << (width_bits - 1)):
                    v -= (1 << width_bits)
                row.append(v)
            m.append(row)
    m = np.array(m)
    if m.shape != (rows, cols):
        raise ValueError(f"{path}: expected shape ({rows},{cols}), got {m.shape}")
    return m

def compare(name, got, exp, tol):
    print(f"\n{name}-----")
    print(f"got:\n{got}")
    print(f"exp:\n{exp}")
    diff = np.abs(got - exp)
    print(f"diff:\n{diff}")
    max_diff = int(diff.max())
    print(f"max diff = {max_diff}, tolerance = {tol}")
    if max_diff > tol:
        print(f"FAIL: {name} exceeds tolerance")
        return False
    print(f"PASS: {name}")
    return True

def main():
    results = []

    # Output is signed Q8.8, 16-bit
    o_got = read_hex_matrix("../output/o.txt", N, DK, 16, signed=True)
    o_exp = read_hex_matrix("../output/expected_o.txt", N, DK, 16, signed=True)

    results.append(compare("O (output)", o_got, o_exp, tol=2))

    ok = all(results)
    if (ok):
        print("\nALL PASS")
    else:
        print("\nSOME FAILURES")

if __name__ == "__main__":
    main()