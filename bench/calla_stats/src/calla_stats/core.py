"""Core parametric and non-parametric statistical metrics for link adaptation evaluation."""

from __future__ import annotations
from typing import Dict, Sequence, Union
import numpy as np
from scipy import stats


def paired_margin(
    treatment: Union[np.ndarray, Sequence[float]],
    baseline: Union[np.ndarray, Sequence[float]],
    confidence: float = 0.90,
) -> Dict[str, float]:
    """Calculate paired per-trace margin: 100 * mean(treatment - baseline) / mean(baseline)

    and its Student-t confidence interval at the specified confidence level.

    Parameters
    ----------
    treatment : array-like of shape (N,)
        Performance metrics of the evaluated policy on N evaluation traces.
    baseline : array-like of shape (N,)
        Performance metrics of the comparator policy paired on the identical N traces.
    confidence : float, default 0.90
        Two-sided confidence level for the t-interval (e.g. 0.90 for 90% CI).

    Returns
    -------
    dict with keys:
        margin_pct : float, point estimate in percent
        ci_lo : float, lower bound of t-interval in percent
        ci_hi : float, upper bound of t-interval in percent
        diff_mean : float, mean paired difference
        baseline_mean : float, mean baseline performance
        se : float, standard error of the mean paired difference
        df : int, degrees of freedom (N - 1)
        n : int, number of paired traces
    """
    a = np.asarray(treatment, dtype=float).ravel()
    b = np.asarray(baseline, dtype=float).ravel()
    if len(a) != len(b):
        raise ValueError(f"Array length mismatch: treatment has {len(a)}, baseline has {len(b)}")
    n = len(a)
    if n < 2:
        raise ValueError("At least 2 paired observations required for confidence interval")

    d = a - b
    bm = float(b.mean())
    if abs(bm) < 1e-12:
        raise ZeroDivisionError("Baseline mean is approximately zero; cannot compute relative margin")

    diff_mean = float(d.mean())
    se = float(d.std(ddof=1) / np.sqrt(n))
    alpha = 1.0 - confidence
    q = float(stats.t.ppf(1.0 - alpha / 2.0, n - 1))

    margin_pct = 100.0 * diff_mean / bm
    ci_lo = 100.0 * (diff_mean - q * se) / bm
    ci_hi = 100.0 * (diff_mean + q * se) / bm

    return {
        "margin_pct": margin_pct,
        "ci_lo": ci_lo,
        "ci_hi": ci_hi,
        "diff_mean": diff_mean,
        "baseline_mean": bm,
        "se": se,
        "df": n - 1,
        "n": n,
    }


def wilcoxon_test(
    treatment: Union[np.ndarray, Sequence[float]],
    baseline: Union[np.ndarray, Sequence[float]],
    zero_method: str = "wilcox",
    correction: bool = False,
    method: str = "approx",
    engine: str = "scipy",
) -> Dict[str, float]:
    """Compute two-sided Wilcoxon signed-rank test on paired trace samples.

    Parameters
    ----------
    treatment : array-like of shape (N,)
    baseline : array-like of shape (N,)
    zero_method : str, default 'wilcox'
    correction : bool, default False
    method : str, default 'approx'
    engine : str, default 'scipy'
        'scipy' uses scipy.stats.wilcoxon (matching paper/analysis/nr2_stats.py).
        'matlab' uses tie-adjusted normal approximation with machine-precision
        tie clustering (matching MATLAB signrank bit-identically).

    Returns
    -------
    dict with keys:
        statistic : float, Wilcoxon test statistic (or 0.0 if all differences zero)
        pvalue : float, two-sided p-value (1.0 if all differences zero)
    """
    a = np.asarray(treatment, dtype=float).ravel()
    b = np.asarray(baseline, dtype=float).ravel()
    if len(a) != len(b):
        raise ValueError(f"Length mismatch: {len(a)} vs {len(b)}")

    d = a - b
    if np.all(d == 0.0):
        return {"statistic": 0.0, "pvalue": 1.0}

    if engine == "matlab":
        d_round = np.round(d, decimals=12)
        d_nz = d_round[d_round != 0.0]
        n = len(d_nz)
        if n == 0:
            return {"statistic": 0.0, "pvalue": 1.0}
        r = stats.rankdata(np.abs(d_nz))
        w = min(float(np.sum(r[d_nz > 0])), float(np.sum(r[d_nz < 0])))
        mean_w = n * (n + 1) / 4.0
        _, tie_counts = np.unique(np.abs(d_nz), return_counts=True)
        tieadj = float(np.sum(tie_counts**3 - tie_counts) / 2.0)
        var_w = (n * (n + 1) * (2 * n + 1) - tieadj) / 24.0
        if var_w <= 0.0:
            return {"statistic": w, "pvalue": 1.0}
        z = (w - mean_w) / np.sqrt(var_w)
        pvalue = float(2.0 * stats.norm.cdf(-abs(z)))
        return {"statistic": w, "pvalue": pvalue}
    else:
        res = stats.wilcoxon(a, b, zero_method=zero_method, correction=correction, method=method)
        return {
            "statistic": float(res.statistic),
            "pvalue": float(res.pvalue),
        }


def holm_adjust(pvalues: Union[np.ndarray, Sequence[float]]) -> np.ndarray:
    """Holm-Bonferroni step-down adjustment over a family of p-values.

    Parameters
    ----------
    pvalues : array-like of shape (M,)

    Returns
    -------
    adjusted_pvalues : np.ndarray of shape (M,), adjusted to control FWER <= alpha
    """
    ps = np.asarray(pvalues, dtype=float)
    m = len(ps)
    if m == 0:
        return np.empty(0, dtype=float)

    order = np.argsort(ps)
    adjusted = np.empty(m, dtype=float)
    cur = 0.0
    for i, idx in enumerate(order):
        multiplier = m - i
        val = ps[idx] * multiplier
        cur = max(cur, min(1.0, val))
        adjusted[idx] = cur

    return adjusted
