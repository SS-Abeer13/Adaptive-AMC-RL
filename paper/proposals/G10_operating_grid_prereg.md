# Pre-registration G10: operating-point grid under the v17 configuration, with per-cell recalibration (v17c-grid)

**STATUS: FROZEN (Checkpoint 5, 4 Nov 2026).** §§1–6 do not change after the freeze commit recorded in `paper/STATUS.md`; results go in §8. Common rules: `common_rules.md`. **Class: essential.** Uses the frozen v17 code; only case structs and calibration drivers are added.

## 1. Question
The only earlier load/deadline grid (v14 Y1–Y4) predates the v17 PF fix and ran at RTT 0; its verdict was "operating-point specific". Does the M1 result (RTT 8, 8 processes, 12 kbit, 10-TTI budget) carry over to neighbouring loads and deadlines under the v17 configuration, **against comparators that are re-calibrated for each cell**?

## 2. Cells and what is recalibrated in each

All cells use M1's configuration (RTT 8, 8 processes, `pf_avg = 'scheduled'`, drain, useful bits) and residual A2C with 3000 episodes.

| Cell | Packet bits | Deadline (TTI) | Note |
|---|---|---|---|
| G1_lo_d10 | 8,000 | 10 | lighter load, M1 deadline |
| G2_hi_d10 | 16,000 | 10 | heavier load, M1 deadline |
| G3_lo_d18 | 8,000 | 18 | lighter load, budget allows 2 HARQ rounds |
| G4_hi_d18 | 16,000 | 18 | heavier load, 2 HARQ rounds |

**Why 10 and 18, not v14's 6 and 14.** With RTT 8 a 6-TTI budget lets no retransmission arrive in time. A budget of 18 (≤ the 20-TTI packet period) allows two feedback rounds.

**Feasibility rule (v14 C2, unchanged):** Fixed's on-time ratio on 20 calibration traces must lie in [0.50, 0.97]. Otherwise move the packet size one step towards 12,000 (8,000 → 10,000; 16,000 → 14,000). If the cell is still outside, it is infeasible and is not run.

- **RL:** 5 seeds per cell, 3000 episodes; base seeds 30042, 31042, 32042, 33042 (blocks +201..+205). **Primary scheme:** the 5-seed mean. The ensemble is secondary. Bandits (global, delay class) are trained on the same episodes as in v17.
- **Evaluation:** 300 traces per cell. Trace seeds 700001+, 720001+, 740001+, 760001+; CRN at +10000. **Calibration traces:** 200 per cell, seeds 900001+1000·k, CRN 910001+1000·k (k = cell index 0–3). The code asserts that all ranges are disjoint from v9–v17, from G6 (600001–600500) and from A6 (800001–800100).
- **Per-cell recalibration (new at Checkpoint 5):** **every comparator is re-calibrated under that cell's own load and deadline**, with the G6 method (`G6_calibration_budget_prereg.md` §2.2–2.3): Fixed, FixedPU (separable grid + joint refinement), Context (exhaustive, 343 tables), OLLA-tuned (30 settings), and the **combined comparator** (36 cells, 4 starts, coordinate ascent to convergence, sanity check, hash before evaluation). Two scale changes are pre-registered, both because each cell has 200 rather than 500 calibration traces: the sparse-cell threshold is **N = 80** decisions (= 200 × 200/500) and the calibration objective is the mean on-time ratio over the 200 traces. Calibration-set and evaluation-set values are reported side by side for every table.
- **Base rule for the residual:** auto-selected as in v17 (the better of Fixed and FixedPU on 20 calibration traces). **Each cell records which base was chosen and whether it is a class oracle** (FixedPU) or not (Fixed), in `base_rule_by_cell.csv` and in the cell table of the paper.

## 3. Decision rules
- **Per cell:** family of **10 comparators** (the nine of v17 with their re-calibrated versions, plus the combined comparator), Holm over 10 (`common_rules.md` R1). Claim A, Claim B and JP (beats the combined comparator) are reported per cell. **A cell is a WIN if the primary scheme beats all 10.** The fairness guard is applied to each cell.
- **Seed-level rule** (`common_rules.md` R2): per cell, the hierarchical seed × trace 95 % CI of the margin vs the best comparator. With 5 seeds it is indicative; a WIN whose lower bound is ≤ 0 is marked "not robust to seed resampling".
- **Cells tested** = the feasible cells that were run (the author may run a subset, `G10_CELLS`). All wording below refers to the tested cells and says how many there were.

## 4. Pre-registered wording

| Outcome (tested cells) | Paper statement |
|---|---|
| **All tested cells WIN** | "The gain was robust across the tested load and deadline range: in all k tested cells residual A2C beat every comparator, including rules re-calibrated for that cell (margins +a % to +b % vs the best rule)." |
| **Mixed** (1 to k−1 cells WIN) | "The gain is operating-point dependent: residual A2C beat every comparator in cells [list] but not in cells [list] (per-cell table)." Also in the abstract's scope sentence |
| **No tested cell WINs** (the M1 operating point only) | A **stated limitation**: "The result was observed at the M1 operating point only; in k neighbouring cells it was not reproduced (per-cell table)." Also in the abstract's scope sentence |

## 5. Compute (basis `compute_basis.md`; per cell; upper-bound rates)

**Answer to the question "is 3.7 h plausible with per-cell calibration?": no.** The earlier 3.7 h covered RL training, evaluation and only ≈ 5 min of calibration per cell. The per-cell recalibration of every comparator, including the combined table, dominates:

| Step (per cell) | Evaluations | Wall time |
|---|---|---|
| RL training: 5 seeds × 3000 episodes × 0.14 s | — | 0.6 h |
| Evaluation: ≈ 8,700 runs (300 traces × 29 scheme runs: 8 deterministic, 5 A2C, 5 best-on-val, 1 ensemble, 10 bandit) × 0.095 s | 8,700 | 0.2 h |
| Single-cue recalibration (Fixed + FixedPU grid 1,800; FixedPU joint ≤ 28,800; Context 68,600; OLLA 6,000) | ≈ 105,200 | 2.8 h |
| Combined comparator: one sweep ≤ 36 × 6 × 200 = 43,200 | min 8 sweeps / expected 12 / cap 24 | 9.1 h / 13.7 h / 27.3 h |
| Feasibility, counting, REPRO | ≈ 2,000 | 0.1 h |
| **Per cell** | | **≈ 12.8 h min, ≈ 17.4 h expected, ≈ 31 h cap** |
| **Four cells** | | **≈ 51 h min, ≈ 70 h expected, ≈ 124 h cap** |
| Two cells (author's choice) | | ≈ 26 h min, ≈ 35 h expected |

Sweeps skip cells under the 80-decision threshold, and the preflight measures the true deterministic-rule rate (expected to be below the 0.095 s basis). The runner prints the projection and pauses if the measured rate exceeds 1.5× the basis (`common_rules.md` R5). `n_workers = 2`.

## 6. Multiplicity
Adds **up to 4 cases** (4 primary-scheme rows + 4 ensemble rows). Project total after all runs: up to 74 cases. The grid is a robustness check and cannot produce a new headline claim.

## 7. Stage specification for the runner (`Optimized/v17x/`, stage `g10`)
Implemented as `stage_g10(ctx)`; per cell, in order G1, G2, G3, G4: units `feas`, `calib_single_*`, `calib_comb_start_k_sweep_s` (checkpoint after each sweep), `train_seed_K` (5, checkpoint every 250 episodes), `bandit_*`, `eval`. Outputs: `fill_summary_v17c.txt`, `base_rule_by_cell.csv`, `table_cells.csv` (calibration vs evaluation per table), `ctxj_cells_<cell>.csv`. `G10_CELLS` (default all four) selects a subset.

## 8. Results
*(empty until run)*
