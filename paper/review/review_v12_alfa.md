# Review (alfa): "Deep Reinforcement Learning for Link Adaptation Beats Calibrated Rules but Not a Supervised One-Step Learner: A Pre-Registered Simulation Study"

## Summary

The manuscript studies downlink link adaptation (LA) in one MATLAB simulator: a single cell, 10 users, a PF scheduler that serves one user per TTI, and multi-process HARQ. It compares a residual A2C policy against OLLA variants, calibrated offset tables, hand-designed rules and, in Section VII, supervised gradient-boosted (GBT) one-step learners on the same gNB-observable features. The evaluation protocol is unusually careful: disjoint calibration, validation and evaluation traces; common random numbers; ten training seeds with hierarchical seed×trace bootstrap intervals; frozen and hashed comparator tables; pre-registered decision rules and wording; and a project-wide multiplicity count.

The new headline (title, abstract, Introduction item 3, C3, Section VII, Section IX-A/B, Table IX, Conclusion) has three parts:
1. The non-oracle residual A2C policy (NR2) beats the strongest calibrated table (+3.35 %, hierarchical 95 % CI [2.22, 4.40] %) and the hand-designed rules (+3.21 %).
2. A GBT classifier of p̂(ACK | x, MCS), trained on ε-greedy (ε = 0.5) exploration logs, beats NR2. The abstract quotes "7.58 % fewer packets on time" for NR2 relative to GBT-full-ACK, with 0 of 10 seeds above it.
3. The replication R1c reports the same ordering over four calibration draws and, with per-cell retraining, at two neighbouring operating points (G2, G3).

The numbers are internally consistent wherever I could check them (Tables VII and VIII against the text and abstract). The finding is useful and is reported honestly in many places. However, the comparison behind the headline is not like-for-like in several ways the paper does not foreground:
- The quoted −7.58 % compares learners with different action sets.
- The RL agent got no reported tuning budget and shows signs of being under-trained.
- RL policies may be evaluated stochastically while the GBT acts greedily.
- The simulator's deadline/RTT structure makes the problem close to a contextual bandit, which makes the "myopic model still wins" result much less surprising than the text presents it.
- The general wording ("deep RL", "supervised", "deployable", "notable") outruns one A2C configuration in one simulator.

I recommend a major revision. Most of the concerns can be addressed with analyses that are cheap given the released infrastructure.

## Major concerns

### 1. The headline margin (−7.58 %) mixes the action-set difference with the learning paradigm

- **Issue.** NR2 is a residual policy: δ ∈ {−1, 0, +1} on the Fixed base of −2 CQI steps, so its total offset is in {−3, −2, −1}. GBT-full-ACK chooses "over all offsets", and its exploration logs use offsets from −4 to +2 (Section VII-B). It can therefore pick offsets up to 3 steps more aggressive than anything NR2 can reach. The like-for-like learner is GBT-res-ACK, at −3.40 % (hier. 95 % CI [−4.43, −2.47] %). Yet the abstract, Introduction item 3, Table IX ("one-step learner on observed ACK/NACK (GBT-full-ACK) −7.58") and the Conclusion all lead with the full-set number. Section VI-F shows that the residual bound is binding:
  - NR2 takes the maximal step δ = +1 in 62.0 % of decisions overall.
  - It does so in 93.0 % of decisions with a busy HARQ process and 97.9 % when at most 0.6 of the deadline budget remains.
  - In 8.6 % of decisions the base offset was clipped at the lowest CQI.

  A policy that saturates its upper action bound in nearly all of its most important states is constrained by its action set, not only by its learning method. The only full-action RL variant (offset A2C, δ ∈ [−4, +2]) was trained for 800 episodes, not 3000 (Table III). Section V-D reports that it "failed Claim B" in M1. It was not retrained on the non-oracle setup or compared with GBT-full-ACK.
- **Where.** Abstract ("the RL policy delivers 7.58 % fewer packets on time"); Section I item 3; C3; Section VII-B/C; Table IX; Section X.
- **Why it matters.** Roughly half of the headline gap (−7.58 % against −3.40 %) is what the GBT gains by escaping a constraint that only the RL agent was subject to. A reader of the abstract will attribute all of it to "supervised one-step vs deep RL".
- **What would address it.**
  - Make the matched action set (GBT-res-ACK, −3.40 %) the headline number everywhere, and report −7.58 % as "with a larger action set".
  - Alternatively, train an RL agent with the same full action set (offset A2C on the Fixed base, 3000 episodes, ten seeds) and compare it with GBT-full-ACK.
  - Also consider a wider residual (δ ∈ {−2, …, +2}) for RL.
  - Report how often GBT-full-ACK chooses offsets outside {−3, −2, −1}.

### 2. The RL learner's tuning budget is unreported and there are signs it is under-trained, while the paper demands tuning parity for rules

- **Issue.** Section IX-B argues that "a fair comparison therefore needs a comparable tuning budget for the rules, and that budget should be reported, as for the learner". The combined table received 24.6 h of search. For A2C, however, Table X gives one fixed hyper-parameter set, "the same values … in all cases", with no search reported. The GBT is described only as "the same settings" with two pre-fixed tree models (Section VI-G). Several facts in the paper point to an RL optimisation shortfall:
  - The margin over Fixed rises from +0.62 % at 800 episodes to +1.87 % at 3000 (Fig. 7b), and no longer run or learning curve is shown.
  - Per-seed behaviour varies enormously (11–78 % upward steps, Section VI-F).
  - A deterministic ensemble of the M1 seeds reaches 0.6306 against a per-seed mean of 0.6126, about +2.9 % (Section VI-C). That is close to the size of the matched GBT-res-ACK gap.
  - The design deliberately anchors the policy to the base rule: an initial logit bias of 3 on δ = 0, a deviation penalty of 0.02|δ|, and an entropy schedule. The GBT has no such prior.
- **Where.** Section IV-C; Table X; Section VI-E (training length); Section VI-C (ensemble); Section IX-B; Limitation 15.
- **Why it matters.** "Deep RL is not needed for the gain on these cues" (C3) and "deep RL was not the best way to learn here" are claims about RL as a method. As things stand they are supported only for one untuned A2C configuration that is regularised toward the base rule.
- **What would address it.**
  - Report the tuning budget for both learners: hyper-parameter trials, environment steps, wall-clock time.
  - Give RL a budget comparable to the combined-table search, e.g. a modest search over learning rates, γ, n-step, entropy, deviation penalty and logit bias, plus longer training with learning curves on validation traces.
  - Report the NR2 ensemble and the best single seed against GBT-res-ACK.
  - Include at least one other standard algorithm (e.g. PPO or a DQN variant). The paper itself lists DQN, TD3 and PPO in the LA literature (Section II-B).

### 3. Possible greedy-vs-stochastic evaluation asymmetry, and unclear data/sample budgets

- **Issue.** The manuscript does not say whether the A2C policies act greedily (argmax) or sample from the softmax at evaluation. The GBT policy is greedy by construction (argmax of p̂ × useful bits). The phrase "A deterministic ensemble of the seeds is a secondary scheme" (Section IV-C) and the sizeable ensemble gain suggest that per-seed policies might be stochastic. Separately, the amount of experience available to each learner is not compared:
  - The GBT is fit to 500 calibration traces with ε = 0.5 exploration over seven offsets.
  - RL trains for 3000 episodes, but the number of transitions and distinct traces is not given.
- **Where.** Section IV-C; Section VII-B; Table X.
- **Why it matters.** Sampling at evaluation would systematically handicap RL in a head-to-head with a greedy learner. Unequal data volumes or coverage would also confound "which paradigm" with "which data".
- **What would address it.**
  - State the evaluation action-selection rule. If it is stochastic, re-evaluate NR2 greedily.
  - Report decisions/transitions seen by each learner and the action coverage of each dataset.

### 4. The "myopic model still wins" interpretation is under-hedged; the setup is nearly a contextual bandit by construction

- **Issue.** Section VII-E calls the myopic model's win "the notable part of the result". Section IX-A concludes that "sequential credit assignment bought less than accurate one-step estimation". The simulator's own parameters make limited sequential structure the expected outcome:
  - Packets of 12 000 bits arrive every 20 TTIs with a 10-TTI budget (Section III-E). There is therefore no queue carry-over between packets.
  - With RTT 8 and a 10-TTI budget, at most one HARQ retransmission can fall inside the deadline.
  - Retransmissions reuse the stored MCS, so "the learner's action affects new transmissions only" (Section III-C).
  - One user is scheduled per TTI among 10.

  In such a setting most of the decision value is the per-transmission trade-off between success probability and transport-block size, as the paper's own reading suggests. A good contextual-bandit (direct-method) estimator should then be expected to do well. The useful-bits term may also already encode the remaining-bits/deadline information, which would add implicit horizon awareness; the text does not say. In addition, the label-generating process is a smooth SINR-to-BLER abstraction (Section III-B), which favours a supervised probability estimator. Section IX-E item 1 notes that the ranking could change with another link abstraction, but Section VII-E does not connect the result to these structural features.
- **Where.** Section VII-E; Section IX-A; Limitation 13; Abstract ("It did so although it plans nothing ahead" in the Conclusion; "plans nothing ahead, and it still wins" in Section I item 3).
- **Why it matters.** "Notable" and "still wins" invite the reader to generalise against RL. The more defensible reading is that the task, as simulated, offers little multi-step credit to assign.
- **What would address it.**
  - Discuss explicitly the deadline/RTT/arrival structure and how many retransmissions fit within the budget.
  - Define "useful bits": is it capped at the remaining packet bits?
  - Add the decisive ablations, which use existing infrastructure:
    - (a) A2C with γ = 0 and an immediate useful-bits reward. This separates "sequential credit" from "optimisation/sample efficiency of policy gradient". If it also loses to the GBT, the gap is about learning efficiency, not myopia.
    - (b) Fitted-Q iteration (with the same GBT regressors) on the same ε-greedy logs, with γ > 0 vs γ = 0. This isolates the value of multi-step credit with identical data, features and function class.
    - (c) A residual RL policy on top of the GBT-res-ACK/GBT-full-ACK policy as base rule. If RL cannot improve on it, that directly supports the "nothing left to credit sequentially" reading.
  - Soften "notable" until such tests exist.

### 5. "Supervised vs deep RL" framing, the bandit inconsistency, and the "deployable"/"exploration price" asymmetry

- **Issue.** The GBT-ACK learner is, methodologically, an offline greedy contextual bandit (direct method) learned from logged ε-greedy data. That makes three things inconsistent or one-sided:
  - **The framing.** The paper frames it as a "supervised one-step model" and positions it against "deep RL", without relating it to the offline contextual-bandit / off-policy learning literature. The related-work section covers bandits for LA [19], [2], [20], [21] but not this connection.
  - **The bandit comparators.** The paper's own "two contextual bandits (global; per delay class)", trained on the learner's episodes, are the worst comparators by far: 41.80 % on time, a +46.55 % margin for A2C (Table V). The paper does not explain why its bandit comparators fail so badly while a bandit-style learner on the same cues is the best scheme. That raises the question of whether the bandit baselines were under-specified, which matters for the "RL beats" half of the headline too.
  - **Deployability.** Section VII-B calls the ACK-trained GBTs "These deployable versions". Section VII-E says the result "has a price the RL policy does not pay in the same form" (exploration). But both learners were trained entirely in simulation on calibration traces. RL training is itself on-policy exploration. Limitation 12 concedes that neither exploration cost was measured. The practical distinction is therefore asserted rather than shown.
- **Where.** Section II-B; Section V-B (bandit definitions); Table V; Section VII-B/E; Section IX-A; Limitation 12; C3 ("although the supervised learner needs exploration logging").
- **Why it matters.** Readers from ML will read the result as "one-step contextual bandit beats multi-step actor-critic on a near-bandit problem", which is a narrower and more expected claim than the title implies. The asymmetric "price" statement tilts the interpretation without evidence.
- **What would address it.**
  - Describe the GBT-ACK learner as an offline contextual-bandit / direct-method policy and cite accordingly.
  - Explain the design of the bandit comparators (context, arms, exploration) and why they underperform.
  - Drop or substantiate "deployable".
  - State symmetrically that both approaches require exploration, either offline or online, with unmeasured cost.

### 6. Headline wording generalises beyond the evidence

- **Issue.**
  - The title and abstract say "Deep Reinforcement Learning … Not a Supervised One-Step Learner" and "deep RL is not the best learner". The evidence is one A2C architecture (57-128-96-3), one hyper-parameter set, one action parameterisation and one simulator.
  - The "RL beats calibrated tables" half rests on NR2 against the combined table at the M1 point only. At G2/G3 the combined table was outside the pre-registered family (Section VI-D3; Limitation 5).
  - The non-oracle recipe was selected on M1's evaluation traces (NR1, Section V-D).
  - The GBT controls entered as Amendments 8, 9 and 10a after the main and NR2 results were known (Table XVI). The paper's framing was changed around them (Fig. 12: "a reframing of the paper is considered only after CONFIRM together with WIN"). Yet the title says "A Pre-Registered Simulation Study", and the reader cannot tell when the Section VII controls were conceived relative to the outcomes they reframe. Were the ε = 0.5, the offset range and the GBT settings fixed before any R1/R1b result? This matters for R1b in particular, since its design followed R1.
- **Where.** Title; Abstract; Section I ("This is narrower than most of the literature suggests"); C3; Section X.
- **Why it matters.** The paper's credibility rests on pre-registration discipline. The headline should be worded with the same discipline.
- **What would address it.**
  - Qualify the title and abstract, e.g. "a residual A2C policy" rather than "deep RL", and "in one simulator".
  - Give a dated timeline of when each amendment was frozen relative to which results were known.
  - State explicitly that the paper's framing changed after R1/R1b.

### 7. Uncertainty treatment of the learner-vs-learner comparison is asymmetric and verdict wording is inconsistent

- **Issue.**
  - **Uncertainty.** In Table VII the hierarchical seed×trace CIs resample RL seeds but treat each GBT fit as fixed. R1c reports only the mean and min/max over four fits and trace-level Holm tests (Appendix D: "Holm over 8 per trace set"). No interval combines GBT fit variance with RL seed variance. Table IX's seed-level column for the cells reads "– (Table VIII)", but Table VIII has no seed-level interval.
  - **Verdict wording.** The R1c criterion is "beats or matches". The text repeats "beat or matched" twice, in two near-identical template sentences in Section VII-C, again in Section I item 3, C3 and Section X. It then says "No fit merely matched". Section IX-A says "every fit beat the RL policy". The stronger, supported statement ("beat in every trace set") should replace "beat or matched" consistently.
  - **Units.** "7.58 % fewer packets" is a relative margin: 0.6201 against 0.6710, about 5.1 percentage points. The abstract does not give the absolute difference, although the paper gives percentage points elsewhere (e.g. +0.40 pp).
- **Where.** Table VII; Table VIII; Table IX; Section VII-C; Section I; Section X.
- **What would address it.**
  - Add a two-level bootstrap over GBT calibration draws × RL seeds × traces for the R1c comparisons.
  - Unify the verdict wording.
  - Add absolute (pp) differences in the abstract and Table IX.

### 8. Unexplained anomaly: observed-ACK labels beat true-SINR labels

- **Issue.** R1 uses simulator labels (expected useful bits computed from the true SINR). These are available counterfactually for every candidate offset, so the logging policy only affects the state distribution. Yet the ACK-trained policies beat their true-SINR twins (+0.73 % and +2.21 %, Section VII-B). The paper notes that labels and logging differ, but does not investigate further. There is also a modelling difference: R1 trains one model per offset, while R1b trains one classifier with the MCS as an input.
- **Why it matters.** A noisier label beating a noiseless one suggests that the gain may come from something other than "accurate one-step estimation": the state coverage induced by exploration, pooling across MCS in a single model, or how useful bits are computed at decision time. That bears directly on the paper's interpretation of why the one-step learner wins.
- **What would address it.** Run a small factorial: label type × logging policy × one-model-vs-per-offset. At minimum, fit true-SINR labels on the exploration-logged states.

## Minor concerns

- **Roadmap omits Section VII.** Section I says "Section VI reports the results, the pre-registered robustness checks, the controls on the learner's cues and the headroom analysis, Section VIII the pitfalls…". Section VII, the "main result", is not mentioned, and the controls are attributed to Section VI.
- **Duplicated template sentences.** The two R1c verdict sentences in Section VII-C are near-verbatim duplicates, differing only in "restricted to base ±1" vs "over all offsets"; merge them. The same applies to the duplicated G10 negative-result sentence ("The result was observed at the M1 operating point only; …"), which appears verbatim in Section VI-D3 and Limitation 5 with a capitalisation glitch after a colon.
- **Reference mismatch.** The text cites "Pulliyakode and Kalyanasundaram [25]", but reference [25] lists "S. K. Pulliyakode and S. Kalyani".
- **Wrong cross-reference.** Section IX-A says the non-oracle configuration "passed the seed-level rule against the combined table (Section IX-B)". The evidence is in Section VI-D.
- **Missing sign.** Section VI-D2 writes "(3.35 %, hierarchical 95 % CI …)" without a sign. Elsewhere the convention is "+3.35 %".
- **Abstract mixes policies without saying so.** "Against OLLA it is 7.49 % after a 200-TTI warm-up" refers to the M1 oracle-base policy, whereas the surrounding sentences are about NR2 (whose warm-OLLA margin is +9.86 %, Section VI-D2). Name the policy.
- **Abstract overstates "adds nothing".** "On full-buffer goodput RL adds nothing (−0.88 %)" omits M4 (−1.73 %), where it does worse than its base rule. "Adds nothing or loses" is more accurate.
- **Inputs to the GBT vs RL.** Table III says the one-step learners use the features "as offset A2C" plus the MCS, and the A2C uses "3 frames". Section VII says the controls see "only the 19 observable features". Clarify whether the GBT sees one frame or three stacked frames, and whether the RL state includes the current MCS.
- **"useful bits" undefined.** Define it in Section VII-B: is it capped at the remaining bits of the packet? This matters for concern 4.
- **Table IX statistics are mixed.** The M1 GBT row reports the single R1b fit with a hierarchical CI. The G2/G3 rows report the weakest of four fits with no interval. Make the statistic uniform or label each row.
- **Table IX "Beats" column semantics.** "no (learner better)" is confusing, because both schemes are learners. Use "no (comparator better)".
- **Registry description.** The abstract says "all 104 cases are registered". Limitation 9 says the released registry covers the 67 main-round cases and that the 37 robustness cases are "listed in Appendix D", but Table XVI lists checks, not 37 cases. Align these statements.
- **Multiplicity.** Report project-wide-corrected p-values for the R1b/R1c comparisons, as is done for NR2 (Section V-D). They will almost certainly survive, but the paper should be consistent.
- **Section VII intro overstates.** "Beats the RL policy at every step" includes R1, which uses non-deployable simulator labels. Fine as stated, but say which steps are deployable.
- **ECE/Brier.** Reporting calibration only on "decisions taken by both policies" is useful. Also report ECE per offset/MCS for the rarely explored aggressive offsets, which are where GBT-full-ACK differs from NR2.
- **Fairness in Section VII-D.** The bottom-decile column is "often zero". Consider per-user 10th-percentile packet delay or the per-user on-time ratio across a pooled set of traces instead.
- **Extraction/hyphenation artefacts.** Fix "handdesigned", "gradientboosted", "deadlineconstrained", "pvalues" and "nonoracle" if they are in the source rather than the extraction.

## Verdict

**Major revision.** The protocol is exemplary and the RL-vs-rules evidence is solid. However, the new headline that a supervised one-step learner beats deep RL rests on three things:
- a margin (−7.58 %) inflated by an action-set asymmetry;
- an untuned and possibly stochastically evaluated single A2C configuration;
- a "myopic still wins" interpretation that ignores how close the simulated task is to a contextual bandit.

The headline therefore needs matched-action-set and matched-tuning comparisons, a γ = 0 / fitted-Q ablation, and correspondingly narrower wording before it can be accepted.
