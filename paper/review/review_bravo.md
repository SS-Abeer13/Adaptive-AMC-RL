# Review (reviewer: bravo) — "When Does Deep Reinforcement Learning Help Link Adaptation? A Pre-Registered Evaluation Against Calibrated Rules"

Target venue: IEEE Transactions on Machine Learning in Communications and Networking.

```
SEED: 14f6a2cfdef5615e38a8879199e91d13
AXIS: Missing ablations (which component is doing the work?)
STANCE: Sharp but balanced
```

## Summary

The paper asks whether a deep-RL link-adaptation policy still beats rules calibrated on the learner's own cues. In one MATLAB simulator (10 users, one cell, multi-process HARQ), the authors report four things.
- A residual A2C policy beats OLLA by +7.49 % on-time delivery after warm-up.
- Re-calibrating the rules on 500 traces removes 58 % of the margin over the best rule. The remaining +0.66 % over a 36-cell "combined table" is not seed-robust (hierarchical 95 % CI [−0.30, +1.70] %).
- A "non-oracle" variant (NR1/NR2) beats the combined table by +3.35 % ([2.22, 4.40] %).
- On full-buffer goodput the learner adds nothing.

The negative result is the best part of the paper. It is honest and well documented, and it is a useful corrective to the "RL beats OLLA" literature. The disciplined statistics (CRN, disjoint splits, hierarchical seed×trace bootstrap, Holm correction) are above the norm for this field.

My main problem is attribution. The paper's headline positive claim, the recommended "non-oracle residual configuration", is a bundle of design choices: base rule, action set, state features, reward shaping, initialisation bias, deviation penalty, frame stacking, and 3000 episodes. Hardly any of these is ablated, and the paper never isolates what in the bundle produces the gain. It also never says whether the gain depends on learning at all or on a richer state than the table sees. The recipe was selected over 17 campaign versions, and the confirmatory replication was added by amendment after the results were known. So the "pre-registered" label covers less of the positive claim than the abstract suggests.

## Major concerns

1. **Issue** — The +3.35 % NR2 gain is attributed to "a learned residual on a non-oracle calibrated offset" with no decomposition of which component produces it. `[Evidence — ablations]` (primary axis, pressed hardest)
   - **Where** — Sec. VI-D.2 (NR1/NR2), Sec. VIII-B, Table III, Appendix A. Ablations beyond "Fixed vs FixedPU base" are absent.
   - **Why it matters** — The residual policy differs from the combined table in many ways at once:
     - continuous or finer slack than 3 bins;
     - three stacked frames of 19 features, including observed SINR and ΔCQI;
     - three HARQ-process features, where the table has one binary "busy" bit;
     - a 3-way action {−1, 0, +1};
     - shaped reward, deviation penalty 0.02|δ|, initial logit bias 3 on δ = 0 (a strong prior toward the base rule), and 3000 episodes.

     The reader cannot tell whether "RL helps" or "this particular feature set and prior helps". The existing evidence points to the second reading: the 800-episode variant is much weaker (+0.62 % over Fixed vs +1.87 %). The goodput policy collapses to δ = 0 in 5000/5000 cells. The 10 seeds differ wildly (11–78 % upward steps) yet score about the same.
   - **What would address it** — A component-wise ablation on the NR2 protocol, with seed-level intervals:
     - (a) state-feature ablation: remove the frames, SINR/ΔCQI, then the HARQ features, then slack, one at a time;
     - (b) action-set and prior ablation: widen the action set, remove the logit bias, remove the deviation penalty;
     - (c) reward ablation: with and without shaping;
     - (d) a non-learned stateful control over the same features, for example the gradient-boosted/tree policy already built for HR1 deployed as an actual policy, or a finer table (more slack bins, 3-level busy count, observed SINR bin) calibrated with the same 500-trace budget.

     Without (d), "learning" is not separated from "more information".

2. **Issue** — The comparator that defines the headline is not information-matched to the learner. The combined table was never given the HARQ-count, SINR or ΔCQI granularity that the learner sees, and it was never scaled up to the learner's budget. `[Evidence — baselines]`
   - **Where** — Table III (rows "Combined table" and "Residual A2C, Fixed base"), Appendix C, Sec. VI-B.
   - **Why it matters** — The paper's own thesis is that a calibrated rule on the same cues is the right control. Table III shows the table has 3 slack bins, delay class, speed class and a binary busy flag. The learner has ΔCQI, observed SINR, 3 frames and several HARQ features. The NR2 comparison (+3.35 %) pits a non-oracle learner against a table whose extra "oracle" info is a feature the paper itself shows is worth about 0.13 %. In effect the paper compares a rich-state learner against a coarse-state table and credits the difference to learning. The authors acknowledge the table's search was capped on one start (24.6 h), which is a one-sided hint that the baseline is still not tuned to the learner's level.
   - **What would address it** — The ablation in (1d). Also an NR2-matched table built on the Fixed base with the same cue granularity (not the FixedPU oracle). The current NR2 comparator is the oracle-based combined table, so the "non-oracle policy vs oracle table" framing is not a like-for-like test of learning.

3. **Issue** — The recommended recipe is post-hoc, and the confirmatory test is narrower than the abstract implies. `[Post-hoc-shaped hypothesis / Narrative — overclaiming]`
   - **Where** — Abstract ("confirmed in a pre-registered replication… the gain also held at two neighbouring operating points"), Sec. V-D, Sec. VIII-E item 6 and item 9, Table XIV (NR2: "added after the other results were known").
   - **Why it matters**
     - The M1 recipe with the oracle base failed at both neighbouring points. The recommended non-oracle recipe was then chosen after seeing NR1 and G6 results, and re-tested at those same two points (NR-G10). The paper itself says "selection effects cannot be fully excluded".
     - NR2 is a single operating point with a single comparator. The only table at G2/G3 with a decision rule is a single-cue rule. The combined-table comparison at G2/G3 is "descriptive" and not pre-registered.
     - The abstract says the gain "also held at two neighbouring operating points". The body qualifies this to single-cue rules, 5 seeds, 300 traces. A reader of the abstract alone will believe the recipe beats the combined table at three points, which is not established.
     - The abstract also uses "robustly" for the +3.35 % result. That is fine for NR2 on fresh seeds, but the same recipe family was shown to be unstable across seeds in M1.
   - **What would address it** — State in the abstract that the non-oracle recipe was selected post hoc after the M1 and neighbouring-point failures, that NR2 is a single point, and that the G10 comparison is against single-cue rules only. Better, add a fully pre-registered run of the non-oracle recipe at a new operating point against a per-point combined table with the full 500-trace budget.

4. **Issue** — The multiplicity accounting is internally inconsistent in how it is used rhetorically. `[Statistical rigour]` (secondary)
   - **Where** — Sec. V-D, C1 ("NR2 keeps p = 4.6×10⁻²⁷ after the project-wide Bonferroni factor").
   - **Why it matters** — Quoting p = 4.6×10⁻²⁷ as confirmatory strength is misleading. That p is a trace-level Wilcoxon test on 500 traces where the 10 seeds are fixed. Traces are the pseudo-replication unit and seed variance is the dominant source of non-replication, as the paper itself shows in M1 (trace-level Holm p = 1×10⁻³, hierarchical CI includes zero). The seed-level evidence for NR2 is 9/10 seeds (sign test about 0.01) and a hierarchical interval. The headline p-value should not be used. Also, the registry count (72 or 126 evaluations, "at most 1260 tests") is a Bonferroni factor by construction and does not reflect the true forking path of 17 versions.
   - **What would address it** — Drop the 10⁻²⁷ figure from the contributions. Report the seed-level result as the primary evidence.

5. **Issue** — Some "baselines" in the tables are not credible comparators. `[Evidence — baselines]`
   - **Where** — Table V (Bandit rows: 41.80 % on time, +46.55 % margin), Table X–XI.
   - **Why it matters** — Bandits scoring 41.8 % when open-loop CQI scores 52.5 % indicate under-tuned or mis-specified bandits. Their presence inflates "beats all nine comparators" and the WIN verdicts (the registry counts a WIN as beating every comparator). It also muddies the claim that RL is compared against learned alternatives. Multi-OLLA at 54.6 % is no better than OLLA, so it is not a meaningful strong-OLLA control either.
   - **What would address it** — Either tune the bandits to at least match Fixed, or remove them from the WIN family and say they are non-competitive.

6. **Issue** — The headroom analysis (HR1) does not do the work the conclusion assigns it. `[Distinguishing-test failure]`
   - **Where** — Sec. VI-G, Fig. 9, Conclusion ("one-step room… existed in every case, so where the learner added nothing the reason is not a lack of such room").
   - **Why it matters** — HR1 is myopic, in expected useful bits, uses gradient-boosted trees fit on the same logged decisions (cross-fitted) and the estimate depends on the predictor (gbt_a vs gbt_b). The authors concede it cannot separate "learner failed" from "later costs cancel the gain". The headroom difference between oracle and non-oracle base is 0.24 points against a realised 2.7-point difference. So HR1 does not explain the NR2 gain either. The recommendation to "estimate headroom before training a deep policy" is not validated: no case is shown where HR1 predicted a learner win or loss ahead of time. In M1 it predicts 5.4–5.7 % for a policy that realises 0.66 %.
   - **What would address it** — Show that HR1 predicts which of M1–M4 and G2/G3 the learner wins, with a correlation or calibration check, or soften the planning recommendation to a hypothesis.

7. **Issue** — The seed-to-seed behavioural spread is a red flag that the policy is mostly a noisy perturbation of the base rule. `[Evidence — alternative explanations]`
   - **Where** — Sec. VI-F.1, Fig. 8b, Sec. VIII-A.
   - **Why it matters** — Upward-step share ranges from 11 % to 78 % across seeds with close on-time ratios. That is what you expect if the policy is exploiting a broad flat optimum around the base rule, or if the gain comes from a mild upward bias at busy HARQ / low slack that a 2-parameter rule would capture. The paper offers a mechanism ("accepts a higher block-error risk") and then says "we have not tested this mechanism". An obvious alternative the authors do not test is that a hand-written rule "δ = +1 if busy ≥ 1 or slack ≤ 0.6 or burst, else 0" on the Fixed base reproduces most of the +3.35 %. This costs nothing and would be the cleanest ablation of "learned vs. designed".
   - **What would address it** — Add that hand-written rule (and a calibrated version of it) as a comparator on NR2 traces.

8. **Issue** — Heterogeneous-user and warm-up checks were run only on the original, not the recommended, configuration. `[Evidence — ablations / Limitations]`
   - **Where** — Sec. VI-D.1, VI-F.2, VIII-A, VIII-E item 4.
   - **Why it matters** — The slow-user loss (−1.71 %, 21 % of user-traces) is a claim about the superseded M1/oracle policy against the original Context table. The recommended configuration's speed breakdown, and its behaviour against OLLA after warm-up, were never computed. The paper flags this, but the "recommendation" in the abstract rests on exactly the cells that were not run. A deployment-minded reader cannot tell whether the recommended policy hurts slow users.
   - **What would address it** — Run the speed breakdown and the warm-up comparison for NR2 policies (both are logged-data analyses that cost no additional training).

9. **Issue** — Replicability is not currently demonstrable. `[Reproducibility]`
   - **Where** — "Code, data and pre-registration availability" section ("[Draft placeholder] Release DOI"), Acknowledgments (refers to `submission_checklist.md`), author names placeholder.
   - **Why it matters** — The paper's central claim is methodological ("every number is regenerated from released macros"). The release is a placeholder with no link, and the pre-registration files and hashes cannot be checked. An internal filename leak in the acknowledgments suggests the draft is not final. A pre-registration whose timestamps cannot be verified externally is much weaker than the text implies, especially since NR2 was an amendment. The simulator is a single MATLAB code base with an SINR-to-BLER abstraction and no cross-validation in ns-3 or Sionna. The authors acknowledge this, but it means a competent grad student cannot reproduce any headline number today.
   - **What would address it** — Deposit code, traces, seeds, frozen pre-registration texts and hashes in a public repository (with an independent timestamp such as OSF or a git tag) before review.

## Minor concerns

- The abstract is overloaded: roughly 12 numerical claims, three recipes (original, non-oracle, G10), several intervals of different levels (90 % trace-level, 95 % hierarchical). A reader cannot extract the one take-away. Cut to the three claims listed in the Introduction.
- "Margin" is a relative percentage (100 d/x). Several figures and sentences mix relative % and percentage points (+0.66 % ≈ +0.40 pp; "differ by 2.7 points" between +3.35 % and +0.66 %). Define one unit for the abstract. The 3.35 % relative gain is only a few percentage points on a 0.62 on-time ratio.
- Trace-level CIs are 90 % while the seed-level are 95 %. This is explained, but it makes figures such as Fig. 6a hard to read at a glance.
- Sec. VI-D.3 contains a self-contradictory paragraph: "the check was negative… it was not reproduced" and then "we then ran the same check with… the gain held". The edit history is visible in the text. Likewise, Sec. VIII-E item 5 is duplicated almost verbatim from Sec. VI-D. Tighten.
- Warm-up for OLLA is only 200 TTIs and each trace scores 150 TTIs after burn-in. Whether OLLA's steady-state target-tracking would close more of the 7.49 % gap with longer traces is not shown. Real OLLA runs continuously for the connection lifetime, so the "+7.49 %" depends on trace length by construction.
- The interference-burst Markov process, 12 000-bit packets and the 10-TTI budget fix one narrow operating regime. Only 10 users and one scheduled user per TTI. Please state clearly in the abstract that all results are for a single traffic configuration.
- The decision-time benchmark (Fig. 11) is on a laptop CPU in Python/NumPy, Windows 10, and the text says it is not a real-time feasibility result. It then occupies a whole subsection and a figure. Either shorten or remove, since the 120 kHz figure (0.0 %) invites misreading.
- Table I's "Calibr. rule / Parity" entries are based on abstracts and "accessible text", with 8 of 24 papers "could not be determined". The headline statistic "0 of 24 compared against such a rule" is thin as a literature finding. Present it as a screening estimate, with the screening protocol in an appendix.
- "Hierarchical bootstrap [45]" is cited to a 2019 neuroscience tutorial. A statistics reference for the two-level bootstrap with a small number of upper-level units (10 seeds) would be better, since percentile bootstrap intervals with 10 clusters are known to be anti-conservative.
- The Context-table numbers in Table XIII are reported to 4 decimals without error bars. A 0.0002 calibration–evaluation gap is not evidence of "no over-fitting" without a sampling distribution.
- Reference [38] is an edited proceedings volume, and [4], [32] are described as 2026 works. Please check dates and venues.
- The paper is very long for the information content. The pitfalls section (Sec. VII) is useful but belongs closer to an appendix or a separate short paper.

## Belief update

- **Strong update (down):** the proposition "deep RL link adaptation beats strong, same-information static rules" drops, and this is the paper's real contribution. Against re-calibrated single-cue rules the gain is about +1.4 to +1.9 %. Against the combined table the original policy is a coin flip (P(improve) = 0.55). On goodput it is negative. I take this at face value, since the authors have every incentive not to publish it.
- **Moderate update (down):** the PF-averaging timing, mobility time-scale and slot-stealing pitfalls make me less willing to trust any published multi-process-HARQ gain over OLLA that does not state its PF definition. Credit to the authors for reporting and quantifying these.
- **Small update (up, with reservations):** a learned residual on a static calibrated offset can add about +3 % on-time delivery over a 36-cell combined table at one operating point (9/10 seeds). I do not update much, for three reasons: (a) the table is not information-matched to the learner, (b) no component ablation exists, and (c) the recipe is post hoc. I do not accept the stronger claim "RL helps in this regime"; the data fit equally well with "a richer state and a prior toward the base rule help".
- **No update:** the headroom analysis as a planning tool. It is not shown to predict anything.

### Verdict

**Major revision** — The strongest concern is the missing ablation of the recommended recipe: the +3.35 % NR2 gain cannot be attributed to learning rather than to the learner's richer state, action prior and reward design, because there is no component ablation, no information-matched non-learned control, and no hand-written rule on the same features.
