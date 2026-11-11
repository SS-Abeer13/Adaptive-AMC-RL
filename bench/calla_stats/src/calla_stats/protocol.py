"""Confirmatory decision rules R1 and R2 and pre-registration verdicts."""

from __future__ import annotations
from typing import Dict, List, Optional, Tuple, Union
import numpy as np

from .core import paired_margin, wilcoxon_test, holm_adjust
from .bootstrap import (
    ensure_seeds_by_traces,
    compute_seed_margins,
    seed_sign_test,
    hierarchical_bootstrap,
    seedmean_bootstrap,
)


def evaluate_rule_r1(
    ci90_lo: float,
    holm_p: float,
    alpha: float = 0.05,
) -> int:
    """Evaluate Rule R1 (trace-level superiority after family-wise adjustment).

    Rule R1 passes if and only if Holm-adjusted p < alpha (default 0.05) AND
    the 90% t-interval lower bound is strictly positive.

    Returns
    -------
    1 if Rule R1 passes, 0 otherwise.
    """
    return int(holm_p < alpha and ci90_lo > 0.0)


def evaluate_rule_r2(
    hier95_lo: float,
) -> bool:
    """Evaluate Rule R2 (hierarchical seed x trace generalizability).

    Rule R2 passes if and only if the hierarchical 95% bootstrap lower bound
    against the strongest pre-registered comparator is strictly positive.
    """
    return bool(hier95_lo > 0.0)


def evaluate_verdict(
    trace_pass: bool,
    seed_pass: bool,
    primary_holm_p: Optional[float] = None,
    primary_ci90_hi: Optional[float] = None,
    family_beats: Optional[Sequence[int]] = None,
) -> Dict[str, Union[str, bool]]:
    """Determine the pre-registered confirmatory verdict.

    Verdict states:
    - CONFIRM : Rule R1 passes on primary comparator AND Rule R2 passes.
    - TRACE   : Rule R1 passes on primary comparator BUT Rule R2 fails.
    - REVERSE : Significant degradation (primary Holm p < 0.05 and 90% CI upper bound < 0).
    - NULL    : No statistically confirmed improvement on the primary comparator.

    WIN criterion:
    - Rule R1 passes against all comparators in the pre-registered family.

    Reframing gate:
    - OPEN if and only if verdict == 'CONFIRM' and WIN == True.
    """
    if trace_pass and seed_pass:
        verdict = "CONFIRM"
    elif trace_pass:
        verdict = "TRACE"
    elif (
        primary_holm_p is not None
        and primary_ci90_hi is not None
        and primary_holm_p < 0.05
        and primary_ci90_hi < 0.0
    ):
        verdict = "REVERSE"
    else:
        verdict = "NULL"

    win = False
    if family_beats is not None and len(family_beats) > 0:
        win = all(b == 1 for b in family_beats)

    gate_open = (verdict == "CONFIRM") and win

    return {
        "verdict": verdict,
        "win": win,
        "reframing_gate": "OPEN" if gate_open else "closed",
        "trace_pass": bool(trace_pass),
        "seed_pass": bool(seed_pass),
    }


def evaluate_study(
    treatment_seeds: np.ndarray,
    comparators: Dict[str, np.ndarray],
    primary_comparator: str,
    B: int = 20000,
    rng_hier: Optional[Union[np.random.Generator, int]] = 20261104,
    rng_seed: Optional[Union[np.random.Generator, int]] = 20261105,
    alpha_r1: float = 0.05,
) -> Dict[str, Union[dict, list]]:
    """Full confirmatory study evaluation against a family of comparators.

    Parameters
    ----------
    treatment_seeds : (S, T) or (T, S) array
        Performance metric across S training seeds and T evaluation traces.
    comparators : dict of name -> (T,) array
        Pre-registered family of comparators.
    primary_comparator : str
        Name of the primary comparator (e.g. 'Context-joint-500').
    B : int, default 20000
    rng_hier : rng or seed for hierarchical bootstrap (default 20261104)
    rng_seed : rng or seed for seed-mean bootstrap (default 20261105)
    alpha_r1 : float, default 0.05

    Returns
    -------
    dict with:
        'family_results': list of dicts for each comparator with margin, CIs, p-values, beats
        'primary_stats': detailed seed-level and hierarchical bootstrap results vs primary
        'verdict': dict with verdict, win, reframing_gate
    """
    A = ensure_seeds_by_traces(treatment_seeds)
    a = A.mean(axis=0)  # Primary evaluated policy is the per-seed trace mean

    if primary_comparator not in comparators:
        raise ValueError(f"Primary comparator '{primary_comparator}' not found in comparators dictionary")

    # Step 1: Paired margins and Wilcoxon p-values for all comparators
    names = list(comparators.keys())
    p_values = []
    comp_rows = []

    for name in names:
        c = np.asarray(comparators[name], dtype=float).ravel()
        pm = paired_margin(a, c, confidence=0.90)
        wx = wilcoxon_test(a, c)
        comp_rows.append({
            "comparator": name,
            "margin_pct": pm["margin_pct"],
            "ci90_lo": pm["ci_lo"],
            "ci90_hi": pm["ci_hi"],
            "wilcoxon_p": wx["pvalue"],
        })
        p_values.append(wx["pvalue"])

    # Step 2: Holm-Bonferroni adjustment across the family
    adjusted_ps = holm_adjust(p_values)
    for row, hp in zip(comp_rows, adjusted_ps):
        row["holm_p"] = float(hp)
        row["beats"] = evaluate_rule_r1(row["ci90_lo"], row["holm_p"], alpha=alpha_r1)

    # Step 3: Seed-level and hierarchical bootstrap vs primary comparator
    prim_row = next(r for r in comp_rows if r["comparator"] == primary_comparator)
    c_prim = np.asarray(comparators[primary_comparator], dtype=float).ravel()

    sm = compute_seed_margins(A, c_prim)
    st = seed_sign_test(sm, alternative="greater")
    hb = hierarchical_bootstrap(A, c_prim, B=B, rng=rng_hier, confidence=0.95)
    sb = seedmean_bootstrap(sm, B=B, rng=rng_seed, confidence=0.95)

    primary_stats = {
        "comparator": primary_comparator,
        "n_seeds": A.shape[0],
        "n_traces": A.shape[1],
        "seeds_above": st["seeds_above"],
        "sign_p": st["sign_p"],
        "seed_min": float(sm.min()),
        "seed_max": float(sm.max()),
        "boot95_lo": sb["boot95_lo"],
        "boot95_hi": sb["boot95_hi"],
        "hier95_lo": hb["hier95_lo"],
        "hier95_hi": hb["hier95_hi"],
        "p_improvement": hb["p_improvement"],
        "p_le0": hb["p_le0"],
    }

    # Step 4: Decisions & Verdicts
    trace_pass = bool(prim_row["beats"] == 1)
    seed_pass = evaluate_rule_r2(hb["hier95_lo"])
    family_beats = [r["beats"] for r in comp_rows]

    verdict_info = evaluate_verdict(
        trace_pass=trace_pass,
        seed_pass=seed_pass,
        primary_holm_p=prim_row["holm_p"],
        primary_ci90_hi=prim_row["ci90_hi"],
        family_beats=family_beats,
    )

    return {
        "family_results": comp_rows,
        "primary_stats": primary_stats,
        "verdict": verdict_info,
    }
