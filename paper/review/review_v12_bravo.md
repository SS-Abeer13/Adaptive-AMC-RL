# Review (bravo): "Deep Reinforcement Learning for Link Adaptation Beats Calibrated Rules but Not a Supervised One-Step Learner: A Pre-Registered Simulation Study"

## Summary

The manuscript studies downlink link adaptation (LA) in one MATLAB simulator. The setup is a single macro cell with 10 users and one user scheduled per TTI. The model includes Jakes fading, a two-state interference burst process, CQI reports delayed 2–8 TTIs with 1 dB noise, an SINR-to-BLER abstraction, and chase-combining HARQ (RTT 8 with 8 processes, or RTT 0). The learned schemes act as CQI offsets on top of an OLLA reference. The protocol is careful:

- disjoint calibration, validation and evaluation traces;
- common random numbers;
- ten training seeds and hierarchical seed×trace bootstraps;
- pre-registered decision rules and wording;
- a public case registry with project-wide multiplicity accounting.

The paper's arc has three steps:

1. A residual A2C policy beats OLLA by a large margin, but most of that margin goes away against rules calibrated on the learner's cues. The oracle-base M1 policy is +0.66 % over the combined table and is not seed-robust.
2. A non-oracle residual policy (NR2) beats the frozen combined table robustly (+3.35 %, hier. 95 % CI [2.22, 4.40] %). It also beats hand-designed rules (+3.21 %).
3. The new headline (Section VII): a gradient-boosted one-step success model, trained on ACK/NACK logged under ε = 0.5 exploration, beats NR2. NR2 delivers 7.58 % fewer packets on time than GBT-full-ACK and 3.40 % fewer than GBT-res-ACK. Replication R1c repeats this over four calibration draws at M1, and with per-cell retraining at two neighbouring operating points (G2, G3).

The methodology is well above the norm for learned-LA papers. The arithmetic I could check is internally consistent: Table VII ratios, R1c worst-fit margins, registry totals, the 83 %/85 % and 58 % shares, and the OLLA step size. The negative-result framing is valuable.

My concerns are about the new headline. In its current form, the "supervised vs deep RL" comparison mixes up three things:

- the learning paradigm;
- the size of the action set;
- the data and exploration regime.

The deployability language ("deployable versions", "labels a gNB observes") is ahead of the evidence. The operating points are structurally close to a one-shot decision, which favours a myopic learner. Fairness and BLER side effects are reported with metrics that cannot separate the schemes, or are not reported at all. The title and the headline sentences in the abstract and C3 state a general ranking of learning paradigms, but the evidence is one simulator, one RL design and three neighbouring deadline-traffic points.

## Major concerns

### 1. The 7.58 % headline mixes the learning paradigm with the size of the action set

- **Issue.** NR2 is a residual policy restricted to δ ∈ {−1, 0, +1} around a Fixed base of −2 CQI steps (Sections IV-A, VI-D-2). GBT-full-ACK chooses "over all offsets", i.e. −4 … +2 (Section VII-B). So GBT-full-ACK can choose offsets up to three CQI steps more aggressive than anything NR2 can reach.
  - The paper's own action analysis suggests NR2 is pressing against its action bound. It takes δ = +1 in 62.0 % of decisions overall, 93.0 % with a busy HARQ process and 97.9 % when ≤ 0.6 of the budget remains, and 8.6 % of its decisions are clipped at the lowest CQI (Section VI-F-1).
  - The like-for-like comparison is GBT-res-ACK vs NR2: −3.40 % (weakest R1c fit −3.10 %). That is less than half the abstract's figure.
- **Where.** Abstract ("the RL policy delivers 7.58 % fewer packets on time"); Intro item 3; Table IX ("one-step learner on observed ACK/NACK (GBT-full-ACK) −7.58"); Conclusion.
- **Why it matters.** The headline claims that *supervised one-step learning* beats *deep RL*. Roughly half of the quoted gap may come from a wider action set that the RL policy was never allowed to use. A reader in LA will notice this at once.
- **What would address it.**
  - Lead with the matched action set (GBT-res-ACK, −3.40 %) in the abstract and intro, and give −7.58 % as "with an unrestricted offset set".
  - Better, add the missing cell of the 2×2. The paper already has an offset A2C with δ ∈ [−4, +2] (Section IV-A), but it was only run at 800 episodes in M1, where it failed Claim B. Train it on the non-oracle base with the 3000-episode recipe, or widen the residual to ±3, and compare it with GBT-full-ACK.
  - Then state which part of the gap is paradigm and which is action set.

### 2. Data, exploration and training budgets are not matched or reported, so "which learner" is not cleanly identified

- **Issue.** The two sides are trained very differently.
  - The GBT learners are trained offline on 500 calibration traces logged with ε = 0.5 uniform exploration.
  - The RL policy is trained on-policy for 3000 episodes per seed, with a bias toward δ = 0 (initial logit bias 3) and a deviation penalty of 0.02|δ| (Sections IV-B/C, Table X).
  - The paper does not report the number of labelled decisions, wall-clock time or compute for the GBT side. Nor does it say whether the RL policy ever saw comparable coverage of non-default offsets.
  - The deviation penalty and the δ = 0 bias deliberately make RL conservative, which may handicap it against an unpenalised greedy argmax.
  - The paper notes that the ACK-trained GBT beats its true-SINR twin, and that labels and logging policy are confounded (Section VII-B). This shows the logging regime matters, which strengthens the confound.
- **Where.** Sections IV-B/C, VII-A/B, Table X.
- **Why it matters.** The conclusion "sequential credit assignment bought less than accurate one-step estimation" (Section IX-A) is only warranted if the two learners had comparable information about the action space. The GBT is in effect a greedy contextual bandit fitted to heavily explored off-policy data. The RL policy is an on-policy learner with a conservatism prior.
- **What would address it.**
  - Report, for both learners: decisions seen in training, share of non-default actions, simulation time and compute.
  - Run at least one bridging control:
    - a residual A2C (or offline RL / fitted-Q) trained on the *same* exploration logs; or
    - a residual RL policy on top of the GBT-ACK policy as its base. This directly tests whether sequential credit adds anything beyond one-step estimation.
  - Run the label × logging 2×2 that Section VII-B says is missing:
    - ACK labels with Fixed logging (ε = 0); this matters for deployability, see 3;
    - true-SINR labels with exploration logging.

### 3. Deployability claims rest on an unmeasured and very aggressive exploration cost

- **Issue.** The "deployable" learner needs logs in which half of the decisions use an offset drawn uniformly from −4 … +2 (Section VII-B).
  - In a live network that means about 50 % of new transmissions at random MCS offsets, some three CQI steps more aggressive than the calibrated offset. The cost in on-time delivery, BLER and HARQ load while logging runs could be large.
  - Limitation 12 says the cost was "not measured". In a simulator it is a single evaluation: the on-time ratio, BLER and Jain index of the ε-greedy logging policy on the calibration traces.
  - No sensitivity analysis exists for ε (e.g. 0.05, 0.1, 0.2) or for log size (e.g. 50, 100, 200 traces). So we do not know whether a tolerable amount of exploration gives most of the gain.
  - The comparison "the RL policy, too, explores during training" (Limitation 12) is not symmetric unless a deployment scenario is defined. If RL is trained in a simulator and deployed, it needs no live exploration. If the GBT is also trained on simulated logs, then "labels a gNB observes" carries no deployability advantage.
- **Where.** Abstract ("trained only on ACK/NACK observed under exploration"); Section VII-B ("These deployable versions…"); C3 ("although the supervised learner needs exploration logging"); Recommendation 6; Limitation 12; Conclusion.
- **Why it matters.** For an operator, the headline's value depends on whether exploration at an acceptable cost gives most of the gain. As written, "deployable" is asserted, not shown.
- **What would address it.**
  - Report the logging-policy KPIs.
  - Sweep ε and log size and report GBT-ACK performance as a function of the exploration budget. Include ε = 0 with natural OLLA/Fixed MCS variation, since the classifier takes MCS as an input.
  - State the deployment scenario explicitly:
    - where training happens (simulator, digital twin, or live logs);
    - how often the model is refit;
    - how covariate shift is handled when the deployed policy changes the state distribution. R1c "transfer" is encouraging but is simulator-to-simulator.
  - Drop "deployable" until this is done.

### 4. "gNB-observable" and "label availability" need a precise definition

- **Issue.**
  - Table III lists the learner's and GBT's features as "reported SINR and its 1- and 4-TTI change", "∆CQI", NACK average, OLLA offset and slack.
    - An NR gNB receives a 4-bit CQI index, not a reported SINR.
    - If the feature is the noisy un-quantised SINR before CQI mapping, the learners have finer-grained information than a gNB has. If it is the SINR implied by the CQI index, the paper should say so.
  - The R2 designed rule and the A2C features use "a 1 dB per TTI drop of reported SINR", which assumes per-TTI reports. With CQI delay of 2–8 TTIs and periodic or aperiodic CSI reporting, consecutive TTIs may carry no new report.
  - Label availability is assumed to be perfect:
    - every first transmission returns a correct ACK/NACK;
    - no PUCCH DTX or ACK/NACK errors;
    - no HARQ-ACK multiplexing or bundling;
    - a fixed RTT of 8 (whereas the PDSCH-to-HARQ timing K1 varies in NR).
  - "Delay class" is called oracle-like information in FixedPU and the combined table. Yet the gNB configures the CSI reporting and arguably knows the report age. Conversely, speed class could be estimated from SRS or DMRS Doppler.
- **Where.** Table III, Sections III-B, IV-A, V-B, VI-D-5, VII-B.
- **Why it matters.** The paper's main contrast between oracle and non-oracle schemes, and its deployability argument, both depend on what the gNB actually sees. If "reported SINR" is finer than a CQI index, every learned scheme gets an advantage over OLLA and the tables that is not available in practice.
- **What would address it.**
  - Define each feature in terms of the 3GPP quantity it stands for: CQI index, CSI report periodicity and age, HARQ-ACK as received.
  - Re-run R1b and NR2 with CQI-index features only, or show that the results do not change.
  - Add a sensitivity run with a small ACK/NACK error/DTX probability.

### 5. The operating points look structurally near one-shot, which favours a myopic learner; the generality of the ranking is untested

- **Issue.**
  - From Table II: packets of 12 000 bits arrive every 20 TTIs with a 10-TTI budget, and HARQ RTT is 8. So, within a budget, a packet can get at most about one retransmission, and only if its first transmission happens in the first ~2 TTIs. In most cases the first transmission is effectively the decisive one.
  - Each trace scores only 150 TTIs. At 3–30 m/s and 50 m shadowing decorrelation, users move at most ~4.5 m per trace, so large-scale fading is roughly static within a trace.
  - Under these conditions a per-decision trade-off between success probability and transport-block size is, by construction, most of the problem. That is the paper's own reading in Sections VII-E and IX-A. The win of the myopic learner may therefore be a property of the operating point, not of the learning paradigms.
  - R1b/R1c were not run where the paper says RL's structure matters least or most:
    - M2 (RTT 0);
    - M3/M4 (full-buffer goodput, where HR1 finds +2.38 % one-step headroom and RL collapsed to its base);
    - longer deadlines relative to the RTT.
  - G3 has a looser deadline, but it sits near the ceiling (0.91–0.94 on-time), so it cannot discriminate much.
  - M1 itself is a heavily stressed cell: about 40 % of deadline packets are missed by every scheme (on-time ≈ 0.60–0.67). A network would rarely run there by design.
- **Where.** Table II, Sections III-E, VI-D-3, VII-C/E, IX-A, Limitation 13.
- **Why it matters.** The headline says supervised one-step learning beats deep RL. The evidence covers one traffic model at three points that are close to each other and arguably close to one-shot.
- **What would address it.**
  - Run R1b on M2–M4.
  - Run at least one deadline/RTT ratio where several HARQ rounds fit, e.g. a 30–40 TTI budget at RTT 8.
  - Run at least one load point with on-time ≈ 0.8–0.9 that is not at the ceiling.
  - Report the share of packets that can receive a retransmission within the budget at each point.
  - Run the headline under the 200-TTI warm-up. Every scheme acts on a cold-starting OLLA reference, and the GBT sees the OLLA offset as a feature, so part of its gain may be correction of the OLLA transient within 150 TTIs. W1 was applied to the M1 policy and to NR2 against OLLA, but apparently not to R1b/R1c.

### 6. Side effects (BLER, fairness, tail users) are under-reported for the headline schemes

- **Issue.**
  - **BLER.** Section VII-D says "GBT-full raises the first-transmission block-error rate to 18.8 % (NR2 18.7 %, GBT-res 16.2 %)".
    - It is unclear whether these are the true-SINR (R1) or the ACK-trained (R1b) learners. The headline schemes GBT-res-ACK and GBT-full-ACK are not reported.
    - "Raises" is misleading when the comparison is 18.8 % vs 18.7 %.
    - No BLER is given for the combined table, Fixed or OLLA (target 10 %). So the reader cannot see that every learned scheme runs at about twice the OLLA target BLER.
    - In a real NR system, a higher first-transmission BLER costs retransmission resources and HARQ soft buffer. With multi-cell interference, which is not modelled, it also adds interference from retransmissions.
    - The chase-combining model (a fixed 2.5 dB per retransmission) directly sets how cheap aggressive first transmissions are. The ranking may be sensitive to it.
  - **Fairness.**
    - Section V-C pre-registers a fairness guard: a Jain-index drop > 0.02 or an edge5 drop > 10 % relative to the best calibrated rule. Section VII instead reports a "bottom decile of per-user on-time ratios", which Table VII's caption calls "coarse and often zero". It is 0.000 for the combined table, so a relative 10 % guard is undefined.
    - Edge5 is not reported for R1/R1b/R1c, and no fairness metric is reported for G2/G3.
    - The speed breakdown (Section VI-F-2) was done for M1 and NR2 but not for the GBT learners, although slow users were where the original policy lost.
- **Where.** Sections V-C, VI-F-2, VII-D; Table VII.
- **Why it matters.** The paper says the one-step learners "do not buy their gain with fairness". With a tail metric that is about zero for every scheme, that statement is not supported.
- **What would address it.**
  - Report first-transmission and residual BLER, mean retransmissions per packet and HARQ-process occupancy for all schemes in Table VII and Table VIII.
  - Report the pre-registered edge5 fairness guard.
  - Compute tail metrics on per-user ratios pooled across traces (e.g. per user-trace class, or by mean-SINR or speed decile), not per 7.5-packet trace.
  - Add the speed breakdown for GBT-ACK.
  - Add a sensitivity run with a different HARQ combining gain.

### 7. The title, abstract, intro and conclusion generalise beyond one simulator and one RL design

- **Issue.**
  - The title ("Deep Reinforcement Learning for Link Adaptation … Not a Supervised One-Step Learner") and C3 ("Deep RL is therefore not needed for the gain on these cues") state a ranking of learning paradigms.
  - The evidence is narrower:
    - one MATLAB simulator with an SINR-to-BLER abstraction and no LDPC tables;
    - single cell, flat-fading, one user per TTI;
    - one A2C architecture with a ±1 residual action, a conservatism penalty and a shaped reward;
    - one deadline traffic model at three nearby points.
  - Limitation 1 says it plainly: "another link abstraction, traffic mix or channel model could change which learner does best". The Conclusion is appropriately hedged ("In one simulator…"), but the abstract's "Learning on the learner's own cues helps, but deep RL is not the best learner" is not.
  - The supervised learner is, in effect, a contextual bandit with a rich feature model fitted to logged data. The finding should be placed against the bandit-LA literature cited in Section II-B ([19], [2], [20], [21]), not presented as supervised learning vs RL in general.
  - The paper's own bandit comparators are extremely weak: 41.80 % on-time, below the 52.53 % open-loop baseline (Table V). That looks like a poorly configured comparator. It is uncomfortable next to a headline that a well-built contextual-bandit-like learner wins.
- **Where.** Title; Abstract; Intro "In short" paragraph and item 3; C3; Section IX-A; Conclusion.
- **What would address it.**
  - Retitle along the lines of "… a residual A2C policy beats calibrated rules but not a supervised one-step success model in a simulated NR cell".
  - Qualify the abstract with "in one simulator, for deadline traffic at three nearby operating points".
  - Change C3 to "was not needed here".
  - Add a sentence relating GBT-ACK to contextual bandits.
  - Explain or fix the bandit comparators' performance.

### 8. The headline's confirmatory status and evaluation-trace reuse should be stated plainly

- **Issue.**
  - R1b (Amendment 9) was added after R1 had shown a one-step learner beats NR2. R1c (Amendment 10a) replicates R1b.
  - At M1, R1c varies only the calibration draws. It evaluates on the same 500 NR2 traces that were already used for NR2, R1, R1b and R2.
  - In the cells, it reuses the G10/NR-G10 evaluation traces.
  - The GBT settings (gbt_a vs gbt_b) were fixed in HR1, which used logged decisions on evaluation traces. R1 is also reported on the M1 evaluation traces.
  - The project-wide multiplicity statement (104 cases, 179 evaluations) does not say whether R1/R1b/R1c are included.
  - None of this is likely to overturn effects of this size: the hierarchical CI of the NR2 margin is [−8.64, −6.61] %. But the paper's selling point is protocol transparency. Section V-D states the analogous caveat for the non-oracle recipe ("only NR2 and NR-G10 … are confirmatory") but gives none for the headline.
- **Where.** Sections V-D, VII-C; Table XVI.
- **What would address it.**
  - Add an explicit statement of which parts of Section VII are confirmatory and on which traces.
  - Ideally, evaluate the frozen R1c fits on fresh evaluation traces at M1.
  - State how the headline enters the project-wide correction.

### 9. Practical cost of the winning learner is not reported

- **Issue.** Section IX-C/D benchmarks A2C, Fixed, the combined table and OLLA (Fig. 11), and discusses DU/dApp placement for the RL policy. The scheme the paper now recommends trying first (Section IX-B) is not timed. Its size (trees, depth) and inference cost are not given.
  - GBT-full-ACK evaluates p̂(ACK | x, MCS) for seven candidate offsets per user per TTI.
  - R1 uses one model per candidate offset.
- **Where.** Sections VII-B, IX-B/C/D; Fig. 11.
- **Why it matters.** The cost and placement discussion is about the scheme the paper no longer recommends. Tree ensembles can be cheap, but this has to be shown, together with the refit and logging pipeline (feature capture at decision time, joined with HARQ-ACK on average 8 TTIs later).
- **What would address it.**
  - Add GBT-res-ACK and GBT-full-ACK to the parameter/FLOP count and to the timing benchmark.
  - Briefly describe the logging pipeline and its data rate per cell.

## Minor concerns

- **Section roadmap (Intro, end):** "Section VI reports the results, …, Section VIII the pitfalls" omits Section VII, which the paper calls its main result.
- **Wrong cross-reference (IX-A):** "it passed the seed-level rule against the combined table (Section IX-B)" should be Section VI-D.
- **Table IX:** rows labelled "M1, non-oracle base" report margins on the NR2 confirmation traces, not the M1 evaluation traces. The G2/G3 one-step row reports the *weakest fit*, while the comparator rows are point margins of means. Label both explicitly.
- **Section VI-G, "The non-oracle base":** the comparison of +0.24 points of headroom with "a realised difference of 2.7 points (+3.35 against +0.66 %)" contrasts margins measured on different trace sets (NR2 traces vs M1 traces).
- **HR1 vs observed results:** HR1's learnable residual headroom over the combined table is +5.84 %, and its free-choice headroom is 9.5–9.6 %. The realised GBT-ACK gains over the combined table are +6.99 % (res) and +11.82 % (full), i.e. *above* the one-step headroom.
  - The units differ, as the paper notes. But Recommendation 7 ("little headroom means little to learn") and the reading that "observed margins are well below the one-step headroom" (Section VI-G) need revisiting: the headroom estimator appears to understate what a one-step learner can realise.
- **Wording that understates the result (VII-C, Intro item 3, C3, Conclusion):** the pre-registered wording "beat or matched" is used, but "No fit merely matched". The same sentence also appears twice in a row in VII-C (res and full), which reads like unedited macro output. Similarly, "the check was negative: The result was observed…" in VI-D-3 and Limitation 5 has a capitalisation and splice artefact.
- **"Calibration" is overloaded:** it means rule calibration, "calibration traces" used as GBT training data, "calibration draws", and probability calibration (ECE ≤ 0.021). Consider "training/logging traces" for the GBT data.
- **ECE/Brier (VII-B):** say which model (res or full, R1b or R1c fits) and give a reliability diagram. Calibration on explored decisions does not imply calibration on the deployed policy's state distribution; the text says "decisions taken by both policies", so give that value separately.
- **"Same cues" is used loosely:** the combined table uses the oracle speed class, which NR2 and GBT do not observe (Table III). "Calibrated tables … on the same cues fell short" (IX-A) should say that the table has *more* information.
- **Section V-D:** "at most 1 790 tests" implies 10 tests per evaluation, while the Bonferroni factor above uses 9 comparators (108 × 9 = 972). Clarify.
- **Section VI-C:** "hierarchical intervals are about 2.3 times wider than trace-only ones" compares 95 % hierarchical intervals with 90 % trace intervals. State the like-for-like ratio.
- **Fixed base −2 and clipping (VI-F-1):** 8.6 % of NR2's decisions have the base offset clipped at the lowest CQI. Report how often each scheme hits the CQI floor and ceiling. It bears on Major concern 1.
- **Interference model:** the 9 dB burst process is single-cell and independent of the scheme's own BLER and retransmissions. In a multi-cell network, more aggressive MCS with more retransmissions feeds back into neighbour interference. Mention this in Limitation 1 as specifically relevant to the BLER side effect.
- **Single user per TTI on all 100 RBs, flat fading:** practical LA deals with subband CQI, rank/PMI and MU-MIMO pairing. These are listed in Limitation 1 but not linked to the headline. With FDM multi-user scheduling the slack/HARQ-busy structure could differ.
- **G2/G3 parameters:** the exact load and deadline values are not given in the main text. G2 uses 14 000-bit packets, which appears only through Deviation D1. Add them to Table II.
- **Limitations section:** Limitations 12–13 are adequate in spirit but not specific enough for the headline. They should list:
  - the action-set mismatch (Major concern 1);
  - the unmatched data budgets (2);
  - the untested exploration cost and ε sensitivity (3);
  - the feature-definition caveat (4);
  - the near-one-shot structure of the tested points (5);
  - the missing BLER and fairness reporting for the ACK learners (6).
- **Abstract:** "release all artefacts" while the availability section is a draft placeholder. Fine for review, but make sure the release includes the GBT models and the exploration logs.
- **Table I:** extraction makes it hard to read. Make sure every "unclear" entry is justified in S4, given the strong claim that 0 of 24 papers used a calibrated rule.

## Verdict

**Major revision.** The protocol is exemplary and the negative findings are useful, but the new headline needs more work before it can stand:

- it needs an action-set-matched comparison and matched or reported training/exploration budgets;
- the exploration cost and ε sensitivity need to be measured;
- the features the paper calls gNB-observable need to be defined in 3GPP terms;
- R1b needs to be tested at points that are not near one-shot (M2–M4, longer deadlines) and under OLLA warm-up;
- BLER and fairness need to be reported properly for the ACK-trained learners;
- the title and abstract need to be narrowed to what one simulator and one RL design can show.
