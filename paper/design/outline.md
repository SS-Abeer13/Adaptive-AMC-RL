# Paper outline (Phase 6)

**Title:** *When Does Deep Reinforcement Learning Help Link Adaptation? A Pre-Registered Evaluation Against Calibrated Rules*
**Primary venue:** IEEE TMLCN. **Backups:** OJ-COMS → OJVT (TVT only if its portal allows ≥ 14 pages at submission).
**Length target (approved):** 13–15 pages. This outline plans **≈ 14.5 pages including references**, plus **≈ 2 pages of appendices** in the same PDF (reviewed) and a supplement (registry, extra tables). The page limit is confirmed by the author on the submission portal.
**Wording rules in force:** "calibrated rules built on the learner's cues" (not "same-information") until G6 decides it; M2 is only a replication; FixedPU is a class oracle; no "definitive", "proves", "firmly", "hype".

Ledger IDs refer to `paper/ledger/claims_ledger.csv`. Every number in the manuscript comes from a macro generated from the ledger sources (Phase 7). `claims_map.csv` maps each claim to its section and float. Items that depend on runs not yet done are marked **[slot: X]** and have a default in §3.

---

## 1. Section plan

Planning estimates: about 800 words per page of pure text (IEEE two-column, 10 pt); figures and tables take the rest. Page counts are the budget for the section including its floats.

| § | Section | Pages | Words | Floats |
|---|---|---|---|---|
| — | Abstract | (in I) | 200 | — |
| I | Introduction | 1.5 | 750 | F1 |
| II | Related work | 0.8 | 450 | T1 |
| III | System model | 1.8 | 700 | T3, F2 |
| IV | Learning formulation and method | 1.2 | 650 | — |
| V | Evaluation protocol | 1.5 | 800 | T2 |
| VI | Results | 3.5 | 1,500 | T4, F3–F7 |
| VII | Pitfalls and corrective findings | 1.3 | 600 | F8, T5 |
| VIII | Discussion and limitations | 1.0 | 650 | — |
| IX | Conclusion and statements | 0.4 | 250 | — |
| — | References (≈ 60) | 1.5 | — | — |
| | **Total** | **14.5** | **≈ 6,550** | |
| App. | A–D | ≈ 2 | — | AT1–AT3 |

### Abstract (200 words; scope sentence first)
1. **Scope:** "We study downlink link adaptation (CQI-offset / MCS selection) in a multi-user LTE/NR-like cell with realistic multi-process HARQ, in simulation."
2. **Question and protocol:** when does deep RL beat OLLA *and* rules calibrated on the learner's cues? Pre-registered decision rules, fresh disjoint traces, project-wide multiplicity (67 cases, 108 scheme evaluations; M01).
3. **Result 1:** against OLLA the gain is large (+11.96 % on-time, M1; R06) **[slot: W1 — quote the warm-up number if its CI does not overlap the cold one]**.
4. **Result 2:** against calibrated rules it shrinks to +1.58 % [1.23, 1.94] (R03; hierarchical 95 % CI [+0.62, +2.62] %, G3a), for deadline traffic at RTT 8 with 8 HARQ processes, using a residual policy. **[slot: G6 — `\wordingsel{C2}{G6}{verdict}{unrun}`; "beats all calibrated comparators" and "same-information" only if the combined comparator is beaten and the seed-level bound is > 0]**.
5. **Result 3:** no gain on full-buffer goodput (−0.88 % / −1.73 % vs Fixed; R19–R20).
6. **Pitfalls:** three simulation pitfalls changed conclusions (mobility time scale, slot stealing, PF-average timing).
7. **Artefacts:** code, data and registry released.
- *Must not say:* "same-information" (before G6), "definitive", "firmly refutes"; no mechanism claim before G1.

### I. Introduction (1.5 pp, F1)
- **¶1 Motivation.** LA picks the MCS from delayed, noisy CQI; OLLA is the industrial baseline. Learned LA is reported to beat OLLA by 10–100 % (Saxena 2022, Ye 2023, You 2026, Wang 2026 [LOLLA], Kela 2022, Demirel 2025).
- **¶2 The comparator gap.** Counts from `lit_matrix.csv`: of 23 learning-based LA papers, none compared against a rule calibrated on the same cues as the learner; three varied OLLA's step or target over a few settings; for 7 the abstract did not allow a determination. Neutral wording; these settings differ from ours.
- **¶3 What we do.** One question, one simulator, one protocol: pre-registered, CRN, disjoint calibration/validation/evaluation traces, nine comparators, fairness guard, headroom bounds, a public registry.
- **¶4 Thesis and preview** (R06, R03, R19–R20; the three pitfalls).
- **Contributions (bulleted, page 1):**
  - **C1** evaluation protocol and open artefacts;
  - **C2** a positive case that survives: deadline traffic under realistic HARQ **[slot: G6 wording]**;
  - **C3** where RL does not help;
  - **C4** pitfalls and recommendations.
- **Positioning here (two sentences):** LOLLA and the other learned schemes are evaluated in different settings; we ask a different question. The closest methodological precedent is Doherty et al. (JOCN 2025). Detail is in II.
- **F1 (thesis figure, 1 column):** M1 on-time ratio per scheme, ordered, with 95 % CIs; brackets show the margin of the primary scheme vs OLLA (+11.96 %), Fixed (+1.87 %) and Context (+1.58 %).

### II. Related work (0.8 pp, T1)
- **A. Classical LA and OLLA.** Nakamura 2002; Park 2015 (dynamic target BLER); Durán 2015 (OLLA self-optimisation); eOLLA, NOLLA, d-OLLA, sequential-test OLLA; URLLC soft-ACK OLLA (Peralta 2022); SALAD (non-RL, three OLLA step sizes). Ahsen et al. (OJ-COMS 2026) is a *rank-dependent* multi-offset OLLA, not the Multi-OLLA we implement; say so in one clause.
- **B. Learned LA.** Bandits (Saxena 2019/2022, Park 2021, Ku 2024); DRL (Ye 2023, Pang 2024, You 2026, Parsa 2025, Demirel 2025); deadline-aware RL-OLLA (Kela 2022, Jin 2024 for the model-based case); learning on top of OLLA (Pulliyakode 2017, Pang 2024, LOLLA 2026). **LOLLA is positioned respectfully:** a residual offset on the OLLA/LUT mapping with PPO, evaluated on a GPU-accelerated NR stack under TDL channels, uplink, round-robin, with an agent observing telemetry OLLA does not use. We do not question its results. Its observation ablation (Table V(a), arXiv 2606.23110v1) is the example for our recommendation to report what the learner observes.
- **C. Evaluation rigour.** Doherty et al. (JOCN 2025) as the closest methodological precedent (tuned heuristics matched published RL in optical networks); our question differs: when does it help. Ferrari Dacrema 2019, McGreivy 2024, Mangal 2026 (wireless ML reproduction); Henderson 2018, Agarwal 2021, Colas 2018 (RL statistics); Nosek 2018, PMLR vol. 181 (pre-registration); Pawlikowski 2002 (simulation credibility).
- **T1 (single column, 8 rows):** Saxena 2022, Ye 2023, Kela 2022, Pang 2024, You 2026, LOLLA 2026, Demirel 2025, SALAD 2025. Columns: setting; HARQ model; calibrated-rule baseline; information parity (yes / partial / no / unclear). Footer line: the 23-paper counts and the abstract-only caveat.

### III. System model (1.8 pp, T3, F2)
Notation follows the v8 draft: N users, T_tti, d_i (CQI delay), q^ref, Δ (OLLA offset), P_tgt, ϑ_m, TBS(m, n_RB) (glossary).
- **A. Cell and channel** (S01, S02, S17). 1 macro cell, N = 10, 20 MHz / 100 RB at 2 GHz; log-normal shadowing 6 dB (50 m); Jakes fading; speeds 3–30 m/s (f_d ≈ 20–200 Hz); Markov interference bursts (+9 dB, dwell 250 / 120 TTI).
- **B. CQI feedback and link abstraction** (S03, S11). 15-level CQI from delayed (2–8 TTI), noisy (1 dB) reports; SINR→BLER abstraction (not NR LDPC tables: limitation); OLLA reference loop (target 10 %, down-step 0.5 dB, |Δ| ≤ 10 dB).
- **C. HARQ** (S05, S06). Chase combining (+2.5 dB per retransmission), up to 3 retransmissions; RTT 0 / 1 process and RTT 8 / 8 processes. Retransmissions reuse the stored MCS/TBS, so the learner's action acts only on new transmissions.
- **D. Scheduler** (S07). PF, one user per TTI; the PF average is updated at scheduling time with the scheduled rate (α = 0.05). The ACK-time alternative is described in VII-C.
- **E. Traffic and metrics** (S09, S10). Deadline traffic (12 kbit every 20 TTI, 10-TTI budget): primary metric is the on-time ratio; full buffer: goodput. Jain index over per-user means and the 5th-percentile user (edge5). 200-TTI traces, 50-TTI burn-in, 150 scored TTIs.
- **T3 (single column):** parameter table. **F2 (double column, two panels):** (a) block diagram: CQI → OLLA reference → base rule + residual δ → MCS → HARQ processes → PF scheduler; (b) PF averaging at scheduling time vs at ACK time (RTT 8 timeline, used again in VII-C).

### IV. Learning formulation and method (1.2 pp)
- **A. Decision problem.** One decision per user and TTI; the effective CQI is `clip(q_ref + b_i + δ)`. Offset action: δ ∈ [−4, +2] on the OLLA reference. **Residual action:** δ ∈ {−1, 0, +1} on a calibrated base rule b_i (S13). Base rule = the better of Fixed and FixedPU, selected on calibration traces; FixedPU is a *class oracle* (stated here, with the information table in V-B).
- **B. Rewards.** Deadline: +1 on time, −1 missed, with potential-based shaping (c = 0.5; Ng 1999; S14) and a deviation penalty 0.02|δ|; goodput: an opportunity-cost reward (the slot-stealing fix, VII-B).
- **C. Learner and training.** Shared multi-user A2C (actor 57-128-96-3, S16; hyper-parameters in Appendix A); logit bias +3 on δ = 0; 3000 episodes (deadline) / 800 (goodput) × 10 seeds; **primary scheme = per-seed mean**, secondary = deterministic ensemble (pre-registered from v14; ensemble weaker in v13).
- **D. Complexity.** About 20 k parameters, about 20 k MACs per decision (S16) **[slot: A3 wall time]**.

### V. Evaluation protocol (1.5 pp, T2)
- **A. Cases and registry** (P03, M01–M02). Fresh disjoint seeds and traces per round; 500 evaluation traces and 10 seeds for headline cases; a registry of 67 cases and 108 scheme evaluations (49 cases from v10, when the current protocol began).
- **B. Comparators, calibration and information (T2).** Nine comparators (P04: 7 distinct in M1). Calibrated on disjoint traces: Fixed and FixedPU on 20, Context table and tuned-target OLLA on 10 (S12) **[slot: G6 re-calibration on 500 traces and the combined comparator]**. **T2 is the information table:** each scheme × {CQI, ACK history, slack, delay class, speed class, HARQ-process state} plus calibration data. FixedPU: class oracle; the residual agent inherits it through its base rule (S13a).
- **C. Splits and CRN** (S10). Calibration (60001+), validation (80001+), evaluation (500001+) traces; common random numbers for the outcome draws; paired per-trace comparison.
- **D. Decision rules and guards** (P01, P02). "Beats X" = Holm-adjusted (over the comparators) Wilcoxon p < 0.05 and a 90 % CI lower bound > 0; Claim A (OLLA family), Claim B (Fixed, FixedPU, Context), WIN; fairness guard (Jain −0.02, edge5 −10 %); headroom bounds (genie and per-trace hindsight, R26). Seed-level inference (hierarchical seed × trace bootstrap; sign test) is reported next to the trace-level test (G3).
- **E. Pre-registration and multiplicity** (R29, M06). Pre-registration README before each run from v12; failed predictions reported (two secondary C4 misses); the approved multiplicity paragraph (67 / 108, 7 cases superseded, 49 from v10; M1 survives Bonferroni over 972 tests, p ≈ 8.8e-10, M04). Honest statement: the recipe was selected during the campaign, M1 is a confirmatory test of that recipe on fresh data.

### VI. Results (3.5 pp, T4, F3–F7)
- **A. Deadline traffic, RTT 8 (M1)** (R01–R08, R10–R11): all nine comparators beaten; margins +1.58 % (Context), +1.87 % (Fixed), +2.70 % (FixedPU), +11.96 % (OLLA family); +0.95 pp absolute (R34). **T4 (double column):** M1 full comparator table with margin, 90 % CI, Holm p, Jain, edge5; M2–M4 summary rows. **F3 (double column):** forest plot of margins vs each comparator, four panels (M1–M4).
- **B. Seed-level robustness** (G3a–c, G3g, G3h, R09): vs Context, 9/10 seeds above 0 (the exception is seed 2, −0.80 %; sign test p = 0.011); 95 % CIs: bootstrap over the 10 seed means [+0.72, +2.53] %, t-based [+0.48, +2.68] %, hierarchical seed × trace [+0.62, +2.62] %. Vs Fixed: [+1.01, +2.81] %, [+0.77, +2.98] %, [+0.89, +2.90] %. **All seed-level lower bounds are > 0, so under common rule R2 no "not robust to seed resampling" qualifier applies to M1.** Trace-only CIs are ≈ 2.3× narrower than the hierarchical ones (G3c). **F4:** per-seed margins and the CIs.
- **C. Fairness and cost** (R12, R13): Jain −0.0025 vs Context, edge5 +1.2 %; goodput 4.45 vs 4.36 Mbps.
- **D. Replication without HARQ delay (M2)** (R16, G3e, S08b): +0.43 % vs Context, hierarchical 95 % CI [−0.03, +0.87] %; earlier RTT-0 wins (v13 X2, v14 Y0, v16 K2) used another PF variant. Described only as a replication.
- **E. Goodput: no gain (M3, M4)** (R19–R21, R19a): −0.88 % / −1.73 % vs Fixed; the residual policy is bit-identical to its base rule in 5,000/5,000 seed × trace cells at RTT 8, not at RTT 0.
- **F. Headroom and training length** (R25–R27, G3d): hindsight bound +3.4 % over Fixed; the ensemble exceeds it; 800 → 3000 episodes raises M1 from +0.62 to +1.87 % vs Fixed, but the 800-episode result does not survive seed resampling. **F5 (two panels):** (a) headroom bars, four cases; (b) learning curves and 800-vs-3000 margin.
- **G. Robustness checks [slots: W1, G6, NR1, G10].** **F6:** panels per check. If none are run, replaced by the operating-point restriction (§3).
- **H. Policy behaviour [slot: G1, A1, A2].** Shares of δ on scheduled new transmissions by state bin (counts shown); by speed class. **F7.** No mechanism claim without it.

### VII. Pitfalls and corrective findings (1.3 pp, F8, T5)
- **A. Mobility time scale** (H01–H04): users moved *v* metres per TTI instead of *v·T_tti*; the +12.8 % goodput gain over OLLA vanished (0/18 wins, A2C −4.08 % vs OLLA in v9).
- **B. Slot stealing** (H07): a per-user goodput reward made the shared agent spend others' slots (policy bimodal at −3 / +2; 1.38 vs 2.92 Mbps); an opportunity-cost reward removed it.
- **C. PF-average timing under multi-process HARQ** (H17, R30, R31, S08): updating the PF average with ACKed bits at t + RTT lets the just-served user be rescheduled; in a 6-trace diagnostic Baseline goodput rose +39.6 % (8 vs 1 process) and Jain fell 0.50 → 0.42 (H17); across the full re-run all 13 schemes were 10–26 % higher under the ACK-time PF (H17a, confounded by traces and by drain/useful-bit changes, so quoted only as a range); a 10 % engine discontinuity had the same cause; bit-exact consistency after the fix. **F8:** goodput and Jain for Baseline under {RTT 0; RTT 8 / 1 proc; RTT 8 / 8 proc} with the two PF definitions.
- **D. PF-definition sensitivity** (S08a, R22, H05): the ranking "open-loop vs OLLA" is positive under one PF definition (v9: +4.5 %) and reversed under the other (v17: OLLA +7 %); protocol sensitivity, not a contribution.
- **E. Results withdrawn or superseded (T5).** Rows: v7/v8 withdrawn; v10 E4c exploratory (trace overlap); v12 pre-registered replication failed (Claim B); v13 X1 failed; v15/v16 RTT > 0 superseded (7 cases, 18 evaluations). Registry in the supplement.
- **F. Recommendations.** Calibrated comparators on the learner's cues, with an information table; CRN and disjoint splits; seed-level intervals; a case registry; results by mobility regime, HARQ timing **and observation set** (LOLLA Table V(a) as a neutral example); complexity reporting.
- **T5 (double column):** pitfalls and superseded results: symptom → diagnosis → fix → effect, with ledger-backed numbers.

### VIII. Discussion and limitations (1.0 pp)
- **A. When does RL help?** Where the decision has structure a static offset cannot use (deadline slack, HARQ-process state) and the policy is anchored to a calibrated base; nowhere on full-buffer goodput. Headroom is the limit. **[slot: G1 for any mechanism sentence]**.
- **B. Practical reading.** Calibrate first; the learned residual adds ≈ 1–2 % on-time at the studied point, with 3000-episode training; inference cost small (S16).
- **C. Limitations (honest, specific).** One cell, 10 users, one user per TTI; SINR→BLER abstraction, no NR LDPC tables or ns-3 validation; 150 scored TTIs, cold-start OLLA **[slot: W1]**; one operating point **[slot: G10]**; FixedPU is a class oracle that the residual inherits **[slot: NR1]**; calibration-budget asymmetry **[slot: G6]**; seed variance and selection over 17 versions; PF-definition dependence; no learned baseline from the literature (LOLLA, SALAD) in our simulator; single codebase, MATLAB-only.

### IX. Conclusion and statements (0.4 pp)
- Conclusion (≈ 100 words), then **Code and data availability** (release DOI), **Pre-registration availability**, **AI-assistance disclosure in the Acknowledgments** (IEEE wording; `manuscript/submission_checklist.md`), author contributions, funding and conflicts placeholders.

### Appendices (reviewed, in the main PDF)
- **A.** Hyper-parameters and training details (AT1).
- **B.** Full comparator tables for M1–M4 (`table_core.csv`) and seed-level tables (AT2).
- **C.** Calibration details: tables, budgets, and G6 / W1 / NR1 details if run (AT3).
- **D.** Registry summary by version, role and status. Supplement: full registry (108 rows) and per-case tables.

---

## 2. Portability to OJ-COMS (and OJVT)
- **One file per section** (`sec_*.tex`) plus `main.tex`, `numbers.tex` (generated), `refs.bib`, and a single `venue.tex` that switches class and front matter (TMLCN / OJ-COMS / OJVT).
- Nothing in the text refers to the journal. Page-sensitive material is isolated in appendices, so a template change only moves floats.
- **Transfer after rejection:** swap `venue.tex`, add the cover-letter disclosure that the paper was rejected elsewhere, and re-run the build. The IEEE Open Journals template name must be confirmed in the IEEE Template Selector at that time (not verified here).
- If TVT is used, the 10-page-plus-US$220/page rule applies. The author checks the portal cap first. We would then move Section VII-E/F and Appendix B to the supplement rather than cut the protocol or pitfalls content.

## 3. Defaults and changes for each pending run

| Slot | If **not run** (default text) | If run (what changes) | Decision wording |
|---|---|---|---|
| **G1** action re-cut | VI-H and F7 removed; VIII-A says the mechanism was not analysed; limitation | VI-H added with counts per bin; mechanism sentence only for a bin with ≥ 5 % of decisions and a consistent seed pattern (G1_SPEC §5) | — |
| **W1** warm-up | Abstract quotes the cold-start gain and says "cold-start OLLA"; limitation | Cold and warm gains side by side in T4/F6; abstract quotes warm-up if the 90 % CIs do not overlap | W1 §3 |
| **G6** budget + combined comparator | C2: "beats the OLLA family and the single-cue calibrated rules (calibrated on 10–20 traces)"; "same-information" not used | Re-calibrated rows added to T4; C2 per G6 §4 table | G6 §4 |
| **NR1** non-oracle residual | Cite earlier RTT-0 wins on a Fixed base (v13 X2, v14 Y0, v16 K2) as partial evidence; limitation stays | F6 panel; qualification if Claim B fails | NR1 §4 |
| **G10** grid | Abstract scope sentence and VIII state the one-operating-point restriction | F6 panel and per-cell table; "robust" or "operating-point specific" per G10 §3 | G10 §4 |
| **A1** speed classes | Recommendation only | One paragraph + panel in F7 | — |
| **A3** timing | Analytic MACs only | µs per decision added to IV-D | — |


## 4. Placeholder macros (Phase 7 uses them from the first draft)
Every number or wording that waits on a run is written with a tagged macro, never typed. Files: `paper/manuscript/pending.tex` (macros), `wording.tex` (pre-registered wording variants), `pending_manifest.csv` (62 keys with description, format, where used, default), `pending_values.csv` and `pending_status.csv` (filled when results arrive), `build_pending.py`, `check_pending.py`, `tests/test_pending.sh` (12 tests, passing with pdflatex).

| Item | Number macro | Examples | Wording switch |
|---|---|---|---|
| G1 | `\Gone{key}` | `\Gone{pct_delta0_m1}` | `\ifitemrun{G1}{VI-H paragraph}{omit}` |
| W1 | `\Wone{key}` | `\Wone{abstract_gain}`; `\wordingsel{W1}{W1}{abstract_cond}{cold}` | abstract quotes the smaller gain (W1 §3) |
| G6 | `\Gsix{key}` | `\Gsix{margin_ctxj}`, `\Gsix{seed_lo_best}` | `\wordingsel{C2}{G6}{verdict}{unrun}` and `\wordingsel{SI}{G6}{verdict}{unrun}` ("same-information" appears only for verdict ABJ) |
| NR1 | `\NR{key}` | `\NR{best_margin}` | `\wordingsel{NR1}{NR}{verdict}{unrun}` |
| G10 | `\Gten{key}` | `\Gten{n_win}`, `\Gten{cells_win}` | `\wordingsel{G10}{G10}{verdict}{unrun}`; `\ifitemrun{G10}{per-cell table}{operating-point sentence}` |
| A1 / A3 / A6 | `\Aone`, `\Athree`, `\Asix` | `\Athree{us_per_decision}` | `\ifitemrun{...}` |

Rules: (i) an unresolved number prints as a red `[[ITEM:key]]` and is logged to `pending_report.txt`; (ii) `check_pending.py --final` is a submission gate that fails on unresolved placeholders, on items still "pending", and on numbers of a not-run item used outside `\ifitemrun`; (iii) the verdict value stored in `pending_values.csv` is the only thing that selects wording, so a result drops into its pre-set sentence without rewriting.
