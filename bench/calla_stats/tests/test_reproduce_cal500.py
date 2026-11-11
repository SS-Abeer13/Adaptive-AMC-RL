"""Strict reproduction of table_cal500.csv (G6c, post-Amendment 4)."""

import os
import csv
import pytest
import numpy as np

from calla_stats import (
    paired_margin,
    wilcoxon_test,
    holm_adjust,
    evaluate_rule_r1,
    load_mat_eval,
)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
M1_PATH = os.path.join(ROOT, "Optimized", "v17", "Dataset", "results_v17_M1_dl_rtt8.mat")
G6C_PATH = os.path.join(ROOT, "Optimized", "v17x", "Dataset", "ckpt", "g6c", "eval.mat")
TABLE_CAL500_CSV = os.path.join(ROOT, "Optimized", "v17x", "Dataset", "table_cal500.csv")


def assert_pvalue(calc_p: float, exp_p: float, name: str):
    rel_diff = abs(calc_p - exp_p) / max(exp_p, 1e-300)
    abs_diff = abs(calc_p - exp_p)
    assert (rel_diff <= 0.01) or (abs_diff <= 1e-12), (
        f"{name} p-value mismatch: calc={calc_p}, exp={exp_p} (rel={rel_diff:.4g}, abs={abs_diff:.4g})"
    )


def test_cal500_reproduction():
    """Strictly assert every row and column of Optimized/v17x/Dataset/table_cal500.csv."""
    assert os.path.exists(M1_PATH), f"Missing {M1_PATH}"
    assert os.path.exists(G6C_PATH), f"Missing {G6C_PATH}"
    assert os.path.exists(TABLE_CAL500_CSV), f"Missing {TABLE_CAL500_CSV}"

    data_m1 = load_mat_eval(M1_PATH)
    P = data_m1["metrics"]["primary"]

    a2c = P["Deep A2C v17"]
    if a2c.shape[0] > a2c.shape[1]:
        a2c = a2c.T
    a2c_mean = a2c[:10, :500].mean(axis=0)

    base = P["Baseline"][0, :500]
    olla = P["OLLA"][0, :500]
    molla = P["Multi-OLLA"][0, :500]
    bglob = P["Bandit (global)"][0, :500]
    bdelay = P["Bandit (delay class)"][0, :500]

    # Load G6c calibrated comparators
    import h5py
    with h5py.File(G6C_PATH, "r") as f_g6c:
        olla500 = np.asarray(f_g6c["out"]["prim_olla500"][()], dtype=float).ravel()[:500]
        f500 = np.asarray(f_g6c["out"]["prim_fixed500"][()], dtype=float).ravel()[:500]
        pu500 = np.asarray(f_g6c["out"]["prim_pu500"][()], dtype=float).ravel()[:500]
        ctx500 = np.asarray(f_g6c["out"]["prim_ctx500"][()], dtype=float).ravel()[:500]
        ctxj500 = np.asarray(f_g6c["out"]["prim_ctxj500"][()], dtype=float).ravel()[:500]

    cmps = [
        ("Baseline", base),
        ("OLLA", olla),
        ("OLLA-tuned-500", olla500),
        ("Multi-OLLA", molla),
        ("Fixed-500", f500),
        ("FixedPU-500", pu500),
        ("Context-500", ctx500),
        ("Bandit (global)", bglob),
        ("Bandit (delay class)", bdelay),
        ("Context-joint-500", ctxj500),
    ]

    pvals = []
    calc_rows = []
    for name, c in cmps:
        pm = paired_margin(a2c_mean, c, confidence=0.90)
        wx = wilcoxon_test(a2c_mean, c, engine="matlab")
        pvals.append(wx["pvalue"])
        calc_rows.append({
            "comparator": name,
            "margin_pct": pm["margin_pct"],
            "ci90_lo": pm["ci_lo"],
            "ci90_hi": pm["ci_hi"],
            "wilcoxon_p": wx["pvalue"],
        })

    hps = holm_adjust(pvals)
    for r, hp in zip(calc_rows, hps):
        r["holm_p"] = hp
        r["beats"] = evaluate_rule_r1(r["ci90_lo"], r["holm_p"])

    # Read stored table_cal500.csv
    with open(TABLE_CAL500_CSV, mode="r", encoding="utf-8") as f:
        stored_rows = list(csv.DictReader(f))

    assert len(calc_rows) == len(stored_rows) == 10

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
