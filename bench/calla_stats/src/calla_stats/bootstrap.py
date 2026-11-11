"""Hierarchical seed x trace and seed-level bootstrap inference procedures."""

from __future__ import annotations
from typing import Dict, Optional, Tuple, Union
import numpy as np
from scipy import stats


def ensure_seeds_by_traces(a: np.ndarray) -> np.ndarray:
    """Ensure array has shape (S, T) where S is number of seeds and T is number of traces."""
    arr = np.atleast_2d(np.asarray(a, dtype=float))
    if arr.shape[0] > arr.shape[1]:
        return arr.T
    return arr


def compute_seed_margins(
    treatment_seeds: np.ndarray,
    baseline_traces: np.ndarray,
) -> np.ndarray:
    """Compute per-seed percentage margins against comparator trace mean:

    margin_s = 100 * (mean_t(A[s, t]) / mean_t(c[t]) - 1)
    """
    A = ensure_seeds_by_traces(treatment_seeds)
    c = np.asarray(baseline_traces, dtype=float).ravel()
    cm = float(c.mean())
    if abs(cm) < 1e-12:
        raise ZeroDivisionError("Baseline trace mean is zero")
    return 100.0 * (A.mean(axis=1) / cm - 1.0)


def seed_sign_test(
    seed_margins: np.ndarray,
    alternative: str = "greater",
) -> Dict[str, Union[int, float]]:
    """One-sided exact sign test over random training seeds.

    Tests whether the proportion of seeds with strictly positive margin exceeds 0.5.
    """
    sm = np.asarray(seed_margins, dtype=float).ravel()
    s_total = len(sm)
    n_pos = int(np.sum(sm > 0.0))
    res = stats.binomtest(n_pos, s_total, p=0.5, alternative=alternative)
    return {
        "seeds_above": n_pos,
        "n_seeds": s_total,
        "fraction_above": n_pos / s_total if s_total > 0 else 0.0,
        "sign_p": float(res.pvalue),
    }


def hierarchical_bootstrap(
    treatment_seeds: np.ndarray,
    baseline_traces: np.ndarray,
    B: int = 20000,
    rng: Optional[Union[np.random.Generator, int]] = 20261104,
    confidence: float = 0.95,
) -> Dict[str, Union[float, int, np.ndarray]]:
    """Hierarchical seed x trace bootstrap inference.

    Resamples seeds with replacement, then resamples evaluation traces with replacement
    (preserving Common Random Numbers / trace pairing across seeds and against the baseline).

    Parameters
    ----------
    treatment_seeds : array-like of shape (S, T) or (T, S)
        Evaluated metric values for each training seed across each evaluation trace.
    baseline_traces : array-like of shape (T,)
        Paired baseline metric values on the identical evaluation traces.
    B : int, default 20000
        Number of bootstrap replications.
    rng : np.random.Generator or int, default 20261104
        Random number generator or seed.
    confidence : float, default 0.95
        Two-sided confidence level for reporting.

    Returns
    -------
    dict with keys:
        hier95_lo, hier95_hi : float, 95% bootstrap percentile bounds (%)
        hier90_lo, hier90_hi : float, 90% bootstrap percentile bounds (%)
        hier_ci_lo, hier_ci_hi : float, bounds for requested confidence level (%)
        mean : float, mean of bootstrap margins
        median : float, median of bootstrap margins
        p_improvement : float, fraction of bootstrap replications strictly > 0
        p_le0 : float, Laplace-smoothed probability of non-improvement (<= 0)
        B : int, number of replications
    """
    A = ensure_seeds_by_traces(treatment_seeds)
    c = np.asarray(baseline_traces, dtype=float).ravel()
    S, T = A.shape
    if len(c) != T:
        raise ValueError(f"Trace dimension mismatch: treatment has T={T}, baseline has T={len(c)}")

    if isinstance(rng, np.random.Generator):
        gen = rng
    elif rng is None:
        gen = np.random.default_rng()
    else:
        gen = np.random.default_rng(rng)

    hb = np.empty(B, dtype=float)
    for b in range(B):
        si = gen.integers(0, S, S)
        ti = gen.integers(0, T, T)
        sample_mean_rl = A[np.ix_(si, ti)].mean()
        sample_mean_cmp = c[ti].mean()
        hb[b] = 100.0 * (sample_mean_rl / sample_mean_cmp - 1.0)

    alpha = 1.0 - confidence
    q_lo = 100.0 * (alpha / 2.0)
    q_hi = 100.0 * (1.0 - alpha / 2.0)

    n_le0 = int(np.sum(hb <= 0.0))
    p_le0 = float((n_le0 + 1) / (B + 1))
    p_improvement = float(np.mean(hb > 0.0))

    return {
        "hier95_lo": float(np.percentile(hb, 2.5)),
        "hier95_hi": float(np.percentile(hb, 97.5)),
        "hier90_lo": float(np.percentile(hb, 5.0)),
        "hier90_hi": float(np.percentile(hb, 95.0)),
        "hier_ci_lo": float(np.percentile(hb, q_lo)),
        "hier_ci_hi": float(np.percentile(hb, q_hi)),
        "mean": float(np.mean(hb)),
        "median": float(np.median(hb)),
        "p_improvement": p_improvement,
        "p_le0": p_le0,
        "B": B,
        "samples": hb,
    }


def seedmean_bootstrap(
    seed_margins: np.ndarray,
    B: int = 20000,
    rng: Optional[Union[np.random.Generator, int]] = 20261105,
    confidence: float = 0.95,
) -> Dict[str, Union[float, int, np.ndarray]]:
    """Bootstrap over the S seed margins only (traces fixed).

    Resamples training seeds with replacement to assess inter-seed variability.
    """
    sm = np.asarray(seed_margins, dtype=float).ravel()
    S = len(sm)

    if isinstance(rng, np.random.Generator):
        gen = rng
    elif rng is None:
        gen = np.random.default_rng()
    else:
        gen = np.random.default_rng(rng)

    sb = np.empty(B, dtype=float)
    for b in range(B):
        si = gen.integers(0, S, S)
        sb[b] = sm[si].mean()

    alpha = 1.0 - confidence
    q_lo = 100.0 * (alpha / 2.0)
    q_hi = 100.0 * (1.0 - alpha / 2.0)

    return {
        "boot95_lo": float(np.percentile(sb, 2.5)),
        "boot95_hi": float(np.percentile(sb, 97.5)),
        "boot90_lo": float(np.percentile(sb, 5.0)),
        "boot90_hi": float(np.percentile(sb, 95.0)),
        "boot_ci_lo": float(np.percentile(sb, q_lo)),
        "boot_ci_hi": float(np.percentile(sb, q_hi)),
        "mean": float(np.mean(sb)),
        "median": float(np.median(sb)),
        "B": B,
        "samples": sb,
    }


def trace_bootstrap(
    treatment_trace_mean: np.ndarray,
    baseline_traces: np.ndarray,
    B: int = 20000,
    rng: Optional[Union[np.random.Generator, int]] = 20261104,
    confidence: float = 0.90,
) -> Dict[str, Union[float, int, np.ndarray]]:
    """Bootstrap over traces only (seeds fixed or averaged)."""
    a = np.asarray(treatment_trace_mean, dtype=float).ravel()
    c = np.asarray(baseline_traces, dtype=float).ravel()
    T = len(a)
    if len(c) != T:
        raise ValueError("Length mismatch between treatment and baseline traces")

    if isinstance(rng, np.random.Generator):
        gen = rng
    elif rng is None:
        gen = np.random.default_rng()
    else:
        gen = np.random.default_rng(rng)

    tb = np.empty(B, dtype=float)
    for b in range(B):
        ti = gen.integers(0, T, T)
        tb[b] = 100.0 * (a[ti].mean() / c[ti].mean() - 1.0)

    alpha = 1.0 - confidence
    q_lo = 100.0 * (alpha / 2.0)
    q_hi = 100.0 * (1.0 - alpha / 2.0)

    return {
        "trace_boot_ci_lo": float(np.percentile(tb, q_lo)),
        "trace_boot_ci_hi": float(np.percentile(tb, q_hi)),
        "trace_boot_ci90_lo": float(np.percentile(tb, 5.0)),
        "trace_boot_ci90_hi": float(np.percentile(tb, 95.0)),
        "mean": float(np.mean(tb)),
        "B": B,
        "samples": tb,
    }
