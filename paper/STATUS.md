# Paper status

**Branch:** `claude/magical-heisenberg-iek5sg` (session branch), mirrored to `paper-draft` (push access confirmed 4 Nov 2026).
**Current phase:** 3 (venue research) complete. **Waiting at Checkpoint 3.**

## Checkpoint 1: approved 4 Nov 2026, with conditions. Status of each condition

| Condition | Done | Where |
|---|---|---|
| 67 cases / 108 evaluations; both views (67 project-wide, 7 cases / 18 evaluations superseded; 49 from v10) | ✅ | ledger M06; multiplicity.md §6 draft paragraph |
| M1 project-wide Bonferroni (8.8e-10 over 972) in the multiplicity paragraph | ✅ | multiplicity.md §6 |
| M2 strictly a replication | ✅ | ledger R16, G3e, M05 |
| X1: `correction` column, no overwrite; corrected verdict used everywhere | ✅ | `Optimized/case_registry.csv` (+2 copies, + builder); ledger H13, M03 (9 valid WIN cases) |
| Drop "open-loop beats OLLA" as a contribution; keep it as a pitfalls example | ✅ | ledger H05 |
| "Both PF variants" limited to the RTT-0 deadline wins; v15/v16 RTT > 0 never cited as support | ✅ | ledger S08b, H17 |
| Verify that pre-v17 RTT-0 runs used the delivered-bits PF update; log file and line | ✅ | ledger S08a (v9, v13, v14, v16; eval and training) |
| Goodput negative result from v17 M3/M4 only | ✅ | ledger H04 |
| Withhold 92 %/76 % and the action-by-state table | ✅ | ledger R23, R24 → NOT USABLE |
| Define "M3 matches FixedPU exactly" | ✅ | ledger R19a: bit-identical goodput, cell throughput, Jain, edge5 in 5000/5000 seed × trace cells; M4 is **not** identical |
| G1 MATLAB script + spec | ✅ | `Optimized/v17/g1/`, `paper/analysis/G1_SPEC.md` (the existing logs are insufficient; instrumented re-evaluation, no training) |
| README fixes as a separate commit with ledger IDs | ✅ | commit `7d085c9` (README.md, README_v17 + release, registry, figure script) |
| `margin_vs_rtt` script reads only v17 CSVs; image marked "do not use" | ✅ | `generate_v17_figures.m`; asset_inventory.md |
| G3 now (sign test, seed t-test, hierarchical bootstrap) | ✅ | `paper/analysis/g3_seed_stats.py`, `out/g3_seed_stats.csv`; ledger G3a–G3f |
| G6, G10 pre-registration proposals | ✅ | `paper/proposals/` |
| Triage of the other gaps | ✅ | gaps.md (Triage) |

## Author actions pending (on the PC)
1. Run `addpath('g1'); g1_recut_v17` in `Optimized\v17` (≈ 20–60 min). Send back `paper/g1/g1_summary.txt` and `g1_action_by_state.csv`.
2. Run `generate_v17_figures` to regenerate `margin_vs_rtt`.
3. Decide on G6 and G10 at Checkpoint 5 (≈ 3–6 h and ≈ 4.5 h compute).

## Notes
- G3 changes two earlier statements. The M1 resid-800 "win" does not survive seed resampling, and M2 vs the Context table has a hierarchical 95 % CI that includes 0. Both are now in the ledger.

## Phase 2 (literature): done
- `paper/lit/bibliography.bib`: 84 entries, all verified (Crossref DOI record, arXiv API, or a named publisher page; see `verification_report.csv`).
- `paper/lit/lit_matrix.csv`: 84 rows; detailed fields for the LA papers.
- `paper/lit/gap_analysis.md`: novelty position + top 30.
- `paper/lit/candidates_audit.md`: named candidates and the v8 reference list (2 wrong DOIs, 1 mis-attribution).
- `paper/lit/search_log.md` + `search_raw/`; tools in `paper/lit/tools/`.

## Checkpoint 2: approved 4 Nov 2026
- Framing: evaluation-led hybrid. Thesis recorded in `lit/gap_analysis.md` §9 item 0. LOLLA positioned respectfully (§5). "Hype or Hope?" used as an anchor, not as the paper's identity (§2, §8).
- Literature counts added (`lit_matrix.csv` columns `calibrated_rule_baseline`, `information_parity`): 23 learning-LA papers; none with a calibrated same-information baseline.

## Phase 3 (venue): done
- `venue/venue_research.md`: policies from official pages, recent papers per venue, blocked sources listed.
- `venue/exemplar_template.md`: 7 exemplars (TMLCN, OJ-COMS) and our section and page template.
- `venue/venue_decision.md`: weighted matrix. **Primary TMLCN (63/75), backup OJ-COMS (58), backup TVT (43); TWC stretch; letter spin-off not advised before the main paper.**
- Bibliography: 98 verified entries. Corrections: Ahsen → OJ-COMS 2026; Doherty → JOCN 2025 (5 authors); LOLLA arXiv v1.

## Open questions for Checkpoint 3
1. Choose the primary venue and backups (recommended: TMLCN; OJ-COMS; TVT).
2. TWC as primary instead (prestige, 13-page limit, method-novelty bar)?
3. Letter spin-off: fold into the main paper (recommended), or plan it for after acceptance?

## Checkpoint 3: approved 4 Nov 2026
Venue order **TMLCN → OJ-COMS → TVT** (or OJVT if TVT's submission cap is under 14 pages). TWC is not primary; revisit only if G6 and G10 are both strongly positive. TMLCN items confirmed in `venue/venue_decision.md`.

## Future work (not before the main paper is accepted)
- A pitfalls letter (e.g. WCL) **only** if it adds substantial new material, such as a general simulation-pitfall checklist validated on a second simulator or on published third-party code. Until then the pitfalls stay in the main paper only.

## Phase 4 (framing and contributions): done. **Waiting at Checkpoint 4.**
- `design/framing.md`: options A/B/C, chosen hybrid C, title options, the "same-information" precision, page budget (~15 pp main).
- `design/contributions.md`: C1–C5 with ledger IDs, novelty paragraph, corrective-history placement.
- `design/reviewer_attacks.md`: 24 criticisms with answers (R/L/P).

## Checkpoint 4: approved 4 Nov 2026
- Title: *When Does Deep Reinforcement Learning Help Link Adaptation? A Pre-Registered Evaluation Against Calibrated Rules.*
- Four contributions: C1 protocol + artefacts; C2 the positive case (wording conditional on G6); C3 where RL does not help; C4 pitfalls + recommendations.
- Wording "calibrated rules built on the learner's cues" until G6; information table added (`design/information_table.md`); FixedPU called a class oracle (attack #25).
- Length 13–15 pp; backups OJ-COMS → OJVT (TVT only if ≥ 14 pp at submission). Checklist: `manuscript/submission_checklist.md` (arXiv notice, AI disclosure).
- Campaign check: a non-oracle (Fixed) base was used in v13 X2, v14 Y0/Y0_noshape and v16 K2 (all RTT-0 WINs, older PF). There was none at RTT 8 under v17, so NR1 is proposed.

## Phase 5 (evidence gap check): done (approved at Checkpoint 5, see below)
- `proposals/checkpoint5_list.md`: consolidated list, classes, compute, prompts.
- Pre-registrations: G6 (revised: 500-trace re-calibration + combined comparator, decision rule for C2), W1 (warm-up), NR1 (non-oracle residual), G10 (compute + prompt). Compute basis: `proposals/compute_basis.md`.

## Checkpoint 5: approved 4 Nov 2026, with changes; pre-registrations FROZEN (v1; amended by v2 below)
**Freeze commit:** `0726555fb7dda0190e780406828f785903d98f30` (branch `claude/magical-heisenberg-iek5sg`, mirrored to `paper-draft`). File hashes (SHA-256) in `paper/proposals/FREEZE.sha256`; verify with `cd paper/proposals && sha256sum -c FREEZE.sha256`.

| File | SHA-256 |
|---|---|
| `G6_calibration_budget_prereg.md` | `058bac584c2811767884df00c186c2f3c5747a1d4d137f88672a1303de985591` |
| `W1_warmup_prereg.md` | `3a69b7d023c601f8c221ca03b4ec60b67d2953c2855c23878683ddf8330f1b5d` |
| `NR1_nonoracle_residual_prereg.md` | `ed4e5e38faadf9ee7ecff10fa0c65367413aaa91526efec9c720d780716f0258` |
| `G10_operating_grid_prereg.md` | `e2150c50bac6e04f0e202e2c8a4d13165593c1d9472c72c48405903b691f9200` |
| `common_rules.md` | `360e2f268937853203a054a588b33d3e4e66c5d486fc14eeba24f62298ce68fa` |
| `checkpoint5_list.md` | `a54a30a728b8056bf5a8a38b9b95b8a4fbe1d3a993c01addbf52669c2bbcd93a` |
| `compute_basis.md` | `d72e7a0f64506fe278ed319bc0bbe74d564de0cf1a27c3543311acd226fade0a` |

Changes applied before freezing: (1) G6 uses exhaustive search for Fixed, Context and OLLA; FixedPU keeps its separable grid plus a joint refinement (the v17 FixedPU was separable and never evaluated jointly); coordinate ascent only for the 36-cell combined table (composite init, 3 random restarts, run to convergence, sanity check, calibration-vs-evaluation reporting). (2) W1: the abstract quotes the smaller gain over the OLLA family; Baseline footnote. (3) G10: every comparator re-calibrated per cell, base rule recorded with oracle flag, wording rows fixed. NR1 wording rows fixed. Seed-level rule R2 added (`common_rules.md`).
**Run list approved:** G1 → W1 → G6 → NR1 → G10 → A1/A3; A2, A4, A5 need no runs; A6 recommended; SALAD and a second simulator stay future work.
**Compute (upper-bound basis):** G6 ≈ 41 h expected (30–76 h), G10 ≈ 70 h for four cells (≈ 17 h per cell), the whole programme ≈ 115 h. Levers pre-registered before any result: measured preflight rate, `G6B_PROFILE=lite`, `G10_CELLS`.

## Checkpoint 5b / 6: approved 4 Nov 2026; FREEZE v2 (amendment 1, before any run)
**Freeze v2 commit:** `e12757480d30744f2954c90c043c03c62393fad1`. Hashes: `paper/proposals/FREEZE.sha256` (v2) and `FREEZE_v1.sha256` (v1, kept for history; it fails for exactly the four files amended). Record of changes: `paper/proposals/AMENDMENTS.md`. Verify: `cd paper/proposals && sha256sum -c FREEZE.sha256`.

| File (v2) | SHA-256 |
|---|---|
| `G6_calibration_budget_prereg.md` | `c629332df0eb98086d201a61505758716bfde5dbfc3dd33175d1d24bad5b8bbd` |
| `G10_operating_grid_prereg.md` | `9963d10a9050151374e4ffed5c9703b40096657eb6d6abddc2d5cad57858e203` |
| `A6_pf_timing_prereg.md` (new) | `35ffa58f563c5e184b5429acafcdbbcb4fa92f78d1ee4970c2609af4dca1a8d8` |
| `common_rules.md` | `f8382b866c5b51131d4185f4fe2920efabe46b6f7ed81963ec5759472fed664f` |
| `checkpoint5_list.md` | `b7eda3b784d9f653cbb26f567fac53dd122d74c46a85b479d019101a9ddc117c` |
| `W1_warmup_prereg.md` (unchanged) | `3a69b7d023c601f8c221ca03b4ec60b67d2953c2855c23878683ddf8330f1b5d` |
| `NR1_nonoracle_residual_prereg.md` (unchanged) | `ed4e5e38faadf9ee7ecff10fa0c65367413aaa91526efec9c720d780716f0258` |
| `compute_basis.md` (unchanged) | `d72e7a0f64506fe278ed319bc0bbe74d564de0cf1a27c3543311acd226fade0a` |
| `AMENDMENTS.md` (new) | `9b05af785eb8cf6ec9a034ec6a9e39b10de1fdedf1ca592cc5c2a72ee8f21055` |

Decisions recorded: **G6 runs the full profile** (lite differs in 100 vs 500 calibration traces per candidate in the restart phase and in polishing only two starts; it is defined but not used). **G10 runs two cells, G2_hi_d10 and G3_lo_d18** (opposite corners; G3 is where calibrated rules were strongest in the old grid); G1_lo_d10 and G4_hi_d18 are future work, decided now. G10 uses the full profile (lite lowers calibration traces per candidate) with 200 calibration traces per cell, a stated difference from G6's 500. Composite fallback table defined in G6 §2.3. Report point after `g6a` (R9). **Run order: G1 → W1 → NR1 → G6 → G10 → A1/A3 → A6.** A6 got its own frozen text. Expected programme length ≈ 80 h (≈ 3.3 days). **Do not launch the batch: the stages are stubs;** Claude Code on the PC implements them (master prompt, `Optimized/v17x/README_v17x_runner.md`) and stops if a frozen spec would need to change.
Checkpoint 6 conditions: 13–15 pages including references, about 8 figures and 5 tables, information table in the main text, the Protocol section states the three calibration findings (ledger S18, S19, S20), seed-level CIs in VI-B.

## G3 (seed-level statistics), reported at Phase 6
M1 primary vs Context: 9/10 seeds above 0 (sign p = 0.0107); 95 % CIs: bootstrap over seed means [+0.72, +2.53] %, t [+0.48, +2.68] %, hierarchical [+0.62, +2.62] %. Vs Fixed: [+1.01, +2.81], [+0.77, +2.98], [+0.89, +2.90] %. All lower bounds > 0 → no qualifier on C2 (ledger G3a, G3g, G3h). M2 vs Context: lower bounds −0.02 / +0.06 / −0.03 → replication only (G3i).

## Runner and placeholders (infrastructure, not part of the freeze)
- `Optimized/v17x/`: `run_v17x_all.bat` + MATLAB orchestrator, checkpoints, heartbeat, preflight with the 1.5× rule, error markers, `README_v17x_runner.md` (stage interface and the master prompt for Claude Code). Tested under Octave 8 (restart, halt, pause logic); **the .bat and MATLAB-only parts are untested here**; run the self-test first.
- `paper/manuscript/pending.tex` etc.: tagged placeholder macros (`\Gsix{...}` etc.), 62-key manifest, wording variants, build and check scripts, 12 passing tests with pdflatex.

## Phase 6 (outline): done (updated at Checkpoint 5). **Waiting at Checkpoint 6.**
- `design/outline.md`: section plan (≈ 14.5 pp incl. references + ≈ 2 pp appendices), per-section content with ledger IDs, OJ-COMS/OJVT portability, defaults for each pending run.
- `design/figure_table_plan.md`: 8 figures, 5 tables, 3 appendix tables; sources, scripts, style rules. New item **A6** (PF-timing demonstration, ≈ 3 min, no training) so the pitfall figure rests on one controlled comparison.
- `design/claims_map.csv` (+ `build_claims_map.py`): 39 rows; **88 of 91 ledger claims placed**, 3 deliberately unused (R23, R24 withheld until G1; H12 pre-v17). The script fails if a withdrawn, superseded or not-usable claim appears outside Section VII.
- `design/glossary.md`: terminology and notation (v8 symbols reused).
- Correction found while drafting: the PF-artefact size. Baseline +39.6 % in the 6-trace diagnostic; 10–26 % across all 13 schemes in the v16-vs-v17 re-run (confounded). "≈ 40 % for every scheme" removed everywhere (ledger H17a, conflicts F1).
- LaTeX is now installed in the container (`texlive-latex-base`, `-recommended`, `-publishers` incl. IEEEtran, `-fonts-recommended`); matplotlib via pip. Octave 8 is installed for testing the runner logic.

## Open questions for Checkpoint 6
1. Approve the section plan and page budget (≈ 14.5 pp + appendices).
2. Approve the 8 + 5 float plan (F6/F7 appear only if their runs are done).
3. Approve A6 as an addition to the run list.
4. Decide the launch profile before any run: `G6B_PROFILE` (full ≈ 41 h | lite ≈ 25 h) and `G10_CELLS` (four cells ≈ 70 h | two cells ≈ 35 h). Both are pre-registered, and the choice is made before any result.

## Next step
Phase 7 (drafting) after Checkpoint 6: numbers macros, figures from repo data, section drafts in the order system model → protocol → results → pitfalls → methods → related work → discussion → introduction → abstract → conclusion.

## Phase 7 — draft v0 (4 Nov 2026)
- Built `paper/manuscript/main.tex` (IEEEtran) with `sec_*.tex`, `numbers.tex` (772 macros generated by `build_numbers.py`; each traces to a source file in `numbers_audit.csv`; simulator constants are checked against the code), `refs.bib` (verification notes stripped), figures F1/F3/F4/F5 (`paper/figures_src/`, vector PDF) and F2 in TikZ.
- Drafted: Related work (T1), System model (T3, F2), Method, Protocol (T2, the three calibration findings, composite definition), Results VI-A to VI-F (G3 seed-level numbers), Pitfalls and recommendations. Placeholders: abstract, introduction, discussion, conclusion, VI-G (W1/G6/NR1/G10), VI-H (G1).
- Build: 8 pages, no LaTeX errors or undefined references. `check_pending.py` (non-final) passes; unresolved placeholders: G6:verdict, NR:verdict, G10:verdict (defaults in use).
- Next: review v0, then draft the placeholder sections; runs on the author's PC per the master prompt.

## Amendment 2 / FREEZE v3 (5 Nov 2026)
- G10 no longer runs the combined comparator (compute, about 100 h extra at two cells); it is tested at the M1 point only (G6). G10 compares against single-cue rules re-calibrated per cell (200 traces); family of 9, WIN = beats all 9. Options (a), (b), (c) and the reasoning are in `paper/proposals/AMENDMENTS.md`.
- Freeze v3 commit: `d08807f425a6cfa4b07fbebf6a2b3485216cbf98`. Changed: G10, checkpoint5_list, AMENDMENTS; G6, W1, NR1, A6, common_rules, compute_basis hashes unchanged from v2 (v2 hashes kept in `FREEZE_v2.sha256`). No G6 output had been read.

## Phase 8 — Checkpoint-5 Stage Completions (8 Nov 2026)
- **Completed stages:** G1, W1, NR1, G6 (g6a, g6b, g6c), A1, A3, A6 all finished cleanly and verified against pre-registered gates (commit `0386055`).
- **G6c (re-calibration on 500 traces & combined table):**
  - Residual A2C (M1 primary) beats all 10 comparators at trace level: vs Context-joint-500 $+0.66$\,\% [0.29, 1.03]\,\% (Holm $p = 1.05\times 10^{-3}$); vs Context-500 $+1.43$\,\%; vs Fixed-500 $+1.87$\,\%; vs FixedPU-500 $+2.70$\,\%; vs OLLA-tuned-500 $+8.40$\,\%.
  - Claims A, B-500, and JP all pass (`verdict = ABJ`).
  - Frozen C2 wording applied: *"beats all calibrated comparators, including rules re-calibrated by exhaustive search on 500 fresh traces and a table that combines deadline slack, user class and HARQ-process state"*, with *"same-information"*.
  - Seed-level statistics vs Context-joint-500: 5/10 seeds above 0 (sign-test $p = 0.623$), seed-mean bootstrap 95\,\% CI [$-0.19, +1.60$]\,\%, hierarchical seed $\times$ trace 95\,\% CI [$-0.30, +1.70$]\,\%. Rule~R2 applies: not robust to seed resampling vs the combined table (vs Context-500 hier 95\,\% CI is [$+0.46, +2.47$]\,\%, seed-robust).
  - Margin closure: exhaustive 500-trace calibration closes about 60\,\% of the v17 margin over the best rule (+1.64\,\% down to +0.66\,\%).
  - Calibration vs evaluation scores: combined table 0.6088 vs 0.6086, Context-500 0.5982 vs 0.6040 (no empirical overfitting).
- **W1 (OLLA warm-up):** 200-TTI warm-up margin over OLLA is $+7.49$\,\% [$6.79, 8.19$]\,\% (cold: $+11.96$\,\%); vs Context table $+1.75$\,\% [$1.41, 2.10$]\,\% (Claim B passes).
- **NR1 (non-oracle base rule):** Fixed base rule (offset $-2$) achieves 0.6235 on-time, beating all 9 comparators (WIN; $+3.38$\,\% vs Context table). Diff vs M1 oracle-base $+1.09$\,pp ($+1.77$\,\%, $p = 2.03\times 10^{-31}$). Descriptive paired margin vs Context-joint-500 $+2.44$\,\% [$2.04, 2.85$]\,\% ($p = 1.48\times 10^{-19}$).
- **A1 (speed classes):** low ($<10$~m/s) $-1.71$\,\%, mid ($10$--$20$~m/s) $+2.82$\,\%, high ($>20$~m/s) $+2.25$\,\% vs Context table.
- **A3 (inference cost):** 2.03~$\mu$s loop (9.01~$\mu$s median forward pass) per decision on Intel Core i5-8350U CPU @ 1.70GHz; 830.3~$\mu$s per 200-TTI trace (10 users, $2.40\times$ FixedPU).
- **A6 (PF-timing demonstration):** Expectation E holds for all 3 schemes; 8-to-1 process goodput ratio is 1.447 (Jain 0.436) under ACK-time PF, and 0.976 (Jain 0.498) under scheduling-time PF.
- **G10 status:** Launching now, expected to complete in $\approx 32$~h.
- **Manuscript:** `numbers.tex` (772 macros), `pending_values.csv` (54 values), `pending_status.csv` (8 items), abstract, introduction, discussion, conclusions, and robustness/policy subsections updated. Ready for PDF compilation.
