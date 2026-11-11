"""Strict reproduction of table_warmup.csv (W1)."""

import os
import csv
import pytest
import numpy as np
import h5py

from calla_stats import (
    paired_margin,
    wilcoxon_test,
    holm_adjust,
    evaluate_rule_r1,
    load_mat_eval,
)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
M1_PATH = os.path.join(ROOT, "Optimized", "v17", "Dataset", "results_v17_M1_dl_rtt8.mat")
CKPT_W1_DIR = os.path.join(ROOT, "Optimized", "v17x", "Dataset", "ckpt", "w1")
TABLE_WARMUP_CSV = os.path.join(ROOT, "Optimized", "v17x", "Dataset", "table_warmup.csv")


def assert_pvalue(calc_p: float, exp_p: float, name: str):
    rel_diff = abs(calc_p - exp_p) / max(exp_p, 1e-300)
    abs_diff = abs(calc_p - exp_p)
    assert (rel_diff <= 0.01) or (abs_diff <= 1e-12), (
        f"{name} p-value mismatch: calc={calc_p}, exp={exp_p} (rel={rel_diff:.4g}, abs={abs_diff:.4g})"
    )


def test_warmup_reproduction():
    """Strictly assert every row and column of Optimized/v17x/Dataset/table_warmup.csv."""
    assert os.path.exists(M1_PATH), f"Missing {M1_PATH}"
    assert os.path.exists(CKPT_W1_DIR), f"Missing {CKPT_W1_DIR}"
    assert os.path.exists(TABLE_WARMUP_CSV), f"Missing {TABLE_WARMUP_CSV}"

    data_m1 = load_mat_eval(M1_PATH)
    P_cold = data_m1["metrics"]["primary"]

    a2c_cold = P_cold["Deep A2C v17"]
    if a2c_cold.shape[0] > a2c_cold.shape[1]:
        a2c_cold = a2c_cold.T
    cold_a2c_mean = a2c_cold[:10, :500].mean(axis=0)

    cold_cmps = [
        ("Baseline", P_cold["Baseline"][0, :500]),
        ("OLLA", P_cold["OLLA"][0, :500]),
        ("OLLA (tuned target)", P_cold["OLLA (tuned target)"][0, :500]),
        ("Multi-OLLA", P_cold["Multi-OLLA"][0, :500]),
        ("Fixed", P_cold["Fixed"][0, :500]),
        ("FixedPU (Oracle)", P_cold["FixedPU (Oracle)"][0, :500]),
        ("Context table", P_cold["Context table"][0, :500]),
        ("Bandit (global)", P_cold["Bandit (global)"][0, :500]),
        ("Bandit (delay class)", P_cold["Bandit (delay class)"][0, :500]),
    ]

    # Load warm evaluation data
    det_path = os.path.join(CKPT_W1_DIR, "comparators_det.mat")
    with h5py.File(det_path, "r") as f_det:
        det_prim = np.asarray(f_det["out"]["primary"][()], dtype=float)
        if det_prim.shape[0] == 500 and det_prim.shape[1] == 7:
            det_prim = det_prim.T

    bg_list, bd_list, a2c_warm_list = [], [], []
    for s in range(1, 11):
        with h5py.File(os.path.join(CKPT_W1_DIR, f"bandit_seed_{s}.mat"), "r") as fb:
            bg_list.append(np.asarray(fb["out"]["prim_g"][()], dtype=float).ravel())
            bd_list.append(np.asarray(fb["out"]["prim_d"][()], dtype=float).ravel())
        with h5py.File(os.path.join(CKPT_W1_DIR, f"a2c_seed_{s}.mat"), "r") as fa:
            a2c_warm_list.append(np.asarray(fa["out"]["primary"][()], dtype=float).ravel())

    bg_mean = np.mean(bg_list, axis=0)
    bd_mean = np.mean(bd_list, axis=0)
    warm_a2c_mean = np.mean(a2c_warm_list, axis=0)

    warm_cmps = [
        ("Baseline", det_prim[0]),
        ("OLLA", det_prim[1]),
        ("OLLA (tuned target)", det_prim[2]),
        ("Multi-OLLA", det_prim[3]),
        ("Fixed", det_prim[4]),
        ("FixedPU (Oracle)", det_prim[5]),
        ("Context table", det_prim[6]),
        ("Bandit (global)", bg_mean),
        ("Bandit (delay class)", bd_mean),
    ]

    # Compute cold statistics
    cold_pvals = []
    cold_rows = []
    for name, c in cold_cmps:
        pm = paired_margin(cold_a2c_mean, c, confidence=0.90)
        wx = wilcoxon_test(cold_a2c_mean, c, engine="matlab")
        cold_pvals.append(wx["pvalue"])
        cold_rows.append({
            "comparator": name,
            "cold_margin_pct": pm["margin_pct"],
            "cold_ci90_lo": pm["ci_lo"],
            "cold_ci90_hi": pm["ci_hi"],
            "cold_wilcoxon_p": wx["pvalue"],
        })
    cold_hps = holm_adjust(cold_pvals)
    for r, hp in zip(cold_rows, cold_hps):
        r["cold_holm_p"] = hp
        r["cold_beats"] = evaluate_rule_r1(r["cold_ci90_lo"], r["cold_holm_p"])

    # Compute warm statistics
    warm_pvals = []
    warm_rows = []
    for name, c in warm_cmps:
        pm = paired_margin(warm_a2c_mean, c, confidence=0.90)
        wx = wilcoxon_test(warm_a2c_mean, c, engine="matlab")
        warm_pvals.append(wx["pvalue"])
        warm_rows.append({
            "comparator": name,
            "warm_margin_pct": pm["margin_pct"],
            "warm_ci90_lo": pm["ci_lo"],
            "warm_ci90_hi": pm["ci_hi"],
            "warm_wilcoxon_p": wx["pvalue"],
        })
    warm_hps = holm_adjust(warm_pvals)
    for r, hp in zip(warm_rows, warm_hps):
        r["warm_holm_p"] = hp
        r["warm_beats"] = evaluate_rule_r1(r["warm_ci90_lo"], r["warm_holm_p"])

    # Read stored table_warmup.csv
    with open(TABLE_WARMUP_CSV, mode="r", encoding="utf-8") as f:
        stored_rows = list(csv.DictReader(f))

    assert len(stored_rows) == len(cold_rows) == len(warm_rows) == 9

    for c_calc, w_calc, stored in zip(cold_rows, warm_rows, stored_rows):
        cmp_name = stored["comparator"]
        assert c_calc["comparator"] == cmp_name
        assert w_calc["comparator"] == cmp_name

        # Cold assertions
        assert abs(c_calc["cold_margin_pct"] - float(stored["cold_margin_pct"])) <= 0.01 + 1e-6, (
            f"{cmp_name} cold margin: {c_calc['cold_margin_pct']} vs {stored['cold_margin_pct']}"
        )
        assert abs(c_calc["cold_ci90_lo"] - float(stored["cold_ci90_lo"])) <= 0.01 + 1e-6, (
            f"{cmp_name} cold ci90_lo: {c_calc['cold_ci90_lo']} vs {stored['cold_ci90_lo']}"
        )
        assert abs(c_calc["cold_ci90_hi"] - float(stored["cold_ci90_hi"])) <= 0.01 + 1e-6, (
            f"{cmp_name} cold ci90_hi: {c_calc['cold_ci90_hi']} vs {stored['cold_ci90_hi']}"
        )
        assert_pvalue(c_calc["cold_holm_p"], float(stored["cold_holm_p"]), f"{cmp_name} cold_holm_p")
        assert c_calc["cold_beats"] == int(stored["cold_beats"])

        # Warm assertions
        assert abs(w_calc["warm_margin_pct"] - float(stored["warm_margin_pct"])) <= 0.01 + 1e-6, (
            f"{cmp_name} warm margin: {w_calc['warm_margin_pct']} vs {stored['warm_margin_pct']}"
        )
        assert abs(w_calc["warm_ci90_lo"] - float(stored["warm_ci90_lo"])) <= 0.01 + 1e-6, (
            f"{cmp_name} warm ci90_lo: {w_calc['warm_ci90_lo']} vs {stored['warm_ci90_lo']}"
        )
        assert abs(w_calc["warm_ci90_hi"] - float(stored["warm_ci90_hi"])) <= 0.01 + 1e-6, (
            f"{cmp_name} warm ci90_hi: {w_calc['warm_ci90_hi']} vs {stored['warm_ci90_hi']}"
        )
        assert_pvalue(w_calc["warm_holm_p"], float(stored["warm_holm_p"]), f"{cmp_name} warm_holm_p")
        assert w_calc["warm_beats"] == int(stored["warm_beats"])
