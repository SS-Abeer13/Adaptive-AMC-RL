"""Reproduce paper/analysis/out/nr2_stats.csv and nr2_seed_stats.csv."""

import os
import csv
import numpy as np
import pytest

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


def test_nr2_reproduction():
    assert os.path.exists(NR2_EVAL_PATH), f"Missing {NR2_EVAL_PATH}"
    assert os.path.exists(NR2_STATS_CSV), f"Missing {NR2_STATS_CSV}"

    mat = load_mat_eval(NR2_EVAL_PATH)
    A = mat["nr2_seeds"]
    if A.shape[0] > A.shape[1]:
        A = A.T  # (10, 500)
    assert A.shape == (10, 500)

    M1 = mat["m1_seeds"]
    if M1.shape[0] > M1.shape[1]:
        M1 = M1.T
    ens = mat["nr2_ens"]

    a = A.mean(axis=0)  # Primary evaluated policy: per-seed trace mean
    cmp = {name: mat["cmp"][key] for name, key in FAMILY}

    # Evaluate family
    p_vals = []
    comp_rows = []
    for name, _ in FAMILY:
        c = cmp[name]
        pm = paired_margin(a, c, confidence=0.90)
        wx = wilcoxon_test(a, c)
        comp_rows.append({
            "comparator": name,
            "margin_pct": pm["margin_pct"],
            "ci90_lo": pm["ci_lo"],
            "ci90_hi": pm["ci_hi"],
            "wilcoxon_p": wx["pvalue"],
        })
        p_vals.append(wx["pvalue"])

    hp = holm_adjust(p_vals)
    for r, x in zip(comp_rows, hp):
        r["holm_p"] = x
        r["beats"] = evaluate_rule_r1(r["ci90_lo"], r["holm_p"])

    # Load stored CSV
    with open(NR2_STATS_CSV, mode="r", encoding="utf-8") as f:
        stored_rows = list(csv.DictReader(f))

    assert len(comp_rows) == len(stored_rows)

    for calc, stored in zip(comp_rows, stored_rows):
        assert calc["comparator"] == stored["comparator"]
        # Margin and CIs to 2 decimals
        assert round(calc["margin_pct"], 2) == pytest.approx(float(stored["margin_pct"]), abs=0.01)
        assert round(calc["ci90_lo"], 2) == pytest.approx(float(stored["ci90_lo"]), abs=0.01)
        assert round(calc["ci90_hi"], 2) == pytest.approx(float(stored["ci90_hi"]), abs=0.01)
        # Holm p within 1% relative
        assert calc["holm_p"] == pytest.approx(float(stored["holm_p"]), rel=0.01)
        assert calc["beats"] == int(stored["beats"])

    # Seed-level analysis vs primary (Context-joint-500)
    c_prim = cmp[PRIMARY]
    sm = compute_seed_margins(A, c_prim)
    st = seed_sign_test(sm)
    assert st["seeds_above"] == 9
    assert st["n_seeds"] == 10
    assert st["sign_p"] == pytest.approx(0.01074, rel=1e-3)

    hb = hierarchical_bootstrap(A, c_prim, B=20000, rng=20261104, confidence=0.95)
    sb = seedmean_bootstrap(sm, B=20000, rng=20261105, confidence=0.95)

    assert hb["hier95_lo"] == pytest.approx(2.224, abs=0.02)
    assert hb["hier95_hi"] == pytest.approx(4.401, abs=0.02)
    assert sb["boot95_lo"] == pytest.approx(2.33, abs=0.02)
    assert sb["boot95_hi"] == pytest.approx(4.219, abs=0.02)

    # Secondary comparisons
    sec_m1 = paired_margin(a, M1.mean(axis=0), confidence=0.90)
    sec_ens = paired_margin(ens, c_prim, confidence=0.90)

    assert sec_m1["margin_pct"] == pytest.approx(2.583, abs=0.02)
    assert sec_m1["ci_lo"] == pytest.approx(2.323, abs=0.02)
    assert sec_m1["ci_hi"] == pytest.approx(2.843, abs=0.02)

    assert sec_ens["margin_pct"] == pytest.approx(5.525, abs=0.02)
    assert sec_ens["ci_lo"] == pytest.approx(4.987, abs=0.02)
    assert sec_ens["ci_hi"] == pytest.approx(6.063, abs=0.02)

    # Verdict
    prim_row = next(r for r in comp_rows if r["comparator"] == PRIMARY)
    v = evaluate_verdict(
        trace_pass=bool(prim_row["beats"] == 1),
        seed_pass=evaluate_rule_r2(hb["hier95_lo"]),
        family_beats=[r["beats"] for r in comp_rows],
    )
    assert v["verdict"] == "CONFIRM"
    assert v["win"] is True
    assert v["reframing_gate"] == "OPEN"
