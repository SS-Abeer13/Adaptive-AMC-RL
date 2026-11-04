# Pre-registration proposal: G6, comparator calibration budget (v17b-cal)

**Status:** PROPOSAL for Checkpoint 5. Nothing has been run. Once approved, §§1–6 are frozen. Results go in §7 after the run.
**Run by:** the author, in Claude Code on the PC (MATLAB R2023a). **No RL training.**

## 1. Question

Does the M1 result (residual A2C beats every comparator, Claim B included) still hold when the calibrated comparison rules get a calibration budget comparable to RL's training budget?

At present (ledger S12):

| Rule | Calibration traces | Search |
|---|---|---|
| Fixed | 20 | 9 global offsets (−5…+3 CQI steps) |
| FixedPU | 20 | per class (2 delay × 3 speed), same candidates |
| Context table | 10 | coordinate ascent, 3 slack bins × 7 offsets (−4…+2) |
| OLLA (tuned target) | 10 | target grid {0.01, 0.03, 0.10, 0.20, 0.30, 0.50} |
| Residual A2C | — | 3000 episodes × 10 seeds = 30,000 training episodes |

A reviewer can fairly say that the Context table was calibrated on 10 traces against 30,000 RL episodes.

## 2. Design

- **Policies under test (frozen, not retrained):** the stored M1 primary residual A2C (`results_v17_M1_dl_rtt8.mat`, `policies.A2C`, 10 seeds), plus the ensemble as a secondary scheme. Their per-trace values are already stored. Re-running them only serves as a REPRO check.
- **New calibration traces:** 500 traces, seeds **600001–600500**. These are disjoint from every evaluation, validation and calibration range in v9–v17 (to be checked by script against all `trace_seed_base` values in the registry). CRN draws use seeds 610001+.
- **Re-calibrated comparators** (suffix "-500"):
  1. **Fixed-500:** global offset, grid −5…+3, best mean on-time over the 500 traces.
  2. **FixedPU-500:** per class (2 × 3), same grid, exhaustive per class with the other classes held at Fixed-500.
  3. **Context-500 (primary new comparator):** slack cue, same 3 bins (edges [2 5]), offsets −4…+2. Exhaustive 7³ = 343 tables, so no coordinate-ascent local optimum.
  4. **Context-500-fine (secondary):** slack in 10 one-TTI bins × delay class (2) = 20 bins. Coordinate ascent from Context-500, up to 5 sweeps. This uses the same information A2C observes (slack, delay class) at a finer resolution.
  5. **OLLA-tuned-500:** target grid {0.01, 0.02, 0.03, 0.05, 0.07, 0.10, 0.15, 0.20, 0.30, 0.50} × down-step {0.25, 0.5, 1.0} dB (this also covers gap G9).
- **Evaluation:** the original M1 evaluation traces (500001–500500) with the original CRN draws (510001+). Comparators are deterministic.
- **Selection rule:** the argmax of the mean on-time ratio on the calibration traces. Ties go to the smaller |offset|. No look at the evaluation traces before the tables are frozen and written to `cal500_tables.txt`.

## 3. Decision rules (same machinery as v17 C3)

The Holm family is the original 9 comparators, with the five rules above **replacing** their originals:

{Baseline, OLLA, OLLA-tuned-500, Multi-OLLA, Fixed-500, FixedPU-500, Context-500, Bandit (global), Bandit (delay class)}.

Context-500-fine is reported as a **10th, secondary** comparator outside the family.

- **Claim A** = beats OLLA, OLLA-tuned-500, Multi-OLLA.
- **Claim B-500** = beats Fixed-500, FixedPU-500 and Context-500.
- **"Beats":** Holm-adjusted two-sided Wilcoxon p < 0.05 and 90 % CI lower bound > 0. As a secondary check, the hierarchical seed × trace bootstrap 90 % CI lower bound > 0 is also reported.

## 4. Pre-registered wording

| Outcome | Paper statement |
|---|---|
| Claim A and B-500 pass | "The M1 result is robust to the comparators' calibration budget: with rules re-calibrated on 500 fresh traces (a search budget comparable to RL's 30,000 training episodes), residual A2C still beat every comparator (+x % vs the best re-calibrated rule)." |
| Claim A passes, B-500 fails | **The headline weakens to Claim A.** "Residual A2C beats the OLLA family under realistic HARQ timing (+x %). Against calibrated rules its advantage depends on their calibration budget: it beat rules calibrated on 10–20 traces, but not rules calibrated on 500 traces." |
| Claim A fails | Not expected (margin vs OLLA ≈ +12 %). "The deadline gain did not survive re-calibration." The paper becomes negative and methodological. |
| Context-500-fine (secondary) | One sentence: beats / ties / loses, with margin and CI. It does not change the primary verdict. |

## 5. Compute estimate

Per trace-run (200 TTI, deterministic rule): ≤ 0.2 s (upper bound from v10 timing; ledger G15).

| Step | Trace-runs | Time (1 worker, ≤) |
|---|---|---|
| Fixed-500 | 9 × 500 = 4,500 | 15 min |
| FixedPU-500 | 6 × 9 × 500 = 27,000 | 1.5 h |
| Context-500 (exhaustive) | 343 × 500 = 171,500 | 9.5 h at 0.2 s. **Fallback, if the preflight shows > 0.1 s/run:** coordinate ascent with 5 random restarts (~10,000 runs, ~35 min) |
| Context-500-fine | ≤ 5 × 20 × 7 × 500 = 350,000 | **too costly.** Use 100 of the 500 traces for this secondary rule (~70,000 runs, ≤ 4 h), or drop it |
| OLLA-tuned-500 | 30 × 500 = 15,000 | 50 min |
| Evaluation | ~6 × 500 | 10 min |

**Proposed:** run the preflight (20 traces) first to measure the true per-run time, then fix the Context search mode by the rule above **before** the main run. Expected total: 3–6 h on 2 workers.

## 6. Multiplicity

This adds **1 case** (M1-cal500) and 2 scheme evaluations to the registry. It is a robustness check of the primary claim, not a new claim.

## 7. Results

*(empty until run)*
