# Pre-registration G6: comparator calibration budget and the combined comparator (v17b-cal)

**STATUS: FROZEN (Checkpoint 5, 4 Nov 2026).** §§1–6 do not change after the freeze commit recorded in `paper/STATUS.md`. Results are appended in §8 only. Common rules are in `common_rules.md`.
**Class:** essential. **No RL training**: the RL per-trace values come from the stored M1 results.

## 1. Questions
- **Q1 (budget):** does M1's Claim B survive when Fixed, FixedPU, the Context table and tuned-target OLLA are re-calibrated with a budget comparable to RL's, **using searches that cannot stop at a local optimum where that is feasible**?
- **Q2 (information):** does M1 beat a calibrated rule that combines the learner's cues (slack × class × HARQ-process state)?

What the original calibration did (code read 4 Nov 2026), which is why G6 exists:

| Rule | Original calibration (v17) |
|---|---|
| Fixed | 9 global offsets, 20 traces (`calibrateFixedClass_v17.m`): exhaustive |
| FixedPU | the **same 9 runs**; each class takes its own argmax from per-class metrics. The finished 6-entry table is never evaluated jointly (separable grid) |
| Context table | **coordinate ascent**, 2 passes from all-zero, 10 traces (`calibrateCtx_v17.m`): can stop at a local optimum |
| OLLA (tuned target) | 6 targets, 10 traces: exhaustive |
| Residual A2C | 3000 episodes × 10 seeds |

## 2. Design

### 2.1 Fixed parts
- **RL under test (frozen):** M1 primary residual A2C (10 seeds) and its ensemble (secondary). Per-trace values come from `results_v17_M1_dl_rtt8.mat` (`metrics.primary`). REPRO: re-evaluating seed 1 on traces 1–20 must reproduce the stored values exactly.
- **Calibration traces:** 500 fresh traces, seeds **600001–600500**, CRN draws **610001+**. The code asserts disjointness from every `trace_seed_base` / `crn_seed_base` range of v9–v17 and from 60000+ and 80000+ (validation).
- **Evaluation:** the original M1 traces 500001–500500 with CRN 510001+.
- **Calibration objective** (all rules): the primary metric, `sum(okU)/sum(resU)` over users and calibration traces after burn-in, exactly as `calibrateCtx_v17.m: score`. Ties are broken by the smallest Σ|offset|, then lexicographically.
- **Environment:** M1's (RTT 8, 8 processes, `pf_avg = 'scheduled'`, drain, useful bits, cold-start OLLA).

### 2.2 Single-cue rules, re-calibrated on the 500 traces ("-500")
No coordinate ascent is used for Fixed, Context or OLLA.
1. **Fixed-500:** exhaustive over offsets −5…+3 (9 candidates).
2. **FixedPU-500 (class oracle):**
   - **(a) separable grid**, as in v17: the 9 global-offset runs; each of the 6 classes takes the argmax of its per-class metric;
   - **(b) joint refinement:** coordinate ascent on the **joint** 6-entry table, evaluated as a whole on the 500 traces. Sweeps over classes in lexicographic order; each class tries the 8 other offsets in −5…+3; a move is accepted if the joint objective rises by more than 1e-6; at most 3 sweeps.
   - FixedPU-500 is the table with the higher calibration objective (never lower than (a)). This only **strengthens** FixedPU relative to v17. The paper notes that v17's FixedPU was separable.
3. **Context-500:** **exhaustive** over all 7³ = 343 tables (3 slack bins, edges [2 5], offsets −4…+2).
4. **OLLA-tuned-500:** exhaustive over targets {0.01, 0.02, 0.03, 0.05, 0.07, 0.10, 0.15, 0.20, 0.30, 0.50} × down-steps {0.25, 0.5, 1.0} dB (30 settings; also answers attack #19 / G9).

### 2.3 Combined comparator, "Context-joint-500"
- **Cells:** slack ≤ 2 / 3–5 / > 5 TTI × delay class d ≤ 4 / d ≥ 5 × speed class < 10 / 10–20 / > 20 m/s (`userClass_v17`; true values, as for FixedPU) × busy HARQ processes 0 / ≥ 1 (`sum(H.proc_busy(u,:)) >= 1` at the decision). **3 × 2 × 3 × 2 = 36 cells.** Busy ≥ 3 merges into ≥ 1 (1.3 % of M1 decisions, `table_action_by_state.csv`).
- **Offsets:** −4…+2 CQI steps on the OLLA reference; applied to new transmissions.
- **Composite table (deterministic):** `composite(cell) = clip(FixedPU-500(class) + Context-500(slack bin) − Fixed-500, −4, +2)`. It is a function of the already re-calibrated rules.
- **Sparse cells:** one counting pass with the composite table counts scheduled new-transmission decisions per cell on the 500 calibration traces. A cell with **fewer than N = 200** decisions is **not searched** and keeps its composite value ("fallback"). The counts and fallback list are written to `ctxj_cells.csv`.
- **Search (coordinate ascent; exhaustive search over 7³⁶ tables is infeasible):**
  - **4 starts:** S0 = the composite table; R1–R3 = random initial offsets, uniform on −4…+2 per searched cell, with generator seeds 90017 + k.
  - One **sweep** visits the searched cells in lexicographic order. Each cell tries the 6 other offsets and accepts the best improvement over 1e-6 (evaluated on all 500 traces).
  - **Every start continues until a full sweep makes no accepted move** ("the calibration objective stops improving"). Safety cap: 6 sweeps per start. A start that hits the cap is reported as such.
  - **Final table:** the start with the highest calibration objective (ties → S0).
  - Checkpoint after every sweep.
- **Sanity check, before any evaluation:** the final table's calibration objective must be ≥ that of **each** coarser table: Fixed-500, FixedPU-500, Context-500 and the composite table. If it is not, it is reported as a **search failure**, and `g6c` refuses to run. Because S0 starts at the composite and a move is accepted only if the objective rises, this can fail only through a bug.
- **Freeze rule:** all tables are written to `cal500_tables.txt` and hashed (SHA-256, logged) **before** any evaluation-trace run.
- **Overfitting visibility:** for every re-calibrated table the calibration-set objective and the evaluation-set on-time ratio are reported side by side (`table_cal500.csv`), for all five rules and for the single-cue originals.

### 2.4 Profiles (chosen by the author at launch, before any result; both frozen)
| Profile | Single-cue rules | Combined search | Wording consequence |
|---|---|---|---|
| **full (default)** | as §2.2 | as §2.3 | none |
| **lite** (`G6B_PROFILE=lite`) | as §2.2 | starts R1–R3 and S0 run to convergence on the **first 100** calibration traces; the best two final tables are then polished on all 500 traces (sweeps until no accepted move, cap 6); the final table is the better of the two by the 500-trace objective | any statement about the combined comparator carries "(search budget reduced)" |

## 3. Decision rules (pre-registered)
- **Family:** {Baseline, OLLA, OLLA-tuned-500, Multi-OLLA, Fixed-500, FixedPU-500, Context-500, Bandit (global), Bandit (delay class), **Context-joint-500**}: **10 comparators, Holm over 10.**
- **"Beats X":** two-sided Wilcoxon signed-rank on paired per-trace values, Holm-adjusted p < 0.05, and the 90 % CI lower bound of the % margin > 0 (`common_rules.md` R1).
- **Claim A** = beats OLLA, OLLA-tuned-500, Multi-OLLA. **Claim B-500** = beats Fixed-500, FixedPU-500, Context-500. **Joint parity (JP)** = beats Context-joint-500.
- **Seed-level rule** (`common_rules.md` R2): for the best comparator in each claim the hierarchical seed × trace 95 % CI lower bound is reported. If a claim passes at trace level but this lower bound is ≤ 0, the paper states the claim with "not robust to seed resampling".

## 4. Pre-registered wording (also governs contribution C2)

| Outcome | Paper statement |
|---|---|
| A, B-500 and JP pass (seed-level lower bounds > 0) | C2 keeps "beats **all calibrated comparators**". The paper may use **"same-information"**: "With rules re-calibrated by exhaustive search on 500 fresh traces, and a table that combines deadline slack, user class and HARQ-process state, residual A2C still beat every comparator (+x % vs the best rule)." |
| A, B-500 and JP pass, but a seed-level lower bound ≤ 0 | as above, followed by "; the margin over [comparator] is not robust to seed resampling (hierarchical 95 % CI [a, b] %)" |
| A and B-500 pass, JP fails | C2 becomes "beats **the OLLA family and the single-cue calibrated rules**". The combined table is reported as matching RL (or beating it, if significant): "A calibrated rule combining the learner's cues matched the learned policy (margin x %, CI …)." "Same-information" is not used |
| A passes, B-500 fails | The headline weakens to Claim A: "Residual A2C beats the OLLA family under realistic HARQ timing (+x %); against calibrated rules its advantage depends on their calibration budget." |
| A fails | "The deadline gain did not survive re-calibration." The paper becomes a negative and methodological result |
| Sanity check fails (search failure) | No wording is decided. The author is told before any evaluation; the search is re-run after the bug is fixed (a new, dated pre-registration note) |

## 5. Compute (basis `compute_basis.md`: 0.095 s per 200-TTI evaluation at RTT 8 with 2 workers, an **upper bound**; the preflight measures the deterministic-rule rate, which should be lower because no network is evaluated)

| Step | Evaluations | Wall time |
|---|---|---|
| Fixed-500 and FixedPU-500 (a): shared 9 offsets × 500 | 4,500 | 0.1 h |
| FixedPU-500 (b): ≤ 3 sweeps × 48 tables × 500 | ≤ 72,000 | ≤ 1.9 h |
| Context-500 exhaustive: 343 × 500 | 171,500 | 4.5 h |
| OLLA-tuned-500: 30 × 500 | 15,000 | 0.4 h |
| **`g6a` total** | **263,000** | **6.9 h** |
| Combined: one sweep ≤ 36 cells × 6 × 500 | 108,000 | 2.85 h per sweep |
| **`g6b` minimum** (4 starts × 2 sweeps) / **expected** (× 3) / **cap** (× 6) | 0.86 M / 1.30 M / 2.59 M | **22.8 h / 34.2 h / 68.4 h** |
| `g6c`: counting pass + evaluation of the re-calibrated rules + REPRO | ≈ 8,000 | 0.2 h |
| **G6 total (full)** | | **≈ 30 h min, ≈ 41 h expected, ≤ 76 h cap** |
| **G6 total (lite)** | `g6b` ≈ 0.26 M (restarts on 100 traces) + ≈ 0.43 M (polish) | **≈ 25 h** |

Sweeps skip cells below the 200-decision threshold, so real sweeps are cheaper than the ≤ 36-cell bound. If the preflight shows a measured rate below the basis, all times scale down proportionally. The runner prints the projected time and pauses if the measured rate is more than 1.5× the basis (`common_rules.md` R5).

## 6. Multiplicity
Adds **1 case** (M1-cal500) with 2 scheme rows (primary, ensemble) to the registry. It is a robustness check of the primary claim and cannot create a new claim.

## 7. Stage specification for the runner (`Optimized/v17x/`)
Stages `g6a`, `g6b`, `g6c`, implemented by the functions `stage_g6a(ctx)`, `stage_g6b(ctx)`, `stage_g6c(ctx)` (interface in `Optimized/v17x/README_v17x_runner.md`).
- **`g6a`** units: `sep_grid_chunkK` (25 traces each), `fixedpu_joint_sweepS`, `ctx_exh_chunkK` (7 chunks of 49 tables), `olla_set_K` (30). Writes `cal500_single.txt`.
- **`g6b`** units: `start_k_sweep_s` (checkpoint after each sweep); writes `ctxj_cells.csv` and `cal500_tables.txt` with the SHA-256 and the sanity check.
- **`g6c`** refuses to run if the sanity check failed or the hash differs. Evaluates on traces 500001–500500, runs REPRO, computes REPLCMP/REPL/REPLSEED for the 10-comparator family and the hierarchical seed-level CIs, writes `fill_summary_v17b_cal.txt`, `table_cal500.csv` and the verdict row of §4.

## 8. Results
*(empty until run)*
