"""Strict reproduction of paper/analysis/out/g3_seed_stats.csv."""

import os
import csv
import pytest
import numpy as np
from scipy import stats

from calla_stats import (
    compute_seed_margins,
    seed_sign_test,
    hierarchical_bootstrap,
    seedmean_bootstrap,
    trace_bootstrap,
    load_mat_eval,
)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
G3_STATS_CSV = os.path.join(ROOT, "paper", "analysis", "out", "g3_seed_stats.csv")


def assert_pvalue(calc_p: float, exp_p: float, name: str):
    rel_diff = abs(calc_p - exp_p) / max(exp_p, 1e-300)
    abs_diff = abs(calc_p - exp_p)
    assert (rel_diff <= 0.01) or (abs_diff <= 1e-12), (
        f"{name} p-value mismatch: calc={calc_p}, exp={exp_p} (rel={rel_diff:.4g}, abs={abs_diff:.4g})"
    )


def test_g3_reproduction():
    """Strictly assert all 15 rows and all columns of g3_seed_stats.csv."""
    assert os.path.exists(G3_STATS_CSV), f"Missing {G3_STATS_CSV}"

    with open(G3_STATS_CSV, mode="r", encoding="utf-8") as f:
        stored_rows = list(csv.DictReader(f))

    rng = np.random.default_rng(20261104)
    rng_seed = np.random.default_rng(20261105)
    B = 20000

    cases = [
        ("M1_dl_rtt8", ["Deep A2C v17", "Deep A2C v17 (resid-800)", "Deep A2C v17 (offset)"]),
        ("M2_dl_rtt0", ["Deep A2C v17", "Deep A2C v17 (resid-800)"]),
    ]

    row_idx = 0
    for tag, schemes in cases:
        mat_path = os.path.join(ROOT, "Optimized", "v17", "Dataset", f"results_v17_{tag}.mat")
        assert os.path.exists(mat_path), f"Missing {mat_path}"
        data = load_mat_eval(mat_path)
        P = data["metrics"]["primary"]

        for rl in schemes:
            A = P[rl]
            A = A[~np.all(np.isnan(A), axis=1)]  # drop empty seeds
            S = A.shape[0]

            for cmp_name in ["Context table", "Fixed", "FixedPU (Oracle)"]:
                c = P[cmp_name][0]
                expected = stored_rows[row_idx]
                row_idx += 1

                label = f"{tag} | {rl} vs {cmp_name}"
                assert expected["case"] == tag
                assert expected["scheme"] == rl
                assert expected["comparator"] == cmp_name

                point = 100.0 * (A.mean() / c.mean() - 1.0)
                seed_m = compute_seed_margins(A, c)
                st = seed_sign_test(seed_m)

                t_res = stats.ttest_1samp(seed_m, 0.0)
                t_ci = stats.t.interval(0.90, S - 1, loc=seed_m.mean(), scale=stats.sem(seed_m))
                t95 = stats.t.interval(0.95, S - 1, loc=seed_m.mean(), scale=stats.sem(seed_m))

                # Advance RNGs in the exact same sequence
                sb = seedmean_bootstrap(seed_m, B=B, rng=rng_seed, confidence=0.95)
                hb = hierarchical_bootstrap(A, c, B=B, rng=rng, confidence=0.95)
                tb = trace_bootstrap(A.mean(axis=0), c, B=B, rng=rng, confidence=0.90)

                assert abs(point - float(expected["margin_pct"])) <= 0.01 + 1e-6, f"{label} margin"
                assert f"{st['seeds_above']}/{S}" == expected["seeds_above"], f"{label} seeds_above"

                assert_pvalue(st["sign_p"], float(expected["sign_test_p_one_sided"]), f"{label} sign_test_p")
                assert_pvalue(float(t_res.pvalue), float(expected["seed_t_p_two_sided"]), f"{label} seed_t_p")

                assert abs(t_ci[0] - float(expected["seed_t_ci90_lo"])) <= 0.01 + 1e-6, f"{label} t_ci90_lo"
                assert abs(t_ci[1] - float(expected["seed_t_ci90_hi"])) <= 0.01 + 1e-6, f"{label} t_ci90_hi"

                assert abs(seed_m.min() - float(expected["seed_margin_min"])) <= 0.01 + 1e-6, f"{label} seed_min"
                assert abs(seed_m.max() - float(expected["seed_margin_max"])) <= 0.01 + 1e-6, f"{label} seed_max"

                assert abs(tb["trace_boot_ci90_lo"] - float(expected["trace_boot_ci90_lo"])) <= 0.01 + 1e-6
                assert abs(tb["trace_boot_ci90_hi"] - float(expected["trace_boot_ci90_hi"])) <= 0.01 + 1e-6

                assert abs(hb["hier90_lo"] - float(expected["hier_boot_ci90_lo"])) <= 0.01 + 1e-6
                assert abs(hb["hier90_hi"] - float(expected["hier_boot_ci90_hi"])) <= 0.01 + 1e-6
                assert abs(hb["hier95_lo"] - float(expected["hier_boot_ci95_lo"])) <= 0.01 + 1e-6
                assert abs(hb["hier95_hi"] - float(expected["hier_boot_ci95_hi"])) <= 0.01 + 1e-6

                assert abs(t95[0] - float(expected["seed_t_ci95_lo"])) <= 0.01 + 1e-6
                assert abs(t95[1] - float(expected["seed_t_ci95_hi"])) <= 0.01 + 1e-6

                assert abs(sb["boot90_lo"] - float(expected["seedmean_boot_ci90_lo"])) <= 0.01 + 1e-6
                assert abs(sb["boot90_hi"] - float(expected["seedmean_boot_ci90_hi"])) <= 0.01 + 1e-6
                assert abs(sb["boot95_lo"] - float(expected["seedmean_boot_ci95_lo"])) <= 0.01 + 1e-6
                assert abs(sb["boot95_hi"] - float(expected["seedmean_boot_ci95_hi"])) <= 0.01 + 1e-6

                assert_pvalue(hb["p_le0"], float(expected["hier_boot_p_le0"]), f"{label} hier_boot_p_le0")

    assert row_idx == len(stored_rows) == 15
