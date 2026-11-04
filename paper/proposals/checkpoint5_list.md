# Checkpoint 5: consolidated evidence-gap list (Phase 5)

Compute basis: `compute_basis.md` (RTT 8, 2 workers: about 0.14 s per training episode and 0.095 s per 200-TTI evaluation; upper bounds). Every run has a 20-trace preflight and pauses if the measured rate exceeds 1.5× the basis. Each pre-registration's §§1–6 are frozen on approval.

## Summary (FROZEN; amended at Checkpoint 5b, see `AMENDMENTS.md`)

All pre-registrations G6, W1, NR1, G10, A6 and `common_rules.md` are frozen; the freeze commits and hashes are in `paper/STATUS.md` and `FREEZE.sha256`. **Run order (approved at Checkpoint 5b): G1 → W1 → NR1 → G6 (g6a → report point → g6b → g6c) → G10 → A1/A3 → A6.** A2, A4 and A5 need no runs. NR1 runs before G6 so that the short items report early.

| ID | Item | Class | New runs? | Wall time (upper-bound basis; 2 workers) | Pre-registration |
|---|---|---|---|---|---|
| **G1** | Action re-cut on scheduled new transmissions (M1, M3) | essential | re-evaluation | 20–60 min | `paper/analysis/G1_SPEC.md` |
| **G3** | Seed-level statistics | essential | none | — | **done** (ledger G3a–G3i) |
| **W1** | Warm-up robustness (200 unscored TTIs, stored policies) | essential | re-evaluation | ≈ 1.2 h | `W1_warmup_prereg.md` |
| **NR1** | Residual on the non-oracle Fixed base at RTT 8 | recommended | training | ≈ 1.5 h | `NR1_nonoracle_residual_prereg.md` |
| **G6** | **Full profile.** Exhaustive re-calibration of Fixed / Context / OLLA on 500 traces, FixedPU separable + joint, and the combined comparator (coordinate ascent, 4 starts) | essential | calibration, no RL training | `g6a` ≈ 6.9 h (**report point**), `g6b` ≈ 23 h min / **≈ 34 h expected** / ≤ 68 h cap; **total ≈ 41 h expected** | `G6_calibration_budget_prereg.md` |
| **G10** | **Two cells** (G2_hi_d10, G3_lo_d18), per-cell recalibration of all comparators incl. the combined one, 200 calibration traces per cell | essential | training + calibration | **≈ 26 h min, ≈ 35 h expected, ≈ 62 h cap** | `G10_operating_grid_prereg.md` |
| A1 | Results by speed class (M1) | approved | re-evaluation | ≈ 20 min | below |
| A2 | On-time attribution by state (from the G1 log) | approved | none | minutes | after G1 |
| A3 | Inference wall time per TTI | approved | micro-benchmark | ≈ 5 min | below |
| A4 | Learning curves and entropy (HDF5) | approved | none | — | Phase 7 figure F5b |
| A5 | Path-agnostic release setup | approved | none | — | below |
| **A6** | PF-timing demonstration (pitfall figure F8) | approved **with its own frozen text, after G10** | re-evaluation (no training) | ≈ 3 min + 2 min test | `A6_pf_timing_prereg.md` |
| F1, F2 | SALAD comparator; second simulator | future work | — | — | — |
| F3, F4 | Grid corners G1_lo_d10 and G4_hi_d18 | future work, decided now (not to be added on the basis of G2/G3) | — | — | `G10_operating_grid_prereg.md` §2 |

**Total on the upper-bound basis:** ≈ 1 h (G1) + 1.2 h (W1) + 1.5 h (NR1) + 41 h (G6) + 35 h (G10) + 0.5 h (A1/A3) + 0.1 h (A6) ≈ **80 h (about 3.3 days)**. The measured preflight rate (expected below the basis for deterministic rules) can only shorten it.

**Multiplicity after all runs:** registry +6 cases (W1 1, G6 1, NR1 1, G10 2, A6 1 diagnostic) → **73 cases**; none is a new claim. M1's Bonferroni factor is at most 1,190 tests (`common_rules.md` R7); M1's p (9.06e-13) gives ≈ 1.1e-9.

**TWC revisit rule (Checkpoint 3):** only if G6 (A, B-500 and JP all pass, seed-level bounds > 0) **and** G10 (both tested cells WIN) are strongly positive.

**Seed-level rule (applies everywhere):** `common_rules.md` R2. For M1 all seed-level 95 % lower bounds vs Context are > 0 (+0.72, +0.48, +0.62; ledger G3g).

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
