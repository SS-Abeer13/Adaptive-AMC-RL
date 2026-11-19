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

## Amendment 5: 10 Nov 2026 (Pre-registered NR-G10: non-oracle residual recipe at the two neighbouring operating cells; before any NR-G10 run)
**Trigger.** The operating-grid evaluation G10 evaluated the M1 recipe, which auto-selected the base rule on 20 calibration traces. In both cells (G2_hi_d10 and G3_lo_d18), the selector chose `FixedPU (Oracle)` (offset -2 in G2, -3 in G3). G10 yielded no WIN in either cell (Claim A passed in both cells, but Claim B failed against Context table in G2, and against FixedPU and Context table in G3), triggering the pre-registered limitation sentence that the M1 result was observed at the M1 operating point only. Meanwhile, the non-oracle residual recipe (`Fixed` base with calibrated offset) demonstrated clear superiority over the oracle base in NR1 and was confirmed on fresh traces and seeds in NR2 (+3.35 % over Context-joint-500, hierarchical 95 % CI [+2.22, +4.40] %, 9/10 seeds positive). Because the non-oracle recipe is now the recommended configuration, testing whether the non-oracle recipe generalizes across the operating grid is a natural and necessary pre-registered step.

**What is added.** `NR_G10_operating_grid_prereg.md` (new, frozen).
1. **Cells & Recipe:** The non-oracle residual recipe (residual A2C with `Fixed` base rule, one global calibrated offset) evaluated at the two tested neighbouring cells:
   - `G2_hi_d10` (16,000 bits, 10 TTI, base offset `Fixed -2`)
   - `G3_lo_d18` (8,000 bits, 18 TTI, base offset `Fixed -3`)
2. **Calibrations:** Frozen single-cue calibrated comparator tables from G10 (Fixed, FixedPU, Context, OLLA tuned; calibrated on 200 traces per cell; hash-checked).
3. **Training & Seeds:** 5 seeds $\times$ 3,000 episodes per cell. Base seeds: `33042` for G2, `34042` for G3 (seeds 33042+201..205 and 34042+201..205; asserted disjoint from all prior rounds, including G10's 31042 and 32042). Primary scheme: 5-seed mean. Secondary scheme: ensemble.
4. **Evaluation Traces:** 300 evaluation traces per cell (G2: seeds 720001+, CRN 730001+; G3: seeds 740001+, CRN 750001+; identical evaluation set to G10).
5. **Comparators & Decision Rules:** Family of 9 single-cue comparators per cell. Rule R1: Holm over 9 per cell; Claim A, Claim B; cell WIN if primary scheme beats all 9. Rule R2: Hierarchical seed $\times$ trace 95 % CI vs best comparator.
6. **Multiplicity Accounting:** Adds 2 cases (`G2_hi_d10_NR`, `G3_lo_d18_NR`), 4 scheme evaluations (primary + ensemble per cell). Total cases in study increase from 74 to 76; scheme evaluations increase from 122 to 126.
7. **Pre-registered Wording:** Explicit wording rows for Both WIN, One WINs, Neither WINs, and unrun.

**What is not changed.** All prior frozen texts (`G6`, `W1`, `NR1`, `G10`, `A6`, `NR2`, `common_rules.md`, `checkpoint5_list.md`, `compute_basis.md`) maintain their specifications. G10 results stand as reported (M1 recipe fails Claim B at both neighbouring cells). NR-G10 evaluates the non-oracle recipe as a separate, distinct pre-registered stage.

**Freeze v6:** hashes recorded in `paper/proposals/FREEZE.sha256`.

## Amendment 6: 10 Nov 2026 (Implementation-only: removal of redundant 'RetainData', true in dlgradient; memory optimization; verified bit-identical)
**Trigger.** A working-tree change in `Optimized/v17/DeepA2C_Shared_v17.m` and `Optimized/v17/release/code/DeepA2C_Shared_v17.m` removed the redundant `'RetainData', true` argument from `dlgradient(cLoss, criticNet.Learnables, 'RetainData', true)`. In MATLAB's automatic differentiation, `RetainData` preserves intermediate activations on the computation graph for subsequent gradient calls. Because actor loss (`aLoss`) and critic loss (`cLoss`) are computed on separate network objects (`actorNet` and `criticNet`), `aLoss` gradients never traverse the critic's computation graph. Removing `RetainData` frees intermediate memory immediately after critic backpropagation, preventing RAM accumulation and accelerating training.

**Verification test (PASS: bit-identical).** An equivalence test was run training one M1 seed (seed 25243) for 20 episodes under both the committed HEAD version and the working-tree version on the identical channel traces:
- Loss trace max absolute difference: 0.00e+00 (`isequal: 1`)
- Entropy trace max absolute difference: 0.00e+00 (`isequal: 1`)
- Actor weights overall max difference: 0.00e+00 (all 6 weight and bias tensors bit-identical)
- Critic weights overall max difference: 0.00e+00 (all 6 weight and bias tensors bit-identical)
- Best episode identical: 1 (HEAD=20, WORK=20)
- Execution speedup: 20.37 s (working-tree) vs 38.22 s (HEAD)
- Timestamp verification: `DeepA2C_Shared_v17.m` was modified at Tue Nov 10 01:03:25 2026, prior to NR2 training (04:42:51–10:06:07). Thus NR2 was trained with the working-tree version, which is verified bit-identical to HEAD.

**Freeze v7:** Hashes recorded in `paper/proposals/FREEZE.sha256`.

## Amendment 7: 11 Nov 2026 (new stage HR1 / `hr1`, Plan 4: learnable myopic headroom; before any instrumented run on evaluation traces)
**What is added.** `HR1_headroom_prereg.md` (new, frozen) and its analysis script `paper/analysis/hr_stats.py` (frozen with it). The instrumented evaluator (`Optimized/v17/headroom/`, commits `fc78cc7`, `5f2659e`) logs 65 columns per scheduled new transmission and is bit-identical to the frozen evaluator on 20 calibration traces (`Dataset/hr/hr_equiv.txt`). The full pass runs the main-round **evaluation** traces of M1 (500001–500500, CRN 510001+) and M3 (540001–540500, CRN 550001+) for Fixed, the Context table, the frozen combined table Context-joint-500 and the stored learned policies (M1, NR2 on M1; the M3 policies on M3), all 10 seeds per learned scheme.

**Decisions fixed by the author (11 Nov 2026), now part of the frozen text (§3):**
- (a) candidate offsets that map to the same MCS because of clipping are treated as one action;
- (b) the residual-restricted headroom uses the base offset ±1 per decision (`base_rule_offset`), and the table headroom uses −4…+2;
- (c) the full-buffer case uses ubits = tbs.

**Predictions** P1–P4 with decision rules and wording rows (§§5–6). HR1 adds no scheme evaluations, so the registry, the robustness ledger and the Bonferroni pool are unchanged (§7).

**Independence.** Written after all main results were known. No headroom quantity has been computed on any trace: `hr_stats.py` was tested on synthetic logs only (rules (a)–(c), determinism, genie ≥ learnable), and the 20-trace calibration logs were not analysed.

**What is not changed.** All earlier frozen texts and scripts keep their hashes.

**Freeze v8:** hashes in `paper/proposals/FREEZE.sha256` (v7 kept as `FREEZE_v7.sha256`). The B4 gate of `stage_hr1.m` opens when this entry and the `hr1` freeze line are present and `sha256sum -c FREEZE.sha256` passes.

## Amendment 8: 13 Nov 2026 (new stages R1–R5, pre-submission attribution and robustness runs; before any of their runs)
**Trigger.** The simulated review of draft v10 (`paper/review/`, four reviewers, all "major revision") asked whether the NR2 gain needs reinforcement learning or would be captured by any learner, or a designed rule, that sees the same gNB-observable features. It also asked for NR2 diagnostics, a seed-level sensitivity analysis and more seeds. The author approved runs R1–R5 of `R1_revision_runs_proposal.md` (R6–R10 stay for the revision round).

**What is added.** `R_presub_prereg.md` (new, frozen) and its analysis script `paper/analysis/presub_stats.py` (frozen with it; it imports the frozen `r1`, `holm` and `seed_level` of `nr2_stats.py`). Stages `r3_nr2diag`, `r1_gbt`, `r2_rule`, `r5_seeds`:
- **R1:** a one-step gradient-boosted predictor (gbt_a settings of HR1) trained only on G6 calibration-trace logs (600001–600500) with the Fixed-500 rule as the behaviour policy; labels q = psucc × ubits (true SINR, training targets only); inputs `obs_1..19` only; deployed as GBT-res (base ±1) and GBT-full (−4…+2).
- **R2:** a designed rule on the Fixed-500 base (δ = +1 if busy ≥ 1, or slack ≤ 0.6 with a packet, or a reported-SINR drop of at least 1 dB/TTI over 4 TTIs), and a calibrated version (160-point grid on the G6 calibration traces; thresholds hashed before evaluation).
- **Evaluation:** primary on the NR2 evaluation traces against NR2 (Holm over 4, R2 at seed level; outcomes BEATS / BEATS-TRACE / LOSES / MATCH / INCONCLUSIVE with wording rows and consequences for C2); secondary on the M1 traces and against Context-joint-500, Fixed-500 and Context-500.
- **R3:** NR2 diagnostics (speed breakdown, warm-up, fairness guard, action shares), descriptive.
- **R4:** t, BCa and exact sign-flip analyses and power on the seed margins (M1, NR2, NR-G10), sensitivity only.
- **R5:** +10 NR2 seeds (25253–25262) and +5 NR-G10 seeds per cell (33248–33252, 34248–34252), reported next to the frozen verdicts, which stand.

**Multiplicity.** +7 cases / +11 scheme evaluations (R1, R2 on two trace sets; R5 three analyses). Project totals become 83 cases / 137 scheme evaluations, Bonferroni pool ≤ 1 370 (added to `ledger/robustness_cases.csv` at integration).

**Independence.** Written after all results of the paper were known. No R1–R5 trace, model, threshold or output exists. `presub_stats.py --selftest` was run on synthetic data only (outcome classes, exact sign-flip, BCa, power, end-to-end R3–R5); no evaluation-trace data were opened by the writing session.

**What is not changed.** All earlier frozen texts and scripts keep their hashes; all earlier verdicts stand.

**Freeze v9:** hashes in `paper/proposals/FREEZE.sha256` (v8 kept as `FREEZE_v8.sha256`). The stages may run once this entry and the v9 freeze file are committed and `sha256sum -c FREEZE.sha256` passes.

## Deviation D1 (Amendment 8, stage `r5_seeds`, cell G2): recorded 15 Nov 2026
**What happened.** R5 G2 was evaluated at **pkt_bits 16000 instead of the calibrated 14000** (`Optimized/v17x/stage_r5_seeds.m:159`, `get_cell_cfg('G2_hi_d10', envN2)` at evaluation). The G2 cell of G10 / NR-G10 uses 14000 bits, so the five added seeds (6–10) were scored in a different traffic configuration from the comparators and from the frozen seeds 1–5. This was found in the audit (`34ed25f`, `5b84537`): seeds 6–10 scored about −20 % each against the frozen Context table, while their training reward matched seeds 1–5, and re-evaluation at 14000 bits gave 0.5445 (r5 seeds) and 0.5478 (stored seeds), both above the Context table (0.5385).
**Effect.** Training is unaffected: the policies were trained with the cell's frozen environment. Only the evaluation of G2 seeds 6–10, and therefore the R5 "NR-G10-10 G2" verdict ("WEAKENS", −9.42 %), rests on the faulty configuration. The NR2-20 and G3 evaluations are checked field by field against their frozen environments (pkt_bits, deadline, period, load, base offset) in the correction run.
**Correction (no retraining, no change to any frozen text).** R5 seeds 6–10 of G2 are re-evaluated at 14000 bits through the frozen `stage_nr_g10` evaluation path, on the same traces and CRN. The corrected per-trace values go to a new file next to the original (`Optimized/v17x/Dataset/presub/pertrace_G2corrected.csv`; the original is not overwritten), and `paper/analysis/presub_stats.py` is run **unchanged** into a separate output folder (`paper/analysis/out/presub_G2corrected/`).
**Reporting.** The paper reports the frozen (faulty) R5 G2 verdict and the corrected re-evaluation **side by side**, names this deviation, and states that the corrected value replaces nothing in the frozen record.

## Amendment 9: 15 Nov 2026 (new stage R1b / `r1b_ack`: one-step learner trained on observed ACK/NACK; before any of its runs)
**Trigger.** In R1, both one-step GBT schemes beat NR2 on the NR2 traces (on-time GBT-full 0.6565, GBT-res 0.6373, NR2 0.6201). The leakage audit was clean (`34ed25f`, `5b84537`), but R1's labels use the simulator's true SINR, which a gNB never has. The deployable analogue needs labels from observed ACK/NACK, and the logged Fixed rule (always offset −2) gives no coverage of the other actions.
**What is added.** `R1b_ack_prereg.md` (new, frozen) and `paper/analysis/r1b_stats.py` (frozen with it; it imports the frozen functions of `nr2_stats.py` and `presub_stats.py`).
- **Logging:** on the G6 calibration traces 600001–600500 only, ε-greedy around the Fixed-500 base with ε = 0.5: offset −2 with probability 0.5, otherwise uniform over −4…+2; draws `rng(3050000 + j)`. Observed first-transmission ACK/NACK, MCS taken, features and candidate useful bits are logged; no true-SINR quantity is logged or used.
- **Model:** p̂(ACK | obs_1..19, MCS), a `HistGradientBoostingClassifier` with the gbt_a settings, trained on the observed first-transmission outcomes; q̂(a) = p̂(x, mcs(a)) × useful_bits(a).
- **Schemes:** GBT-res-ACK (base ±1) and GBT-full-ACK (−4…+2), deterministic.
- **Evaluation:** as R1 (NR2 traces primary, Holm over 2, R2 at seed level, the frozen outcome classes and wording rows; secondary on the comparators, the M1 traces and against the true-SINR R1 schemes); calibration of p̂ reported (reliability curve, Brier, ECE; cross-fitted on calibration logs and on deployment decisions).
**Multiplicity.** +2 cases / +4 scheme evaluations; with Amendment 8 the project totals become 85 cases / 141 scheme evaluations, Bonferroni pool ≤ 1 410.
**Independence.** Written after the R1–R5 results and audits were known. No R1b log, model or output exists. `r1b_stats.py --selftest` was run on synthetic data only; no evaluation-trace data were opened by the writing session.
**What is not changed.** All earlier frozen texts and scripts keep their hashes, apart from this file (`AMENDMENTS.md`), to which D1 and this entry are appended.

**Freeze v10:** hashes in `paper/proposals/FREEZE.sha256` (v9 kept as `FREEZE_v9.sha256`). Stage `r1b_ack` may run once this entry and the v10 freeze file are committed and `sha256sum -c FREEZE.sha256` passes.

## Amendment 10: 15 Nov 2026 (new stage R1c / `r1c`: calibration-set replication and operating-cell generalization of the ACK-trained learner; before any of its runs)
**Trigger.** Stage R1b (`5183a89`) demonstrated that a one-step supervised learner trained purely on observed first-transmission ACK/NACK feedback beat NR2 across all 10 policy seeds on the NR2 confirmatory traces (GBT-res-ACK on-time 0.6420, margin −3.40 % [−3.75, −3.05] %, hier [−4.43, −2.47] %; GBT-full-ACK on-time 0.6710, margin −7.58 % [−8.09, −7.07] %, hier [−8.64, −6.61] %; twins over simulator true-SINR labels +0.73 % and +2.21 %; all ECE ≤ 0.021). Two critical scientific questions arise immediately:
(a) **Calibration-set replication:** was this advantage dependent on the specific 500 calibration traces used (draw chance), or does it hold across independent calibration sets?
(b) **Operating-cell generalization:** does the ACK-trained learner maintain its advantage at neighbouring operating points across the NR-G10 grid (G2 at 14 kbit and G3) against the RL policy and calibrated heuristic baselines?

**What is added.** `R1c_ack_prereg.md` (new, frozen) and `paper/analysis/r1c_stats.py` (frozen with it; validated on synthetic data):
- **Replication across 4 fits:** 3 additional fresh, disjoint calibration trace sets (500 traces each, M1 setup, ε-greedy logging with ε = 0.5):
  - Fit 1: traces 600001–600500, CRN 610001+, exploration stream `rng(3050000 + j)` (from R1b);
  - Fit 2: traces 620001–620500, CRN 630001+, exploration stream `rng(3060000 + j)`;
  - Fit 3: traces 640001–640500, CRN 650001+, exploration stream `rng(3070000 + j)`;
  - Fit 4: traces 660001–660500, CRN 670001+, exploration stream `rng(3080000 + j)`.
  All 4 fits trained with `HistGradientBoostingClassifier` under `gbt_a` settings (`max_iter=300, lr=0.05, 31 leaves, min 40 per leaf`).
  Each fit deployed as `GBT-res-ACK` (base ±1) and `GBT-full-ACK` (−4…+2) on the 500 NR2 confirmatory evaluation traces (traces 1000001–1000500).
  Reporting: fit-level mean, min, max, Student-t 95 % CI across fits, and the worst fit evaluated against NR2 under Rule R1 (Holm over the 2 schemes) and Rule R2 (hierarchical 95 % CI over 10 NR2 seeds).
- **Operating-cell generalization:** The 4 ACK fits evaluated on the 300 held-out evaluation traces of the two neighbouring cells from the pre-registered NR-G10 operating grid:
  - `G2_hi_d10`: 14,000 bits (corrected per Deviation D1), 10 TTI deadline, base offset `Fixed -2` (traces 720001–720300, CRN 730001+);
  - `G3_lo_d18`: 8,000 bits, 18 TTI deadline, base offset `Fixed -3` (traces 740001–740300, CRN 750001+).
  Evaluated against the frozen per-cell single-cue comparators (`G_FAMILY`, Holm over 9 per cell) and the cell's RL policies from NR-G10 (`NRG10`, Rule R1 and Rule R2).
- **Pre-registered wording rows (§5):**
  - "holds across all 4 fits and both cells"
  - "fit-dependent"
  - "operating-point dependent"
  - "neither holds nor generalizes"
  - "not run"

**Multiplicity.** Adds **11 cases / 22 scheme evaluations** (3 new fits on NR2 = +3 cases / +6 evaluations; 4 fits on G2 = +4 cases / +8 evaluations; 4 fits on G3 = +4 cases / +8 evaluations; alternatively +5 cases grouped by cell). With Amendment 9 the project totals become **96 cases / 163 scheme evaluations**, Bonferroni pool ≤ 1 630 tests.

**Compute estimate.** 3 calibration logs (≈ 4 min), 3 model trainings (≈ 3 min), gates (≈ 1 min), NR2 evaluations for 3 fits (≈ 4.9 h), cell G2 evaluations for 4 fits (≈ 3.7 h), cell G3 evaluations for 4 fits (≈ 3.7 h). Total: **≈ 12.3 h** (roughly 12–14 h).

**Independence.** Written after the R1b results were known. No R1c exploration draw, calibration log, model or evaluation output exists. `r1c_stats.py --selftest` was validated on synthetic data only; no evaluation data were opened by the writing session.

**What is not changed.** All earlier frozen texts and scripts maintain their hashes, apart from this file (`AMENDMENTS.md`), to which this entry is appended. All earlier results and verdicts stand as recorded.

**Freeze v11:** hashes in `paper/proposals/FREEZE.sha256` (v10 kept as `FREEZE_v10.sha256`). Stage `r1c` may run once this entry and the v11 freeze file are committed and `sha256sum -c FREEZE.sha256` passes.

## Amendment 10a: 15 Nov 2026 (revision of R1c before any of its runs)
**Trigger.** Review of the Amendment 10 text (`85b0518`, Freeze v11) before stage `r1c` ran. The weaknesses were:
- the cells were tested only with M1-trained models;
- the cell parameters were typed into the text, which is the class of error behind Deviation D1;
- the RL comparator in the cells used 5 seeds;
- "match" was not defined;
- the "fit-dependent" wording over-interpreted the outcome.

No R1c draw, log, model or output exists. `R1c_ack_prereg.md` and `paper/analysis/r1c_stats.py` are replaced; the v11 versions stay in git history.

**Changes.**
1. **Primary cell test = per-cell fits.** Four GBT-ACK fits per cell, on fresh disjoint calibration traces of that cell, with the same ε-greedy logging (ε = 0.5) around the cell's frozen base offset and the same gbt_a settings. Ranges:
   - G2 fit k: traces 4100000 + 1000(k−1) + j, CRN 4200000 + …, stream `rng(4300000 + …)`;
   - G3 fit k: traces 4400000 + …, CRN 4500000 + …, stream `rng(4600000 + …)`;
   - j = 1…500, all asserted disjoint.

   The M1-trained fits evaluated in the cells become a secondary **transfer** analysis.
2. **Cell environments are loaded from `Optimized/v17x/Dataset/ckpt/g10/calib_single_<cell>.mat`, never hard-coded.** The stage asserts pkt_bits (G2 = 14 000), deadline, period, N, offered load and base offset against the file. `get_cell_cfg` is not used. The typed G3 parameters are removed; the values read from the file on 15 Nov are given for reference only.
3. **RL comparator per cell = 10 seeds.** G2 seeds 6–10 are the corrected 14 kbit re-evaluation of Deviation D1 (`pertrace_G2corrected.csv`; the script refuses to run without it). R1 (Holm over the 8 fit × scheme comparisons per trace set) and R2 apply as for NR2.
4. **Wording:**
   - **"match"** = Holm not significant and |margin| < 0.5 %;
   - **"beats rules"** = R1 against every member of the cell's family of 9, with Holm over 9;
   - "fit-dependent" is reworded to **"depends on the calibration draw"**;
   - rows are added for **"replicates across fits, cell-dependent"** and **"cells hold, fit-dependent"**;
   - the verdict is given per scheme.
5. **Compute** about 20.5 h, including per-cell logging (8 draws) and 8 cell fits. The stage specification is updated. **Multiplicity** becomes +19 cases / +38 scheme evaluations, giving project totals of 104 / 179 and a Bonferroni pool ≤ 1 790.

**Validation.** `r1c_stats.py --selftest` (synthetic data only) passes. It produces each of the six wording rows from a pattern built for it, checks the MATCH definition and the order of the outcome classes, checks the refusal without the corrected G2 file, and checks that the statistics functions are the frozen ones.

**Independence.** No evaluation data were opened. The writing session read only the frozen G10 calibration files (`calib_single_<cell>.mat`, `out.env` field names and values) to state §4.1.

**Freeze v12:** hashes in `paper/proposals/FREEZE.sha256` (v11 kept as `FREEZE_v11.sha256`). Stage `r1c` may run once this entry and the v12 freeze file are committed and `sha256sum -c FREEZE.sha256` passes.

## Amendment 11: 17 Nov 2026 (new stage R6 / `r6_fullaction`: residual RL with the full action set −4…+2; before any of its runs)
**Trigger.** R1b and R1c show that the one-step learner trained on observed ACK/NACK beats NR2. All three internal reviewers of draft v12 (`3757e1d`, `paper/review/review_v12_*.md`) named the action set as the main confound:
- NR2 chooses base ±1;
- GBT-full-ACK chooses any offset in −4…+2;
- the matched comparison (GBT-res-ACK, −3.40 %) removes the action-set difference, but no RL policy with the wider set exists.

No R6 policy, log, model or output exists.

**What is added.** `R6_fullaction_prereg.md` (new, frozen) and `paper/analysis/r6_stats.py` (frozen with it; it imports the frozen functions of `nr2_stats.py` and `presub_stats.py`).
1. **R6a (primary): RL-full.**
   - Recipe: NR2's residual A2C recipe, unchanged except `env.resid_actions = -2:4` on the forced Fixed −2 base, so the offsets are −4…+2, the set of GBT-full-ACK.
   - The logit bias on δ = 0 and the deviation penalty 0.02 × |δ| are as in NR2.
   - Seeds: 10 fresh (`base_seed = 27042`, +201…+210), 3000 episodes.
   - Gates: default-path reproduction of NR2 seed 1 before training, and REPRO before evaluation.
   - Evaluation: greedy, on the NR2 traces; decision draws `rng(2340000 + 100 j + s)`, all asserted disjoint.
   - Comparison: GBT-full-ACK M1 fits 1–4, with R1 statistics (Holm over 4), seed level and the R1c outcome classes.
   - Wording rows:
     - **"the supervised learner beats RL at both action sets"** (all fits LOSES);
     - **"the gap closes with the full action set"** (no fit LOSES, not all BEATS);
     - **"RL-full beats the supervised learner"** (all BEATS);
     - **"depends on the calibration draw"** (mixed);
     - **"not run"**.
   - Secondary, descriptive: gap closure, RL-full vs NR2, vs the combined table and vs GBT-res-ACK, and the δ shares.
2. **R6b (optional observation): a true-SINR one-step model on the R1b exploration logs.**
   - The logging re-run must match the stored R1b log row for row.
   - Model: R1's model form and labels, deployed as res and full.
   - It separates the logging effect from the label effect in the R1b twin result. Descriptive only; no verdict.

**Multiplicity.** +2 cases / +3 scheme evaluations (R6a 1 / 1; R6b 1 / 2), counted from this freeze. Project totals become **106 / 182**, with a Bonferroni pool ≤ 1 820. Ledger row `R6` is added.

**Compute.** About 7.5–8.5 h; R6a alone about 6–6.5 h. R6b may run last or not at all.

**Validation.** `r6_stats.py --selftest` (synthetic data only) passes. It produces each of the four state-based wording rows and "not run" from patterns built for them, checks the outcome classes and their order (identical to R1c), checks that R6a is unaffected by the presence or absence of R6b, and checks that the statistics functions are the frozen ones.

**Independence.** No evaluation data were opened. The writing session read the code to confirm that `env.resid_actions` sets the action set and the actor width (`DeepA2C_Shared_v17.m:20–29, 88–94`; `defaultEnv_v17.m:167–169`), and searched the repository to confirm that the seed base 27042 and the draw range 2340000+ are unused.

**What is not changed.** All earlier frozen texts and scripts keep their hashes. All earlier results and verdicts stand as recorded, with Deviation D1.

**Freeze v13:** hashes in `paper/proposals/FREEZE.sha256` (v12 kept as `FREEZE_v12.sha256`). Stage `r6_fullaction` may run once this entry and the v13 freeze file are committed and `sha256sum -c FREEZE.sha256` passes.

## Amendment 12: 19 Nov 2026 (new stage `eot`: end-of-trace accounting sensitivity S-EOT, PF-definition diagnostic D-PF, retransmission-rate diagnostic D-RS; before any of their runs on evaluation traces)
**Trigger.** The 8 Nov code review (code reading only) left three items open that the manuscript does not disclose:
- **End-of-trace accounting.** The HARQ drain completes packets without the deadline check, and unresolved packets leave the ratio. About 6–7 % of counted packets are exposed. The bias may favour aggressive schemes, and the ACK-trained learners are the more aggressive ones.
- **PF averaging at RTT 0.** Training uses ACK-time PF averaging, while the evaluation uses scheduling-time averaging (M2, M4).
- **Retransmission scheduled rate.** At RTT 8 the training-side PF scheduled rate on retransmissions can read the wrong HARQ process.

The tooling commit `17bf7d1` added `env.eot_mode`. Its default `'asrun'` is bit-identical to the frozen evaluators on calibration traces 60001–60020 (15 scheme × case pairs). No `'resolved'` value on any evaluation trace exists.

**What is added.** `S_EOT_PF_prereg.md` (new, frozen). No new analysis script: the frozen scripts are rerun unchanged in logic, and only path-only copies are allowed, with their diffs reported.
1. **S-EOT.**
   - Every frozen deadline comparison is re-scored on its stored traces under `'resolved'` accounting:
     - only packets with `dl ≤ T_end` count;
     - the deadline applies during the drain;
     - at RTT 0 there is one expiry step at `T + 1`.
   - Sets: NR2, M1, and the R1c cells G2 and G3.
   - A full `'asrun'` pass first must reproduce every stored per-trace value exactly. That pass also gives the exposure counters.
   - Wording rows: (a) "every frozen verdict is unchanged (largest shift x pp)"; (b) "the following verdicts change: …; both reported", which goes to the abstract if a headline comparison changes; (c) "not run".
2. **D-PF.** The stored M2 and M4 policies and comparators are re-evaluated under `pf_avg = 'scheduled'` (which must reproduce exactly) and `'acked'` (the training definition), using the frozen R1 and R2 rules.
   - Wording rows: (a) "verdicts unchanged", (b) "verdict changes to …", (c) "not run".
   - Under every row the mismatch is disclosed, and retraining goes to the revision round.
3. **D-RS.** On calibration traces only, the frequency and size of the retransmission scheduled-rate mismatch in the RTT 8 training loop. Descriptive; one limitation sentence.

**Multiplicity.** None. These are sensitivity analyses of existing comparisons: no case, no registry row, nothing added to the Bonferroni pool. Totals stay **106 / 182**.

**Compute.** About 1.8 h (S-EOT, two passes on 2 workers) + 1 h (D-PF) + 0.5 h (D-RS).

**Independence.** No evaluation data were opened. The writing session read `17bf7d1` (the diffs of `evalPolicy_g6_eot.m`, `evalPolicy_presub_eot.m` and the `_eot` helpers against their frozen originals) and `Optimized/v17x/Dataset/eot/eot_equiv.txt`.

**What is not changed.** All earlier frozen texts, scripts, results and verdicts stand as recorded. All earlier hashes are unchanged except `AMENDMENTS.md`, which gains this entry.

**Freeze v14:** hashes in `paper/proposals/FREEZE.sha256` (v13 kept as `FREEZE_v13.sha256`). S-EOT and D-PF may run on evaluation traces once this entry and the v14 freeze file are committed and `sha256sum -c FREEZE.sha256` passes 23/23.
