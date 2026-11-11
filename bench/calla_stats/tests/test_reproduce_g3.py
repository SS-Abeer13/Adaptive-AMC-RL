"""Reproduce paper/analysis/out/g3_seed_stats.csv."""

import os
import csv
import numpy as np
import pytest
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


def test_g3_reproduction():
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

                assert round(point, 3) == pytest.approx(float(expected["margin_pct"]), abs=0.001)
                assert f"{st['seeds_above']}/{S}" == expected["seeds_above"]
                assert float(f"{st['sign_p']:.3g}") == pytest.approx(float(expected["sign_test_p_one_sided"]), rel=1e-2)
                assert float(f"{t_res.pvalue:.3g}") == pytest.approx(float(expected["seed_t_p_two_sided"]), rel=1e-2)
                assert round(t_ci[0], 3) == pytest.approx(float(expected["seed_t_ci90_lo"]), abs=0.001)
                assert round(t_ci[1], 3) == pytest.approx(float(expected["seed_t_ci90_hi"]), abs=0.001)
                assert round(seed_m.min(), 3) == pytest.approx(float(expected["seed_margin_min"]), abs=0.001)
                assert round(seed_m.max(), 3) == pytest.approx(float(expected["seed_margin_max"]), abs=0.001)

                assert round(tb["trace_boot_ci90_lo"], 3) == pytest.approx(float(expected["trace_boot_ci90_lo"]), abs=0.001)
                assert round(tb["trace_boot_ci90_hi"], 3) == pytest.approx(float(expected["trace_boot_ci90_hi"]), abs=0.001)
                assert round(hb["hier90_lo"], 3) == pytest.approx(float(expected["hier_boot_ci90_lo"]), abs=0.001)
                assert round(hb["hier90_hi"], 3) == pytest.approx(float(expected["hier_boot_ci90_hi"]), abs=0.001)
                assert round(hb["hier95_lo"], 3) == pytest.approx(float(expected["hier_boot_ci95_lo"]), abs=0.001)
                assert round(hb["hier95_hi"], 3) == pytest.approx(float(expected["hier_boot_ci95_hi"]), abs=0.001)
                assert round(t95[0], 3) == pytest.approx(float(expected["seed_t_ci95_lo"]), abs=0.001)
                assert round(t95[1], 3) == pytest.approx(float(expected["seed_t_ci95_hi"]), abs=0.001)
                assert round(sb["boot90_lo"], 3) == pytest.approx(float(expected["seedmean_boot_ci90_lo"]), abs=0.001)
                assert round(sb["boot90_hi"], 3) == pytest.approx(float(expected["seedmean_boot_ci90_hi"]), abs=0.001)
                assert round(sb["boot95_lo"], 3) == pytest.approx(float(expected["seedmean_boot_ci95_lo"]), abs=0.001)
                assert round(sb["boot95_hi"], 3) == pytest.approx(float(expected["seedmean_boot_ci95_hi"]), abs=0.001)
                assert float(f"{hb['p_le0']:.3g}") == pytest.approx(float(expected["hier_boot_p_le0"]), rel=1e-2)

    assert row_idx == len(stored_rows) == 15
