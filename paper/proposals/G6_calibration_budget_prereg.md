# Pre-registration: G6, comparator calibration budget and the combined same-cue comparator (v17b-cal)

**Status:** PROPOSAL, revised at Checkpoint 4 (4 Nov 2026). Nothing has been run. On approval at Checkpoint 5, §§1–6 are frozen, and results are appended in §7.
**Class:** **essential.** **No RL training.** RL per-trace values are read from the stored M1 results.

## 1. Questions
- **Q1 (budget):** does M1's Claim B survive when Fixed, FixedPU, the Context table and tuned-target OLLA are re-calibrated with a budget comparable to RL's?
- **Q2 (information):** does M1 beat a calibrated rule that combines the learner's cues (slack × class × HARQ-process state)?

| Rule | Current calibration | RL budget |
|---|---|---|
| Fixed / FixedPU | 20 traces | 3000 episodes × 10 seeds |
| Context table, tuned-target OLLA | 10 traces | (same) |

## 2. Design

### 2.1 Fixed parts
- **RL under test (frozen):** M1 primary residual A2C (10 seeds) and its ensemble (secondary). Per-trace values come from `results_v17_M1_dl_rtt8.mat` (`metrics.primary`). The REPRO check re-evaluates seed 1 on 20 traces and must reproduce the stored values exactly.
- **Calibration traces:** 500 fresh traces, seeds **600001–600500**, with CRN 610001+. The script asserts that these ranges are disjoint from every `trace_seed_base`/`crn_seed_base` range in v9–v17 and from 60000+ / 80000+.
- **Evaluation:** the original M1 traces 500001–500500 with CRN 510001+, so the pairing with the stored RL values is exact.

### 2.2 Re-calibrated single-cue rules (suffix "-500")
All are calibrated on the same 500 traces.
1. **Fixed-500:** offsets −5…+3, exhaustive.
2. **FixedPU-500:** per (delay class × speed class), offsets −5…+3. Coordinate ascent over the 6 classes, 2 sweeps, starting from Fixed-500.
3. **Context-500:** slack cue, the same 3 bins (edges [2 5]), offsets −4…+2. Coordinate ascent, 3 sweeps, from the current table. *(An exhaustive search, 343 tables, is too costly; see §5.)*
4. **OLLA-tuned-500:** target {0.01, 0.02, 0.03, 0.05, 0.07, 0.10, 0.15, 0.20, 0.30, 0.50} × down-step {0.25, 0.5, 1.0} dB, exhaustive.

### 2.3 The combined comparator, "Context-joint-500"
- **Cells:**
  - slack ≤ 2 / 3–5 / > 5 TTI (Context edges) × delay class d ≤ 4 / d ≥ 5 × speed class < 10 / 10–20 / > 20 m/s (`userClass_v17`; true values, exactly as FixedPU) × busy HARQ processes 0 / ≥ 1.
  - This gives **3 × 2 × 3 × 2 = 36 cells**.
  - Busy ≥ 3 is merged into ≥ 1 because it holds only 1.3 % of M1 decisions (8,150 / 618,192; `table_action_by_state.csv`).
- **Offsets:** −4…+2 CQI steps on the OLLA reference, as for the Context table. Applied to new transmissions; retransmissions reuse their MCS.
- **Initialisation:** offset(cell) = FixedPU-500(class) + [Context-500(slack bin) − Fixed-500], clipped to [−4, +2].
- **Search:**
  - 2 coordinate-ascent sweeps over the 36 cells, in a fixed order (busy, then slack, delay class, speed class; lexicographic);
  - each cell tries the 6 alternative offsets;
  - a change is accepted only if the mean on-time ratio over the 500 calibration traces rises by more than 1e-4 (absolute); ties keep the current value.
- **Matched budget:** the same 500 traces as the other -500 rules, with a search size of 432 table evaluations. That is comparable to Context-500's 3 × 3 × 6 = 54 evaluations scaled by cell count, and to the 343 tables an exhaustive Context search would need.
- **Sparse-cell rule:**
  - Before the search, one counting pass with the initial table counts **scheduled new-transmission decisions per cell** on the 500 calibration traces.
  - A cell with **fewer than N = 200** decisions is not searched. It takes the value of the coarser table, slack × class (busy merged), if that coarser cell has at least 200 decisions; otherwise it takes FixedPU-500's class value.
  - Cell counts and fallback decisions are written to `ctxj_cells.csv` before evaluation.
- **Freeze rule:** all tables are written to `cal500_tables.txt` and hashed (SHA-256 in the log) **before** any evaluation-trace run.

## 3. Decision rules (pre-registered)
- **Family:** {Baseline, OLLA, OLLA-tuned-500, Multi-OLLA, Fixed-500, FixedPU-500, Context-500, Bandit (global), Bandit (delay class), **Context-joint-500**}. That is **10 comparators, Holm over 10**.
- **"Beats X":** two-sided Wilcoxon signed-rank on paired per-trace values, Holm-adjusted p < 0.05 **and** 90 % CI lower bound of the % margin > 0. This is identical to `analyze_v17_replication.m`. Hierarchical seed × trace bootstrap 90 % CIs are reported as a secondary.
- **Claim A** = beats OLLA, OLLA-tuned-500 and Multi-OLLA.
- **Claim B-500** = beats Fixed-500, FixedPU-500 and Context-500.
- **Joint parity (JP)** = beats Context-joint-500.

## 4. Pre-registered wording (also governs contribution C2)

| Outcome | Paper statement |
|---|---|
| A, B-500 and JP pass | C2 keeps "beats **all calibrated comparators**". The paper may use **"same-information"**: "With rules re-calibrated on 500 fresh traces, including a table that combines deadline slack, user class and HARQ-process state, residual A2C still beat every comparator (+x % vs the best rule)." |
| A and B-500 pass, JP fails | C2 becomes "beats **the OLLA family and the single-cue calibrated rules**". The combined table is reported as matching RL (or beating it, if significant): "A calibrated rule combining the learner's cues matched the learned policy (margin x %, CI …)." |
| A passes, B-500 fails | The headline weakens to Claim A: "Residual A2C beats the OLLA family under realistic HARQ timing (+x %); against calibrated rules its advantage depends on their calibration budget." |
| A fails | Not expected. "The deadline gain did not survive re-calibration." The paper becomes negative and methodological. |

## 5. Compute (basis: `compute_basis.md`, 0.095 s per trace evaluation, 2 workers)

| Step | Trace evaluations | Wall time |
|---|---|---|
| Fixed-500 | 9 × 500 = 4,500 | 7 min |
| FixedPU-500 | 2 × 6 × 8 × 500 = 48,000 | 1.3 h |
| Context-500 | 3 × 3 × 6 × 500 = 27,000 | 43 min |
| OLLA-tuned-500 | 30 × 500 = 15,000 | 24 min |
| Context-joint-500 | 500 (count) + 432 × 500 = 216,500 | 5.7 h |
| Evaluation on M1 traces | 6 × 500 = 3,000 | 5 min |
| REPRO + preflight | ~1,000 | 2 min |
| **Total** | **≈ 316,000** | **≈ 8.4 h** (an overnight run) |

## 6. Multiplicity
This adds **1 case** (M1-cal500) with 2 scheme rows (primary, ensemble) to the registry. It is a robustness check of the primary claim; it cannot create a new claim.

## 7. Claude Code prompt (for the author's PC)
> In `Optimized/v17/`, implement G6 as pre-registered in `paper/proposals/G6_calibration_budget_prereg.md` (§§1–6 are frozen; do not change them).
> 1. Create `g6/evalPolicy_v17_g6.m` as a copy of `evalPolicy_v17.m`. Add one new `ptype 'ctx_joint'` that applies `env.ctxj_tab(slackBin, dc, vc, busyBin)` on the OLLA reference, exactly as `'ctxtab'` applies `env.ctx_tab`. Use the bins of §2.3 (`userClass_v17`, true delays and mean speeds as for FixedPU; busy = `sum(H.proc_busy(u,:)) >= 1`). Change nothing else.
> 2. Write `g6/test_g6_equivalence.m`. For every existing ptype on 5 M1 traces, `[tp,bler,cqi_err,act]` from the copy must equal `evalPolicy_v17` bit for bit. Stop if not.
> 3. Write `g6/g6_calibrate.m`. Generate calibration traces 600001–600500 / CRN 610001+ the way `runComparison_v17.m` L183–191 does. Assert disjointness from all registry seed ranges. Calibrate Fixed-500, FixedPU-500, Context-500, OLLA-tuned-500 and Context-joint-500 exactly as in §2, including the counting pass and the N = 200 sparse rule. Write `cal500_tables.txt` and `ctxj_cells.csv`, and log a SHA-256 of the tables before any evaluation. Run a 20-trace preflight first and stop if the per-evaluation time exceeds 0.14 s (1.5× basis).
> 4. Write `g6/g6_evaluate.m`. Evaluate the 5 re-calibrated rules on M1's evaluation traces (500001–500500, CRN 510001+). Load the stored per-trace values of every original scheme and of `Deep A2C v17` / `(ensemble)` from `results_v17_M1_dl_rtt8.mat`. Do a REPRO check: re-evaluate A2C seed 1 on traces 1–20 and require max |diff| = 0 vs stored. Compute REPLCMP/REPL lines for the 10-comparator family with the same functions as `analyze_v17_replication.m` (signrank two-sided, `holmAdjust_v17`, 90 % CI) and write them to `Dataset/fill_summary_v17b_cal.txt` and `paper/table_cal500.csv`.
> 5. Write `README_v17b_cal.md` §7 with the verdict row from §4, quoting the numbers. Do not reinterpret the rules. Commit on a new branch `v17b-cal`.
