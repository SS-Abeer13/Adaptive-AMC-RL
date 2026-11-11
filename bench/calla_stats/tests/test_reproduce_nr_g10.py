"""Reproduce paper/analysis/out/nr_g10_ctxj_descriptive.csv."""

import os
import csv
import numpy as np
import pytest

from calla_stats import (
    paired_margin,
    wilcoxon_test,
    hierarchical_bootstrap,
    compute_seed_margins,
    seed_sign_test,
    load_mat_eval,
)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
DESCRIPTIVE_CSV = os.path.join(ROOT, "paper", "analysis", "out", "nr_g10_ctxj_descriptive.csv")
CKPT_DIR = os.path.join(ROOT, "Optimized", "v17x", "Dataset", "ckpt")


def test_nr_g10_reproduction():
    assert os.path.exists(DESCRIPTIVE_CSV), f"Missing {DESCRIPTIVE_CSV}"

    with open(DESCRIPTIVE_CSV, mode="r", encoding="utf-8") as f:
        stored_rows = list(csv.DictReader(f))

    assert len(stored_rows) == 2

    for row_idx, cell in enumerate(["G2_hi_d10", "G3_lo_d18"]):
        g_mat_path = os.path.join(CKPT_DIR, "g10", f"eval_{cell}.mat")
        n_mat_path = os.path.join(CKPT_DIR, "nr_g10", f"eval_{cell}.mat")
        assert os.path.exists(g_mat_path)
        assert os.path.exists(n_mat_path)

        g = load_mat_eval(g_mat_path)
        n = load_mat_eval(n_mat_path)

        A = n["seeds"]
        if A.shape[0] > A.shape[1]:
            A = A.T  # (5, 300)
        assert A.shape == (5, 300)

        # Context-joint comparator from g10
        c = g["comparators"]["Context-joint"]
        ct = n["comparators"]["Context table"]
        prim = n["primary"]

        pm = paired_margin(prim, c, confidence=0.90)
        wx = wilcoxon_test(prim, c)
        hb = hierarchical_bootstrap(A, c, B=20000, rng=20261104, confidence=0.95)
        sm = compute_seed_margins(A, c)
        st = seed_sign_test(sm)

        expected = stored_rows[row_idx]
        assert expected["cell"] == cell
        assert expected["n_traces"] == "300"
        assert expected["n_seeds"] == "5"

        assert round(float(c.mean()), 4) == pytest.approx(float(expected["ctxj_mean"]), abs=1e-4)
        assert round(float(prim.mean()), 4) == pytest.approx(float(expected["primary_mean"]), abs=1e-4)

        assert round(pm["margin_pct"], 2) == pytest.approx(float(expected["margin_pct"]), abs=0.01)
        assert round(pm["ci_lo"], 2) == pytest.approx(float(expected["ci90_lo"]), abs=0.01)
        assert round(pm["ci_hi"], 2) == pytest.approx(float(expected["ci90_hi"]), abs=0.01)

        assert wx["pvalue"] == pytest.approx(float(expected["wilcoxon_p"]), rel=0.02)
        assert round(hb["hier95_lo"], 2) == pytest.approx(float(expected["hier_ci95_lo"]), abs=0.01)
        assert round(hb["hier95_hi"], 2) == pytest.approx(float(expected["hier_ci95_hi"]), abs=0.01)
        assert st["seeds_above"] == int(expected["seeds_above"])

        ctx_vs_ctxj = 100.0 * (c.mean() / ct.mean() - 1.0)
        assert round(ctx_vs_ctxj, 2) == pytest.approx(float(expected["ctx_vs_ctxj_pct"]), abs=0.01)
