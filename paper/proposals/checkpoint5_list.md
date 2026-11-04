# Checkpoint 5: consolidated evidence-gap list (Phase 5)

Compute basis: `compute_basis.md` (RTT 8, 2 workers: about 0.14 s per training episode and 0.095 s per 200-TTI evaluation; upper bounds). Every run has a 20-trace preflight and pauses if the measured rate exceeds 1.5× the basis. Each pre-registration's §§1–6 are frozen on approval.

## Summary (revised at Checkpoint 5: FROZEN texts)

All pre-registrations G6, W1, NR1, G10 and `common_rules.md` are **frozen**; the freeze commit and file hashes are in `paper/STATUS.md`. Run order (approved): **G1 → W1 → G6 → NR1 → G10 → A1/A3**. A2, A4 and A5 need no runs.

| ID | Item | Class | New runs? | Wall time (upper-bound basis; 2 workers) | Pre-registration |
|---|---|---|---|---|---|
| **G1** | Action re-cut on scheduled new transmissions (M1, M3) | essential | re-evaluation | 20–60 min | `paper/analysis/G1_SPEC.md` |
| **G3** | Seed-level statistics | essential | none | — | **done** (ledger G3a–G3i) |
| **W1** | Warm-up robustness (200 unscored TTIs, stored policies) | essential | re-evaluation | ≈ 1.2 h | `W1_warmup_prereg.md` |
| **G6** | Exhaustive re-calibration of Fixed / FixedPU / Context / OLLA on 500 traces + the combined comparator (coordinate ascent, ≥ 3 random restarts) | essential | calibration, no RL training | `g6a` ≈ 6.9 h; `g6b` ≈ 23 h min, **≈ 34 h expected**, ≤ 68 h cap; **total ≈ 41 h expected** (lite profile ≈ 25 h) | `G6_calibration_budget_prereg.md` |
| **NR1** | Residual on the non-oracle Fixed base at RTT 8 | recommended | training | ≈ 1.5 h | `NR1_nonoracle_residual_prereg.md` |
| **G10** | v17 load × deadline grid, **per-cell recalibration of all comparators incl. the combined one** | essential | training + calibration | **≈ 17 h per cell expected (≈ 13 h min), ≈ 70 h for four cells**; two cells ≈ 35 h | `G10_operating_grid_prereg.md` |
| A1 | Results by speed class (M1) | approved | re-evaluation | ≈ 20 min | below |
| A2 | On-time attribution by state (from the G1 log) | approved | none | minutes | after G1 |
| A3 | Inference wall time per TTI | approved | micro-benchmark | ≈ 5 min | below |
| A4 | Learning curves and entropy (HDF5) | approved | none | — | Phase 7 figure F5b |
| A5 | Path-agnostic release setup | approved | none | — | below |
| **A6** | PF-timing demonstration (pitfall figure F8) | recommended | re-evaluation | ≈ 3 min | `design/figure_table_plan.md` |
| F1, F2 | SALAD comparator; second simulator | future work | — | — | — |

**Total on the upper-bound basis:** ≈ 1 h (G1) + 1.2 h (W1) + 41 h (G6) + 1.5 h (NR1) + 70 h (G10) + 0.5 h ≈ **115 h (about 5 days)**. The two long items are G6's combined-table search and G10's per-cell repeat of it. Levers, all pre-registered and chosen before any result: (i) the measured preflight rate (expected below the basis for deterministic rules); (ii) `G6B_PROFILE=lite` (≈ 25 h for G6); (iii) `G10_CELLS` (a subset of cells). Stage order and subsets are set by the `STAGES` variable of the runner.

**Multiplicity after all runs:** registry +7 cases (W1 1, G6 1, NR1 1, G10 4) → **74 cases**; none is a new claim. M1's Bonferroni factor rises to at most (108 + 15 rows) × 10 = 1,230 tests; M1's p (9.06e-13) is far below 0.05/1,230.

**TWC revisit rule (Checkpoint 3/5):** only if G6 (A, B-500 and JP all pass, seed-level bounds > 0) **and** G10 (all tested cells WIN) are both strongly positive.

**Seed-level rule (applies everywhere):** `common_rules.md` R2. Current state for M1: seed-level 95 % lower bounds vs Context are +0.72 (bootstrap over seed means), +0.48 (t) and +0.62 (hierarchical), all > 0 (ledger G3g).

## Prompts for the items without their own file

**G1 (already given):**
> In `Optimized\v17`, run `addpath('g1'); g1_recut_v17` (default cases M1, M3). Report `paper/g1/g1_summary.txt` and `g1_action_by_state.csv` back. If `EQUIV` or `REPRO` fails, stop and report. Do not edit `evalPolicy_v17.m`.

**A1: results by mobility regime (pre-registration, short):**
- *Question:* how does M1's margin vs the Context table and vs Fixed vary with the user's speed class (< 10, 10–20, > 20 m/s, i.e. f_d ≈ 20–67, 67–133, 133–200 Hz)?
- *Design:* re-evaluate the stored M1 policies (10 seeds), Context, Fixed and FixedPU on the 500 M1 traces. Record per-user on-time counts (`info.okU`, `info.resU`) and per-user mean speed. Aggregate on-time per speed class. Use the hierarchical bootstrap CI per class.
- *Status:* descriptive only. No new claim; it backs the "report by mobility regime" recommendation (C4).
> Prompt: "In `Optimized/v17`, write `a1/a1_by_speed.m`: regenerate M1's evaluation traces exactly as `runComparison_v17.m` L183–191 does; evaluate `Deep A2C v17` (10 stored seeds), `ctxtab`, `fixed` and `fixed_class` with the frozen `evalPolicy_v17.m`; save per trace and per user `okU`, `resU`, mean speed and true delay to `paper/a1/a1_peruser.mat`; REPRO-check cell goodput against the stored `metrics.cell_tp`. No statistics in MATLAB; the Python bootstrap is done on the cloud side."

**A3: inference wall time:**
> "In `Optimized/v17`, write `a3/a3_timing.m`: load seed 1 of the M1 policy, extract the actor weights as `diag_action_by_state_v17.m` does, and time 10^5 forward passes for N = 10 users (input 57) with `timeit`. Also time one full `evalPolicy_v17('a2c_v17', …)` 200-TTI trace vs `'fixed_class'`. Report the median µs per decision and per TTI, plus the CPU model."

**A5: path-agnostic release setup:**
> "Create `Optimized/v17/release/code/v17_setup_portable.m` that derives `root` from `fileparts(mfilename('fullpath'))` instead of the hard-coded `D:\` path, and document it in `README_release.md`. Do not change `v17_setup.m` (frozen); add a test that both give identical `C` and `base` structs."

## Changes to the paper plan implied by these items
- C2's wording depends on G6 (rule in G6 §4) and, if run, on NR1 (§4 there).
- The abstract's gain-vs-OLLA number depends on W1 (§3 there).
- The behaviour paragraph (Results VI-G) depends on G1, and optionally A2.
- The robustness paragraph depends on G10. If G10 is not run, the paper states the operating-point restriction explicitly.
