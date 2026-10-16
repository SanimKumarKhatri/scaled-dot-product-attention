"""
Fixed-point quantization study for scaled dot-product attention.

Runs the same attention computation in:
  1. Floating point (reference)
  2. Fixed point at several (total_bits, frac_bits) formats

and reports error + saturation for each, so you can justify your
bit-width choice in the README.

Convention: a format is (total_bits, frac_bits).
  - Signed (two's complement)
  - Range: [-2^(total_bits-1), 2^(total_bits-1) - 2^-frac_bits]
  - Precision (LSB): 2^-frac_bits

Note on naming: "Q9.6" is ambiguous. (16, 6) is sometimes called Q10.6
(sign + 9 int + 6 frac) and sometimes Q9.6 (9 int including sign).
This script uses the unambiguous (total, frac) form.
"""

import numpy as np

np.random.seed(0)

# ---------------------------------------------------------------
# Quantization
# ---------------------------------------------------------------

class Stats:
    """Tracks saturation events across a run, grouped by stage."""
    def __init__(self):
        self.sat = {}
        self.total = {}

    def record(self, stage, n_sat, n_total):
        self.sat[stage] = self.sat.get(stage, 0) + n_sat
        self.total[stage] = self.total.get(stage, 0) + n_total

    def report(self):
        if not self.sat:
            return "    (no saturation)"
        lines = []
        for k in self.sat:
            pct = 100.0 * self.sat[k] / max(self.total[k], 1)
            flag = "  <-- OVERFLOW" if pct > 1.0 else ""
            lines.append(
                f"    {k:10s}: {self.sat[k]:5d}/{self.total[k]:5d} "
                f"({pct:5.2f}%){flag}"
            )
        return "\n".join(lines)


def quantize(x, total_bits, frac_bits, stats=None, stage=""):
    """
    Round x to a signed fixed-point format.

    Uses round-half-away-from-zero, which matches the typical hardware
    rounder (add 0.5 LSB, truncate). Python's round() uses banker's
    rounding, which would NOT match hardware.
    """
    scale = 2.0 ** frac_bits
    qmax = (2 ** (total_bits - 1) - 1) / scale
    qmin = -(2 ** (total_bits - 1)) / scale

    n_sat = int(np.sum((x > qmax) | (x < qmin)))
    if stats is not None:
        stats.record(stage, n_sat, x.size)

    x_clipped = np.clip(x, qmin, qmax)
    x_rounded = np.sign(x_clipped) * np.floor(
        np.abs(x_clipped) * scale + 0.5
    ) / scale
    return x_rounded


# ---------------------------------------------------------------
# Attention: floating-point reference
# ---------------------------------------------------------------

def attention_fp(X, WQ, WK, WV):
    Q = X @ WQ
    K = X @ WK
    V = X @ WV
    dk = Q.shape[-1]

    S = (Q @ K.T) / np.sqrt(dk)
    S = S - S.max(axis=-1, keepdims=True)      # numerical stability
    E = np.exp(S)
    A = E / E.sum(axis=-1, keepdims=True)
    return A @ V


# ---------------------------------------------------------------
# Attention: fixed-point, mirrors the hardware pipeline
# ---------------------------------------------------------------

def attention_q(X, WQ, WK, WV, fmt, stats=None):
    """
    Every intermediate is quantized, exactly as the hardware would
    store it in a buffer. This models error accumulation.
    """
    total_bits, frac_bits = fmt

    def q(a, stage):
        return quantize(a, total_bits, frac_bits, stats, stage)

    # Stage 1: quantize inputs (as loaded from the .hex files)
    Xq  = q(X,  "X")
    WQq = q(WQ, "WQ")
    WKq = q(WK, "WK")
    WVq = q(WV, "WV")

    # Stage 2: projections Q = X*WQ, etc.
    Q = q(Xq @ WQq, "Q")
    K = q(Xq @ WKq, "K")
    V = q(Xq @ WVq, "V")

    # Stage 3: raw scores, then scale
    dk = Q.shape[-1]
    S = q(Q @ K.T, "S_raw")
    S = q(S / np.sqrt(dk), "S_scaled")

    # Stage 4: softmax with max-subtraction
    S = q(S - S.max(axis=-1, keepdims=True), "S_shifted")
    E = q(np.exp(S), "exp")
    denom = q(E.sum(axis=-1, keepdims=True), "sum")
    A = q(E / denom, "attn")

    # Stage 5: output projection
    O = q(A @ V, "O")
    return O


# ---------------------------------------------------------------
# Experiment
# ---------------------------------------------------------------

def main():
    N, d = 4, 8              # tokens, embedding dimension

    # Realistic transformer initialization
    X  = np.random.randn(N, d)                     # unit variance, like post-LayerNorm
    WQ = np.random.randn(d, d) / np.sqrt(d)        # Xavier-like
    WK = np.random.randn(d, d) / np.sqrt(d)
    WV = np.random.randn(d, d) / np.sqrt(d)

    ref = attention_fp(X, WQ, WK, WV)

    print(f"N={N}, d={d}, Xavier-init weights")
    print(f"Float reference output:\n{np.round(ref, 4)}\n")

    formats = [
        ((16, 6),  "Q(16,6)"),
        ((16, 8),  "Q(16,8)"),
        ((16, 10), "Q(16,10)"),
        ((16, 12), "Q(16,12)"),
        ((8,  4),  "Q(8,4)"),
    ]

    print(f"{'format':12s} {'max_err':>10s} {'mean_err':>10s} "
          f"{'SNR (dB)':>10s}")
    print("-" * 46)

    for fmt, name in formats:
        stats = Stats()
        out = attention_q(X, WQ, WK, WV, fmt, stats)
        err = out - ref

        max_err = np.max(np.abs(err))
        mean_err = np.mean(np.abs(err))

        sig_p = np.mean(ref ** 2)
        noise_p = np.mean(err ** 2)
        snr = 10 * np.log10(sig_p / noise_p) if noise_p > 0 else float("inf")

        print(f"{name:12s} {max_err:10.5f} {mean_err:10.5f} {snr:10.2f}")
        print(stats.report())

    print()
    print("Rule of thumb: SNR > 40 dB is indistinguishable for a single")
    print("attention head. 20-40 dB is acceptable. Below 20 dB, the")
    print("output is visibly degraded.")


if __name__ == "__main__":
    main()