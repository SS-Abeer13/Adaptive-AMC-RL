# Conflicts found during evidence consolidation (Phase 1)

Each conflict below was resolved by source priority (raw summaries > README §6 / paper CSVs > registry > Project notes > top-level README). Severity: 🔴 changes what the paper may claim · 🟠 a number or wording fix · 🟢 cosmetic.

## A. Errors in the top-level `README.md` (prompt §2.4): status check

All five known errors are **still present** in `README.md` as of commit `8616a9a`. None has been fixed.

| # | README.md says | Raw evidence | Resolution |
|---|---|---|---|
| A1 🟠 | "Primary **single-seed** Deep A2C: +1.58 %" | `Deep A2C v17` = mean over 10 seeds (REPLSEED L114, 10 seed means) | Use "10-seed mean" |
| A2 🔴 | v15/v16 artefact explained as RL-specific ("RL transmitted higher-MCS packets … scheduler disproportionately grant[ed] it more slots") and "+37 % to +44 %" | README_v17 §1: Baseline alone rose 3.466 → 4.837 Mbps (RTT 8, 1 → 8 processes); the artefact inflated **every** scheme | Describe it as a scheduler artefact affecting all schemes |
| A3 🟠 | Replications listed as "v10 E4c, v13 X1, v14 Y0, v16 K2" | v13 X1 primary failed Claim B (README_v13 §7.2); E4c is exploratory | Use X2, Y0, K2, M2 (see multiplicity.md §4) |
| A4 🔴 | "selecting action 0 **>99 %** of the time" | ACT L293/L397: 92.3 % (M3), 76.3 % (M4), and these count all users per TTI (see C2) | Use 92 % / 76 % with the correct denominator, or better a re-cut (gaps G1) |
| A5 🔴 | Mechanism: "+1 offset, >85 % share during busy HARQ processes … conservative on retransmissions" | `table_action_by_state.csv`: the ≥3-busy bin holds only 8,150 decisions (1.3 %); retransmission actions are no-ops (`harqTransmit_v17.m` L27–31 reuses the stored MCS) | Do not state a mechanism from this table until it is re-cut |
| A6 🔴 | "**Definitive** WIN", "**firmly refutes**", "confirming the advantage is **structural**" | Wording not allowed by the pre-registrations (prompt rule 3) | Banned words list for the manuscript |

The repo README is not a paper source. Fixing it is optional housekeeping and was **not done** here, so as not to touch files outside `paper/` without your approval.

## B. Case-count conflicts

| # | Conflict | Resolution |
|---|---|---|
| B1 🟠 | README_v17 §6.2 and §6.8: "39 registered cases across v10–v17"; top-level README: 67 | 39 is the v10–v15 registry count carried over from README_v16 §2. Registry: v10–v17 = **49**, v9–v17 = **67** cases / **108** rows. Use 67/108 (multiplicity.md) |
| B2 🟢 | README_v17 §2.2: "78 data rows preserved"; §6.9 and release README: "90 rows"; file: 108 | Snapshots at different times (v16 → v17 → v9 rows added in commit `8616a9a`). The file is the truth: 108 |
| B3 🟢 | README_v16 §C7 "project total 35" vs its own §2 "39 unique cases" | Internal inconsistency in v16; superseded by the registry |
| B4 🟢 | Registry gives `n_seeds = 10` for the M3 offset-800 row; v17_setup `n_seeds_a2c_offset = 5` for M3; REPLSEED L358 shows 5 seeds + 5 NaN | 5 seeds. Registry field wrong for that row |

## C. Conflicts that change what may be claimed

| # | Conflict | Evidence | Consequence |
|---|---|---|---|
| C1 🔴 | `v17/paper/figures/margin_vs_rtt.*` is captioned as a v17 result | `generate_v17_figures.m` L67–70 hard-codes v16 K1/K2/K3/K4 and v15 Z2 values (K1 −1.94 %, superseded) and labels two of them "v17" | ⛔ Never use. Rebuild from `table_harq_ablation.csv` |
| C2 🔴 | "δ = 0 in 92 % / 76 % of decisions" (prompt §2.2, README_v17 §6.7) | `runComparison_v17.m` L330–332 accumulates `act(b0+1:end, :)` over **all N = 10 users** every TTI. PF serves one user per TTI, so about 90 % of counted "decisions" have no effect. M3: all 10 seed means are **identical** to FixedPU to 4 decimals (SEEDS L290), so on effective decisions the greedy policy is (almost) always δ = 0 | Report as "the policy is behaviourally identical to its base rule (identical goodput on all 500 traces for all 10 seeds)". Drop the 92 % figure or restate its denominator. Same caveat for the M1/M2 histograms and the `acthist_*` figures |
| C3 🔴 | Prompt §2.4 says `table_action_by_state.csv` "includes unscheduled users" | `diag_action_by_state_v17.m` uses `sch_log`, which logs **only scheduled users** after burn-in (`evalPolicy_v17.m` L489–501). The real flaw is different: the slack and busy-process bins **mix in retransmissions**, where δ is a no-op. The "retransmission conservatism" finding (README_v17 §6.7 item 1) describes actions with no effect | Re-cut to scheduled **new** transmissions only (gaps G1). Drop finding 1 |
| C4 🔴 | Proposed contribution 2: "the open-loop mapping beats OLLA at a 10 % target" | True in v9 gp_O (+4.5 %, L9–10) and v16 K4 (Baseline 2.8768 vs OLLA 2.7249). **Reversed in v17**: OLLA beats Baseline by +7.4 % (M3) and +6.9 % (M4) | The claim is PF-definition dependent. It cannot be a contribution unless stated as such (see C5) |
| C5 🔴 | Registry marks every pre-v17 RTT-0 case "valid". README_v17 says M2 replicates "under the corrected PF" | Pre-v17 engines update the PF average with **delivered** bits (`evalPolicy_v9.m` L212, `evalPolicy_v16.m` L526: `ema*tpr`), so a NACKed user's average does not rise. v17 uses the **scheduled** rate. README_v17 §2.1 shows this changes Baseline goodput by +10 % even at RTT 0 (3.2941 → 3.6293, legacy engine) | v9–v16 RTT-0 results are internally valid but use a **different PF definition**. v13 X2, v14 Y0 and v16 K2 are replications of the *direction* of the effect under another scheduler variant, not exact replications. The paper should state this. It is arguably a strength: the RTT-0 effect holds under both PF variants |
| C6 🟠 | v14 "shaping helps" as a mechanism for the win | Y0_noshape (unshaped) also met WIN (+0.21 % vs Fixed, registry case 50); shaping adds +0.23 % (paired) | Shaping improves the margin but is not necessary for the RTT-0 win. Word it that way |
| C7 🟠 | v13 X1 per-seed-mean row in the registry shows `win = 1` | README_v13 §4: the pre-registered primary scheme was the ensemble (failed) | Note in the registry supplement: "not the pre-registered scheme" |
| C8 🟠 | Prompt §2.1 v10: slot-stealing policy "bimodal −4/+2, ~1.4 vs 2.8 Mbps" | `matlab_v10b_check.log` L17: 58 % at −3, 35.8 % at +2 (actions −4…+2). Campaign E1_train: A2C 1.38 vs OLLA 2.92 Mbps (v9 A2C was 2.80) | Use "−3/+2", 1.38 vs 2.92 |
| C9 🟠 | Prompt §2.1 v9: "open-loop Baseline beats OLLA-10 % by about 5 %" | v9 gp_O: 3.0554 vs 2.9233 = +4.5 % | Use +4.5 % (and see C4) |
| C10 🟢 | README_v17 §3.1 OLLA "step 0.1/0.9" | `defaultEnv_v17.m` L100–101: target 0.10, down-step 0.5 dB → up-step 0.5·0.1/0.9 ≈ 0.056 dB | Describe as 10 % target, Δdown = 0.5 dB |
| C11 🟢 | Prompt §2.2 calls FixedPU a "per-class oracle table" | FixedPU uses the true speed/delay class (hence "Oracle"). It is the **base rule** of the residual A2C in all four v17 cases (BASE_RULE lines) | Define clearly. Note that residual A2C at δ = 0 *is* FixedPU, which is why M3 equals FixedPU exactly |
| C12 🟢 | README_v17 §6.8 training-length sentence uses margins vs the best rule (+0.34 → +1.58); `table_training_length.csv` uses margins vs Fixed (+0.62 → +1.87) | Both correct, different comparators | Pick one in the paper (recommend vs best rule = Context) and say which |
| C13 🟢 | README_v17 §6.9: table_core includes "TOST equivalences" | `table_core.csv` has no TOST column (TOST only appears in CMP lines) | Minor; TOST is available from CMP lines if needed |

## D. Unverifiable here

- Project notes `claude/amc_*` (priority 4) are in the claude.ai Project, not in this repo. I could not open them. Claims sourced only from them: none in the ledger. The E4c fresh-only numbers come from README_v12 §1, which cites that note.
- `papers/v8_draft/AMC_full_paper_v8_rev1_source.md` has not been read yet. It is reserved for Phase 2 (system-model notation and reference candidates).

## E. Citation errors found in Phase 2 (literature)

| # | Where | Error | Resolution |
|---|---|---|---|
| E1 🟠 | `Optimized/v17/evalPolicy_v17.m` L4 (and earlier versions): "Multi-OLLA … (arXiv:2604.20459)" | Ahsen et al. 2026 is a **rank-dependent** multi-offset OLLA. Our Multi-OLLA is a fast/slow integrator blend, a different method | In the paper, describe our Multi-OLLA on its own terms. Cite Ahsen et al. only as "multi-offset OLLA variants exist". The code comment is left untouched (frozen code); noted here |
| E2 🟠 | v8 draft ref [2] | Pedersen 2007 DOI 10.1109/VETECF.2007.380 points to a different paper | Correct DOI: 10.1109/vetecf.2007.378 |
| E3 🟢 | v8 draft ref [8] | Dahlman book DOI not registered | Do not cite with that DOI |
| E4 🟢 | prompt §4.1 | "Ahsen et al. (IEEE OJ-COMS)" | **Corrected in Phase 3:** the OJ-COMS version exists (2026, DOI 10.1109/ojcoms.2026.3714148). My Checkpoint-2 verdict was wrong |
| E5 🟢 | prompt §4.1 | "Park 2015" | It is a GLOBECOM 2015 paper, not a letter |

## F. Phase 6 finding (outline drafting)

| # | Where | Error | Resolution |
|---|---|---|---|
| F1 🟠 | My Phase 1–5 documents (gap_analysis, venue_decision, outline draft) and the prompt's §2.1 summary: "PF-average timing inflated every scheme by about 40–50 %" | The single-factor diagnostic (6 traces, Baseline, 8 vs 1 process) gives +39.6 %. The full v16 K3 vs v17 M3 re-run shows all 13 schemes higher by 10–26 %, but that comparison is confounded (different traces/seeds, plus drain and useful-bit accounting added in v17) | Quote "+39.6 % (Baseline, 6-trace diagnostic)" and "10–26 % across schemes (confounded)" with ledger H17 and H17a. Never "40 % for every scheme". Corrected in outline.md, gap_analysis.md, venue_decision.md, reviewer_attacks.md |

## G. Checkpoint-5 review of commit `1aae150` (8 Nov 2026)

The manuscript edits made on the PC in `1aae150` were reviewed line by line against the stage outputs. From this date only one writer edits `paper/`.

| # | Where | Error | Resolution |
|---|---|---|---|
| G1 🔴 | `Optimized/v17x/Dataset/fill_summary_v17b_cal.txt` (`CLAIMS … seed_robust=1`, `VERDICT`, `WORDING`); `pending_values.csv` G6 verdict `ABJ`; abstract, C2, results | `seed_robust` was computed against **Context-500 only**. R2 and G6 §3 require it for the best comparator of each claim; for JP that is Context-joint-500: 5/10 seeds above 0, hierarchical 95 % CI [−0.30, +1.70] % (`paper/analysis/g6_seed_stats.py`). The margin over the combined table is **not robust to seed resampling** | Generated file not edited. Verdict set to `ABJ-seed` (G6 §4 row 2, now defined in `wording.tex`); "same-information" only with the qualifier; `check_pending.py --final` fails if the verdict and R2 disagree. Ledger G6b, G6e |
| G2 🟠 | Ledger G6d, STATUS, discussion: "closes about 60 % (+1.64 % → +0.66 %)" | +1.64 % has no source; the v17 margin over the Context table is +1.58 % (R03, `table_core.csv`) | 1 − 0.66/1.58 = 58 % (macro `\NGsixClosure`) |
| G3 🟠 | Results/abstract-level text: A1 margins "vs Context table" | Comparator not named: it is the **v17 Context table (10-trace calibration)**, not Context-500. CIs had no script behind them | `paper/analysis/a1_speed_stats.py` reproduces the margins and the PC's CIs (hierarchical seed × trace, 95 %); comparator named; slow-user loss reported in the abstract and limitations |
| G4 🟠 | Results: NR1 vs Context-joint-500 "+2.44 % … Wilcoxon p" | No source file | `paper/analysis/nr1_g6_compare.py` reproduces it (secondary, descriptive, trace level). NR1 has **no seed-level inference** (per-seed values not saved by `stage_nr1.m`); NR2 must save them |
| G5 🟠 | Pitfalls (A6): "proving that the apparent multi-process HARQ gain was entirely an artefact" | Overclaim; the frozen A6 wording is "the timing of the PF average, not HARQ itself, accounts for the apparent gain in this diagnostic" | Frozen A6 wording used |
| G6 🟠 | Results (G1, A1), discussion: "the agent aggressively shifts MCS to protect expiring packets"; "rapid Doppler shifts … undermine static lookup rules"; "the optimal offset depends jointly on …" | Mechanism stated as fact; G1/A1 are descriptive | Rephrased as "consistent with" |
| G7 🟠 | Abstract, discussion, results: hard-coded numbers (0.66, 1.05e-3, 60 %, −0.88, 0.6126, CIs, 200, 500, 10–20 …) | Violates the macro rule (every number from `numbers.tex`) | All routed through macros; `check_pending.py --final` fails on literal numbers in main/intro/results/discussion |
| G8 🟠 | Conclusion: "genuine gains", "paramount", "Crucially" | Wording rules (outline) | Rewritten |
| G9 🟠 | Intro ¶1: "improvements ranging from 10 % to over 100 %" | Not traceable to a ledger row; outline flagged it as a literature claim | Removed; replaced by a qualitative statement |
| G10 🟢 | Abstract: "registry of 67 cases and 108 evaluations" | The v17x stages are not yet in `case_registry.csv` (R7) | Open item REG1; counts update when the rows are added |
| G11 🟢 | Results (G6): "an exhaustive coordinate-ascent search" | Coordinate ascent is not exhaustive (exhaustive search applies to the single-cue rules) | Corrected |
| G12 🟢 | Hierarchical CI vs Context-500: MATLAB [+0.46, +2.47] %, python [+0.47, +2.46] % | Bootstrap Monte-Carlo difference (different RNG streams) | The python value (same estimator and RNG as G3) is used in the text; both recorded in G6b |

## H. Audit of draft v1 against award-paper criteria (8 Nov 2026, evening)

Reference papers: Björnson & Sanguinetti (OJ-COMS 2020; ComSoc Outstanding Paper Award 2023), Di Renzo et al. (OJ-COMS 2020; same award 2022), Agarwal et al. (NeurIPS 2021 Outstanding Paper), Ferrari Dacrema et al. (RecSys 2019 Best Paper). Full report: `paper/ledger/audit_2026-11-08.md`.

| # | Where | Error | Resolution |
|---|---|---|---|
| H1 🔴 | `pending_values.csv` G6 `cap_hit = no` (source given as `cal500_tables.txt`, which has no cap information); Appendix C "no start reached the cap" | Start S3 reached the 6-sweep cap still improving (heartbeat log); G6 §2 requires a capped start to be reported | Value set to `yes` with the log as source; appendix and results report it; `build_numbers.py` now fails if the log shows a capped start and the value says `no`. Ledger G6h |
| H2 🔴 | Discussion: "each step is cheap compared with training ten deep policies"; Cost: "a table search that needs no gradient steps" | The combined-table search took 24.6 h of simulation against 2.7 h to train and evaluate the ten M1 policies | Rewritten with the measured budgets; tuning budgets reported for comparators (Ferrari Dacrema lesson) |
| H3 🔴 | Protocol (multiplicity): project-wide Bonferroni reported only for M1 vs the best v17 rule | Applied to the G6 combined-table comparison it gives p = 1.00 | Added to protocol, results and abstract ("does not survive correction over all tests in the project"). Ledger M07 |
| H4 🟠 | Results (headroom): "margin of 0.95 points … small against these bounds" | Compares percentage points with relative-percent bounds | Compared on the same scale (margin over Fixed vs bound over Fixed); noted that the per-trace bound can be exceeded by an adaptive policy |
| H5 🟠 | Protocol: "Rule R2", "Claim B-500", "joint parity" and the margin/CI definitions used but never defined | — | Margin, pp vs %, t-interval, R1 and R2 defined in V-D; Claim B-500 and joint parity defined in VI-G |
| H6 🟠 | Protocol: "we froze eight pre-registrations before any further run"; Table IV caption "frozen before any of these stages ran" | NR2 was added after the other results | Corrected (seven, plus NR2 by amendment) |
| H7 🟠 | Fig. 4 showed per-seed margins only against the v17 Context table (9/10 seeds) | Hid the R2 failure against the combined table (5/10) | Middle row added; caption updated (Agarwal: show the distribution over runs) |
| H8 🟢 | Abstract, method: internal version labels ("v17 Context table", "pre-registered from v14") | Undefined jargon | "v17 rules" defined once in V-A; abstract and method reworded |
| H9 🟢 | Results: "Section VI-G" written as `\ref{sec:results}-G` in the protocol | — | `\ref{sec:robust}` |
| H10 🟢 | Integers ≥ 10,000 printed without separators (587016) | IEEE style | thin-space separators in `build_pending.py` |
| H11 🟢 | Conclusion "rarely, and by little" | Vague; award papers state conditions | Rewritten as three explicit conditions |

## I. NR-G10 integration (11 Nov 2026)

- **I1. G10 runner vs Amendment 2.** Amendment 2 (5 Nov) chose option (b): single-cue rules only in G10, "no combined-comparator code". `Optimized/v17x/stage_g10.m` nevertheless contains `run_cell_combined_search` since commit c1a5acb (5 Nov) and evaluated a per-cell combined table (`Context-joint`; 200 calibration traces, 4 starts, up to 6 sweeps, sparse threshold 80, i.e. a lighter search than G6 at M1). It was not in the pre-registered G10 family (9 comparators, Holm over 9) and did not enter the G10 or NR-G10 verdicts. **Resolution:** reported in the paper only as a descriptive, not pre-registered comparison (`paper/analysis/nr_g10_ctxj_descriptive.py`), paired per trace with NR-G10 (same traces and CRN; pairing check: the nine shared comparators are bit-identical). The verdicts are unchanged.
- **I2. Bootstrap reproduction.** The Python hierarchical bootstrap (rng 20261104, B = 20000) reproduces the stored MATLAB R2 intervals of NR-G10 vs the Context table to Monte-Carlo precision: G2 [0.86, 2.72] vs stored [0.90, 2.73]; G3 [0.63, 1.40] vs stored [0.63, 1.42]. The paper uses the stored (MATLAB) values for the pre-registered R2 and the Python values for the descriptive comparison.
- **I3. Latency text.** The A3 laptop figures in Sections III and VIII were loop means, not medians, and supported the claim "this is small". Per the author's instruction (11 Nov 2026) wall-clock latency is withheld until A3c (medians and noise-floor-corrected tails only; no real-time feasibility claim, none at 120 kHz); the hardware-independent cost (19,872 MACs, 40,195 FLOPs per user decision) is used instead. The A3 macros remain in numbers.tex but are no longer used in the text.
