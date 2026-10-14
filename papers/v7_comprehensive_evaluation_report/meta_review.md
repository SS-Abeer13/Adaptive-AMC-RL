# Meta-Review: Project Briefing & Characterization Report: Reinforcement Learning-Based Adaptive Modulation and Coding (v7)

## Per-reviewer verdicts
- **alfa** — **Major revision**: While the report offers a commendably transparent post-mortem of why reinforcement learning failed to beat a fixed-offset baseline, the sweeping conclusion that state-conditional adaptivity has no value is undermined by the complete omission of the RL reward function and hyperparameters, an action/HARQ MDP formulation that structurally restricts dynamic adaptation during bursts, and reliance on an oracle-initialized clone to assert throughput parity under low statistical power.
- **bravo** — **Major revision**: While the paper provides an exceptionally candid, rigorous, and valuable characterization of why RL fails to beat constant offsets in link adaptation, the central claims are undermined by critical experimental confounds—including circular behavior-cloning initialization in the parity benchmark, an out-of-control OLLA baseline operating at 65% BLER, a cold-start transient evaluation protocol where converged OLLA actually beats RL, and unresolved random-seed instability—which must be addressed before publication.
- **charlie** — **Major revision**: The paper provides valuable empirical transparency by documenting a pre-registered null result and exposing HARQ setpoint shifts, but its core claim that state-conditional adaptivity has no value rests on under-tuned and mischaracterized baselines—most critically evidenced by the fact that steady-state OLLA actually defeats the RL agent ($p = 0.0003$).

## Common concerns

1. **Circular Behavior Cloning Initialization and Overclaimed Oracle Parity**
   - *Reviewers:* alfa, bravo, charlie
   - *Description:* The headline claim that Deep A2C matches the oracle-tuned per-class baseline (`FixedPU`) without calibration data is directly contradicted by the fact that parity was achieved exclusively by initializing the network via behavior cloning (BC) on the oracle itself (`tier1b`, $p = 0.813$), with subsequent RL fine-tuning yielding zero gain, while the only clean from-scratch learner (`tier1-nobc`) suffered a 5.1% throughput deficit ($p = 0.06$).
   - *Strongest quote (charlie):* "In reality, `tier1b` achieved statistical parity with `FixedPU` ($p = 0.813$) only because its weights were explicitly initialized via behavior cloning directly on the oracle's action distribution, after which 500 episodes of RL fine-tuning produced exactly zero additional throughput. The only methodologically clean from-scratch learner (`tier1-nobc`) suffered a 5.1% throughput deficit (3.54 vs. 3.66 Mbps). Presenting this as 'recovering oracle performance without calibration' conflates copying an oracle with learning autonomously."

2. **OLLA Baseline Flaws and Transient vs. Steady-State Confound (`Warm OLLA` Defeats RL)**
   - *Reviewers:* bravo, charlie (with related notes from alfa)
   - *Description:* The reported +7% to +13% advantage over OLLA is an artifact of scoring OLLA during cold-start integration on short traces; when evaluated at steady state with a 1000-TTI warm-up (`Warm OLLA`), OLLA actually outperforms Deep A2C by 5.9% ($p = 0.0003$). Furthermore, the OLLA target-BLER sweep is crippled by static step sizes that leave measured BLER frozen at ~65% across all target settings (10% to 50%), testing a saturated baseline rather than a calibrated one.
   - *Strongest quote (charlie):* "In Table 1, under the `Warm OLLA` condition (1000 TTIs of convergence), OLLA achieves 3.77 Mbps, beating Deep A2C (3.56 Mbps) by 5.9% ($p = 0.0003$). The authors dismiss this result as an 'unrealistic 1000-TTI convergence head start.' In operational cellular networks, base stations serve active data flows over thousands of TTIs... The entire +7–13% gain reported across the other points is an artifact of scoring OLLA during its initial transient integration phase from an arbitrary initialization."

3. **High Random-Seed Instability and Equivalence Inferred from Underpowered Non-Significance**
   - *Reviewers:* alfa, bravo, charlie
   - *Description:* Seed variation introduces massive performance swings (re-running the headline point on a fresh seed converted a -0.7% parity result into a statistically significant -4.4% loss, $p = 0.006$), yet post-hoc diagnostics were evaluated on only a single seed across 30 traces, with the authors interpreting non-significant $p$-values ($p = 0.06$) as 'near-parity' without formal equivalence testing (TOST).
   - *Strongest quote (alfa):* "The authors explicitly note in Section 4.2 that evaluating under a fresh random seed altered the A2C vs. FixedPU comparison from a non-significant -0.7% ($p = 0.517$) to a statistically significant loss of -4.4% ($p = 0.006$). Despite discovering this high seed sensitivity, the subsequent Tier-1 diagnostics, state ablations, and external validations were evaluated on a single seed configuration across only 30 held-out traces... Concluding that A2C is 'statistically indistinguishable from a constant offset' ($p = 0.136$) or that `tier1-nobc` achieves 'near-parity' ($p = 0.06$) commits the classical error of equating absence of evidence with evidence of absence."

4. **Complete Omission of RL Reward Formulation, Discount Factor, and Core Hyperparameters**
   - *Reviewers:* alfa, charlie
   - *Description:* The report omits the mathematical definition of the reward function $R_t$, discount factor $\gamma$, optimizer settings, learning rates, rollout horizon, batch sizes, and state discretization boundaries for tabular baselines, preventing independent replication and leaving open the possibility that the null result is an optimization failure.
   - *Strongest quote (alfa):* "The scalar reward function $R_t$ driving Q-learning, Tabular Actor-Critic, and Deep A2C is nowhere specified in the text. Was $R_t$ defined as instantaneous throughput, binary ACK/NACK feedback, or effective spectral efficiency penalized by dropped packets after exceeding `harq_max_retx`? If the discount factor $\gamma$ was set to 0 (myopic) or close to 0, the agent is mathematically incapable of learning anticipatory actions across the 250-TTI calm / 120-TTI burst Markov interference cycles... These omissions render independent replication impossible."

## Unique concerns

1. **Structural MDP Handicapping of Dynamic Adaptation (OLLA-Relative Action Bounds and HARQ Retransmission Freezing)**
   - *Reviewer:* alfa
   - *Description:* Constraining actions to an additive delta $\{-5, \dots, +3\}$ relative to a sluggish OLLA integrator prevents rapid reaction to +9/+12 dB bursts, while the simulation code (`txStep_v7.m`) freezes retransmission MCSs to the initial transmission's MCS for up to 3 retries, bypassing RL control and structurally forcing the policy toward an invariant setpoint.

2. **Unlevel Baseline Comparator with Privileged Offline Oracle Knowledge (`FixedPU`)**
   - *Reviewer:* bravo
   - *Description:* `FixedPU` partitions users into an idealized $2 \times 3$ grid of delay and velocity classes and applies exhaustive offline grid-searched offsets per class, whereas online RL agents (especially Tier-A) are deprived of noise-free class labels or must infer them from noisy, delayed observations.

3. **Expressive Capacity Limits of Feedforward MLPs in Delayed POMDPs (Tier-A vs. Tier-B Distinguishing Test Failure)**
   - *Reviewer:* charlie
   - *Description:* The statistical indistinguishability of Tier-A and Tier-B features does not prove the channel environment lacks exploitable state structure; rather, it reflects the known inability of a 2-layer (96x96) memoryless feedforward MLP to learn predictive representations from delayed (2–8 TTI), noisy feedback signals without recurrence (LSTM/GRU) or channel-state filtering.

4. **Missing Prior Art on HARQ Operating Point Economics and Classical Adaptive Baselines**
   - *Reviewer:* charlie
   - *Description:* Framing the shift of optimal BLER from 10% to 40–45% under HARQ Chase combining as a novel empirical discovery ignores established LTE/5G PHY-layer literature on HARQ economics, while failing to cite foundational RL-for-OLLA formulations (Pulliyakode & Kalyani [arXiv:1708.00994]), modern feedback-tracking link adaptation (Wiesmayr et al. [arXiv:2510.05784]), and multi-offset OLLA (Ahsen et al. [arXiv:2604.20459]).

5. **Incomplete Specification of Physical Layer Simulation Parameters and Waterfall Curves**
   - *Reviewer:* alfa
   - *Description:* Omission of carrier bandwidth, subcarrier spacing, total resource block grid dimensions, MCS-to-SINR lookup tables, and exact parameter values for the steepened sigmoid curves ($k \in [3.0, 5.8]$) makes the wireless environment impossible to reconstruct.

## Ranking
1. **charlie** — Uncovered the fatal baseline confound that steady-state OLLA (`Warm OLLA`) actually defeats Deep A2C ($p = 0.0003$), demonstrated that the target-BLER sweep tested a saturated baseline at 65% BLER, analyzed the expressive limitations of feedforward networks in POMDPs, and anchored the critique in wireless communications literature with actionable citations.
2. **bravo** — Sharply dissected the circularity of claiming oracle parity via behavior cloning, exposed the unlevel playing field between offline-partitioned `FixedPU` and online RL, and correctly demanded formal equivalence testing (TOST) rather than reliance on underpowered non-significant $p$-values.
3. **alfa** — Identified critical reproducibility blockers (complete omission of reward formulation, discount factor, and optimization hyperparameters), detailed the architectural MDP constraints that force static policies (retransmission MCS freezing and bounded OLLA deltas), and flagged PHY simulation parameter gaps.

## Verdict synthesis
**Major revision** (Unanimous consensus across all three reviewers).

The report provides an exceptionally candid, rigorous, and valuable empirical post-mortem of why deep reinforcement learning failed to beat constant-offset rules across a 12-point pre-registered campaign. The exposure of HARQ Chase-combining setpoint shifts (~40–45% BLER) as the primary driver of reported RL-over-OLLA gains is a high-value empirical contribution to the wireless communications literature. However, the overarching conclusion that "the optimal link-adaptation policy in this environment class is a constant, not a state-conditional policy" is premature and contradicted by the paper's own data. Most critically, when OLLA is evaluated at steady state (`Warm OLLA`), it actually defeats Deep A2C by 5.9% ($p = 0.0003$), revealing that the claimed RL gain over the industry standard is an artifact of short-trace transient initialization. Furthermore, the claimed parity with the oracle baseline was attained solely by supervised behavior cloning of the oracle comparator, while the from-scratch RL agent lagged by 5.1% under an underpowered sample ($p = 0.06, N = 30$). To reach publication standard, the authors must: (1) provide the complete reward function, MDP formulation, and hyperparameter tables; (2) reframe claims to acknowledge that steady-state OLLA beats RL and that from-scratch RL trailed the oracle; (3) test whether memory-based architectures (recurrent networks or channel predictors) or unconstrained action spaces can exploit non-stationary bursts; and (4) conduct multi-seed evaluations with formal equivalence testing.
