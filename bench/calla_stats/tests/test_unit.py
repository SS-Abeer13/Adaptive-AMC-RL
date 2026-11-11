"""Unit tests for calla_stats core statistical functions."""

import numpy as np
import pytest
from calla_stats import (
    paired_margin,
    wilcoxon_test,
    holm_adjust,
    seed_sign_test,
    evaluate_rule_r1,
    evaluate_rule_r2,
    evaluate_verdict,
)


def test_paired_margin_identical():
    x = np.array([1.0, 2.0, 3.0, 4.0, 5.0])
    res = paired_margin(x, x, confidence=0.90)
    assert res["margin_pct"] == 0.0
    assert res["ci_lo"] == 0.0
    assert res["ci_hi"] == 0.0
    assert res["se"] == 0.0


def test_paired_margin_known_offset():
    baseline = np.array([10.0, 10.0, 10.0, 10.0, 10.0])
    treatment = baseline + 1.0  # +10%
    res = paired_margin(treatment, baseline, confidence=0.90)
    assert np.isclose(res["margin_pct"], 10.0)
    assert np.isclose(res["ci_lo"], 10.0)
    assert np.isclose(res["ci_hi"], 10.0)


def test_wilcoxon_identical():
    x = np.array([1.0, 2.0, 3.0, 4.0])
    res = wilcoxon_test(x, x)
    assert res["pvalue"] == 1.0


def test_holm_adjust():
    raw_p = [0.01, 0.04, 0.03]
    # m = 3
    # sorted: 0.01 (x3 -> 0.03), 0.03 (x2 -> 0.06), 0.04 (x1 -> 0.04 -> max(0.06, 0.04) = 0.06)
    adj = holm_adjust(raw_p)
    assert np.isclose(adj[0], 0.03)
    assert np.isclose(adj[1], 0.06)
    assert np.isclose(adj[2], 0.06)


def test_seed_sign_test():
    # 9 out of 10 positive
    margins = np.array([1.2, 0.5, 2.1, 3.0, -0.1, 0.8, 1.9, 2.5, 0.4, 1.1])
    res = seed_sign_test(margins)
    assert res["seeds_above"] == 9
    assert res["n_seeds"] == 10
    # binomtest(9, 10, 0.5, greater) = 11/1024 = 0.010742...
    assert np.isclose(res["sign_p"], 11.0 / 1024.0, atol=1e-5)


def test_verdict_rules():
    assert evaluate_rule_r1(ci90_lo=1.5, holm_p=0.01) == 1
    assert evaluate_rule_r1(ci90_lo=-0.5, holm_p=0.01) == 0
    assert evaluate_rule_r1(ci90_lo=1.5, holm_p=0.06) == 0

    assert evaluate_rule_r2(hier95_lo=0.5) is True
    assert evaluate_rule_r2(hier95_lo=-0.1) is False

    v_confirm = evaluate_verdict(trace_pass=True, seed_pass=True, family_beats=[1, 1, 1])
    assert v_confirm["verdict"] == "CONFIRM"
    assert v_confirm["win"] is True
    assert v_confirm["reframing_gate"] == "OPEN"

    v_trace = evaluate_verdict(trace_pass=True, seed_pass=False, family_beats=[1, 1, 0])
    assert v_trace["verdict"] == "TRACE"
    assert v_trace["win"] is False
    assert v_trace["reframing_gate"] == "closed"
