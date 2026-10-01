#!/usr/bin/env python3
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
    save_int_matrix("input/x.txt", X)
    save_int_matrix("input/wq.txt", WQ)
    save_int_matrix("input/wk.txt", WK)
    save_int_matrix("input/wv.txt", WV)

    q, k, v, s, s_scaled, w, o = attention(X, WQ, WK, WV, D_K)

    for name, mat in [("Q", q), ("K", k), ("V", v), ("S = Q K^T", s),
                      ("S / sqrt(d_k)", s_scaled), ("softmax weights", w),
                      ("O (output)", o)]:
        print(f"{name}:\n{mat}\n")

    np.savetxt("output/expected_output.txt", o, fmt="%.6f")
    print("filled input/x.txt input/wq.txt input/wk.txt input/wv.txt output/expected_output.txt")