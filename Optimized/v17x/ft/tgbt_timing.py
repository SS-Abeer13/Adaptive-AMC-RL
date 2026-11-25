"""tgbt_timing.py -- T-GBT decision timing benchmark (Amendment 13, Section 7).
Reuses the A3c benchmark harness and protocol:
  - Strictly single-threaded (OMP/OPENBLAS/MKL/VECLIB/NUMEXPR = 1)
  - HIGH_PRIORITY_CLASS
  - Empty loop noise floor subtracted
  - Times complete decision: 1-frame 19-feature build + candidate MCS scoring + tbs*p_hat + argmax
  - Evaluated for GBT-res-ACK fit 1 (3 actions: -3:-1) and GBT-full-ACK fit 1 (7 actions: -4:+2)
  - Outputs Optimized/v17x/Dataset/ft/tgbt_timing.txt
"""
import os
import sys

os.environ["OMP_NUM_THREADS"] = "1"
os.environ["OPENBLAS_NUM_THREADS"] = "1"
os.environ["MKL_NUM_THREADS"] = "1"
os.environ["VECLIB_MAXIMUM_THREADS"] = "1"
os.environ["NUMEXPR_NUM_THREADS"] = "1"

import time
import platform
import subprocess
import joblib
import psutil
import numpy as np
import pandas as pd

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
DATASET_DIR = os.path.join(REPO_ROOT, "Optimized", "v17x", "Dataset")
FT_OUT_DIR = os.path.join(DATASET_DIR, "ft")
os.makedirs(FT_OUT_DIR, exist_ok=True)


def construct_s_now_1frame(ref_in, prevRef_in, obs_in, prev_obs_in, obs_4_in, off_in,
                           nk_in, H_pend_in, H_nret_in, r_ema_in, sl_in, busy_cnt_in, ctx_in, N, Dm=10.0):
    """Build the 19-feature current-frame matrix (N x 19), matching evalPolicy_presub.m lines 310-312 & 500-502."""
    dRef = np.clip(ref_in - prevRef_in, -3, 3)
    dS = obs_in - prev_obs_in
    slope4 = (obs_in - obs_4_in) * 0.25
    r_max = np.max(r_ema_in)
    r_norm = r_ema_in / r_max if r_max > 1e-6 else np.zeros_like(r_ema_in)

    s_now = np.empty((N, 19), dtype=np.float64)
    s_now[:, 0] = ref_in / 15.0
    s_now[:, 1] = dRef / 5.0
    s_now[:, 2] = obs_in / 30.0
    s_now[:, 3] = dS / 5.0
    s_now[:, 4] = off_in / 5.0
    s_now[:, 5] = slope4 / 5.0
    s_now[:, 6] = nk_in
    s_now[:, 7] = H_pend_in
    s_now[:, 8] = H_nret_in / 3.0
    s_now[:, 9] = r_norm
    s_now[:, 10] = np.minimum(sl_in, Dm) / Dm
    s_now[:, 11] = 1.0
    s_now[:, 12] = 0.0
    s_now[:, 13] = busy_cnt_in / 8.0
    s_now[:, 14] = 0.0
    s_now[:, 15] = 0.0
    s_now[:, 16:19] = ctx_in
    return s_now


def gbt_decision_step(clf, s_now, ref_in, bits_rem, offsets, tbs_lut):
    """Complete GBT-ACK decision: candidate MCS expansion, batch scoring, utility tbs*p_hat, argmax."""
    N = len(ref_in)
    K = len(offsets)
    # Candidate CQI [1..15] -> MCS [0..14]
    cand_cqi = np.clip(ref_in[:, None] + offsets[None, :], 1, 15)
    cand_mcs = np.clip(cand_cqi - 1, 0, 14)  # (N, K)

    # Build (N*K, 20) feature matrix: [obs19, mcs]
    X_cand = np.empty((N * K, 20), dtype=np.float64)
    X_cand[:, :19] = np.repeat(s_now, K, axis=0)
    X_cand[:, 19] = cand_mcs.ravel()

    # Score candidate MCS probabilities
    p_hat = clf.predict_proba(X_cand)[:, 1].reshape(N, K)
    tb = tbs_lut[cand_mcs]
    ub = np.minimum(tb, bits_rem[:, None])
    q = p_hat * ub
    best_k = np.argmax(q, axis=1)
    chosen_mcs = cand_mcs[np.arange(N), best_k]
    return chosen_mcs


def main():
    try:
        p = psutil.Process()
        p.nice(psutil.HIGH_PRIORITY_CLASS)
        prio_str = "HIGH_PRIORITY_CLASS (128)"
    except Exception as e:
        prio_str = f"Default ({e})"

    try:
        power_out = subprocess.check_output("powercfg /getactivescheme", shell=True, text=True).strip()
    except Exception:
        power_out = "Unknown"

    model_path = os.path.join(DATASET_DIR, "r1b_model.joblib")
    clf = joblib.load(model_path)

    # Load stored A3c values for comparison
    a3c_csv = os.path.join(DATASET_DIR, "table_a3c.csv")
    a3c_df = pd.read_csv(a3c_csv)

    # TBS LUT for 50 RBs, MCS 0..14 (exact monotonic table for timing)
    tbs_lut = np.array([1376, 1736, 2216, 2856, 3624, 4392, 5160, 6200, 7224,
                        8248, 9528, 10680, 12216, 13536, 15264], dtype=np.float64)

    n_warm = 100
    n_ttis = 5000  # 5,000 TTIs per condition (~3 min total)

    # Measure timer noise floor
    for _ in range(n_warm):
        t0 = time.perf_counter_ns()
        _ = (time.perf_counter_ns() - t0)

    t_noise = np.empty(n_ttis, dtype=np.float64)
    for it in range(n_ttis):
        t0 = time.perf_counter_ns()
        t_noise[it] = (time.perf_counter_ns() - t0) / 1000.0
    noise_med = float(np.median(t_noise))
    noise_p999 = float(np.percentile(t_noise, 99.9))

    res_offsets = np.array([-3, -2, -1], dtype=np.int32)
    full_offsets = np.array([-4, -3, -2, -1, 0, 1, 2], dtype=np.int32)

    lines = []
    lines.append("=" * 88)
    lines.append("T-GBT DECISION TIMING BENCHMARK (Amendment 13, Section 7 -- A3c Protocol)")
    lines.append("=" * 88)
    lines.append(f"Power Scheme     : {power_out}")
    lines.append(f"Process Priority : {prio_str}")
    lines.append(f"CPU Model        : {platform.processor()}")
    lines.append(f"Threading        : Single-Threaded (OMP=1, MKL=1, OPENBLAS=1)")
    lines.append(f"Sample Count     : {n_ttis:,} TTIs per condition ({n_warm:,} warm-up excluded)")
    lines.append(f"Noise Floor      : median = {noise_med:.3f} us | p99.9 = {noise_p999:.3f} us")
    lines.append(f"Model            : r1b_model.joblib (HistGradientBoostingClassifier, 300 trees, max_leaf=31)")
    lines.append("")

    for N in [10, 50, 100]:
        rng = np.random.RandomState(60001 + N)
        ref = rng.randint(1, 16, size=N).astype(np.int32)
        prevRef = ref.copy()
        obs_SINR = rng.randn(N).astype(np.float64) * 8.0 + 10.0
        prev_obs = obs_SINR.copy()
        obs_4 = obs_SINR.copy()
        off = np.zeros(N, dtype=np.float64)
        nk = rng.rand(N).astype(np.float64) * 0.2
        H_pend = (rng.rand(N) > 0.5).astype(np.float64)
        H_nret = rng.randint(0, 4, size=N).astype(np.float64)
        r_ema = rng.rand(N).astype(np.float64) * 50.0
        sl = rng.randint(1, 11, size=N).astype(np.float64)
        busy_cnt = rng.randint(0, 5, size=N).astype(np.float64)
        bits_rem = rng.randint(500, 10000, size=N).astype(np.float64)
        ctx = np.zeros((N, 3), dtype=np.float64)
        ctx[:, 0] = 1.0

        # Warmup and time GBT-res-ACK
        for _ in range(n_warm):
            s = construct_s_now_1frame(ref, prevRef, obs_SINR, prev_obs, obs_4, off, nk, H_pend, H_nret, r_ema, sl, busy_cnt, ctx, N)
            _ = gbt_decision_step(clf, s, ref, bits_rem, res_offsets, tbs_lut)
        t_res = np.empty(n_ttis, dtype=np.float64)
        for it in range(n_ttis):
            t0 = time.perf_counter_ns()
            s = construct_s_now_1frame(ref, prevRef, obs_SINR, prev_obs, obs_4, off, nk, H_pend, H_nret, r_ema, sl, busy_cnt, ctx, N)
            _ = gbt_decision_step(clf, s, ref, bits_rem, res_offsets, tbs_lut)
            t_res[it] = (time.perf_counter_ns() - t0) / 1000.0

        # Warmup and time GBT-full-ACK
        for _ in range(n_warm):
            s = construct_s_now_1frame(ref, prevRef, obs_SINR, prev_obs, obs_4, off, nk, H_pend, H_nret, r_ema, sl, busy_cnt, ctx, N)
            _ = gbt_decision_step(clf, s, ref, bits_rem, full_offsets, tbs_lut)
        t_full = np.empty(n_ttis, dtype=np.float64)
        for it in range(n_ttis):
            t0 = time.perf_counter_ns()
            s = construct_s_now_1frame(ref, prevRef, obs_SINR, prev_obs, obs_4, off, nk, H_pend, H_nret, r_ema, sl, busy_cnt, ctx, N)
            _ = gbt_decision_step(clf, s, ref, bits_rem, full_offsets, tbs_lut)
            t_full[it] = (time.perf_counter_ns() - t0) / 1000.0

        # Fetch stored A3c NR2 values
        row_np = a3c_df[(a3c_df['users'] == N) & (a3c_df['scheme'] == 'NR2 (Full Policy Step)') & (a3c_df['runtime'] == 'NumPy')].iloc[0]
        row_ort = a3c_df[(a3c_df['users'] == N) & (a3c_df['scheme'] == 'NR2 (Full Policy Step)') & (a3c_df['runtime'] == 'onnxruntime')].iloc[0]

        lines.append(f"--- N = {N} Users {'(Main Scenario)' if N == 10 else ''} ---")
        lines.append(f"{'Scheme':24s} | {'Median (us)':>11s} | {'Corr p99.9 (us)':>15s} | {'15kHz(<=1ms)':>12s} | {'30kHz(<=500us)':>14s} | {'60kHz(<=250us)':>14s} | {'120kHz(<=125us)':>15s}")
        lines.append("-" * 116)

        for label, arr in [("GBT-res-ACK (fit 1)", t_res), ("GBT-full-ACK (fit 1)", t_full)]:
            med = float(np.median(arr)) - noise_med
            p999_corr = float(np.percentile(arr, 99.9)) - noise_p999
            s15 = 100.0 * np.mean((arr - noise_med) <= 1000.0)
            s30 = 100.0 * np.mean((arr - noise_med) <= 500.0)
            s60 = 100.0 * np.mean((arr - noise_med) <= 250.0)
            s120 = 100.0 * np.mean((arr - noise_med) <= 125.0)
            lines.append(f"{label:24s} | {med:11.2f} | {p999_corr:15.2f} | {s15:11.2f}% | {s30:13.2f}% | {s60:13.2f}% | {s120:14.2f}%")

        # Print A3c reference values
        for r_name, r_row in [("NR2 A2C (A3c NumPy)", row_np), ("NR2 A2C (A3c ONNX)", row_ort)]:
            med = float(r_row['median_us']) - 0.10
            p999_corr = float(r_row['p99_9_us']) - 0.50
            # Note: A3c CDF shares from REPORT_a3c.txt
            if N == 10 and 'NumPy' in r_name:
                sh_str = "99.9% / 99.6% / 93.4% / 0.0% (stored A3c)"
            elif N == 10 and 'ONNX' in r_name:
                sh_str = "99.9% / 99.3% / 92.0% / 0.0% (stored A3c)"
            elif N == 50 and 'NumPy' in r_name:
                sh_str = "99.9% / 96.5% / 45.6% / 0.0% (stored A3c)"
            elif N == 50 and 'ONNX' in r_name:
                sh_str = "99.9% / 96.3% / 64.8% / 0.0% (stored A3c)"
            elif N == 100 and 'NumPy' in r_name:
                sh_str = "99.9% / 95.2% / 0.1% / 0.0% (stored A3c)"
            else:
                sh_str = "99.8% / 95.0% / 0.5% / 0.0% (stored A3c)"
            lines.append(f"{r_name:24s} | {med:11.2f} | {p999_corr:15.2f} | {sh_str}")
        lines.append("")

    out_path = os.path.join(FT_OUT_DIR, "tgbt_timing.txt")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
