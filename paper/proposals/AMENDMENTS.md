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

## Amendment 3: 8 Nov 2026 (new stage NR2; no frozen text changed)
**Trigger.** The review of the Checkpoint-5 results (`paper/ledger/conflicts.md` §G) found that (i) M1's margin over the G6 combined table passes at trace level but fails Rule R2 (5/10 seeds; hierarchical 95 % CI [−0.30, +1.70] %), and (ii) NR1 (non-oracle Fixed base) beat every comparator, but on M1's evaluation traces, with only a descriptive comparison against the combined table, and without stored per-seed values, so R2 cannot be applied to it. The author asked for a confirmatory replication of NR1.

**What is added.** `NR2_confirmatory_prereg.md` (new, frozen) and its analysis script `paper/analysis/nr2_stats.py` (frozen with it). Fixed base, the residual recipe, 3000 episodes, 10 fresh seeds (base 25042), 500 fresh evaluation traces (1000001–1000500, CRN 1010001+, decision draws 1020000+; disjoint from every earlier range, asserted in code), primary comparator **Context-joint-500 from the frozen G6 tables (hash-checked, not re-searched)**, primary scheme the per-seed mean, decision at trace level (Holm over a family of 8) **and** seed level (R2). Verdicts CONFIRM / TRACE / NULL / REVERSE with a wording row each (`wording.tex`, slot NR2); WIN reported with each. Compute ≈ 4.4 h on the measured NR1 basis (range 3.3–6.3 h). **Runs after G10.**

**What is not changed.** No frozen text changes: G6, W1, NR1, G10, A6, `common_rules.md`, `checkpoint5_list.md` and `compute_basis.md` keep their v3 hashes. NR2 is listed here and in `FREEZE.sha256` rather than by editing `checkpoint5_list.md`. R7 bookkeeping: +1 case (M1-NR2), up to 3 rows.

**Independence.** NR2 was designed after the NR1 and G6 results were read; that is why it uses fresh traces and seeds and fixes the comparator, the scheme, the family and both decision levels in advance. The script was validated before freezing on the M1/G6 data, where it reproduces `table_cal500.csv` and returns TRACE.

**Related decision (not a freeze change).** The G6 stage's summary file marked the claim seed-robust because it evaluated R2 against Context-500 only; G6 §3 and R2 require the best comparator. The manuscript uses the G6 §4 row 2 wording (`ABJ-seed`); the generated file is not edited (ledger G6e).

**Freeze v4:** hashes in `FREEZE.sha256` (v3 hashes kept in `FREEZE_v3.sha256`); the commit is recorded in `paper/STATUS.md`.

## Amendment 4: 9 Nov 2026 (Code review finding: fixed_class_tab bug in comparator evaluation and calibration; watchdog heartbeat in G10; before any valid G10 or NR2 run)
**Trigger.** A systematic code review of the live v17/v17x pipeline (`claude/amc_code_review_2026-11-08.md`) identified that `evalPolicy_v17_g6.m` evaluated policy `'fixed_class'` exclusively by reading `env.fixed_class_tab`, whereas the calibration and evaluation stages (`stage_g6a.m`, `stage_g6c.m`, `stage_g10.m`, and `stage_nr2.m`) wrote the calibrated table to `env.class_tab`. Consequently, the G6c evaluation evaluated M1's historical 20-trace table (`[-2 -2 -2; -3 -2 -3]`) under the label `FixedPU-500` instead of the calibrated 500-trace table (`[-1 -2 -2; -1 -2 -2]`). In G10, the same mismatch prevented per-cell FixedPU refinement and corrupted FixedPU base-rule selection. In addition, G10 was repeatedly terminated by `watchdog_v17x.ps1` (14 times) due to a 30-minute watchdog timeout during the exhaustive 343-candidate Context search because heartbeats were not emitted during long optimization loops.

**What is fixed.**
1. `evalPolicy_v17_g6.m`: updated so that policies `'fixed_class'`, `'fixed_oracle'`, `'fixed_online'`, and residual base selection inspect `env.class_tab` first, falling back to `env.fixed_class_tab`.
2. `stage_g6a.m`, `stage_g6c.m`, `stage_g10.m`, and `stage_nr2.m`: explicitly assign both `env.fixed_class_tab` and `env.class_tab` across all calibration and evaluation units.
3. `stage_g10.m`: added throttled heartbeat calls (`ctx.hb(...)`) within Context candidate search (every 10 candidates), OLLA search (every 5 candidates), and coordinate ascent sweeps (every cell).
4. `stage_g6c.m`: re-evaluated on the 500 held-out traces with the corrected FixedPU-500 table. The true FixedPU-500 margin is +1.73 % [1.31, 2.14] % (Holm p = 2.79e-12; hierarchical 95 % CI [+0.72, +2.80] %, 9/10 seeds > 0). Residual A2C beats all 10 comparators. Calibrated rule order is strictly monotonic: Fixed-500 (+1.87 %) > FixedPU-500 (+1.73 %) > Context-500 (+1.43 %) > Context-joint-500 (+0.66 %).
5. `stage_nr2.m`: inherits the fix so that the REPRO gate and fresh evaluations correctly evaluate the true calibrated FixedPU-500 table.
6. G10 checkpoints were reset so G10 begins cleanly from the start before any valid results are produced.

**What is not changed.** The pre-registration specifications (`G6_calibration_budget_prereg.md`, `G10_operating_grid_prereg.md`, `NR2_confirmatory_prereg.md`, `common_rules.md`, `checkpoint5_list.md`, `compute_basis.md`) are completely unchanged. They specify the methodology and mathematical formulations; this amendment corrects an implementation variable-name disconnect.

**Freeze v5:** hashes recorded in `paper/proposals/FREEZE.sha256`; commit recorded in `paper/STATUS.md`.
