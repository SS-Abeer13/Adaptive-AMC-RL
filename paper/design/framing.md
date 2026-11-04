# Phase 4: framing options and the chosen framing

Venue: **IEEE TMLCN** (portable to OJ-COMS). Main-text budget is about 15 pages (exemplars run 13–17). Ledger IDs refer to `paper/ledger/claims_ledger.csv`.

## Option A: evaluation leads
*"When does deep RL help link adaptation? A pre-registered evaluation against calibrated baselines."*

Learned link adaptation is usually shown to beat OLLA by 10–100 %. We ask how much of that gain survives once the comparison includes rules that are calibrated on the same cues the learner uses. Over a 17-version, 67-case campaign with pre-registered decision rules, common random numbers and project-wide multiplicity accounting, the answer is: very little.
- A calibrated constant or context offset on the same OLLA loop already captures 83–86 % of the RL gain over OLLA (R33).
- On full-buffer goodput, no RL design beats calibrated rules, and the residual policy collapses exactly onto its base rule (R19–R21, R19a).
- One regime survives: deadline traffic under realistic downlink HARQ (RTT 8, 8 processes). There, residual A2C beats all nine comparators by +1.58 % over the best rule (R03), and the result survives seed-level resampling (G3a) and project-wide Bonferroni correction (M04).

We also report three simulation and design pitfalls that manufactured or hid gains during the campaign.

- **Fit vs gap analysis:** strongest. The comparator gap is documented by counts: 0 of 23 learning-LA papers compare against a calibrated rule (lit_matrix). The protocol is unique in the LA literature.
- **Fit vs TMLCN:** high. The journal publishes evaluation and lessons papers (Raca 2024, Baur 2025) and advocates artefact sharing.
- **Risk:** reads as "negative". Mitigated by the surviving positive case.

## Option B: method leads
*"Residual deep RL for deadline-aware link adaptation under realistic HARQ timing."*

A residual policy on a calibrated rule, with a potential-shaped on-time reward, exploits deadline slack and HARQ-process state that OLLA cannot use.

- **Fit vs gap analysis:** weak. LOLLA (IEEE TMC 2026) already learns a residual offset on the OLLA/LUT mapping. Pang 2024 already learns on top of OLLA. Kela 2022 already does deadline-aware RL-OLLA.
- **Effect size:** +1.6 % is small for a method paper.
- **Fit vs TMLCN:** acceptable, but reviewers would expect method novelty we cannot claim. **Rejected.**

## Option C (chosen at Checkpoint 2): evaluation-led hybrid with a real positive result
**Thesis.**
- Against OLLA, RL gains look large, and we see that too: +11.96 % vs tuned OLLA in M1 (R06). The size is to be re-checked with warm-up (W1); if it drops a lot, the abstract quotes the warm-up number.
- Against **calibrated rules built on the learner's cues**, the gain shrinks to about +1.6 % (R03).
- It survives only for deadline traffic under realistic HARQ, with a residual policy. Goodput shows no gain (R19–R21).

**Narrative order:** comparator gap → protocol → the positive case (M1) and why it is credible → where RL does not help (goodput; RTT 0 only marginally) → pitfalls that would have changed the conclusion → what to report in future LA studies.

**Title (approved at Checkpoint 4):** *When Does Deep Reinforcement Learning Help Link Adaptation? A Pre-Registered Evaluation Against Calibrated Rules*. "Reinforcement Learning" is always spelled out in the title.

## Precision required by the framing (decide at Checkpoint 4)
The phrase "calibrated rules that use the same information" is **only partly accurate** (S13, code checked 2026-11-04):
- The RL state is gNB-observable: tier O excludes true speed and true delay. It adds the slack cue and three HARQ-process features (busy processes, retx-ready, in-flight bits).
- The RL's base rule is **FixedPU**, whose class table uses the *true* delay class and the *true* mean-speed class (`evalPolicy_v17.m` L166–177). The RL therefore inherits that class information.
- **Context table** uses the slack cue only. **FixedPU** uses the class only. **No comparator** uses slack × class × HARQ-process state jointly.

Options:
- **(i) Reword** to "calibrated rules built on the learner's cues (the slack cue in the Context table, the class information in FixedPU)" and list joint-information parity as a limitation.
- **(ii) Add an information-parity comparator** to G6: a Context table over slack × FixedPU class (× busy-process bin at RTT 8), calibrated with the 500-trace budget. If RL still wins, the claim becomes clean.

**Recommendation:** (ii), plus (i)'s wording until G6 is run.

## Page budget (TMLCN, about 15 pages main text)

| Section | Pages |
|---|---|
| Abstract + I. Introduction (thesis figure, bulleted contributions on p. 1) | 1.8 |
| II. Related work (classical LA; learned LA incl. LOLLA; evaluation rigour incl. Doherty JOCN 2025) | 1.0 |
| III. System model (incl. PF averaging definition, HARQ timing) | 2.0 |
| IV. Learning formulation and method (offset vs residual, shaping, A2C, complexity) | 1.5 |
| V. Evaluation protocol (comparators, calibration, CRN, splits, pre-registration, decision rules, fairness guard, headroom, multiplicity) | 1.5 |
| VI. Results (M1; M2 replication; M3/M4; training length; headroom; fairness; behaviour after G1) | 3.7 |
| VII. Pitfalls and corrective findings (incl. "Results withdrawn or superseded") | 1.5 |
| VIII. Discussion and limitations | 1.0 |
| IX. Conclusion + availability + AI disclosure | 0.5 |
| References (~55–65) | 1.5 |
| **Total** | **≈ 16** (main text ≈ 14.5) |

Appendices (in the paper, reviewed): hyper-parameters, full comparator tables. Supplement: registry (108 rows), extra tables.

## Checkpoint 4 decisions (4 Nov 2026)
- **Wording rule until G6 is done:** "calibrated rules built on the learner's cues". The phrase "same-information" may be used only if M1 beats the G6 combined comparator (proposals/G6, §3).
- An information table (`design/information_table.md`) goes in Section III or V. FixedPU is called a **class oracle**. The residual agent's inheritance of the oracle class is stated as a limitation (reviewer_attacks #25).
- **Length target: 13–15 pages.** The author confirms the limit on the TMLCN portal before submitting. Backups: OJ-COMS → OJVT (TVT only if its portal allows ≥ 14 pages at submission).
