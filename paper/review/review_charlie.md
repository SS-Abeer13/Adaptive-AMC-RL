# Review by reviewer charlie

```
SEED: cd9021d88ad8e60501561b4a7bfd67bd
LENS: Experimental design (controls, confounds, blinding, pre-registration)
STANCE: Skeptical-but-fair
```

(Derivation: 0xcd = 205, 205 mod 6 = 1. 0x90 = 144, 144 mod 3 = 0.)

### Summary

The paper asks when deep RL helps downlink link adaptation once it is compared with rules calibrated on the learner's own cues, not only with OLLA. It uses a single MATLAB simulator of a 10-user NR-like cell with multi-process HARQ, with deadline and full-buffer traffic. The learner is a shared A2C policy, mostly a ±1 residual on a calibrated base offset. The protocol uses disjoint calibration, validation and evaluation traces, common random numbers, 10 training seeds, nine comparators, Holm-corrected trace-level tests, a hierarchical seed×trace bootstrap, and "pre-registered" decision rules and wording. The headline findings are:

- Against OLLA the learner wins by +7.49 % on-time delivery after warm-up (+11.96 % cold).
- Against a re-calibrated 36-cell "combined" table on the same cues the margin is +0.66 %, and it is not seed-robust (hierarchical 95 % CI [−0.30, +1.70] %).
- A non-oracle residual variant, found in an ablation (NR1) and replicated (NR2), beats that table by +3.35 %.
- On full-buffer goodput the learner adds nothing (−0.88 %).
- A one-step "headroom" analysis shows room even where the learner fails.
- Three simulation pitfalls are documented.

The topic and the methodological stance are valuable. Comparing against comparators calibrated on the learner's own cues, reporting seed-level uncertainty and reporting failures are all commendable. My concerns are about whether the design actually supports the strength of the "pre-registered", "confirmatory" and "recommended" language, and about comparator and simulator validity.

### Major concerns

1. **Issue.** The "pre-registered, confirmatory" framing is stronger than the design supports. The recipe, the comparator that it is tested against, and the key positive result were all chosen after seeing evaluation outcomes.
   **Where.** Title and abstract; Section V-D ("the recipe was chosen during the campaign"); Section VIII-E items 6 and 9; Appendix D / Table XIV ("NR2 was added after the other results were known"; NR2 added "by amendment"); NR-G10; Section VI-D.2.
   **Why it matters.**
   - The residual recipe was selected over 17 campaign versions, and the paper concedes "selection effects cannot be fully excluded".
   - The combined table was constructed after M1 showed a margin over the existing rules. It is the one comparator the learner barely beats.
   - The non-oracle configuration (NR1) was selected using the same M1 evaluation traces it was then evaluated on; the paper says NR1 "reused M1's evaluation traces".
   - NR2 uses fresh traces and seeds, which is good. But the hypothesis, the comparator and the decision rule were all fixed after the full results of M1, G6 and NR1 were known, and after earlier decision rules (v12, v13) had failed.
   - A pre-registration written after the exploratory phase protects only against analytic flexibility within NR2. It does not protect against the garden of forking paths in recipe selection.
   - The same holds for NR-G10, which was frozen after the original recipe failed at the neighbouring points and was then re-run with a different recipe.
   - Calling M1 a "confirmatory test of that recipe on fresh data" is also questionable. M1's traces belong to the round whose results drove the recipe choice, and the paper itself reports that NR1 reused them.

   **What would address it.**
   - Use "pre-registered" only for stages whose hypotheses were fixed before any related result existed.
   - Label M1, NR1 and G10 as exploratory/development and NR2 as the single confirmatory test, with an explicit statement of the researcher degrees of freedom (the number of recipes and variants tried before NR2).
   - State the NR2 pre-registration timestamp relative to the NR1, G6 and HR1 results.
   - Ideally run one further confirmatory round, with a recipe and a comparator set frozen in advance and an independent holdout of simulator seeds and configurations.

2. **Issue.** The comparator set is asymmetric in tuning effort and expressiveness, and the "beats all nine" claim is inflated by degenerate comparators.
   **Where.** Section V-B; Table V; Table VI; Appendix C; Section VIII-B.
   **Why it matters.**
   - Both bandits score 41.80 % in M1, which is 12.7 points below open-loop CQI (52.53 %). This is a pathological implementation, not a competitive baseline. The two bandits and the tuned-target OLLA are identical to other comparators in M1. These duplicates inflate the "beats all nine comparators" statement and consume Holm family slots.
   - The strongest comparator is a 36-cell table searched by coordinate ascent. One of 4 starts hit the safety cap while still improving (score 0.6087 versus the selected 0.6088). The search space is clipped to offsets in [−4, +2], and many cells sit at the boundary (many −4 entries in Table XII, and −4, −4 in the re-calibrated Context table), so the table may be constrained by the grid, not by information.
   - Cells with fewer than 200 decisions were not searched and keep the composite value.
   - The learner receives 3000 episodes × 10 seeds with periodic validation and a hand-chosen reward (shaping, deviation penalty 0.02|δ|, initial logit bias 3), which is considerable design effort that is not budgeted for the tables. There is also no tuned learned baseline of the same class (for example a supervised or boosted-tree policy, which HR1 already trains, or a tabular or Q-learning agent on the same features).
   - Because the learner is a ±1 residual on a calibrated offset, a table with slack × HARQ state × speed class cells and finer bins or a wider search range is an obvious stronger comparator. A 0.66 % margin over an acknowledged "slightly under-optimised" table cannot be interpreted.

   **What would address it.**
   - Remove or fix the bandit baselines and report the number of distinct comparators.
   - Widen the offset range and show that no cell is at the boundary.
   - Run the combined-table search to convergence from more starts, or report sensitivity to the search budget.
   - Add at least one matched-budget non-RL learned baseline on the same features (for example the gbt policy from HR1 deployed as an actual policy).
   - Report the learner's total design and tuning effort, including the reward and logit-bias choices, next to the tables' 24.6 h.

3. **Issue.** The statistical evidence for the central comparisons rests on trace-level tests with extreme p-values, on small seed counts, and on inconsistent multiplicity accounting. The headline interpretation also shifts between trace-level and seed-level rules.
   **Where.** Abstract; Section V-C/D; Table IV; Table VI; Section VI-C; Appendix B.
   **Why it matters.**
   - Quoting p = 4.6×10⁻²⁷ (NR2) or 1.2×10⁻⁶⁶ treats the 500 traces as the inferential unit for a quantity (policy quality) whose real variability is across training seeds. Such values are uninformative, and the paper itself shows that the trace-level result for the combined table is nullified at seed level.
   - The hierarchical bootstrap with 10 seeds (5 in G10/NR-G10) has poor coverage. The paper notes "with 5 seeds this is indicative", yet the abstract treats the operating-point result as having "held".
   - The Bonferroni factors are inconsistent: 972 (108 × 9), then "at most 1 260 tests" (126 × 10), and the Holm families differ between Table V (nine) and Table VI (ten).
   - The 90 % one-sided-style trace CI is combined with a 95 % hierarchical CI, and rule R1 combines a two-sided Wilcoxon with a one-sided 90 % t-interval. The "Beats" labels are therefore hard to compare across tables.
   - The probability of improvement, 0.55 (95 % CI [0.49, 0.61]), is arguably the cleanest practitioner-relevant statistic and should lead the abstract. Instead the abstract's first positive statements are the +7.49 % over OLLA and the +3.35 % NR2 result.
   - Relative margins (+0.66 %) and absolute ones (+0.40 pp) alternate, which makes effect sizes hard to read.
   - The deterministic ten-seed ensemble reaches 0.6306 on time against 0.6086 for the combined table. That is a gap far larger than any single-policy margin, but it is dismissed as "secondary" and "not pre-registered". It is informative about seed variance and about what a practitioner would do.

   **What would address it.**
   - Make seed-level (policy-level) uncertainty primary throughout, including the abstract, and demote trace-level p-values.
   - Use one consistent interval level and one multiplicity scheme that is explained in a single table.
   - Increase seeds in G10/NR-G10 to at least 10 or drop the "held" claim.
   - Report the ensemble result against the combined table with its own interval, flagged as exploratory.
   - Provide a power or precision calculation for the seed count (cf. Colas et al., cited as [35]).

4. **Issue.** The claim that the gain generalises ("also held at two neighbouring operating points") is weakly controlled and inconsistently worded.
   **Where.** Abstract; Section VI-D.3; Section VIII-E.5; Section IX; Table VII.
   **Why it matters.**
   - At those points the comparators are single-cue rules, and the combined table was dropped "for compute reasons" (Amendment 2). The strongest comparator, which defines the paper's main finding, is therefore absent exactly where generalisation is claimed.
   - The descriptive per-cell combined table (a lighter search: 200 traces, 4 starts) is outside the family, and the margins over it are only +1.04 % and +1.17 %.
   - Both points are close to M1 along a single load/deadline axis. G3 is close to the ceiling (0.91 on time), so a +1.02 % margin there is hard to interpret.
   - Section VI-D.3 is internally contradictory: it states that "the check was negative … at the two tested neighbouring points it was not reproduced" for the original recipe, then that the non-oracle recipe held. The recipe was changed after the failure.
   - No variation in traffic model, user count, speed distribution, interference model or scheduler is tested.
   - The headline recommendation therefore rests on one simulator configuration and two nearby cells.

   **What would address it.**
   - Include the combined table in every operating-point comparison.
   - Cover a wider grid, including the two untested corners and different user counts, speed mixes and load patterns, and report all cells including negative ones.
   - Soften the abstract wording to match what was established.

5. **Issue.** The simulator and the HARQ and scheduler design may drive the findings, and the paper's own pitfalls section lowers confidence in it.
   **Where.** Section III; Section VII; Section VIII-E.1; Table II.
   **Why it matters.**
   - Three errors (a 1000× mobility error, slot stealing, PF timing) each produced large spurious gains, and a 10.71 % "engine discontinuity" was found. That suggests further undetected simulator artefacts are plausible.
   - The setup is unusual. One user receives all 100 RBs per TTI. Deadline traffic is 12 000 bits per 20 TTIs with a 10-TTI budget at RTT 8, so at most one retransmission fits. On-time ratios are only about 60 %, an overloaded regime. Block errors use an SINR-to-BLER abstraction with no link-level validation. Chase combining is modelled by a fixed 2.5 dB per retransmission.
   - The learner is scored on 150 TTIs after burn-in with a shared reward.
   - The results are single-simulator, and the released Sionna prototype was "not used to replicate any result".
   - Under these conditions a +0.4 pp effect could easily be an artefact of the BLER abstraction or of how the PF update interacts with the policy's high-MCS bias (the policy raises CQI by one step in 54.6 % of decisions).
   - The PF-timing demonstration, the A6 diagnostic (six traces) and the "10–26 %" range are described as confounded, so the evidence for "timing, not HARQ, accounts for the apparent gain" is thinner than the text implies.

   **What would address it.**
   - Cross-validate at least the M1 comparison in a second independent simulator (ns-3, Sionna or the released prototype) or against LDPC link-level BLER tables.
   - Test sensitivity of the margin to the BLER abstraction, the chase-combining gain, the CQI delay and noise model, and the scheduler (for example round-robin and multi-user per TTI).
   - Rerun the PF-timing comparison unconfounded for all schemes.

6. **Issue.** The headroom analysis (HR1) is presented as stronger evidence than it is, and its estimator selection biases the results.
   **Where.** Abstract ("one-step room over every table, even on goodput, so the missing gain there is not due to a lack of room"); Section VI-G; Fig. 9; Section VIII.
   **Why it matters.**
   - Headroom is estimated with gradient-boosted trees on the same logged decisions, with the larger of two estimators reported (gbt_a "in every comparison"). This is an upward-biased selection and "the size of the headroom depends on the predictor".
   - It is myopic (first transmission, expected useful bits). The paper itself says it cannot distinguish a learning failure from later costs, and that margins and headroom are in "not the same units" and are compared "only qualitatively".
   - The abstract nevertheless says the missing gain is "not due to a lack of room", and the contribution list states that the NR2 base "makes existing room easier to capture". That mechanism is untested: the headroom difference is only +0.24 points against a 2.7-point realised difference.
   - Headroom is also computed around the learner's own decision distribution (the policy's decisions), so it is a policy-dependent quantity, not a property of the comparator.
   - Recommendation 6 ("estimate headroom before training") is not validated. There is no demonstration that headroom predicts which cases the learner wins.

   **What would address it.**
   - Report a single pre-specified estimator, or show both with a selection-aware interval.
   - Show that headroom rank-orders realised margins across cases (M1 to M4, G2, G3, NR2), with the correlation and its uncertainty.
   - Temper the abstract and the contributions, and remove the mechanism sentence that is not tested.

7. **Issue.** The mechanism and heterogeneity analyses are post hoc and uneven, and they leave a deployment-relevant loss unresolved.
   **Where.** Section VI-F; Fig. 8; Section VIII-A; Limitations 4 and 5.
   **Why it matters.**
   - Users below 10 m/s (21 % of user-traces) lose −1.71 % against the original Context table, yet the speed breakdown was never run against the re-calibrated rules or for the recommended non-oracle policy.
   - The ten policies use upward steps 11–78 % of the time while achieving similar on-time ratios, which suggests that the learned policy is not a single interpretable behaviour. The "mechanism" paragraph ("accepts a higher block-error risk") is explicitly untested.
   - The recommended recipe is the one with the fewest diagnostics (no speed breakdown, no per-seed values for NR1, no fairness/edge5 report for NR2 in the text).
   - The fairness guard (Jain drop over 0.02, edge5 drop over 10 %) is defined but its outcome for NR2 and for the combined-table comparison is not shown.

   **What would address it.**
   - Run the full diagnostic set (speed bins, Jain, edge5, action analysis) on NR2 and on the G10 points against the strongest comparators.
   - Report per-user-class results with the hierarchical CIs.
   - Show whether a speed-gated deployment removes the slow-user loss, or say that the recommendation applies to an average only.

8. **Issue.** The related-work screening claim and the novelty framing are not reproducible or verifiable as stated, and some conclusions in them are asserted rather than demonstrated.
   **Where.** Abstract and Section I ("Of the 24 learning-based LA papers we screened … 0 compared"); Section II; Table I.
   **Why it matters.**
   - The 24 papers are not listed, the screening criteria and coders are not given, and the counts rest on "abstracts and accessible text". Eight "could not be determined". The headline "0 of 24" is therefore fragile and could be read as criticism of prior work, although the authors say it is not.
   - Several Table I entries are "unclear" or "not stated", and the "Parity" column is subjective.
   - The paper does not re-implement any published learned LA method (LOLLA, SALAD, Saxena's bandits, Pulliyakode and Kalyanasundaram's RL-over-OLLA), so the evidence about "RL for LA" is about one A2C design.
   - The generalised conclusions in the title and conclusion ("When does deep RL help link adaptation?") overreach relative to a single A2C recipe.
   - The recommendation that "a calibrated rule on the same cues" be the comparator is itself not novel as a methodological principle, and the closest precedents are cited only in other domains.

   **What would address it.**
   - Provide the full screening list and a coding protocol in the supplement, with a second coder or agreement statistic.
   - Narrow the title and claims to "a residual A2C policy" or add at least one more published method implemented in the same simulator.

9. **Issue.** Reproducibility and the release claims are incomplete in the submitted text.
   **Where.** Abstract ("Code, traces and the registry are released"); "Code, data and pre-registration availability" (placeholder); Acknowledgments (placeholder); Section VIII-D.
   **Why it matters.**
   - The abstract states the release as fact, but the availability statement is a "[Draft placeholder] Release DOI", and the pre-registration hashes and freeze commits cannot be verified by reviewers.
   - Section III states that all parameters are checked against code "by the number-generation script", but the claims ledger, the registry and the hashes are not available to check.
   - The registry in the paper covers 67 cases, plus a separate ledger of 9 cases (76 in total), which complicates auditing. 7 cases (18 evaluations) were superseded after an error.
   - The corrected-verdict history (the automatic summary wrongly marked the combined-table result as seed-robust until the code review) shows that the pipeline had a bug that flipped a verdict, which increases the need for independent verification.
   - The timing benchmark (Python/NumPy on a laptop CPU) is unrelated to the MATLAB simulator or any deployment target, and its tail results (0 % within the slot at 120 kHz) are not informative.
   - The AI-assistance disclosure and the funding statement are placeholders.

   **What would address it.**
   - Provide an anonymised review-time archive containing the registry, hashes, per-trace and per-seed results, and the pre-registration texts with timestamps.
   - Complete the disclosure statements.
   - Reduce the claims about deployment to the FLOP count, or measure the decision time in a realistic DU/dApp environment.

### Minor concerns

- The abstract is very dense (more than ten numerical claims) and mixes warm-up, re-calibration, non-oracle and operating-point results in a single paragraph. Lead with the seed-level result and the probability of improvement.
- Internal campaign jargon (v17, G6, G10, NR1, NR2, NR-G10, A3b/A3c, P1–P4, HR1) appears throughout without a glossary. Reviewers cannot follow the chain of amendments from the main text.
- Section VI-D.3 contains duplicated, contradictory sentences ("the check was negative … it was not reproduced", then "the gain held"). It reads like text from two drafts and should be rewritten.
- Table VII's first row labels the comparator "OLLA" with margins +11.96 / +7.49 but gives a seed-level CI [+7.15, +9.66], which belongs to the re-tuned OLLA (+8.40, footnote †). The row is easy to misread.
- Fig. 12 says "WIN: beats all 8?" while the text says nine comparators (and ten in Table VI). Make the family size consistent.
- The Bonferroni factors (972, 1 260) and the project-wide p-values (1.1×10⁻⁹, 1.00, 4.6×10⁻²⁷) should be collected in a table that shows how each is derived.
- The speed classes are described as "three" with slow/medium/fast thresholds (10 and 20 m/s). State the class boundaries in Table II and how many users fall in each.
- "Margin" mixes relative percent and percentage points, and the percent symbol is used for both. Always report both in tables.
- Table VI shows seed-level intervals only for some rows ("–" for Baseline, OLLA, Multi-OLLA, bandits). Explain why.
- The 58 % figure compares +1.58 % with +0.66 %. Most of that reduction comes from adding the oracle-based combined table, not from re-calibration (+1.43 % against the re-calibrated Context table, a reduction of about 10 %). The sentence is potentially misleading.
- The statement that "the non-oracle policy beats a table that uses the true speed class" is notable, but the observation that the oracle speed class is "worth almost nothing" (0.13 %) also undermines the paper's own use of the class-oracle rules as the "same-information" comparator. Please discuss.
- The simulator parameters for the learner (the reward weights, logit bias 3, entropy schedule) are listed in Appendix A, but there is no sensitivity analysis.
- The checkpoint selection (validation every 50 episodes on 10 traces) is noisy. Say how the final policy is chosen.
- Reference [38] is given as an editor list of a workshop proceedings; [45] is a neuroscience hierarchical-bootstrap source, and its suitability for the policy-level coverage claim should be justified. Several references are dated 2026 and some are arXiv-only; check the final bibliographic data.
- Figure 11's CDF at 120 kHz (0.0 %) and the 15 kHz result (99.9 %) both use the same laptop, so the figure says little about the policy. Consider removing it or moving it to an appendix.
- Author names, acknowledgments and the release DOI are still placeholders.

### Verdict

**Major revision** — The question and the protocol ideas (same-information calibrated comparators, seed-level intervals, a failure ledger) are worthwhile and the honesty about negative results is a strength. However, the "pre-registered and confirmatory" framing, the strongest-comparator tuning and simulator validity, the thin seed and operating-point evidence for the recommended recipe, and the incomplete release do not yet support the paper's stated conclusions.
