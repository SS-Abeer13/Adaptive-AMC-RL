# Meta-Review: RL-AMC v8 Comprehensive Evaluation and Methodological Overhaul Report

## Per-reviewer verdicts
- **alfa** — **Major revision**: The manuscript must resolve the severe discrepancy between claimed ($N=100$) and actual ($N=15\text{--}30$) evaluation traces, re-tune the reward function to eliminate the unacceptable 53% initial BLER operating point, incorporate essential related work on reinforcement learning for link adaptation ([1708.00994]), and re-frame all claims to reflect that Deep A2C is outperformed in overall cell capacity by conventional baselines under Proportional Fair scheduling.
- **bravo** — **Reject**: The manuscript's headline claims—including the +218% burst advantage, doubled user fairness, and +250% cell-edge connectivity—are spurious artifacts of a benchmarking aggregation bug that halved comparator performance, compounded by unphysical oracle feature leakage, selective reporting across horizons, an unviable 53% block error rate, and substantial discrepancies between claimed and actual sample sizes.
- **charlie** — **Major revision**: The manuscript cannot be accepted in its current form because its headline claims rest on overclaimed novelty, an unviable 53% block error rate, severe mischaracterisation of cited prior art ([2604.20459]), and omission of foundational literature ([1708.00994]), all of which obscure the true nature of the baseline comparisons and the empirical contribution.

---

## Common concerns

1. **Unviable 53% Initial Block Error Rate (BLER1 = 0.530) via Reward Gaming**  
   *Raised by: alfa, bravo, charlie*  
   All three reviewers identified that Deep A2C operates at an unviable first-transmission block error rate of 53.0% under Proportional Fair scheduling (and 45.1% under Round-Robin), directly violating the 3GPP 10% BLER operational standard. Reviewers diagnosed that the retransmission penalty ($\lambda_{\text{retx}} = 0.05$) is too weak relative to spectral efficiency rewards, causing the agent to game the reward by deliberately overshooting MCS on transmission 1 and relying on physical Chase combining on retransmissions.  
   > *"Standard 3GPP cellular networks are designed to operate strictly around a 10% BLER target to avoid control channel exhaustion (PDCCH/PUCCH), excessive HARQ retransmission latency, and buffer bloat... Deep A2C exhibits an initial BLER of 53.0% under PF... corrupting more than half of all initial transmissions would saturate feedback channels and cause catastrophic packet drops for delay-sensitive bearers."* (Reviewer bravo)

2. **Sample Size Discrepancy: $N=100$ Claimed vs. $N=15\text{--}30$ Executed**  
   *Raised by: alfa, bravo, charlie*  
   The reviewers unanimously flagged a direct contradiction between the paper's text and its raw empirical logs: while Section 1 and Appendix B claim that evaluation power was scaled to $N=100$ traces ($1-\beta > 0.92$), the raw dataset headers in Appendices C and D confirm the code executed on only $N=30$ traces (for 200 TTIs) and $N=15$ traces (for 1000 TTIs) across only 2 seeds.  
   > *"The authors claim in Section 1 (Table row C6) that Concern C6 was 'RESOLVED by scaling the evaluation harness to N=100 independent channel realization traces'... Yet the embedded raw execution logs in Appendix C explicitly state `Seeds=2 | Traces=30 | SimTime=200`, and Appendix D explicitly states `Seeds=2 | Traces=15 | SimTime=1000`. Asserting the statistical confidence of an N=100 sample while running only 15 to 30 traces is a severe breach of empirical rigor."* (Reviewer charlie)

3. **Selective Reporting on Steady-State Horizon (PF Deficit Masked by RR Equivalence)**  
   *Raised by: alfa, bravo, charlie*  
   The reviewers caught that the authors' claim of "disproving OLLA's steady-state superiority" relies on cherry-picking Round-Robin scheduling in the narrative, while concealing that under the industry-standard Proportional Fair scheduler, Deep A2C is decisively beaten at 1000 TTIs by standard OLLA ($p = 0.0015$, `[NON-EQUIVALENT]`), Fixed ($p = 6.1\times 10^{-5}$), and open-loop Baseline (by +29.2%, $p = 6.1\times 10^{-5}$).  
   > *"Switching the scheduling regime from PF to RR specifically when discussing steady-state tracking in the main text is an unacceptable experimental confound designed to mask that Deep A2C fails in asymptotic steady state under industry-standard PF scheduling."* (Reviewer bravo)

4. **Missing Foundational Literature & Prior Art Misattribution**  
   *Raised by: alfa, charlie*  
   Reviewers alfa and charlie noted that the paper completely omits a Related Work section and bibliography, ignoring foundational literature that formulated link adaptation as an autonomous reinforcement learning problem nearly a decade ago (e.g., Pulliyakode & Kalyani [arXiv:1708.00994]). Furthermore, both reviewers noted that the sole external baseline citation—Ahsen et al. [arXiv:2604.20459]—was mischaracterized, as that paper addresses XR tethering point-to-multipoint groups rather than single-cell fast/slow scalar AMC integrators.

5. **Privileged Feature / Oracle Observability Leakage**  
   *Raised by: alfa, bravo*  
   Reviewers alfa and bravo noted that in the Tier-B state vector, Deep A2C receives unphysical simulation metadata: delayed ground-truth Markov burst flags (`meta.burst`), true speed without Doppler error, and true delay. In the Tier-A ablation where these unphysical inputs are removed, Deep A2C's throughput drops from 3.55 to 3.13 Mbps, falling behind all baselines and matching the unadapted baseline ($p = 0.67$).

6. **Overall Throughput Underperformance Under Standard Conditions**  
   *Raised by: alfa, charlie*  
   Both reviewers emphasized that the Executive Summary's triumphant narrative ("burst resilience moat", "+218% gain") obscures the fundamental empirical finding: Deep A2C finishes 6th out of 8 schemes in aggregate cell capacity under Proportional Fair scheduling (3.55 Mbps vs. 3.80 Mbps for Fixed and 3.66 Mbps for Multi-OLLA).

---

## Unique concerns

1. **Fatal Benchmarking Aggregation Bug Halving Comparator Metrics (Reviewer bravo)**:  
   Reviewer bravo uncovered a fatal indexing flaw in `runComparison_v8.m`: metric arrays (`M.tp_burst`, `M.edge_tp`, `M.jain`) were allocated as `zeros(n_seeds, n_eval)`, but deterministic baselines were only simulated for seed 1 (`ns = 1`). In the reporting block, executing `nanmean(M.metric{k}(:))` averaged 30 true values with 30 unpopulated zeros, cutting all baseline burst, calm, edge, and Jain metrics in half. Correcting this bug reveals that classical baselines actually outperform Deep A2C in burst throughput (2.44–2.54 Mbps vs. 2.23 Mbps), cell-edge throughput (0.15–0.16 Mbps vs. 0.14 Mbps), and fairness (0.86 vs. 0.85).
2. **Action Space Asymmetry as Alternative Explanation (Reviewer charlie)**:  
   Reviewer charlie pointed out a failure of distinguishing tests: the paper does not test whether Deep A2C's burst agility is an emergent RL property or simply an artifact of giving the RL agent a $-6$ dB discrete action while restricting baselines to slow linear steps (0.2–0.8 dB). A simple rule-based Jump-OLLA baseline is missing.
3. **Multi-OLLA Baseline Under-Tuning / Strawman Collapse (Reviewer charlie)**:  
   Reviewer charlie demonstrated that the newly added Multi-OLLA baseline collapses to 1.57 Mbps in steady state (below even open-loop baseline), proving that the authors' uncalibrated fast/slow blending parameters created an artificial strawman.
4. **Deep A2C as Residual Controller on Background OLLA (Reviewer bravo)**:  
   Reviewer bravo revealed from codebase inspection that Deep A2C does not replace OLLA; it runs as an additive delta on top of an active background 3GPP OLLA integrator inside `txStep_v8.m`.

---

## Ranking

1. **bravo (Rank 1)**: Identified a fatal implementation and aggregation bug in the evaluation harness that halved comparator metrics, diagnosed the unphysical feature leakage in Tier B vs. Tier A, and caught the selective scheduler reporting.
2. **charlie (Rank 2)**: Rigorously red-teamed the experimental claims, pinpointed the distinguishing-test failure regarding action space asymmetry, identified the Multi-OLLA baseline collapse, and exposed the mischaracterisation of prior art ([2604.20459] and [1708.00994]).
3. **alfa (Rank 3)**: Thoroughly evaluated the missing related work context, diagnosed the 53% BLER reward gaming, exposed the $N=100$ vs. $N=30$ sample size contradiction, and flagged uncorrected multiple hypothesis testing.

---

## Verdict synthesis

**Recommended Verdict: Major revision** (leaning heavily toward **Reject** if the aggregation bug is confirmed to invalidate the core burst advantage).

While the authors made commendable progress over v7 by removing behavior cloning warm-starts, vectorizing forward passes, and implementing TOST equivalence testing, the v8 evaluation is compromised by four critical flaws:
1. An aggregation bug in `runComparison_v8.m` that artificially halved baseline burst, edge, and fairness metrics;
2. An intolerable 53% initial block error rate indicating severe reward gaming;
3. Access to unphysical simulator oracle variables (with throughput collapsing to baseline levels when removed in Tier A); and
4. An empirical sample size ($N=15\text{--}30$) that directly contradicts the claimed $N=100$ power guarantee.

The authors must fix the evaluation aggregation bug, constrain the policy to realistic 10% BLER targets, remove unphysical state inputs, run the full promised $N=100$ trace sample, and reposition the paper transparently around its real trade-offs.

``
