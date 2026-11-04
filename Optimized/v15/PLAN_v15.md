# v15 — confirmation and robustness of the deadline result: implementation plan for Claude Code

Written 26 Oct 2026, after the v13 review (`claude/amc_v13_results_review_2026-10-26.md`).
Work in `D:\Adaptive AMC A2C+QL\Optimized`. Stages A → B → C, in order, with a user approval
stop before any campaign.

---

## 0. Why v15 (read first)

| Round | Deadline result vs the OLLA family | vs the calibrated fixed offset (PF) |
|---|---|---|
| v10 E4c | +1.9 % | +0.35 % (traces overlapped with the exploratory run) |
| v12 R1_pf (pre-registered primary) | +0.9–1.0 % | **−0.47 %** (loss) |
| v13 X1_pf (pre-registered primary, ensemble) | +1.3–1.6 % | +0.04 % (n.s.) |
| v13 X1_pf, per-seed mean (secondary) | — | +0.26 % (Holm 8e-4) |
| v13 X2_pf_shaped (secondary) | +1.4–1.6 % | +0.25 % (Holm 4e-4); beats all 9; 10/10 seeds |

So the gain over the OLLA family is replicated. The gain over calibrated rules was seen only in
**secondary** analyses, and three questions remain open:
1. Does the X2 recipe (residual on the calibrated rule + shaped on-time reward) win when it is
   the **pre-registered primary**, on fresh data?
2. Is it the **shaping** that helps? X1 and X2 differed in reward, seeds and traces at once,
   so the v13 data cannot answer this.
3. Does the result hold **beyond the single operating point** (12 kbit packets, 10-TTI
   deadline)? Reviewers will look for a robustness section first.

Known v13 facts used here:
- The seed **ensemble was the weakest aggregator in all three cases**: averaging the softmax
  pulls the policy back to δ = 0.
- Per-seed mean and best-on-validation were both better than the ensemble.
- v15 therefore declares the **per-seed mean** as the primary scheme. This choice is informed
  by v13 and is stated as such; it is legitimate only because v15 uses fresh data.

Code base: `Optimized/v13/` (it has the residual action, ensemble, shaping, EDF, headroom tools
and `crn_seed_base`). v15 = the v13 core files copied and renamed `_v13` → `_v15`, as before.

---

## Stage A — Correct README_v13 (no runs)

Edit `Optimized/v13/README_v13.md`. These are accuracy fixes only; append a "Corrections
(26 Oct)" note listing each change.
1. **§1 v12 numbers.**
   - R1_pf vs OLLA / tuned / Multi-OLLA: +0.96 / +0.93 / +1.03 %.
   - R2_edf: +1.83 / +1.83 / +1.69 %.
   - In R2_edf A2C **beat** Fixed (+0.28 %, Holm 1.8e-4) and **tied** FixedPU. Replace
     "tie after Holm adjustment".
   - Source: `Optimized/v12/Dataset/fill_summary_v12.txt`.
2. **§7.2 X1_pf.**
   - Replace the "Pre-Registered Paper Statement" with the actual §6 wording for the outcome
     "Claim B fails".
   - Keep the per-seed result as a clearly labelled **secondary (not pre-registered)**
     observation.
3. **§7.2 X2.**
   - Remove "CLEAN SWEEP WIN", "Proven", and the "Core Finding" attribution to shaping.
   - State: secondary case; meets the WIN criterion; the attribution to shaping is untested
     (confounded with seeds and traces).
4. **Add a short §7.3 "Aggregators":**
   - ensemble < per-seed mean < best-on-val in all three cases (numbers from the summary);
   - under EDF the ensemble equals Fixed exactly (δ never used).

---

## Stage B — v15 code (small) and tests

### B1. Copy v13 → v15
Core functions only, renamed (same procedure as v12/v13). Do not copy `fill_*`, `run_*`,
`*_setup`, `README`, `PLAN`, `headroom_v13`, `test_*` (port the tests separately as
`*_v15`).

### B2. Changes
1. **Primary-scheme switch for the analyser.**
   - `analyze_v15_replication(matFile, tag, fid, si, schemeName)`, with `schemeName` defaulting
     to `'Deep A2C v15'` (the per-seed mean scheme).
   - Write `REPL` lines for **all three** aggregators: per-seed (primary), ensemble and
     best-on-val (secondary). Each line carries `scheme=<name>`.
   - Decision rules are unchanged (Holm over 9 non-RL comparators, plus the 90 % CI lower
     bound > 0; Claim A, Claim B, WIN).
2. **Paired shaping test.**
   - New script `shaping_pair_v15.m`.
   - Input: two results files trained with **identical** `base_seed`, `trace_seed_base` and
     `crn_seed_base` (`Y0_base`, `Y0_noshape`).
   - Compute the per-trace difference of the primary scheme (shaped − unshaped): mean, 90 % CI
     and Wilcoxon p.
   - Also compute the per-seed paired difference (seed s vs seed s, same training seed).
   - Output: `SHAPE|...` lines.
3. **Feasibility check for the grid** (`feasibility_v15.m`).
   - For each grid cell, on **calibration traces only** (60000+): calibrate and evaluate OLLA
     and Fixed, and compute the hindsight per-trace offset bound and the genie bound (reuse
     the `headroom_v13` functions).
   - Output: `FEAS|cell|olla=..|fixed=..|hindsight=..|genie=..`.
   - Apply the load-substitution rule (C2). Never use evaluation traces here.

### B3. Tests (all must pass; log the results in README_v15 §5)
1. `test_equivalence_v15`: bit-exact with v13 under defaults (same scope as before).
2. **Pairing check.** With 2 seeds, 6 traces and 3 episodes, `Y0_base` and `Y0_noshape` must
   produce identical traces and CRN draws, and identical **initial** actor weights. The
   learning curves differ only once training starts.
3. The analyser on `results_v13_X2_pf_shaped.mat` reproduces the v13 `REPL` line for the
   ensemble scheme.
4. Preflight (2 episodes, 2 seeds, 6 traces) of all 6 cases; `REPL`, `SHAPE` and `FEAS`
   lines parse.

---

## Stage C — Pre-registration and campaign

### C1. Write `Optimized/v15/README_v15.md` from this section before running anything.
After user approval, §1–5 never change; results go in §6.

### C2. Cases

All cases use the v13 X2 recipe:
- `action_mode = 'resid'`, with the base rule = the better of {Fixed, FixedPU} on calibration
  traces;
- δ ∈ {−1, 0, 1}, `resid_pen = 0.02`, logit bias +3;
- `reward_kind = 'ontime_shaped'`, `shape_c = 0.5`;
- 800 episodes, the `base.a2c` hyper-parameters, PF scheduler;
- validation selection on (`val_every = 50`, `n_val = 10`, validation traces 80000+).

Only the listed fields differ.

| Tag | Role | pkt_bits | deadline | Reward | Seeds (base_seed) | Eval traces | CRN |
|---|---|---|---|---|---|---|---|
| `Y0_base` | **primary** | 12000 | 10 | ontime_shaped | 10 (6042) | 500: 200001–200500 | 210001+ |
| `Y0_noshape` | secondary (shaping test) | 12000 | 10 | **ontime** | 10 (**6042**, same) | **same as Y0_base** | **same** |
| `Y1_lo_tight` | robustness | 8000 | 6 | ontime_shaped | 5 (7042) | 300: 220001–220300 | 230001+ |
| `Y2_lo_loose` | robustness | 8000 | 14 | ontime_shaped | 5 (8042) | 300: 240001–240300 | 250001+ |
| `Y3_hi_tight` | robustness | 16000 | 6 | ontime_shaped | 5 (9042) | 300: 260001–260300 | 270001+ |
| `Y4_hi_loose` | robustness | 16000 | 14 | ontime_shaped | 5 (10042) | 300: 280001–280300 | 290001+ |

**Seed ranges** are disjoint from everything used in v9–v13 and from the RNG offsets used
internally:
- calibration 60000–62xxx;
- validation 80000+;
- the evaluation-policy RNG 77000 + 100·j + …, which stays below 200000 for j ≤ 500.

**Load substitution** (applied in Stage B3 / `feasibility_v15`, on calibration traces only):
- If Fixed's on-time ratio in a cell is outside [0.50, 0.97], replace that cell's `pkt_bits`
  with the next value towards 12000: 8000 → 10000, or 16000 → 14000.
- If it is still outside, report the cell as "infeasible" and do not run it.
- Record every substitution in README_v15 §5 **before** launch.

### C3. Primary scheme and comparators
- **Primary scheme:** `Deep A2C v15`, the per-seed mean, as declared in §0.
- **Secondary schemes:** ensemble, best-on-val.
- **Comparators:** the v13 set of 9: Baseline, OLLA, OLLA (tuned target), Multi-OLLA, Fixed,
  FixedPU (Oracle), Context table, Bandit (global), Bandit (delay class).

### C4. Decision rules (fixed now)
- **Primary (Y0_base, primary scheme):**
  - **Claim A**: beats OLLA, tuned OLLA and Multi-OLLA.
  - **Claim B**: beats Fixed, FixedPU and the context table.
  - **WIN**: beats all 9.
  - "Beats" means Holm over 9 < 0.05 and the 90 % CI lower bound > 0.
- **Shaping test (Y0_base vs Y0_noshape, primary scheme, paired):**
  - "shaping helps" if the mean per-trace difference has a 90 % CI lower bound > 0 and
    Wilcoxon p < 0.05;
  - "no evidence" if the CI contains 0;
  - "shaping hurts" if the CI upper bound < 0.
- **Robustness (Y1–Y4, primary scheme):**
  - Report Claim A / B / WIN per cell.
  - Summary rule: "**robust**" if Claim A passes in ≥ 3 of the feasible cells **and** the mean
    difference vs the best calibrated rule is ≥ 0 in ≥ 3 of the feasible cells. Otherwise
    "**operating-point specific**".
  - With fewer than 4 feasible cells, the threshold is "all feasible cells".

### C5. Wording table (fixed now)

| Result | Paper may say |
|---|---|
| Y0 WIN | "In a pre-registered confirmation on fresh data, residual A2C with a shaped on-time reward beat every comparator, including calibrated fixed-offset rules (+x %)." Report the case count and the history (v12 failure, v13 secondary). |
| Y0 Claim B fails, Claim A passes | "Gains over calibrated fixed-offset rules did not confirm; the gain over the OLLA family (+x %) is robust." |
| Y0 Claim A fails | "The deadline gain did not confirm." The paper becomes negative and methodological. |
| Shaping helps / no evidence / hurts | One sentence each, with the paired CI. |
| Robust / operating-point specific | One sentence plus the per-cell table, in the robustness section. |

### C6. Multiplicity
v15 adds 6 cases: 1 primary, 1 paired secondary, 4 robustness. That brings the project total to
about 26, and the total is reported with every claim.

### C7. Run
- `run_v15_headless.bat`, with auto-restart and per-seed checkpoints (as in v13).
- **Order:** `Y0_base` → `Y0_noshape` → `Y1` … `Y4`.
- **Estimated time:**
  - Y0_base and Y0_noshape: about 110 min each.
  - Each grid cell: about 55 min.
  - **Total: about 7.5 h**, so run it overnight. Keep the PC awake.

### C8. After the run
- Append §6 to README_v15:
  - the `REPL` lines (all aggregators), `SHAPE` lines and the per-cell table;
  - which row of C5 applies;
  - restarts and deviations.
- **No re-runs, re-tags or re-tuning.** Then hand off to the paper rebuild.

---

## Stage D (optional, after C) — paper-ready release

Prepare `release/` with:
- the v15 core code;
- `README_release.md` covering requirements (MATLAB R2023a and toolboxes), how to reproduce
  each table, and the seed ranges;
- the summary files, the pre-registration documents and a LICENSE placeholder.

The user decides whether and where to publish it (e.g. GitHub + Zenodo DOI) for the paper's
code-and-data availability statement.

---

## Prompt to give Claude Code
> Read `Optimized/v15/PLAN_v15.md`. Do Stage A (README_v13 corrections, with a corrections note).
> Then Stage B: create `Optimized/v15` from v13 (core files only, `_v13` → `_v15`), implement
> B2, and run all B3 tests and `feasibility_v15.m` headless with `matlab -batch`. Then write
> README_v15 §1–5 from Stage C, apply the load-substitution rule from the feasibility results,
> and stop to show me the tests, the feasibility table and README_v15 §1–5. Do not launch the
> campaign until I approve.
