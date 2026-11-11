# Pre-registration G10: operating-point check at two neighbouring cells, with per-cell recalibration (v17c-grid)

**STATUS: FROZEN (Checkpoint 5, 4 Nov 2026), amended at Checkpoint 5b (4 Nov 2026) and by Amendment 2 (5 Nov 2026), both before any G10 run started** (`AMENDMENTS.md`: amendment 1: two cells instead of four, profile decided, wording rows for two cells; **amendment 2: the combined slack × class × HARQ-state comparator is not run in G10; it is tested at the M1 point only, in G6**). §§1–6 do not change after the freeze-v3 commit recorded in `paper/STATUS.md`; results go in §8. Common rules: `common_rules.md`. **Class: essential.** Uses the frozen v17 code; only case structs and calibration drivers are added.

## 1. Question
The only earlier load/deadline grid (v14 Y1–Y4) predates the v17 PF fix and ran at RTT 0; its verdict was "operating-point specific". Does the M1 result (RTT 8, 8 processes, 12 kbit, 10-TTI budget) carry over to **two neighbouring operating points** under the v17 configuration, **against single-cue comparators (Fixed, FixedPU, Context table, tuned-target OLLA) that are re-calibrated for each cell**? The combined slack × class × HARQ-state comparator is **not** part of G10 (Amendment 2); its test belongs to G6 at the M1 point.

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
**Every single-cue comparator is re-calibrated under that cell's own load and deadline with the G6 method** (`G6_calibration_budget_prereg.md` §2.2, search on 200 calibration traces per cell): Fixed (exhaustive over the 9 offsets), FixedPU (separable grid plus joint refinement, at most 3 sweeps), Context table (exhaustive, 343 tables) and OLLA-tuned (30 settings). Calibration-set and evaluation-set values are reported side by side for every table. The search of every one of these four rules is **exhaustive or identical to G6**, so this section has no profile choice to make (the `lite` profile of G6 concerns only the combined table and is not used anywhere in G10).

**Amendment 2: no combined comparator in G10.** The combined comparator of G6 §2.3 (36 cells, coordinate ascent from four starts, re-run per cell) is **not calibrated or evaluated in any G10 cell**. Reason: re-calibrating it per cell dominates the compute of this stage (the corrected preflight projects about 100 h extra for two cells, `AMENDMENTS.md`), and a lighter variant of the search would give a weaker comparator than the one used in M1, so a win against it would be weaker evidence than the M1 result. The decision was taken before any G6 result existed and does not depend on one. **Consequence for what the paper may claim:** G10 can support statements about the OLLA family and the single-cue calibrated rules at the two neighbouring points. The statements "beats a rule that combines slack, class and HARQ-process state" and "same-information" are tested **at the M1 operating point only** (G6) and are never extended to other cells. Whether a combined rule closes the gap at the other cells is not tested and is listed as future work, decided now (it will not be added on the basis of what G2 and G3 show).

**One budget difference from G6, stated plainly.** Each G10 cell has **200** calibration traces, where G6 has 500. This is a compute-driven reduction of the calibration set size, applied to **all** comparators in the cell alike; the calibration objective is the mean on-time ratio over the 200 traces. The paper states that the G10 comparators were calibrated on 200 traces per cell, against 500 in G6 and 10–20 in v17.

**Base rule for the residual:** auto-selected as in v17 (the better of Fixed and FixedPU on 20 calibration traces). **Each cell records which base was chosen and whether it is a class oracle** (FixedPU) or not (Fixed), in `base_rule_by_cell.csv` and in the cell table of the paper.

## 3. Decision rules
- **Per cell:** family of **9 comparators** (the nine of v17, with Fixed, FixedPU, Context and OLLA re-calibrated for the cell), Holm over 9 (`common_rules.md` R1). Claim A and Claim B are reported per cell. **A cell is a WIN if the primary scheme beats all 9** (the v17 definition; there is no JP in G10). The fairness guard is applied to each cell.
- **Seed-level rule** (`common_rules.md` R2): per cell, the hierarchical seed × trace 95 % CI of the margin vs the best of the nine comparators. With 5 seeds it is indicative; a WIN whose lower bound is ≤ 0 is marked "not robust to seed resampling".
- **Cells tested** = the feasible cells of the pair that were run (`G10_CELLS`, default `G2_hi_d10,G3_lo_d18`). All wording below says how many cells were tested.

## 4. Pre-registered wording (two cells tested; the paper never says "robust across the load and deadline range")

| Outcome | Paper statement |
|---|---|
| **Both cells WIN** (2 of 2) | "The gain held at both tested neighbouring operating points (a higher load at the M1 deadline, and a lower load with a looser deadline): residual A2C beat the OLLA family and the single-cue calibrated rules re-calibrated for each cell (margins +a % and +b % vs the best rule). The combined slack, class and HARQ-state rule was tested at the M1 point only. Two further grid corners were not tested." |
| **One cell WINs** (1 of 2) | "The gain is operating-point dependent: residual A2C beat the OLLA family and the single-cue rules at [cell] but not at [cell] (per-cell table). The combined rule was tested at the M1 point only. Two further grid corners were not tested." Also in the abstract's scope sentence |
| **No tested cell WINs** | A **stated limitation**: "The result was observed at the M1 operating point only; at the two tested neighbouring points it was not reproduced (per-cell table). Two further grid corners were not tested." Also in the abstract's scope sentence |
| **Only one cell feasible** | The row above for 1 cell: "…at the one testable neighbouring point…", and the text says the other chosen cell was infeasible under the feasibility rule |
| **G10 not run** | "The result is established at one operating point (12 kbit packets, 10-TTI budget); other loads and deadlines were not tested under the corrected scheduler." |

## 5. Compute (basis `compute_basis.md`; per cell; upper-bound rates; Amendment 2 removes the combined-comparator row)

| Step (per cell) | Evaluations | Wall time (basis) |
|---|---|---|
| RL training: 5 seeds × 3000 episodes × 0.14 s | — | 0.6 h |
| Evaluation: ≈ 8,400 runs (300 traces × 28 scheme runs: 7 deterministic, 5 A2C, 5 best-on-val, 1 ensemble, 10 bandit) × 0.095 s | 8,400 | 0.2 h |
| Single-cue recalibration (Fixed + FixedPU grid 1,800; FixedPU joint ≤ 28,800; Context 68,600; OLLA 6,000) | ≈ 105,200 | 2.8 h |
| Feasibility, counting, REPRO | ≈ 2,000 | 0.1 h |
| **Per cell** | | **≈ 3.7 h** |
| **Two cells (this pre-registration)** | | **≈ 7.4 h** |

(Before Amendment 2 the table also held the combined comparator, ≈ 9.1 h min / 13.7 h expected / 27.3 h cap per cell, giving ≈ 26 / 35 / 62 h for two cells.) The runner prints the projection from the measured rate (`PREFLIGHT_g10.txt`) and pauses if it exceeds 1.5× the basis (`common_rules.md` R5). `n_workers = 2`.

## 6. Multiplicity
Adds **2 cases** (G2, G3) with 2 rows each (primary-scheme row and ensemble row). The check is a robustness check and cannot produce a new headline claim.

## 7. Stage specification for the runner (`Optimized/v17x/`, stage `g10`)
Implemented as `stage_g10(ctx)`; per cell, in the order G2, G3: units `feas`, `calib_single_*`, `train_seed_K` (5, checkpoint every 250 episodes), `bandit_*`, `eval`. Outputs: `fill_summary_v17c.txt`, `base_rule_by_cell.csv`, `table_cells.csv` (calibration vs evaluation per table). `stage_g10_report(ctx)` writes a descriptive per-cell report (calibration information only) after each cell's calibration. The stage contains **no** combined-comparator code path (Amendment 2). `G10_CELLS` defaults to the two tested cells; the future-work cells are not offered by the stage.

## 8. Results
*(empty until run)*
