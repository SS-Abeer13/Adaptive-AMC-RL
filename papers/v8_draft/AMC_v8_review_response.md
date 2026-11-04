# Response to the internal review of the v8 full paper (19 Oct 2026)

Revised paper: `AMC_full_paper_v8_rev1.docx` / `.pdf` / `_source.md`. The earlier `AMC_full_paper_v8.*` files are left unchanged.
Every point below was checked against the v8 code (`Optimized/v8`, plus `v7/generateChannel_v7.m`, which v8 calls) and the result files (`Dataset/fill_summary_*.txt`, `results_v8_final_headline_O_goodput.mat`).

Verdicts:
- **Valid** means the point was corrected.
- **Partly valid** means it was corrected with a different explanation.
- **Not valid** means the text was right and the reviewer's arithmetic or reading was off.
- **Needs re-run** means it is disclosed in the paper but needs new simulations.

## 1. New finding raised by the review (most important)

The reviewer called the missing $T_{tti}$ in Eq. (2) a typo. It is not a typo: the code really does move users $v$ metres every TTI (`pos = pos + v*dir/L`). Large-scale mobility therefore runs 1000× faster than the TTI clock, while the Jakes Doppler uses the real speed.

Consequences:
- Users move 3–30 m per TTI.
- The shadowing correlation per TTI is 0.55–0.94, so shadowing decorrelates within about 2–20 TTIs. That is the same time scale as the CQI delay.
- Every v8 number contains this effect.

What I changed in the paper:
- Section 2.1 now writes Eq. (2) with κ = 1000.
- The consequences are stated in 2.1.
- It is added to Table I and to the 6.4 checklist.
- An author note sets out the decision: keep it as a disclosed time compression, or set κ = 1 and re-run.

## 2. Point-by-point

| # | Review point | Verdict | What was found / done |
|---|---|---|---|
| S1 | Related Work section missing | Valid | 1.3 is now "Related Work and the Residual RL Formulation", covering four groups of prior work. The literature paragraph moved there from 1.4. Four suggested new references are listed in an author note for verification; none was added unverified. |
| S2 | Δ/δ notation in 1.2 differs from $o$, Δup, Δdown | Valid | 1.2 now uses $o_i$ and Δup/Δdown. The repeated derivation in 3.1 now points back to Eq. (1). |
| S3 | "Steady-state OLLA" vs Warm-OLLA confusion | Valid | Clarified in the abstract, 1.2, 1.4 and 5.2. On the 200-TTI horizon the agent beats Warm-OLLA (+5.3%); it trails converged OLLA only in P4. |
| S4 | Math formatting: δup, Ptgt, $10^{-10}$, βBC, λ, $s_b$, $G_b$, Table V exponents | Valid | Fixed in all files. Table V and the text now use $\times10^{-n}$ math, not Unicode superscripts. |
| W2 | Retransmission half-steps shift OLLA's equilibrium | Valid | 3.1 now states $P^* \approx P_{tgt}/(1-P_{tgt}/2) \approx 0.105$. |
| 2.2 | h = 0 gives 3 m/s, not 5 m/s | Partly valid | The code treats h = 0 as a separate case: 5 m/s and 4 TTIs (`env.speed`, `env.delay_hom`). 2.4 now says so. |
| 2.3 | Feature definitions missing | Valid | Added from `stateFeat_v8` and `build_state_v8`. Δq_ref is clipped to ±6; ΔSINR is not clipped. β⁽⁴⁾ = (γ̃_t − γ̃_{t−4})/4. NACK indicator: 0.7n + 0.3·NACK when scheduled, 0.95n otherwise. All features use wall-clock TTIs, and the frame stack is zero-padded at the start. |
| 2.4a | How Fixed/FixedPU apply their offset; grid of 9 vs 11 actions | Valid | They apply an integer CQI offset through Eq. (tx) with OLLA still active. The grid difference never binds: the optima are interior, and the learner uses −6/+4 in 0.75% of decisions. |
| 2.4b | Drop update: "instead of" or "in addition to" | Valid | It is "instead of": the last failed attempt costs −Δdown, so a block that fails all four attempts costs −3Δdown in total. |
| 2.4c | Multi-OLLA conditions underspecified | Valid | Added: \|β⁽⁴⁾\| > 1 dB/TTI, n > 0.4, both loops updated in parallel, and full steps also on retransmissions. |
| 2.5 | θ vector and TBS mapping not listed | Valid | Both are now listed in 2.6. The TBS table is TS 36.213 V14.2.0 (taken from the code header); MCS m uses row I_TBS = m. The 100-RB column matches the standard exactly. |
| 2.6 | No bandit or lightweight-calibrator baseline | Needs re-run | Scope is now stated in 1.4, 6.3 and Appendix A. Running an 11-arm bandit would be the most direct test of the paper's thesis. |
| 2.7 | RR/EQ unused; the scheduler input is constant | Partly valid | 3.2 and 4.1 now state that c_t = [1,0,0] in every run. The author note on re-running RR/EQ is kept. |
| — | Matrix formatting; Table VIII cross-reference; γ and α symbol collisions; Eq. (34) transpose | Valid | Fixed. PF smoothing is now α_PF and the Multi-OLLA blend is α_M. A sentence distinguishes the discount γ from SINR. |
| 4.1 | Section 4.6 has no v8 results | Valid | Moved to Appendix A and marked as not evaluated. The 4.0 and 1.5 roadmaps are updated. |
| 4.2 | Critic target G_b in cloning | Valid | G_b uses the same per-user bootstrapped return, including retransmissions. The actor loss covers first transmissions only. The Adam state carries over into fine-tuning. Eq. (bca) now averages over 𝒦. |
| 4.3 | n_step, buffer, P4 update count | Valid | n_step only sizes the buffer, so returns have variable horizon. P1: one update per episode. P4: five updates per episode, about 750 per seed. The entropy schedule is indexed by episode. |
| 4.4 | Entropy is averaged over retransmission states | Valid | The loss averages entropy over all B transitions. The Fig. 5 entropy is over all users and TTIs, and the caption and text now say this inflates it. |
| 4.5 | BC p-values with only 5 seeds | Valid | Now states that tests are paired over the 100 traces of the 5-seed average, and that one seed drives the change. A hedged reason for the clone slightly beating the teacher is added. |
| 4.7 | Optimizer paragraph duplicated in 4.2 and 4.5 | Valid | Consolidated in 4.5. |
| 5.1 | 3.84/3.86, 4.07/4.08 and OLLA = Fixed(0) differ | Valid (explained) | The cause is that each (trace, scheme, seed) has its own random-number stream: `rng(77000+100j+10k+s)`. Traces are common to all schemes, but outcome draws are not. Explained in 5.1 as Monte-Carlo resolution of about 0.02 Mbps. Fully reconciling them needs common random numbers and a re-run. |
| 5.2a | Margins don't match Eq. (62) (Baseline +13.0, FixedPU −0.3) | Not valid | The reviewer used rounded means. Unrounded: 3.9748/3.5188 → +12.96%; 3.9748/3.9880 → −0.33%. 5.6 now explains this. |
| 5.2b | CI and TOST estimator unspecified | Valid | Now written out. The CI is a paired t-interval on d_j divided by the comparator mean (it ignores the denominator's variance). TOST is two one-sided paired t-tests at ±0.02·mean (`fill_stats_v8.m`). |
| 5.2c | Scheduler-gaming range omits Tier-A | Valid | The range is 8.6% (Tier-O) to 17.6% (Tier-A). Corrected everywhere; the abstract and conclusion now say 9–18%. |
| 5.2d | 3.7% uses the wrong denominator | Not valid | (3.9748 − 3.8279)/3.9748 = 3.70%. The text now says "of the goodput agent's throughput". |
| 5.3a | OLLA vs Warm-OLLA in P4 | Valid | In P4 they are the same controller (same warm-up segment), differing only in outcome draws. Stated in 5.5 and the Table IV caption. |
| 5.3b | P4 calibrated and trained on cold-start traces | Valid, and broader than stated | Not only FixedPU: the learner was also trained on cold-start 1000-TTI episodes (no warm-up in `DeepA2C_Shared_v8`). The −2.9% vs converged OLLA is therefore an out-of-distribution test. Qualified in 1.4, 5.5 and 6.1. A matched control needs a re-run. P4 scores 950 TTIs, not 1000; corrected. |
| 5.3c | Why Warm-OLLA underperforms in P1 | Partly valid | Added a hedged explanation in 5.2: the warm-up runs on an independent segment, so offsets start mismatched, and the cell-average BLER mixes in pinned users. The mechanism was not isolated. |
| 5.3d | "2.36 vs 3.43" carry-over number | Not a carry-over | These are from the audit's 6-trace Octave check of unbounded vs bounded Warm-OLLA. The bullet now says so. |
| 5.4 | Burst/calm do not combine into the cell column | Valid (explained) | 48 of 100 traces have no scored burst TTI and 3 have no calm TTI. NaN traces are omitted, so the columns average over different subsets. Equations are now in 5.1. Baseline's drop in P4 comes from longer traces having more burst time: traces start calm, giving 24.6% expected burst share vs 31%. |
| 5.5 | Regime sweep forward references | Valid | Removed from 2.4 and Table I. The author note on re-running is kept. |
| 5.6 | Eq. (64) assumptions; meaning of the 0.39 BLER | Valid | 6.2 now says the equation is a quasi-static approximation for interior users. The 0.39 is a cell average lifted by pinned users. Converged OLLA drives adaptable users toward about 0.105, so landing near the optimum is partly coincidental. |
| — | "chapter"; 27/48/26 shares sum to 101; Table VIII third column has no margins; signrank font; V1–V3 row wrap | Valid | Fixed. Shares are now 26.7/47.7/25.7. Third-column margins are vs FixedPU under the original scheduler (3.93 Mbps): −21.6/−11.1/−20.5%. |
| — | Mean offset rounding (−2.3 vs −2.2) | Valid | Now −2.26 vs −2.23 everywhere. |
| R | References | Mostly valid | Bruno: full authors and DOI verified. Ahsen, Wiesmayr, Mota: full authors verified on arXiv. Dahlman: 2018. TS 36.213: V14.2.0, 2017. TR 38.901: V17.0.0, 2022. Kingma: "presented at ICLR". The reviewer's Ahsen OJCOMS DOI and Saxena vol./pages could not be verified and were not added. |

## 3. Still open (author decisions or re-runs)

1. The κ = 1000 mobility time scale: keep and disclose, or re-run with κ = 1. **This is the highest priority.**
2. A matched steady-state control: train the learner and calibrate FixedPU after the 1000-TTI warm-up.
3. A lightweight calibrator baseline: an 11-arm or class-conditioned bandit over offsets.
4. Common random numbers in the harness. This would remove the 0.02 Mbps label-to-label differences.
5. RR/EQ evaluation and the regime sweep (author notes in 3.2 and 5.3).
6. Related-work additions: Park 2015, Durán 2015, Pang 2024 and LOLLA 2026, all to verify before citing.
