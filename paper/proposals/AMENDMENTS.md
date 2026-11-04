# Amendments to the frozen pre-registrations

The freeze rule (`common_rules.md`, STATUS.md) lets a text change only **before any run that uses it has started**, and every change is recorded here with its reason. No stage of the Checkpoint-5 programme has been run: the runner stages are stubs (`Optimized/v17x/`).

## Amendment 1: Checkpoint 5b, 4 Nov 2026 (author's decisions)
Freeze v1: commit `0726555fb7dda0190e780406828f785903d98f30`. Freeze v2: commit recorded in `paper/STATUS.md` and `paper/proposals/FREEZE.sha256`.

| File | Change | Reason |
|---|---|---|
| `G6_calibration_budget_prereg.md` | (a) the composite table is defined in full in §2.3 (formula, indices, when it is computed, its three uses); (b) profile fixed to **full**, with the exact differences of `lite` stated in §2.4; (c) new §2.5 report point after `g6a` | the sparse-cell fallback must be defined in the frozen text, not only in code; C2's wording depends on G6, so it gets the strongest search; the author wants early, descriptive information |
| `G10_operating_grid_prereg.md` | four cells → **two tested cells** (G2_hi_d10, G3_lo_d18); G1_lo_d10 and G4_hi_d18 are future work, decided now; profile decision and the 200-vs-500 calibration-trace difference stated; wording rows for two cells; compute for two cells; multiplicity 2 cases | the pair spans both axes in opposite directions and includes the regime where calibrated rules were strongest; programme length (≈ 3 days) |
| `A6_pf_timing_prereg.md` | **new frozen text** | A6 needs new evaluations, so it joins the queue after G10 with its own pre-registration |
| `common_rules.md` | R9 (report points); R7 case counts | descriptive reports after each stage; new totals |
| `checkpoint5_list.md` | run order G1 → W1 → NR1 → G6 → G10 → A1/A3 → A6; G10 two cells; totals | author's order and profile decisions |
| `W1`, `NR1`, `compute_basis.md` | unchanged | — |

Run order after the amendment: **G1 → W1 → NR1 → G6 (g6a → report point → g6b → g6c) → G10 → A1/A3 → A6.** Expected programme length on the upper-bound basis: ≈ 80 h (about 3.3 days).
