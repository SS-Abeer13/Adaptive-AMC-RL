"""Strict reproduction of table_nr2.csv and nr2_seed_stats.csv."""

import os
import csv
import pytest
import numpy as np

from calla_stats import (
    paired_margin,
    wilcoxon_test,
    holm_adjust,
    hierarchical_bootstrap,
    seedmean_bootstrap,
    seed_sign_test,
    compute_seed_margins,
    evaluate_rule_r1,
    evaluate_rule_r2,
    evaluate_verdict,
    load_mat_eval,
)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
NR2_EVAL_PATH = os.path.join(ROOT, "Optimized", "v17x", "Dataset", "ckpt", "nr2", "eval.mat")
TABLE_NR2_CSV = os.path.join(ROOT, "Optimized", "v17x", "Dataset", "table_nr2.csv")
NR2_STATS_CSV = os.path.join(ROOT, "paper", "analysis", "out", "nr2_stats.csv")
NR2_SEED_STATS_CSV = os.path.join(ROOT, "paper", "analysis", "out", "nr2_seed_stats.csv")

FAMILY = [
    ("Baseline", "baseline"),
    ("OLLA", "olla"),
    ("OLLA-tuned-500", "olla_tuned500"),
    ("Multi-OLLA", "multi_olla"),
    ("Fixed-500", "fixed500"),
    ("FixedPU-500", "fixedpu500"),
    ("Context-500", "ctx500"),
    ("Context-joint-500", "ctxj500"),
]
PRIMARY = "Context-joint-500"


def assert_pvalue(calc_p: float, exp_p: float, name: str):
    rel_diff = abs(calc_p - exp_p) / max(exp_p, 1e-300)
    abs_diff = abs(calc_p - exp_p)
    assert (rel_diff <= 0.01) or (abs_diff <= 1e-12), (
        f"{name} p-value mismatch: calc={calc_p}, exp={exp_p} (rel={rel_diff:.4g}, abs={abs_diff:.4g})"
    )


def test_nr2_reproduction_table_nr2():
    """Strictly assert every row and column of Optimized/v17x/Dataset/table_nr2.csv."""
    assert os.path.exists(NR2_EVAL_PATH), f"Missing {NR2_EVAL_PATH}"
    assert os.path.exists(TABLE_NR2_CSV), f"Missing {TABLE_NR2_CSV}"

    mat = load_mat_eval(NR2_EVAL_PATH)
    A = mat["nr2_seeds"]
    if A.shape[0] > A.shape[1]:
        A = A.T  # (10, 500)
    assert A.shape == (10, 500)

    M1 = mat["m1_seeds"]
    if M1.shape[0] > M1.shape[1]:
        M1 = M1.T
    m1_mean = M1.mean(axis=0)

    a = A.mean(axis=0)  # Treatment: 10-seed trace mean
    cmp = {name: mat["cmp"][key] for name, key in FAMILY}

    # Evaluate the 8 comparators
    p_vals = []
    calc_rows = []
    for name, _ in FAMILY:
        c = cmp[name]
        pm = paired_margin(a, c, confidence=0.90)
        wx = wilcoxon_test(a, c, engine="matlab")
        calc_rows.append({
            "comparator": name,
            "margin_pct": pm["margin_pct"],
            "ci90_lo": pm["ci_lo"],
            "ci90_hi": pm["ci_hi"],
            "wilcoxon_p": wx["pvalue"],
        })
        p_vals.append(wx["pvalue"])

    hp = holm_adjust(p_vals)
    for r, x in zip(calc_rows, hp):
        r["holm_p"] = x
        r["beats"] = evaluate_rule_r1(r["ci90_lo"], r["holm_p"])

    # Row 9: M1 (Oracle-base primary) secondary comparison
    pm_m1 = paired_margin(a, m1_mean, confidence=0.90)
    wx_m1 = wilcoxon_test(a, m1_mean, engine="matlab")
    calc_rows.append({
        "comparator": "M1 (Oracle-base primary)",
        "margin_pct": pm_m1["margin_pct"],
        "ci90_lo": pm_m1["ci_lo"],
        "ci90_hi": pm_m1["ci_hi"],
        "wilcoxon_p": wx_m1["pvalue"],
        "holm_p": wx_m1["pvalue"],  # Not in family-wise adjustment
        "beats": evaluate_rule_r1(pm_m1["ci_lo"], wx_m1["pvalue"]),
    })

    # Read stored table_nr2.csv
    with open(TABLE_NR2_CSV, mode="r", encoding="utf-8") as f:
        stored_rows = list(csv.DictReader(f))

    assert len(calc_rows) == len(stored_rows) == 9

    for calc, stored in zip(calc_rows, stored_rows):
        cmp_name = stored["comparator"]
        assert calc["comparator"] == cmp_name

        # Margin and CIs to 0.01 tolerance
        assert abs(calc["margin_pct"] - float(stored["margin_pct"])) <= 0.01 + 1e-6, (
            f"{cmp_name}: margin {calc['margin_pct']} vs stored {stored['margin_pct']}"
        )
        assert abs(calc["ci90_lo"] - float(stored["ci90_lo"])) <= 0.01 + 1e-6, (
            f"{cmp_name}: ci90_lo {calc['ci90_lo']} vs stored {stored['ci90_lo']}"
        )
        assert abs(calc["ci90_hi"] - float(stored["ci90_hi"])) <= 0.01 + 1e-6, (
            f"{cmp_name}: ci90_hi {calc['ci90_hi']} vs stored {stored['ci90_hi']}"
        )

        # Wilcoxon and Holm p-values: 1% relative or 1e-12 absolute
        assert_pvalue(calc["wilcoxon_p"], float(stored["wilcoxon_p"]), f"{cmp_name} wilcoxon_p")
        assert_pvalue(calc["holm_p"], float(stored["holm_p"]), f"{cmp_name} holm_p")

        # Beats exact
        assert calc["beats"] == int(stored["beats"]), f"{cmp_name}: beats mismatch"


def test_nr2_reproduction_seed_stats():
    """Strictly assert every entry of nr2_seed_stats.csv."""
    assert os.path.exists(NR2_EVAL_PATH)
    assert os.path.exists(NR2_SEED_STATS_CSV)

    mat = load_mat_eval(NR2_EVAL_PATH)
    A = mat["nr2_seeds"]
    if A.shape[0] > A.shape[1]:
        A = A.T
    a = A.mean(axis=0)

    M1 = mat["m1_seeds"]
    if M1.shape[0] > M1.shape[1]:
        M1 = M1.T
    ens = mat["nr2_ens"]

    c_prim = mat["cmp"]["ctxj500"]

    # Seed-level analysis vs primary (Context-joint-500)
    sm = compute_seed_margins(A, c_prim)
    st = seed_sign_test(sm)
    sb = seedmean_bootstrap(sm, B=20000, rng=20261105, confidence=0.95)
    hb = hierarchical_bootstrap(A, c_prim, B=20000, rng=20261104, confidence=0.95)

    sec_m1 = paired_margin(a, M1.mean(axis=0), confidence=0.90)
    wx_m1 = wilcoxon_test(a, M1.mean(axis=0))

    sec_ens = paired_margin(ens, c_prim, confidence=0.90)
    wx_ens = wilcoxon_test(ens, c_prim)

    expected = {
        "R2_vs_Context-joint-500_seeds_above": 9,
        "R2_vs_Context-joint-500_n_seeds": 10,
        "R2_vs_Context-joint-500_sign_p": 0.01074,
        "R2_vs_Context-joint-500_seed_min": -0.03579,
        "R2_vs_Context-joint-500_seed_max": 4.897,
        "R2_vs_Context-joint-500_boot95_lo": 2.33,
        "R2_vs_Context-joint-500_boot95_hi": 4.219,
        "R2_vs_Context-joint-500_hier95_lo": 2.224,
        "R2_vs_Context-joint-500_hier95_hi": 4.401,
        "secondary_vs_M1_margin_pct": 2.583,
        "secondary_vs_M1_ci90_lo": 2.323,
        "secondary_vs_M1_ci90_hi": 2.843,
        "secondary_vs_M1_p": 5.455e-42,
        "secondary_ensemble_vs_Context-joint-500_margin_pct": 5.525,
        "secondary_ensemble_vs_Context-joint-500_ci90_lo": 4.987,
        "secondary_ensemble_vs_Context-joint-500_ci90_hi": 6.063,
        "secondary_ensemble_vs_Context-joint-500_p": 1.212e-43,
    }

    # Verify against calculated values
    assert st["seeds_above"] == expected["R2_vs_Context-joint-500_seeds_above"]
    assert st["n_seeds"] == expected["R2_vs_Context-joint-500_n_seeds"]
    assert_pvalue(st["sign_p"], expected["R2_vs_Context-joint-500_sign_p"], "sign_p")

    assert abs(sm.min() - expected["R2_vs_Context-joint-500_seed_min"]) <= 0.01
    assert abs(sm.max() - expected["R2_vs_Context-joint-500_seed_max"]) <= 0.01

    assert abs(sb["boot95_lo"] - expected["R2_vs_Context-joint-500_boot95_lo"]) <= 0.01
    assert abs(sb["boot95_hi"] - expected["R2_vs_Context-joint-500_boot95_hi"]) <= 0.01
    assert abs(hb["hier95_lo"] - expected["R2_vs_Context-joint-500_hier95_lo"]) <= 0.01
    assert abs(hb["hier95_hi"] - expected["R2_vs_Context-joint-500_hier95_hi"]) <= 0.01

    assert abs(sec_m1["margin_pct"] - expected["secondary_vs_M1_margin_pct"]) <= 0.01
    assert abs(sec_m1["ci_lo"] - expected["secondary_vs_M1_ci90_lo"]) <= 0.01
    assert abs(sec_m1["ci_hi"] - expected["secondary_vs_M1_ci90_hi"]) <= 0.01
    assert_pvalue(wx_m1["pvalue"], expected["secondary_vs_M1_p"], "sec_m1_p")

    assert abs(sec_ens["margin_pct"] - expected["secondary_ensemble_vs_Context-joint-500_margin_pct"]) <= 0.01
    assert abs(sec_ens["ci_lo"] - expected["secondary_ensemble_vs_Context-joint-500_ci90_lo"]) <= 0.01
    assert abs(sec_ens["ci_hi"] - expected["secondary_ensemble_vs_Context-joint-500_ci90_hi"]) <= 0.01
    assert_pvalue(wx_ens["pvalue"], expected["secondary_ensemble_vs_Context-joint-500_p"], "sec_ens_p")

    # Read stored CSV to ensure on-disk consistency
    with open(NR2_SEED_STATS_CSV, mode="r", encoding="utf-8") as f:
        stored = {row["analysis"]: float(row["value"]) for row in csv.DictReader(f)}

    for k, exp_val in expected.items():
        assert k in stored
        if "seeds" in k:
            assert int(stored[k]) == int(exp_val)
        elif "_p" in k:
            assert_pvalue(stored[k], exp_val, k)
        else:
            assert abs(stored[k] - exp_val) <= 0.01 + 1e-6
