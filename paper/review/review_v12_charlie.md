# Review (charlie): statistics, pre-registration, multiplicity, claims versus evidence

## Summary

The manuscript compares a residual A2C link-adaptation policy with OLLA variants, calibrated tables, hand-designed rules and supervised one-step learners in one MATLAB simulator with multi-process HARQ. The new headline is: "deep RL beats calibrated tables and hand-designed rules, but a supervised one-step success model trained on observed ACK/NACK beats deep RL". The protocol is unusually careful for this field. It uses CRN pairing, disjoint splits, a hierarchical seed×trace bootstrap, pre-registered wording, a project-wide multiplicity statement, and it reports frozen and corrected values side by side (D1). I checked most of the arithmetic against the tables and it is internally consistent. Some examples:

- 3.35 % = 0.6201/0.6000 − 1.
- −7.58 % = 0.6201/0.6710 − 1.
- The "58 %" is (1.58 − 0.66)/1.58.
- 83 % and 85 % are (60.14 − 54.72)/(61.26 − 54.72) and (60.31 − 54.72)/(61.26 − 54.72).
- The weakest-fit margins in Table VIII match the [min] on-time values.
- The Bonferroni products are correct (9.1e−13 × 972 and × 1790).

Chance is not the main threat to the new headline. The supervised-learner margins are large: 0 of 10 seeds are above, and the hierarchical CI is far from zero. The problems are design and sequencing problems that affect what the headline can claim:

- (i) The headline number compares learners with different action sets.
- (ii) R1b and R1c were designed and registered after R1 (and NR2) results were seen, on reused evaluation traces. The paper's description of its pre-registration does not disclose this sequence.
- (iii) The R1c "replication" includes the original R1b draw, and the paper reports no inferential quantities for it.
- (iv) The definitions of "match" and "holds" are point-estimate rules, not equivalence tests.
- (v) Several statements about confirmatory status and the multiplicity accounting do not match the rest of the text.

These are fixable, but they need a major revision of how the main result is framed and reported.

## Major concerns

### 1. The headline margin (−7.58 %) confounds learning paradigm with action set and regularisation

- **Issue.** The abstract, introduction (item 3), Table IX and conclusion quote GBT-full-ACK, which chooses over all offsets −4…+2 (Section VII-B). NR2 is restricted to base ±1 (Section IV-A). NR2 is also regularised toward δ = 0 by a deviation penalty of 0.02|δ| and an initial logit bias of 3 (Section IV-B/C). The like-for-like comparison is GBT-res-ACK: −3.40 % (hierarchical CI [−4.43, −2.47] %; R1c weakest fit −3.10 %). No RL policy with the full action set was evaluated on the NR2 traces. The offset-action A2C (δ ∈ [−4, +2]) exists in the paper but only appears in M1 at 800 episodes.
- **Where.** Abstract ("the RL policy delivers 7.58 % fewer packets on time"); Introduction item 3; C3; Section VII-B; Table IX row "one-step learner … −7.58"; Section IX-A; Conclusion; title.
- **Why it matters.** Roughly half of the headline gap (7.58 versus 3.40) may come from the larger action set, not from supervised versus RL learning. The claim "deep RL was not the best way to learn here" is supported only by the res-vs-res comparison. The paper applies a conservative-quote rule elsewhere ("As pre-registered, the abstract quotes the smaller, warm-up gain over OLLA", Section VI-D1). Here it quotes the larger of the two pre-registered learner margins, which is the one more favourable to the new headline.
- **What would address it.**
  - Lead with GBT-res-ACK (−3.40 %), or quote both with the action-set difference stated in the same sentence.
  - Either add a full-action-set RL arm on the NR2 traces, or restrict the claim to "on the residual action set".
  - Narrow the title and abstract from "deep RL" to "this residual A2C recipe".

### 2. The order of amendments relative to the data seen is not disclosed, and the main result was promoted from a control after the fact

- **Issue.** Section V-D says that "seven short pre-registrations" were frozen after the main round, plus "an eighth, the confirmatory replication". Table XVI lists about 16 checks, including HR1, R1/R2 (Amendment 8), R3–R5, R1b (Amendment 9) and R1c (Amendment 10a). Its caption only says that "NR2 was added after the other results were known". Nowhere does the text say:
  - that R1 (with GBT-full beating NR2 by 5.54 %) had been observed before R1b was designed;
  - that R1b had been observed before R1c was registered;
  - that HR1's headroom result motivated R1 (Section VII-A implies this).

  The design choices of R1b were all made with R1's outcome known: ACK labels, ε = 0.5, a uniform draw over −4…+2, and keeping the full-offset arm. Fig. 12 pre-specifies that "a reframing of the paper is considered only after CONFIRM together with WIN" for NR2. It does not pre-specify reframing the paper around a control, yet Section VII is now "the main result".
- **Where.** Section V-D; Table XVI caption; Section VII opening; Fig. 12; Section IX-E9.
- **Why it matters.** Each stage was frozen before it ran, which is good. But the sequence HR1 → R1 → R1b → R1c is adaptive: each step was chosen in light of the previous result. Readers need this sequence to judge which statements are confirmatory. Only R1c's new draws and the per-cell fits are confirmatory of R1b. The choice of the headline itself is post hoc.
- **What would address it.**
  - Add a dated timeline (freeze date and hash per amendment, and the results available at each freeze), in the main text or as a table column in Table XVI.
  - Update the "seven + eighth" count in Section V-D.
  - State explicitly that the reframing around R1b was decided after R1 and R1b had been seen.
  - Label R1 and R1b as exploratory-then-confirmed and R1c as the confirmatory test.
  - Give the pre-registered wording that R1, R1b and R1c attached to each outcome (BEATS/LOSES/MATCH/INCONCLUSIVE), and show that the abstract wording is that wording.

### 3. R1c is not a full independent replication, and it reports no inferential quantities

- **Issue.** Table VIII gives the weakest GBT-full-ACK fit on the NR2 traces as "1: −7.58". That is exactly the R1b value (Table VII, 0.6710 = the [min] of R1c), so fit 1 appears to be the R1b draw. "Four independent calibration draws" is therefore three new draws plus the original. Other gaps:
  - At M1, all fits are evaluated on the same 500 NR2 traces that were already used by NR2, R2, R1 and R1b. Variation over evaluation-trace sampling is therefore not replicated.
  - Table VIII reports only point estimates. It gives no Holm p-values, no 90 % CIs, no hierarchical CIs and no seeds-above counts, although the decision rule ("Holm over 8 per trace set") depends on them.
  - Table IX points to "– (Table VIII)" for the seed-level column, but Table VIII has no seed-level column.
  - Table VII's caption says "Holm over the controls of each pre-registered family", but Table VII shows no p-values either.
- **Where.** Section VII-C; Tables VII, VIII, IX; Table XVI (R1c data: "NR2 and cell evaluation traces").
- **Why it matters.** "Holds" cannot be checked from the paper. The statement "R1b did not rest on a favourable draw" is circular if fit 1 is the R1b fit. Repeated reuse of the "confirmation" traces for successive, data-dependent controls weakens their confirmatory status.
- **What would address it.**
  - State whether fit 1 is the R1b draw. If it is, say "the original draw and three new draws".
  - Add per-fit Holm p, the 90 % CI, and the hierarchical CI (resampling RL seeds and traces) to Table VIII, plus a between-fit interval.
  - Ideally, evaluate the frozen fits and NR2 on a fresh M1 evaluation set.
  - Show the Holm p-values in Table VII.

### 4. "Match" and "holds" are point-estimate rules, not equivalence tests, and "match" is used inconsistently

- **Issue.** R1c defines "match" as "Holm not significant and |margin| < 0.5 %" (Section VII-C). A non-significant test with a small point estimate is not evidence of equivalence. An equivalence statement needs the CI to lie within ±0.5 % (TOST). Elsewhere "match" is used without any rule: "Both rules match the combined table (+0.13 %, 90 % CI [−0.26, 0.52] %)" (Section VI-D5). That CI exceeds the 0.5 % margin, so the claim fails a TOST at that margin. The "holds" state treats "beat or match" as success. A learner that is non-significantly worse by 0.49 % would therefore "hold".
- **Where.** Section VII-C; Table VIII caption; Section VI-D5; abstract, introduction, C3 and conclusion ("beat or matched").
- **Why it matters.** In this data no fit merely matched, so the practical effect is nil. However, the headline wording "beat or matched" is inherited from a weak rule, and the "match" verdict for the designed rules is not supported at the stated tolerance.
- **What would address it.**
  - Since every fit beat, say "beat" in the abstract and conclusion.
  - Redefine "match" as CI-within-margin, or relabel it "not distinguishable".
  - Either drop "match" for the designed-rule comparison or state the rule used.
  - Remove the duplicated generated sentence in Section VII-C (the res and full sentences are nearly identical) and in Section VI-D3 / IX-E5.

### 5. The project-wide multiplicity statement is incomplete for the new headline and internally inconsistent

- **Issue.**
  - **Correction factors.** The registry correction uses 972 = 108 × 9 comparators. The project-wide correction uses 1 790 = 179 × 10. The per-evaluation factor changes between the two without explanation.
  - **R1/R1b/R1c accounting.** It is not stated whether R1, R1b and R1c (including R1c's 40 fit evaluations and 9-comparator families in each cell) are among the "37 robustness cases" and the 71 extra scheme evaluations. Table XVI lists checks, not 37 cases.
  - **Missing corrected p for the headline.** A project-wide corrected p is reported for M1 and NR2 versus the combined table, but not for the new main result (NR2 versus GBT-full/res-ACK).
  - **Unadjusted seed-level intervals.** The hierarchical 95 % intervals, which the paper calls the primary evidence, are not multiplicity-adjusted. The 90 % trace-level CI used in the "Beats" rule is not Holm-adjusted either.
  - **Overstated registration.** The abstract says that "all 104 cases are registered". Limitation 9 says the released registry covers 67 cases, and the other 37 are in a separate ledger "listed in Appendix D", but Appendix D does not list them as cases.
  - **HR1.** HR1 "adds no case", yet its four unadjusted intervals are used to argue mechanism (Sections VI-G, VII-E, IX-A).
- **Where.** Section V-D; Section IX-E9; Appendix D, Appendix E; Table XVII; abstract.
- **Why it matters.** The paper's credibility rests on its accounting, and readers cannot reconstruct the 104/179/1 790 figures from what is shown. With effects this large the headline would almost certainly survive correction, but that should be demonstrated, not assumed.
- **What would address it.**
  - Give a table of the 37 robustness cases and their scheme evaluations, per amendment.
  - Reconcile the 9 versus 10 per-evaluation factor.
  - Report the project-wide corrected p for R1b and R1c.
  - Change "registered" to "recorded in a registry or ledger" where appropriate.
  - Say explicitly that seed-level intervals and HR1 intervals are unadjusted.

### 6. Confirmatory-status statements contradict the reuse of traces, and Deviation D1 enters the R1c comparator

- **Issue.**
  - **NR-G10 timing.** Section V-D says that NR2 and NR-G10 were "frozen before any of their data existed". But NR-G10 reused G10's 300 evaluation traces and CRN, and its nine comparators are "bit-identical" to G10's (Section VI-D3). The comparator results on those traces were therefore known before the freeze.
  - **D1 in the R1c comparator.** In R1c the cell RL policy is the ten-seed NR-G10 policy with "G2 seeds 6–10 corrected, Deviation D1" (Table VIII caption). The paper does not say whether Amendment 10a was frozen before or after D1 was found, or whether it specified the corrected or the frozen evaluation.
  - **D1 in the summary table and C2.** Table IX reports the corrected G2 value (+2.14 %, "yes") as the primary entry and keeps the frozen −9.42 % in a footnote. C2 likewise counts the corrected point. The text says "the corrected value does not replace the frozen record".
  - **How D1 was found.** The paper does not say how D1 was detected. If it was found because the frozen result looked anomalous (WEAKENS), error-checking was asymmetric. The authors should say whether the same packet-size audit was applied to every stage, including the favourable ones.
- **Where.** Section V-D (last sentences); Section VI-D3–4; Table VIII caption; Table IX ‡; C2; Section IX-E14.
- **Why it matters.** The direction of D1 is harmless for the supervised-learner claim: with the frozen seeds, RL would look worse. It is not harmless for the RL-versus-rules claim at G2. The confirmatory labels need to be accurate.
- **What would address it.**
  - Correct the NR-G10 sentence ("policies and seeds fresh; evaluation traces and comparator results reused from G10").
  - State when D1 was found relative to Amendment 10a, and which evaluation R1c pre-specified.
  - In Table IX, show both values with equal prominence or mark the row "corrected, not pre-registered".
  - Describe how D1 was detected and what audit was applied to the other stages.

### 7. The scope of "deep RL beats calibrated tables" is wider in the abstract and conclusion than the confirmatory evidence

- **Issue.**
  - **Where it was confirmed.** The robust, confirmatory win over the strongest table exists for one configuration (NR2) at one operating point. At the neighbouring points the combined table was not in the pre-registered family. There the comparison is descriptive, with a lighter search and 5 seeds (Section VI-D3). The pre-registered oracle-base M1 policy did not pass the seed-level rule.
  - **Recipe selection.** The non-oracle recipe was chosen after seeing M1's evaluation traces (NR1, G6; Limitation 6).
  - **"Same cues".** The abstract says NR2 beats "the strongest calibrated table on the same cues". The combined table also uses the oracle speed class (Table III), so it observes more than NR2.
  - **"Adds nothing".** The phrase "adds nothing (−0.88 %)" on goodput understates the result. In M3 RL is significantly worse than Fixed (Table XII, 90 % CI [−1.44, −0.33]).
  - **Mixed policies in the abstract.** The abstract moves from NR2 numbers to "Against OLLA it is 7.49 %", which is the M1 oracle-base policy (NR2 versus warmed OLLA is +9.86 %), without saying that the policy changed.
- **Where.** Abstract; Introduction "In short"; C2; Section IX-A; Conclusion; title.
- **Why it matters.** This is claim-versus-evidence alignment for half of the headline.
- **What would address it.**
  - Qualify the claim as "a non-oracle residual A2C recipe, selected during the campaign and confirmed at the main operating point".
  - Replace "on the same cues" with "that additionally uses the true speed class".
  - Replace "adds nothing" with "is worse than a single calibrated offset".
  - Attribute the 7.49 % explicitly to the oracle-base M1 policy.

### 8. Seed-level inference for the learner comparison treats the supervised model as fixed, and RL is never paired with its training-data budget

- **Issue.**
  - **One-sided uncertainty in R1/R1b.** The hierarchical CIs resample NR2 seeds and traces but hold the GBT fit fixed (a single draw). Between-fit variance enters only descriptively, as the R1c [min, max] range.
  - **Undercoverage.** With 10 seeds (5 in NR-G10) the percentile bootstrap may undercover, as Limitation 11 acknowledges. The cell RL comparator mixes five NR-G10 seeds with five R5 seeds trained later.
  - **Unequal budgets.** The training budgets are not stated side by side: the number of calibration traces per R1c draw, the logged decisions, and simulator time for the GBT versus 3000 episodes × 10 seeds for RL. Exploration cost is unmeasured for both (Limitation 12).
- **Where.** Section VII-A–C; Table VII; Table VIII; Section IX-E11–12.
- **Why it matters.** The direction of the result is clear, but the size of the interval is understated and the comparison of data efficiency, which matters for the "which learner" claim, cannot be made.
- **What would address it.**
  - Give a two-level interval over GBT fits × RL seeds × traces for R1c.
  - Report the data and compute budget of each learner in one table.
  - Say whether the R5 G2 seeds differ systematically from seeds 1–5.

## Minor concerns

- **Exploratory labelling.**
  - The "twin" comparison is properly labelled "an observation, not a pre-registered test". It is a surprising result (noisier labels do better), so a one-line diagnostic would help: for example, the true-SINR model trained on the exploration log, which separates labels from logging.
  - The ECE/Brier statement says "well calibrated" without a threshold. Table XVI lists "calibration of p̂" as part of the R1b rule. State the pre-registered criterion if there is one; otherwise label the statement descriptive. Also give the ECE binning and the base-rate Brier score for reference.
  - The transfer rows are labelled "secondary", yet Table VIII gives them a "holds" state. Say whether a decision rule was registered for them.
  - Several statements are unlabelled but appear descriptive or post hoc:
    - the NR2 slow-user gain (+2.09 %), which the introduction states as a confirmed property ("lost nothing for slow users");
    - the NR2 action breakdown;
    - "+2.58 % above the M1 oracle-base policies";
    - the BLER figures in Section VII-D.
  - The ensemble (0.6306) is correctly labelled.
- **Terminology.** "Learner" means the RL policy almost everywhere ("the learner's cues", "the learner's margin"). In Table IX "no (learner better)" means the one-step learner. Write "one-step learner better" or "comparator better".
- **Fairness guard.** The guard is defined on edge5 (Section V-C), but Section VII uses a bottom-decile metric that is "often zero". Apply the pre-registered guard metric, or explain the switch.
- **HR1 cross-trace comparison.** HR1 compares a "realised difference of 2.7 points" between NR2 and M1 margins, but these were measured on different trace sets (NR2 traces versus M1 traces), and they are relative percentages rather than points.
- **Max-of-two-estimators.** HR1 reports "the larger estimate" of gbt_a and gbt_b, which biases the headroom upward. The paper does report both; say so where the max rule is introduced.
- **Rule mixing.** The trace-level rule combines a Holm-adjusted two-sided Wilcoxon test with an unadjusted 90 % t-interval of a relative margin. State how the CI of a ratio of means is computed (delta method or bootstrap).
- **Roadmap.** The roadmap at the end of Section I omits Section VII, which is the main result, and attributes "the controls on the learner's cues" to Section VI.
- **Cross-reference.** Section IX-A cites "Section IX-B" for the NR2 seed-level pass. The primary source is Section VI-D.
- **Table IX first row.** It mixes comparators: the cold and warm margins are against default OLLA, while the seed-level interval is against re-tuned OLLA (footnote †). Consider separate rows.
- **Release placeholder.** The data and pre-registration section is a placeholder. For a paper whose argument rests on pre-registration, the freeze hashes and commit dates must be available to reviewers, at least in the supplement, before acceptance.
- **Power.** The power statement ("below about 1.62 % would not be detected reliably") implies that the M1 combined-table test (+0.66 %) was underpowered by design. Say this where the M1 non-robust verdict is interpreted, so that "not robust" is not read as "no effect".

## Verdict

**Major revision.** The protocol and its arithmetic are sound, and the supervised-learner effect is large. However, the new headline quotes a margin that confounds action set with learning paradigm, and it was promoted from controls designed after earlier results were seen, on reused traces. R1c's "replication" status, its "match"/"holds" rules and the project-wide multiplicity accounting also need to be stated accurately before the claims match the evidence.
