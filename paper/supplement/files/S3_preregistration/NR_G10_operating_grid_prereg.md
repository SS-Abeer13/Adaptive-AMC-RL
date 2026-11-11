# Pre-registration NR-G10: operating-point check with the non-oracle residual recipe (v17x-nr-grid)

**STATUS: FROZEN (Amendment 5, 10 Nov 2026, before any NR-G10 run started)** (`AMENDMENTS.md`). §§1–6 do not change after the freeze-v6 commit recorded in `paper/STATUS.md`; results go in §8. Common rules: `common_rules.md`. **Class: confirmatory robustness check.** Uses the frozen v17x code; only stage and case configurations are added.

## 1. Question
Stage G10 evaluated whether the M1 recipe (which auto-selected the class-oracle base `FixedPU (Oracle)` on 20 calibration traces) generalised to two neighbouring operating points (`G2_hi_d10` and `G3_lo_d18`). In G10, neither cell achieved a WIN (Claim A passed in both cells, but Claim B failed against Context table in G2, and against FixedPU and Context table in G3). However, NR1 and NR2 demonstrated that the non-oracle residual recipe (`Fixed` base with calibrated offset) is superior to the oracle base, beating all comparators including the combined table robustly across seeds (+3.35 % over Context-joint-500, hierarchical 95 % CI [+2.22, +4.40] %, 9/10 seeds). Does the **recommended non-oracle residual recipe** (`Fixed` base with the cell's calibrated static offset) generalise to the two neighbouring operating points, against the frozen single-cue comparators re-calibrated for each cell?

## 2. Cells & Recipe

Both cells use the non-oracle residual recipe: RTT 8, 8 processes, `pf_avg = 'scheduled'`, drain, useful bits, and residual A2C with 3000 episodes on a **forced `Fixed` base rule** (no class oracle) using the per-cell calibrated static offsets frozen from G10:

| Cell | Packet bits | Deadline (TTI) | Base Rule Offset | Status |
|---|---|---|---|---|
| **G2_hi_d10** | 16,000 | 10 | `Fixed -2` | **tested**: higher load at M1's deadline |
| **G3_lo_d18** | 8,000 | 18 | `Fixed -3` | **tested**: lower load with looser deadline |
| G1_lo_d10 | 8,000 | 10 | — | future work, decided at Checkpoint 5b |
| G4_hi_d18 | 16,000 | 18 | — | future work, decided at Checkpoint 5b |

- **RL Training:** 5 seeds per cell, 3000 episodes.
  - Base seeds: `33042` (G2) and `34042` (G3), blocks +201..+205. Disjoint from all prior rounds (v9–v17, G10 seeds 31042/32042, NR2 seeds 25042).
  - Primary scheme: the 5-seed mean. Secondary scheme: ensemble.
- **Evaluation:** 300 traces per cell.
  - Evaluation traces: seeds 720001+ (G2) and 740001+ (G3); CRN at +10000 (730001+ and 750001+). Identical trace sets to G10.
- **Comparator Tables:** Frozen from G10 (`Optimized/v17x/Dataset/ckpt/g10/calib_single_*.mat`, hash-checked). No re-calibration is performed. Single-cue family of 9 comparators per cell (Baseline, OLLA, OLLA tuned, Multi-OLLA, Fixed, FixedPU, Context table, Bandit global, Bandit delay class).

## 3. Decision Rules
- **Per cell:** family of **9 single-cue comparators**, Holm over 9 (`common_rules.md` R1). Claim A and Claim B are reported per cell. A cell is a **WIN** if the primary scheme beats all 9 comparators.
- **Seed-level rule** (`common_rules.md` R2): per cell, the hierarchical seed $\times$ trace 95 % CI of the margin vs the best of the nine comparators. With 5 seeds it is indicative; a WIN whose lower bound is $\le 0$ is marked "not robust to seed resampling".
- **Cells tested:** 2 (`G2_hi_d10`, `G3_lo_d18`).

## 4. Pre-registered Wording

| Outcome | Paper statement |
|---|---|
| **Both cells WIN** (2 of 2) | "With the non-oracle residual recipe, the gain held at both tested neighbouring operating points (a higher load at the M1 deadline, and a lower load with a looser deadline): residual A2C on a calibrated static offset beat the OLLA family and the single-cue calibrated rules re-calibrated for each cell (margins +a % and +b % vs the best rule). Two further grid corners were not tested." |
| **One cell WINs** (1 of 2) | "With the non-oracle residual recipe, the gain is operating-point dependent: residual A2C on a calibrated static offset beat the OLLA family and the single-cue rules at [cell] but not at [cell] (per-cell table). Two further grid corners were not tested." |
| **No tested cell WINs** (0 of 2) | "With the non-oracle residual recipe, the result was observed at the M1 operating point only; at the two tested neighbouring points it was not reproduced (per-cell table). Two further grid corners were not tested." |
| **NR-G10 not run** | "The non-oracle residual recipe was confirmed at the M1 operating point only; neighbouring operating points were not tested under this recipe." |

## 5. Compute Basis
Per cell (no calibration pass needed; comparators are frozen from G10):
- RL training: 5 seeds $\times$ 3000 episodes $\times$ 0.14 s $\approx$ 0.58 h.
- Evaluation: 300 traces $\times$ 23 scheme runs (7 deterministic, 10 bandit, 6 RL) $\times$ 0.095 s $\approx$ 0.18 h.
- **Per cell:** $\approx$ 0.76 h (sequential) / $\approx$ 0.4 h (`n_workers = 2`).
- **Two cells:** $\approx$ 0.8 h wall time (`n_workers = 2`, basis upper bound $\approx$ 1.5 h).

## 6. Multiplicity
Adds **2 cases** (`G2_hi_d10_NR`, `G3_lo_d18_NR`) with 2 rows each (primary 5-seed mean and ensemble).
Total cases across the project: 74 $\to$ **76**.
Total scheme-evaluation rows: 122 $\to$ **126**.

## 7. Stage Specification for the Runner (`Optimized/v17x/`, stage `nr_g10`)
Implemented as `stage_nr_g10(ctx)`; per cell:
1. Loads frozen comparator calibration from `ckpt/g10/calib_single_<cell>.mat`.
2. Enforces non-oracle base rule: `env.base_rule_kind = 'fixed'`, `env.fixed_offset = -2` (G2) or `-3` (G3).
3. Trains 5 seeds (`train_seed_<cell>_1..5`).
4. Evaluates on 300 traces against the 9 comparators.
5. Outputs: `Dataset/table_cells_nr.csv`, `Dataset/REPORT_nr_g10.txt`.

## 8. Results
*(empty until run)*
