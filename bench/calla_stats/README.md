# calla_stats: Confirmatory Link Adaptation Evaluation Protocol

`calla_stats` is a standalone Python statistics package implementing the confirmatory evaluation protocol for 5G/NR wireless link adaptation research. It requires Python >= 3.11 and has **no MATLAB dependency**, operating directly on NumPy arrays, CSV/JSON files, or HDF5 evaluation archives.

---

## 1. Protocol Architecture

The package formalizes a two-level confirmatory inference hierarchy:

1. **Paired Per-Trace Margin**:
   $$\text{Margin}(\%) = 100 \cdot \frac{\bar{d}}{\bar{b}} = 100 \cdot \left(\frac{\bar{a}}{\bar{b}} - 1\right)$$
   with a two-sided 90% Student-$t$ confidence interval:
   $$100 \cdot \frac{\bar{d} \pm t_{0.95, N-1} \cdot \text{SE}(d)}{\bar{b}}$$
   where $a$ is the evaluated policy, $b$ is the comparator, and $d = a - b$ is evaluated under identical channel realizations (Common Random Numbers / CRN).

2. **Multiplicity Control (Family-wise Error Rate)**:
   - Two-sided Wilcoxon signed-rank test against each comparator.
   - Holm-Bonferroni step-down adjustment across the pre-registered family of comparators.

3. **Hierarchical Seed $\times$ Trace Bootstrap ($B = 20{,}000$)**:
   - Accounts for dual sources of uncertainty: random training seed initialization and wireless fading trace sampling.
   - Resamples training seeds with replacement, then evaluation traces with replacement (preserving trace pairing with comparator and CRN).
   - Generates 95% and 90% bootstrap percentile confidence intervals.

4. **Seed-Level Inference**:
   - Exact one-sided sign test over training seeds ($H_0: p \le 0.5$).
   - Seed-mean bootstrap over the $S$ seed margins.

5. **Pre-Registered Decision Rules & Verdicts**:
   - **Rule R1**: Trace-level superiority after family-wise adjustment ($\text{Holm } p < 0.05$ and $90\% \text{ CI lower bound} > 0$).
   - **Rule R2**: Generalizability across training seeds ($\text{Hierarchical } 95\% \text{ CI lower bound} > 0$ vs the strongest comparator).
   - **Verdict States**:
     - `CONFIRM`: Rule R1 passes on primary comparator AND Rule R2 passes.
     - `TRACE`: Rule R1 passes on primary comparator BUT Rule R2 fails.
     - `REVERSE`: Significant degradation ($\text{Holm } p < 0.05$ and $90\% \text{ CI upper bound} < 0$).
     - `NULL`: No statistically confirmed improvement on the primary comparator.
   - **WIN**: Rule R1 passes against all comparators in the pre-registered family.

---

## 2. Installation

```bash
cd bench/calla_stats
pip install -e .
```

Dependencies: `numpy>=1.24.0`, `scipy>=1.10.0`, `h5py>=3.8.0`, `pytest>=7.0.0`.

---

## 3. Worked Example: Evaluated Policy vs Combined Table

The following example evaluates a 10-seed trained neural link adaptation policy (`NR2`) against the pre-registered comparator family in deadline traffic (`M1_dl_rtt8`), focusing on the primary benchmark (`Context-joint-500`):

```python
import numpy as np
from calla_stats import (
    paired_margin,
    wilcoxon_test,
    holm_adjust,
    hierarchical_bootstrap,
    compute_seed_margins,
    seed_sign_test,
    evaluate_rule_r1,
    evaluate_rule_r2,
    evaluate_verdict,
    load_mat_eval,
)

# 1. Load evaluation checkpoint (HDF5 format, no MATLAB required)
data = load_mat_eval("Optimized/v17x/Dataset/ckpt/nr2/eval.mat")
A = data["nr2_seeds"]      # Shape (10, 500): 10 seeds x 500 traces
a = A.mean(axis=0)          # Treatment policy: mean across training seeds
comparators = data["cmp"]   # Dictionary of comparator trace metrics (500 traces)
c_primary = comparators["ctxj500"]  # Context-joint-500

# 2. Rule R1: Paired Margin & Multiplicity-Adjusted Wilcoxon Test
pm = paired_margin(a, c_primary, confidence=0.90)
wx = wilcoxon_test(a, c_primary)

print(f"Margin vs Context-joint-500: {pm['margin_pct']:+.2f}%")
print(f"90% Student-t CI: [{pm['ci_lo']:+.2f}%, {pm['ci_hi']:+.2f}%]")
print(f"Wilcoxon p-value: {wx['pvalue']:.3e}")

# 3. Rule R2: Hierarchical Bootstrap (B = 20,000, seed 20261104)
hb = hierarchical_bootstrap(A, c_primary, B=20000, rng=20261104, confidence=0.95)
print(f"Hierarchical 95% CI: [{hb['hier95_lo']:+.2f}%, {hb['hier95_hi']:+.2f}%]")
print(f"Probability of improvement: {hb['p_improvement']:.4f}")

# 4. Seed Sign Test
seed_margins = compute_seed_margins(A, c_primary)
st = seed_sign_test(seed_margins)
print(f"Seeds above comparator: {st['seeds_above']}/{st['n_seeds']} (sign test p = {st['sign_p']:.4g})")

# 5. Pre-Registration Verdict
r1_pass = evaluate_rule_r1(ci90_lo=pm["ci_lo"], holm_p=wx["pvalue"])
r2_pass = evaluate_rule_r2(hier95_lo=hb["hier95_lo"])
verdict = evaluate_verdict(trace_pass=r1_pass, seed_pass=r2_pass, family_beats=[1]*8)

print(f"Verdict: {verdict['verdict']} | WIN: {verdict['win']} | Gate: {verdict['reframing_gate']}")
```

Expected reproduction output:
```text
Margin vs Context-joint-500: +3.35%
90% Student-t CI: [+2.93%, +3.76%]
Wilcoxon p-value: 3.681e-30
Hierarchical 95% CI: [+2.22%, +4.40%]
Probability of improvement: 1.0000
Seeds above comparator: 9/10 (sign test p = 0.01074)
Verdict: CONFIRM | WIN: True | Gate: OPEN
```

---

## 4. Evaluation Reporting Card Template

Whenever publishing or pre-registering an evaluation study, report the following standardized card:

```markdown
# Wireless Link Adaptation Evaluation Reporting Card

## 1. Study Information & Protocol Identification
| Parameter | Value |
|:---|:---|
| Protocol Specification | v17x / Pre-registration Protocol |
| Evaluation Case / Study ID | M1_dl_rtt8 |
| Treatment Scheme | Deep A2C (NR recipe) |
| Primary Comparator | Context-joint-500 |
| Traffic Model | Deadline (RTT = 8 TTIs) |
| Multi-user Scheduler | Proportional Fair (scheduled rate average) |
| HARQ Feedback Delay | 8 TTIs |
| Target First-Tx BLER | 0.10 |
| Achieved First-Tx BLER | 0.089 |

## 2. Experimental Rigor & Calibration Budgets
| Rigor Dimension | Specification |
|:---|:---|
| Calibration Traces & Seeds | 20 traces x 5 schemes (seeds 60001+) |
| Evaluation Traces & Seeds | 500 traces x 10 seeds (seeds 70001+) |
| Data Split & Seed Disjointness | Verified disjoint: calibration seeds != eval seeds != CRN |
| PF Average Definition | `R_ema = (1 - 0.05)*R_ema + 0.05*r_sched` |
| HARQ State Timing | RTT-delayed ACK/NACK credit allocation |

## 3. Decision Rules & Pre-registered Verdict
| Criterion | Metric & Threshold | Outcome |
|:---|:---|:---|
| Rule R1 (Trace-Level Superiority) | Holm p < 0.05 AND 90% CI lower bound > 0 | **PASS (+3.35%, 90% CI [+2.93, +3.76], Holm p = 3.68e-30)** |
| Rule R2 (Seed-Level Generalizability)| Hierarchical 95% CI lower bound > 0 vs Primary | **PASS (hierarchical 95% CI [+2.22, +4.40], 9/10 seeds > 0)** |
| Pre-registered Verdict | CONFIRM / TRACE / REVERSE / NULL | **CONFIRM / WIN (reframing gate OPEN)** |
```

---

## 5. CLI Usage

The package includes a command-line interface `calla-stats`:

```bash
# Generate a markdown reporting card template
calla-stats card --output REPORTING_CARD.md

# Evaluate a study from JSON input
calla-stats eval --input study_data.json --primary "Context-joint-500" --out-csv results.csv --out-json results.json
```
