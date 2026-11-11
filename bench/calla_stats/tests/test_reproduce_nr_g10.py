"""Strict reproduction of REPORT_nr_g10.txt (18 rows) and nr_g10_ctxj_descriptive.csv."""

import os
import csv
import pytest
import numpy as np

from calla_stats import (
    paired_margin,
    wilcoxon_test,
    holm_adjust,
    hierarchical_bootstrap,
    compute_seed_margins,
    seed_sign_test,
    evaluate_rule_r1,
    load_mat_eval,
)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
DESCRIPTIVE_CSV = os.path.join(ROOT, "paper", "analysis", "out", "nr_g10_ctxj_descriptive.csv")
REPORT_NR_G10_TXT = os.path.join(ROOT, "Optimized", "v17x", "Dataset", "REPORT_nr_g10.txt")
CKPT_DIR = os.path.join(ROOT, "Optimized", "v17x", "Dataset", "ckpt")


def assert_pvalue(calc_p: float, exp_p: float, name: str):
    rel_diff = abs(calc_p - exp_p) / max(exp_p, 1e-300)
    abs_diff = abs(calc_p - exp_p)
    assert (rel_diff <= 0.01) or (abs_diff <= 1e-12), (
        f"{name} p-value mismatch: calc={calc_p}, exp={exp_p} (rel={rel_diff:.4g}, abs={abs_diff:.4g})"
    )


def test_nr_g10_report_18_rows():
    """Strictly assert all 18 rows and all columns of REPORT_nr_g10.txt."""
    assert os.path.exists(REPORT_NR_G10_TXT), f"Missing {REPORT_NR_G10_TXT}"

    # Parse the 18 rows from REPORT_nr_g10.txt
    stored_rows = []
    with open(REPORT_NR_G10_TXT, mode="r", encoding="utf-8") as f:
        for line in f:
            if line.strip().startswith("cell,comparator,"):
                table_lines = [line]
                for l in f:
                    if not l.strip():
                        break
                    table_lines.append(l)
                reader = csv.DictReader(table_lines)
                stored_rows = list(reader)
                break

    assert len(stored_rows) == 18, f"Expected 18 rows in REPORT_nr_g10.txt, found {len(stored_rows)}"

    calc_rows = []
    for cell in ["G2_hi_d10", "G3_lo_d18"]:
        mat_path = os.path.join(CKPT_DIR, "nr_g10", f"eval_{cell}.mat")
        assert os.path.exists(mat_path), f"Missing {mat_path}"
        data = load_mat_eval(mat_path)
        prim = data["primary"]
        cmps = data["comparators"]

        cmp_names = [
            "Baseline", "OLLA", "OLLA (tuned target)", "Multi-OLLA",
            "Fixed", "FixedPU (Oracle)", "Context table",
            "Bandit (global)", "Bandit (delay class)"
        ]

        pvals = []
        cell_rows = []
        for name in cmp_names:
            c = cmps[name]
            pm = paired_margin(prim, c, confidence=0.90)
            wx = wilcoxon_test(prim, c, engine="matlab")
            pvals.append(wx["pvalue"])
            cell_rows.append({
                "cell": cell,
                "comparator": name,
                "margin_pct": pm["margin_pct"],
                "ci90_lo": pm["ci_lo"],
                "ci90_hi": pm["ci_hi"],
                "wilcoxon_p": wx["pvalue"],
            })

        hps = holm_adjust(pvals)
        for r, hp in zip(cell_rows, hps):
            r["holm_p"] = hp
            r["beats"] = evaluate_rule_r1(r["ci90_lo"], r["holm_p"])
            calc_rows.append(r)

    assert len(calc_rows) == len(stored_rows) == 18

    for calc, stored in zip(calc_rows, stored_rows):
        label = f"{stored['cell']} | {stored['comparator']}"
        assert calc["cell"] == stored["cell"]
        assert calc["comparator"] == stored["comparator"]

        # Margin and CIs to 0.01 tolerance
        assert abs(calc["margin_pct"] - float(stored["margin_pct"])) <= 0.01 + 1e-6, (
            f"{label}: margin {calc['margin_pct']} vs stored {stored['margin_pct']}"
        )
        assert abs(calc["ci90_lo"] - float(stored["ci90_lo"])) <= 0.01 + 1e-6, (
            f"{label}: ci90_lo {calc['ci90_lo']} vs stored {stored['ci90_lo']}"
        )
        assert abs(calc["ci90_hi"] - float(stored["ci90_hi"])) <= 0.01 + 1e-6, (
            f"{label}: ci90_hi {calc['ci90_hi']} vs stored {stored['ci90_hi']}"
        )

        # Wilcoxon and Holm p-values: 1% relative or 1e-12 absolute
        assert_pvalue(calc["wilcoxon_p"], float(stored["wilcoxon_p"]), f"{label} wilcoxon_p")
        assert_pvalue(calc["holm_p"], float(stored["holm_p"]), f"{label} holm_p")

        # Beats exact
        assert calc["beats"] == int(stored["beats"]), f"{label}: beats mismatch"


def test_nr_g10_ctxj_descriptive():
    """Strictly assert nr_g10_ctxj_descriptive.csv."""
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

        assert abs(pm["margin_pct"] - float(expected["margin_pct"])) <= 0.01 + 1e-6
        assert abs(pm["ci_lo"] - float(expected["ci90_lo"])) <= 0.01 + 1e-6
        assert abs(pm["ci_hi"] - float(expected["ci90_hi"])) <= 0.01 + 1e-6

        assert_pvalue(wx["pvalue"], float(expected["wilcoxon_p"]), f"{cell} ctxj wilcoxon_p")
        assert abs(hb["hier95_lo"] - float(expected["hier_ci95_lo"])) <= 0.01 + 1e-6
        assert abs(hb["hier95_hi"] - float(expected["hier_ci95_hi"])) <= 0.01 + 1e-6
        assert st["seeds_above"] == int(expected["seeds_above"])

        ctx_vs_ctxj = 100.0 * (c.mean() / ct.mean() - 1.0)
        assert abs(ctx_vs_ctxj - float(expected["ctx_vs_ctxj_pct"])) <= 0.01 + 1e-6
