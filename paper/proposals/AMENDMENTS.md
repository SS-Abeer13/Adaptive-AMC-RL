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

## Amendment 2: 5 Nov 2026 (G10 compute; before any G6 result and before any G10 run)
**Trigger.** The corrected preflight, reported by the author, shows that G10 with two cells costs about **100 h extra** because the combined comparator is re-calibrated per cell (36 cells, four starts, coordinate ascent to convergence). The basis in `G10` §5 had this step at 9.1–27.3 h per cell. Only the combined comparator is affected by the choice below; training, evaluation and the single-cue calibration are not.

**Independence from results.** The choice uses compute and claim scope only. No G6 output (`REPORT_g6a.txt`, tables, evaluation) was read by the writer of this amendment. `G6_calibration_budget_prereg.md`, `W1`, `NR1`, `A6` and `common_rules.md` are **unchanged**, so the running G6 stages are not touched.

**Options considered.** Hours are on the preflight scale implied by the author's figure, which the writer read as ≈ 135 h for two cells at the old design (basis: ≈ 35 h expected, factor ≈ 3.9 applied uniformly; replace by the numbers in `PREFLIGHT_g10.txt`; the ratios between options do not depend on the factor).

| Option | What G10 does | Compute (basis, two cells → scaled) | What the paper can claim | Main weakness |
|---|---|---|---|---|
| **(a)** `lite` combined table in G10 cells, full exhaustive search for single-cue rules | per cell: 4 starts to convergence on a small subset (20 % of the 200 calibration traces = 40), best two polished on all 200 | ≈ 9.9 h per cell → ≈ 20 h → **≈ 77 h** | per cell: beats the OLLA family, the single-cue rules, **and a combined rule calibrated with a lighter search than in M1** | saves little; the strongest comparator is weaker than in M1, so a win is weaker evidence, and the 5b ruling excluded profiles that lower the calibration traces; sparse threshold must be rescaled for 40 traces |
| **(b)** single-cue rules only in G10; combined comparator at M1 only (G6) | per cell: Fixed, FixedPU, Context, OLLA re-calibrated (full, 200 traces); no combined-comparator code | ≈ 3.7 h per cell → ≈ 7.4 h → **≈ 29 h** | two points: beats the OLLA family and the single-cue calibrated rules, or not; "same-information" and "beats the combined rule" are claims about M1 only | the combined rule might close the gap at the other cells; this is not tested (limitation, future work) |
| **(c)** one cell (G3_lo_d18) at full profile | all comparators incl. combined, full G6 method | ≈ 17.4 h → **≈ 68 h** | one neighbouring point, against every comparator incl. the combined one; no statement about which axis matters | one point cannot separate load from deadline; programme still long |

**Decision recommended and applied: (b).** It keeps both neighbouring cells and both axes, which is what lets a loss locate a direction (the reason the pair was chosen at 5b), uses the same exhaustive search as G6 for every rule it does include, and costs about a quarter of the old G10. The combined comparator is where the headline wording of C2 is decided; that decision is made at M1 (G6), where the search is full and the calibration set is 500 traces, and not extended to other points. (a) saves too little and weakens the strongest comparator; (c) keeps the strongest comparator but loses the second cell and still costs about half of the old G10.

| File | Change | Reason |
|---|---|---|
| `G10_operating_grid_prereg.md` | §1 question names the single-cue comparators; §2.1 rewritten (no combined comparator, no profile choice left, consequence for claims, future work decided now); §3 family of 9, Holm over 9, WIN = beats all 9, no JP; §4 four wording rows carry "single-cue rules" and "combined rule tested at M1 only"; §5 compute (≈ 3.7 h per cell, 7.4 h for two); §7 units and outputs without the combined comparator | compute |
| `checkpoint5_list.md` | G10 row and totals (≈ 53 h on the basis; was ≈ 80 h) | consistency |
| `Optimized/v17x/README_v17x_runner.md` | g10 units without `calib_comb_*` | runner spec |
| `paper/manuscript/wording.tex`, `paper/design/outline.md` | G10 wording variants and outline row follow §4 | consistency |
| `G6`, `W1`, `NR1`, `A6`, `common_rules.md`, `compute_basis.md` | unchanged | G6 is running |

Freeze v3: hashes in `FREEZE.sha256`; the commit is recorded in `paper/STATUS.md`. If the author prefers (a) or (c), the text can be replaced before any G10 run starts, with a further amendment entry (G10 has not started; the runner stage is a stub).
