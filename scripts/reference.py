"""reference for the scaled dot-product attention task.

Code to populate the input files the Verilog testbench will read, then computes the
floating-point reference output and prints every intermediate stage.

Problem size:
    N = 2
    D_MODEL = 4
    D_K = 4
"""

import numpy as np

N, D_MODEL, D_K = 2, 4, 4

# Inputs from the hand-worked example
X = np.array([[1, 2, 0, 1],
              [2, 0, 1, 1]])

WQ = np.array([[1, 0, 1, 0],
               [0, 1, 0, 1],
               [1, 0, 0, 1],
               [0, 1, 1, 0]])

WK = np.array([[1, 1, 0, 0],
               [0, 0, 1, 1],
               [1, 0, 1, 0],
               [0, 1, 0, 1]])

WV = np.array([[1, 0, 0, 1],
               [0, 2, 0, 0],
               [0, 0, 1, 0],
               [1, 0, 0, 1]])


def save_int_matrix(path, m):
    with open(path, "w") as f:
        for row in m:
            f.write(" ".join(str(int(v)) for v in row) + "\n")
            
def save_q88_hex_matrix(path, m):
    with open(path, "w") as f:
        for row in m:
            tokens = []
            for v in row:
                q88 = int(round(float(v) * 256)) & 0xFFFF
                tokens.append(f"{q88:04x}")
            f.write(" ".join(tokens) + "\n")

def save_q115_hex_matrix(path, m):
    """Write matrix as Q1.15 unsigned, 18-bit hex (top 2 bits zero)."""
    with open(path, "w") as f:
        for row in m:
            tokens = []
            for v in row:
                q = int(round(float(v) * 32768)) & 0x3FFFF  # 18 bits
                tokens.append(f"{q:05x}")
            f.write(" ".join(tokens) + "\n")

def save_exp_lut(path):
    """256 entries: round(32768 * 2^(-f/256)) for f = 0..255"""
    with open(path, "w") as f:
        for k in range(256):
            v = min(0xFFFF, int(round(32768.0 * (2.0 ** (-k / 256.0)))))
            f.write(f"{v:04x}\n")
            
def softmax_rows(s):
    shifted = s - s.max(axis=1, keepdims=True)
    e = np.exp(shifted)
    return e / e.sum(axis=1, keepdims=True)


def attention(x, wq, wk, wv, d_k):

    # Q, K, V matrices
    q = x @ wq
    k = x @ wk
    v = x @ wv

    # Sclaed dot product S = Q.K^T
    s = q @ k.T

    # Scaling S matrix by swrt(dk)
    s_scaled = s / np.sqrt(d_k)

    # Computing softmax of S
    w = softmax_rows(s_scaled)

    # Final output O = W.V  
    o = w @ v

    return q, k, v, s, s_scaled, w, o


if __name__ == "__main__":
    save_q88_hex_matrix("input/x.txt", X)
    save_q88_hex_matrix("input/wq.txt", WQ)
    save_q88_hex_matrix("input/wk.txt", WK)
    save_q88_hex_matrix("input/wv.txt", WV)

    q, k, v, s, s_scaled, w, o = attention(X, WQ, WK, WV, D_K)

    save_q88_hex_matrix("input/q.txt", q)
    save_q88_hex_matrix("input/k.txt", k)
    save_q88_hex_matrix("input/v.txt", v)
    save_q88_hex_matrix("input/s.txt", s)
    save_q88_hex_matrix("input/s_scaled.txt", s_scaled)

    save_q115_hex_matrix("input/a.txt", w)

    save_exp_lut("input/exp_lut.hex")
    np.savetxt("output/expected_output.txt", o, fmt="%.6f")
    

    for name, mat in [("Q", q), ("K", k), ("V", v), ("S = Q K^T", s),
                      ("S / sqrt(d_k)", s_scaled), ("softmax weights", w),
                      ("O (output)", o)]:
        print(f"{name}:\n{mat}\n")