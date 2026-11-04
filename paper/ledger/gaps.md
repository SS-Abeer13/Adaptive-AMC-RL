# Gaps: questions a reviewer will ask that the current evidence cannot fully answer

Input to Phase 5 (§7). Tag: **[A]** = can be answered by analysis of existing results (needs MATLAB on the author's PC if marked *mat*, or can be done here from text logs if marked *txt*) · **[R]** = needs new runs (pre-registration required) · **[W]** = writing only (acknowledge as a limitation).

## Mechanism and behaviour

- **G1 [A, mat] Which decisions does the policy actually change?** The action histograms count all users per TTI. The state table mixes retransmissions (no-ops) with new transmissions. A reviewer will want: share of δ ≠ 0 on *scheduled new transmissions*, by slack bin and by busy-process count, plus the conditional on-time gain. Without it, the "mechanism" paragraph cannot be written. *Minimal fix:* re-run `diag_action_by_state_v17.m` with `is_retx == 0`, add δ-by-CQI and δ-by-delay-class bins. M3: report share of δ ≠ 0 on effective decisions (expected ≈ 0, given identical goodput).
- **G2 [A, txt/mat] Is the RTT-8 gain explained by HARQ process occupancy or by slack?** The busy-process ≥3 bin has only 8,150 of 618,192 decisions. A per-bin attribution of the on-time difference vs FixedPU is needed to say *where* the +1.6 % comes from.

## Statistics

- **G3 [A, txt] Training-seed variance is not in the test.** The Wilcoxon is over 500 traces of the 10-seed mean. Need a seed-level analysis: per-seed margins with CI (from REPLSEED), sign test (9/10 → p ≈ 0.011 one-sided), and a two-level (seed × trace) bootstrap. Partly possible from text logs; a trace×seed bootstrap needs the .mat files.
- **G4 [W] Effect size vs practical significance.** +1.58 % relative on-time (≈ +0.95 pp absolute: 0.6126 vs 0.6031). We must state both relative and absolute, and argue relevance (deadline-sensitive traffic; gain comparable to the hindsight-adaptivity headroom of +3.4 %).
- **G5 [W] Selection over 17 versions.** The final recipe was chosen during the campaign. M1 is confirmatory for that recipe only. Multiplicity numbers are in `multiplicity.md`.

## Baseline fairness

- **G6 [W/A] Calibration budget asymmetry.** Fixed/FixedPU use 20 calibration traces, Context table and tuned-OLLA use 10, while A2C gets 3000 training episodes (×10 seeds). A reviewer may argue the Context table is under-calibrated. *Possible analysis [A, mat]:* re-calibrate the Context table on 200 traces and re-evaluate on the same 500 M1 traces (cheap, no RL training). Probably **essential**.
- **G7 [W] Bandit comparators are very weak in deadline cases** (41.8 % vs 60 % on-time in M1). They will look like straw men. We need to explain why (goodput-normalised reward, global arm) or drop them from the headline count. Also: in M1 only 7 of 9 comparators are distinct (OLLA = tuned OLLA, bandit global = delay class).
- **G8 [W] No learning-based LA baseline from the literature** (e.g. a contextual Thompson-sampling LA, or a DQN MCS selector). Expect: "why not compare with [published RL-LA method]?"
- **G9 [W] OLLA parameters.** Only one step size (0.5 dB down) and a target grid. Reviewer (a) will ask about OLLA tuned for HARQ RTT 8 (e.g. delayed-feedback-aware step), and about OLLA with per-HARQ-process handling.

## Generalisation and realism

- **G10 [R] v17 operating-point robustness.** The only load/deadline grid (v14) predates the v17 PF fix and was "operating-point specific". There is no v17-era evidence that M1 holds at other loads, deadlines or user counts.
- **G11 [W] Simulator realism.** Single cell, 10 users, 15-level CQI with a SINR→BLER abstraction (not NR LDPC / TS 38.214 MCS tables), one user per TTI (no frequency-domain scheduling), 150 scored TTIs per trace (0.15 s), no ns-3 / 5G Toolbox cross-check.
- **G12 [W/R] Trace length.** 150 scored TTIs is short compared with OLLA convergence times under RTT 8. A reviewer may say OLLA is disadvantaged by short horizons (no warm-up: `olla_warm_ttis = 0`). v9 had a steady-state point (`steady_match`), but nothing similar exists in v17.
- **G13 [W] PF definition dependence** (conflicts C4/C5). Rankings of Baseline vs OLLA flip between PF variants. Results before v17 used the delivered-throughput PF.

## Cost

- **G14 [A, mat or analytic] Inference complexity.** The actor is a 2-hidden-layer MLP (fc1, fc2). FLOPs per decision can be computed analytically once layer widths are read from `DeepA2C_Shared_v17.m`. Wall time per TTI needs MATLAB.
- **G15 [A, txt] Training cost.** 3000 episodes × 200 TTI × 10 seeds. Wall-clock compute ~160 min for M1 on a 16 GB PC (`STEP` lines). Learning curves: `LCURVE` lines hold 11-point decile summaries only, not a time series, so a learning-curve figure needs the .mat files.

## Reproducibility

- **G16 [W] Hard-coded Windows paths** (`D:\Adaptive AMC A2C+QL`) in `v17_setup.m` and the release. MATLAB-only, Deep Learning Toolbox required. Recommend a Zenodo DOI and a path-agnostic setup.
- **G17 [W] No independent re-implementation.** All results come from one codebase. The self-found bugs (mobility, PF timing, v11 GRU bug, v14 script signature) show the risk.
