# Pre-registration G10: operating-point check at two neighbouring cells, with per-cell recalibration (v17c-grid)

**STATUS: FROZEN (Checkpoint 5, 4 Nov 2026), amended once at Checkpoint 5b (4 Nov 2026) before any run started** (`AMENDMENTS.md`, amendment 1: two cells instead of four; profile decided; wording rows for two cells). §§1–6 do not change after the freeze-v2 commit recorded in `paper/STATUS.md`; results go in §8. Common rules: `common_rules.md`. **Class: essential.** Uses the frozen v17 code; only case structs and calibration drivers are added.

## 1. Question
The only earlier load/deadline grid (v14 Y1–Y4) predates the v17 PF fix and ran at RTT 0; its verdict was "operating-point specific". Does the M1 result (RTT 8, 8 processes, 12 kbit, 10-TTI budget) carry over to **two neighbouring operating points** under the v17 configuration, **against comparators that are re-calibrated for each cell**?

## 2. Cells

All cells use M1's configuration (RTT 8, 8 processes, `pf_avg = 'scheduled'`, drain, useful bits) and residual A2C with 3000 episodes.

| Cell | Packet bits | Deadline (TTI) | Status |
|---|---|---|---|
| **G2_hi_d10** | 16,000 | 10 | **tested**: higher load at M1's deadline (the tightest budget that lets a retransmission arrive at RTT 8) |
| **G3_lo_d18** | 8,000 | 18 | **tested**: lower load with a looser budget that allows two HARQ rounds |
| G1_lo_d10 | 8,000 | 10 | **future work, decided now** |
| G4_hi_d18 | 16,000 | 18 | **future work, decided now** |

**Why this pair (one line).** G2 and G3 are opposite corners of the grid, so a win at both cannot be credited to a single axis and a loss at either locates the failing direction; G3_lo_d18 also sits where the older v14 grid (RTT 0, pre-v17 scheduler) found calibrated rules strongest (loose deadlines), which makes it the hardest test.

**The other two cells are future work, decided now.** They will **not** be added on the basis of what cells G2 and G3 show, and the paper lists them as untested. If a chosen cell is infeasible (below) it is **not replaced** by a future-work cell; the verdict is then computed on the remaining cell and the text says one cell was untestable.

**Why 10 and 18, not v14's 6 and 14.** With RTT 8 a 6-TTI budget lets no retransmission arrive in time. A budget of 18 (≤ the 20-TTI packet period) allows two feedback rounds.

**Feasibility rule (v14 C2, unchanged):** Fixed's on-time ratio on 20 calibration traces must lie in [0.50, 0.97]. Otherwise move the packet size one step towards 12,000 (8,000 → 10,000; 16,000 → 14,000). If the cell is still outside, it is infeasible and is not run.

- **RL:** 5 seeds per cell, 3000 episodes; base seeds 31042 (G2) and 32042 (G3), blocks +201..+205. **Primary scheme:** the 5-seed mean. The ensemble is secondary. Bandits (global, delay class) are trained on the same episodes as in v17.
- **Evaluation:** 300 traces per cell. Trace seeds 720001+ (G2) and 740001+ (G3); CRN at +10000. **Calibration traces:** 200 per cell, seeds 901001–901200 (G2) and 902001–902200 (G3); CRN 911001+ and 912001+ (the cell index k of the full four-cell design is kept, so adding a future cell would not change these ranges). The code asserts that all ranges are disjoint from v9–v17, from G6 (600001–600500) and from A6 (800001–800100).

### 2.1 Per-cell recalibration and the profile decision
**Every comparator is re-calibrated under that cell's own load and deadline with the G6 method** (`G6_calibration_budget_prereg.md` §2.2–2.3, **full profile**): Fixed, FixedPU (separable grid plus joint refinement), Context (exhaustive, 343 tables), OLLA-tuned (30 settings), and the **combined comparator** (36 cells, 4 starts, coordinate ascent to convergence, the composite table as defined in G6 §2.3, sanity check, hash before evaluation). Calibration-set and evaluation-set values are reported side by side for every table.

**Why G10 uses `full` and not `lite`.** G6's `lite` profile would change (i) the number of calibration traces used per candidate during the restart phase (100 instead of the full set) and (ii) how many of the four starts are ever evaluated on the full budget (two). Because it lowers the number of calibration traces per candidate, it is **not used** (decided at Checkpoint 5b: a profile that changes only restarts or caps could be used, one that lowers calibration traces could not). The restart count (4 starts), the cap (6 sweeps), the grid of offsets and the 36 cells are identical to G6 `full`.

**One budget difference from G6, stated plainly.** Each G10 cell has **200** calibration traces, where G6 has 500. This is a compute-driven reduction of the calibration set size, applied to **all** comparators in the cell alike. Two scale changes follow from it: the sparse-cell threshold is **N = 80** decisions (= 200 × 200/500) and the calibration objective is the mean on-time ratio over the 200 traces. The paper states that the G10 comparators were calibrated on 200 traces per cell, against 500 in G6 and 10–20 in v17.

**Base rule for the residual:** auto-selected as in v17 (the better of Fixed and FixedPU on 20 calibration traces). **Each cell records which base was chosen and whether it is a class oracle** (FixedPU) or not (Fixed), in `base_rule_by_cell.csv` and in the cell table of the paper.

## 3. Decision rules
- **Per cell:** family of **10 comparators** (the nine of v17 with their re-calibrated versions, plus the combined comparator), Holm over 10 (`common_rules.md` R1). Claim A, Claim B and JP (beats the combined comparator) are reported per cell. **A cell is a WIN if the primary scheme beats all 10.** The fairness guard is applied to each cell.
- **Seed-level rule** (`common_rules.md` R2): per cell, the hierarchical seed × trace 95 % CI of the margin vs the best comparator. With 5 seeds it is indicative; a WIN whose lower bound is ≤ 0 is marked "not robust to seed resampling".
- **Cells tested** = the feasible cells of the pair that were run (`G10_CELLS`, default `G2_hi_d10,G3_lo_d18`). All wording below says how many cells were tested.

## 4. Pre-registered wording (two cells tested; the paper never says "robust across the load and deadline range")

| Outcome | Paper statement |
|---|---|
| **Both cells WIN** (2 of 2) | "The gain held at both tested neighbouring operating points (a higher load at the M1 deadline, and a lower load with a looser deadline): residual A2C beat every comparator, including rules re-calibrated for that cell (margins +a % and +b % vs the best rule). Two further grid corners were not tested." |
| **One cell WINs** (1 of 2) | "The gain is operating-point dependent: residual A2C beat every comparator at [cell] but not at [cell] (per-cell table). Two further grid corners were not tested." Also in the abstract's scope sentence |
| **No tested cell WINs** | A **stated limitation**: "The result was observed at the M1 operating point only; at the two tested neighbouring points it was not reproduced (per-cell table). Two further grid corners were not tested." Also in the abstract's scope sentence |
| **Only one cell feasible** | The row above for 1 cell: "…at the one testable neighbouring point…", and the text says the other chosen cell was infeasible under the feasibility rule |
| **G10 not run** | "The result is established at one operating point (12 kbit packets, 10-TTI budget); other loads and deadlines were not tested under the corrected scheduler." |

## 5. Compute (basis `compute_basis.md`; per cell; upper-bound rates)

| Step (per cell) | Evaluations | Wall time |
|---|---|---|
| RL training: 5 seeds × 3000 episodes × 0.14 s | — | 0.6 h |
| Evaluation: ≈ 8,700 runs (300 traces × 29 scheme runs: 8 deterministic, 5 A2C, 5 best-on-val, 1 ensemble, 10 bandit) × 0.095 s | 8,700 | 0.2 h |
| Single-cue recalibration (Fixed + FixedPU grid 1,800; FixedPU joint ≤ 28,800; Context 68,600; OLLA 6,000) | ≈ 105,200 | 2.8 h |
| Combined comparator: one sweep ≤ 36 × 6 × 200 = 43,200 | min 8 sweeps / expected 12 / cap 24 | 9.1 h / 13.7 h / 27.3 h |
| Feasibility, counting, REPRO | ≈ 2,000 | 0.1 h |
| **Per cell** | | **≈ 12.8 h min, ≈ 17.4 h expected, ≈ 31 h cap** |
| **Two cells (this pre-registration)** | | **≈ 26 h min, ≈ 35 h expected, ≈ 62 h cap** |

Sweeps skip cells under the 80-decision threshold, and the preflight measures the true deterministic-rule rate (expected to be below the 0.095 s basis). The runner prints the projection and pauses if the measured rate exceeds 1.5× the basis (`common_rules.md` R5). `n_workers = 2`.

## 6. Multiplicity
Adds **2 cases** (G2, G3) with 2 rows each (primary-scheme row and ensemble row). The check is a robustness check and cannot produce a new headline claim.

## 7. Stage specification for the runner (`Optimized/v17x/`, stage `g10`)
Implemented as `stage_g10(ctx)`; per cell, in the order G2, G3: units `feas`, `calib_single_*`, `calib_comb_start_k_sweep_s` (checkpoint after each sweep), `train_seed_K` (5, checkpoint every 250 episodes), `bandit_*`, `eval`. Outputs: `fill_summary_v17c.txt`, `base_rule_by_cell.csv`, `table_cells.csv` (calibration vs evaluation per table), `ctxj_cells_<cell>.csv`, `composite_table_<cell>.csv`. `stage_g10_report(ctx)` writes a descriptive per-cell report (calibration information only) after each cell's calibration. `G10_CELLS` defaults to the two tested cells; the future-work cells are not offered by the stage.

## 8. Results
*(empty until run)*
