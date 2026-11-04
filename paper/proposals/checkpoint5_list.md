# Checkpoint 5: consolidated evidence-gap list (Phase 5)

Compute basis: `compute_basis.md` (RTT 8, 2 workers: about 0.14 s per training episode and 0.095 s per 200-TTI evaluation; upper bounds). Every run has a 20-trace preflight and pauses if the measured rate exceeds 1.5× the basis. Each pre-registration's §§1–6 are frozen on approval.

## Summary

| ID | Item | Class | New runs? | Wall time | Pre-registration | Status |
|---|---|---|---|---|---|---|
| **G1** | Action re-cut on scheduled new transmissions (M1, M3) | **essential** | re-evaluation only | 20–60 min | `paper/analysis/G1_SPEC.md` | running on author's PC |
| **G3** | Seed-level statistics (sign test, seed t-test, hierarchical bootstrap) | **essential** | none | — | — | **done** (ledger G3a–G3f) |
| **W1** | Warm-up robustness (200 unscored TTIs, all OLLA-based schemes, stored policies) | **essential** | re-evaluation only | ≈ 1.2 h | `W1_warmup_prereg.md` | proposal |
| **G6** | Re-calibrated rules (500 traces) + combined slack × class × busy-HARQ comparator | **essential** | calibration + re-evaluation, no RL training | ≈ 8.4 h (overnight) | `G6_calibration_budget_prereg.md` | proposal |
| **G10** | v17 load × deadline grid (4 cells, 5 seeds, 3000 ep, 300 traces) | **essential** (for TMLCN robustness; also gates any TWC revisit) | training | ≈ 3.7 h | `G10_operating_grid_prereg.md` | proposal |
| **NR1** | Residual on the non-oracle Fixed base at RTT 8 | **nice-to-have (recommended)**; removes limitation #25 | training | ≈ 1.5 h | `NR1_nonoracle_residual_prereg.md` | proposal |
| A1 | Results by mobility regime (per-user on-time by speed class, M1) | nice-to-have | re-evaluation only | ≈ 20 min | below | proposal |
| A2 | On-time attribution by state (G2), from the G1 log | nice-to-have | none (analysis of G1 output) | minutes | below | after G1 |
| A3 | Inference wall time per TTI (G14) | nice-to-have | micro-benchmark | ≈ 5 min | below | proposal |
| **A6** | PF-timing demonstration (Baseline, OLLA, Fixed; ACK-time vs scheduling-time PF × 3 HARQ configs; 100 traces) for pitfall F8 | nice-to-have, **strongly recommended** | re-evaluation only | ≈ 3 min | `design/figure_table_plan.md` (A6 section) | proposal (added in Phase 6) |
| A4 | Learning curves and entropy (3000 ep, 10 seeds) from the HDF5 files (G15) | nice-to-have | none | — | done in Phase 7 here | planned |
| A5 | Path-agnostic setup for the release (G16) | nice-to-have (before release) | none | — | below | proposal |
| F1 | SALAD as an extra comparator (attack #4) | **future work** | port + runs | days | — | not proposed |
| F2 | Second simulator / NR LDPC abstraction / ns-3 (G11, G17) | **future work** | — | — | — | not proposed |

**Essential total ≈ 13.3 h** of wall time (W1 + G6 + G10), plus G1. With NR1 and A1–A3 it is **≈ 15.2 h**.

**Suggested order:** G1 (running) → A6 (3 min) → W1 → G6 (overnight) → NR1 → G10 → A1/A3.
- W1 comes first because it is cheap and can change the abstract number.
- G6 and NR1 settle C2's wording.

**Multiplicity after all runs:** registry +7 cases (W1 1, G6 1, NR1 1, G10 4), giving **74 cases**. They are all robustness checks or design ablations of M1, none a new claim. The project-wide Bonferroni factor for M1 rises from 972 to at most (108 + 15 new rows: W1 2, G6 2, NR1 3, G10 8) × 10 = 1,230 tests. M1's p (9.06e-13) is far below 0.05/1,230.

**TWC revisit rule (Checkpoint 3):** only if G6 (all three of A, B-500 and JP pass) **and** G10 ("robust" with Claim B in ≥ 3 cells) are both strongly positive.

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
