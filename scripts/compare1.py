import numpy as np
import sys

N, DK = 2, 4

def read_hex_matrix(path, rows, cols, width_bits):
    m = []
    for line in open(path):
        t = line.split()
        if not t: continue
        m.append([ (int(x,16) - (1<<width_bits) if int(x,16) >= (1<<(width_bits-1)) else int(x,16)) for x in t])
    return np.array(m)

def compare(name, got, exp, tol):
    d = np.abs(got-exp).max(); print(name, "max diff", d, "tol", tol); return d <= tol

ok = True
ok &= compare("O", read_hex_matrix("../output/o.txt",N,DK,16), read_hex_matrix("../output/expected_o.txt",N,DK,16), 2)
try:
    ok &= compare("A", read_hex_matrix("../output/a.txt",N,N,18), read_hex_matrix("../input/a.txt",N,N,18), 32)
except FileNotFoundError:
    print("SKIP A")
print("ALL PASS" if ok else "SOME FAILURES"); sys.exit(0 if ok else 1)