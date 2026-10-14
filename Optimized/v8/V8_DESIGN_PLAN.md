# v8 Master Design Plan: Autonomous & Rigorous Link Adaptation

**Author:** Deep RL & PHY Wireless Research Group  
**Framework Version:** v8  
**Scope:** Resolving all 10 reviewer criticisms from the v7 multi-agent peer review  
**Status:** Pre-registered Architecture & Implementation Document  

---

## 1. Executive Summary & Design Principles

The v7 campaign produced a valuable empirical finding: published deep reinforcement learning (DRL) link adaptation gains over standard OLLA were primarily setpoint shifts (~40–45% BLER subsidized by HARQ Chase combining) rather than dynamic channel tracking. However, peer review by independent agents (**alfa**, **bravo**, **charlie**) revealed that v7's conclusion—that state-conditional adaptivity has no value in this environment class—was compromised by critical design confounds:
1. **Circular Benchmark Leakage:** Deep A2C only matched `FixedPU` when warm-started via Behavior Cloning (BC) directly on `FixedPU`'s actions; pure RL from scratch trailed by 5.1% ($p=0.06$).
2. **Transient vs. Steady-State Confound:** Standard OLLA was scored during initial cold-start transient integration on short 200-TTI traces. When given a 1000-TTI warm-up (`Warm OLLA`), **OLLA actually defeated Deep A2C by 5.9% ($p=0.0003$)**.
3. **Multi-Agent Credit Assignment Noise:** Cell-wide reward was broadcast to all 10 users every TTI, polluting 90% of unscheduled transitions with pure noise.
4. **Saturated Baseline:** OLLA's target sweep was evaluated on short traces with unscaled step sizes, leaving measured BLER stuck at ~65%.
5. **POMDP Memoryless Bottleneck:** A 2-layer MLP without recurrence cannot infer non-stationary Markov interference bursts under 2–8 TTI delayed feedback.
6. **Structural Action Handicaps:** The action space ($\pm 3$ offsets) and HARQ retransmission MCS locking structurally constrained dynamic burst recovery.

v8 addresses every point with an uncompromising commitment to methodological honesty, autonomous learning from scratch, calibrated baselines, and statistical rigor.

---

## 2. The 10 Peer-Review Fixes in v8

### Fix 1: Strictly Autonomous RL from Scratch (`bc_warm_eps = 0`)
- **Action:** Completely remove Behavior Cloning on the oracle comparator (`FixedPU`).
- **Rationale:** Evaluating an RL agent initialized by supervised cloning of its comparator creates circular data leakage and misleads readers into believing RL autonomously discovered the oracle's policy.
- **Protocol:** In v8, `bc_warm_eps = 0`. All deep networks initialize from random weights and learn autonomously via policy gradients. If warm starts are evaluated, they are strictly initialized from standard OLLA (action 0).

### Fix 2: Evaluation in Both Transient and Steady-State Regimes
- **Action:** Evaluate all comparators across both short-dwell transient traces ($T=200\text{ TTIs}$) and long-dwell steady-state traces ($T=1000\text{--}2000\text{ TTIs}$).
- **Rationale:** Real cellular base stations serve sessions lasting thousands of TTIs. RL must prove whether it provides asymptotic steady-state gains, rapid transient acquisition during mobility/burst handovers, or both.

### Fix 3: Dynamic Step-Size Scaling for OLLA Baselines
- **Action:** Scale OLLA step sizes proportionally:
  $$d_{\text{down}} = \delta_0 \cdot \frac{1}{\sqrt{T_{\text{dwell}}}}, \quad d_{\text{up}} = d_{\text{down}} \cdot \frac{P_{\text{tgt}}}{1 - P_{\text{tgt}}}$$
- **Rationale:** Ensures OLLA tracks commanded target BLERs ($10\%\text{--}50\%$) without loop saturation or freeze, establishing a calibrated classical baseline.

### Fix 4: Per-User Scheduled Credit Assignment
- **Action:** Mask policy gradient updates so that transitions $(s_{i,t}, a_{i,t}, r_{i,t}, s_{i,t+1})$ update actor-critic learnables *only* if user $i$ was scheduled ($RB_i > 0$).
- **Rationale:** In a 10-user cell with proportional fair scheduling, broadcasting cell throughput to unscheduled users corrupts 90% of buffer transitions with uncorrelated noise. Per-user scheduled credit assignment isolates true causal impact.

### Fix 5: Recurrent / Temporal Memory Architecture (LSTM-A2C)
- **Action:** Replace memoryless feedforward MLP with an LSTM / Temporal Sequence Actor-Critic network.
- **Rationale:** Cellular link adaptation with 2–8 TTI delayed feedback is a Partially Observable Markov Decision Process (POMDP). The recurrent hidden state $h_t$ maintains a recursive Bayesian belief over fading trend and Markov burst states, allowing dynamic tracking of interference transitions.

### Fix 6: Unconstrained Action Space & Dynamic Retransmissions
- **Action:**
  1. Widen the action space to $\Delta \in \{-6, \dots, +4\}$ (11 discrete actions), allowing instant recovery from $+9\text{ dB}$ bursts.
  2. Unfreeze HARQ: Allow outer loop / RL tracking on retransmission events and log retransmission throughput.

### Fix 7: Online Realistic Baseline (`Fixed-Online`) Alongside Oracle (`FixedPU`)
- **Action:** Introduce `Fixed-Online`, which estimates user velocity from Doppler autocorrelation and feedback delay from ACK latency, selecting per-class offsets dynamically.
- **Rationale:** Pitting online RL against an offline exhaustive grid-searched genie (`FixedPU`) is an unlevel comparison. `FixedPU` is formally retained as a theoretical non-adaptive upper bound.

### Fix 8: Multi-Seed Statistical Rigor & Equivalence Testing (TOST)
- **Action:**
  1. Train across $\ge 5$ random seeds; evaluate across $\ge 100$ held-out traces.
  2. Implement Two One-Sided Tests (TOST) with pre-declared equivalence margin ($\epsilon = \pm 2\%$).
  3. Report bootstrap 95% confidence intervals and paired Wilcoxon $p$-values with Holm-Bonferroni corrections.

### Fix 9: Explicit Mathematical MDP Formulation & Hyperparameter Transparency
- **Action:** Document the complete MDP tuple $(\mathcal{S}, \mathcal{A}, \mathcal{P}, \mathcal{R}, \gamma)$ and full hyperparameter tables in all code headers, design reports, and logs.

### Fix 10: Modern Link-Adaptation Baselines & Literature Attribution
- **Action:** Implement **Multi-Offset OLLA** (`Multi-OLLA`) following Ahsen et al. (2026) [arXiv:2604.20459], maintaining fast and slow integration filters for bursty regimes. Properly attribute HARQ BLER operating points to LTE/5G PHY literature.

---

## 3. Mathematical MDP Specification for v8

### 3.1 State Space $\mathcal{S}$
The observation vector for user $i$ at TTI $t$ is $s_{i,t} \in \mathbb{R}^{17}$:
$$\mathbf{s}_{i,t} = \begin{bmatrix}
\frac{\text{CQI}_{\text{ref}, i}}{15}, &
\frac{\Delta\text{CQI}_{\text{ref}, i}}{5}, &
\frac{\gamma_{\text{obs}, i}}{30}, &
\frac{\Delta\gamma_{\text{obs}, i}}{5}, &
\frac{\Delta_{\text{OLLA}, i}}{5}, \\
\frac{\text{slope}_{4, i}}{5}, &
\bar{n}_{k, i}, &
\mathbb{I}_{\text{HARQ}, i}, &
\frac{n_{\text{retx}, i}}{3}, &
\frac{v_{\text{est}, i}}{30}, &
\hat{b}_{i, t}, \\
\mathbf{c}_{\text{sched}}, &
\frac{\bar{R}_{\text{EMA}, i}}{\max_j \bar{R}_{\text{EMA}, j} + \epsilon}, &
\frac{d_{\text{est}, i}}{8}
\end{bmatrix}^T$$

### 3.2 Action Space $\mathcal{A}$
The action is an additive correction to the reference CQI:
$$a_{i,t} \in \mathcal{A} = \{-6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4\}$$
The transmitted MCS is:
$$\text{MCS}_{i,t} = \max\left(0, \min\left(14, \text{CQI}_{\text{ref}, i, t} + a_{i,t} - 1\right)\right)$$

### 3.3 Reward Formulation $\mathcal{R}$
For scheduled user $i$ ($RB_i > 0$):
$$R(s_{i,t}, a_{i,t}, s'_{i,t}) = \frac{\text{TBS}_{i,t} \cdot \mathbb{I}_{\text{ACK}}}{S_R} - \lambda_{\text{drop}} \cdot \mathbb{I}_{\text{drop}} - \lambda_{\text{retx}} \cdot \mathbb{I}_{\text{NACK}}$$
where $S_R = 30$, $\lambda_{\text{drop}} = 0.5$, $\lambda_{\text{retx}} = 0.05$.  
For unscheduled users ($RB_i = 0$): $R = 0$ (masked out during policy gradient backpropagation).

---

## 4. File Architecture in `Optimized/v8/`

```
Optimized/v8/
├── V8_DESIGN_PLAN.md             # This document
├── defaultEnv_v8.m               # Complete 3GPP PHY & MDP defaults
├── txStep_v8.m                   # Transmission physics with unconstrained HARQ & scaled steps
├── estimateBLER_v8.m             # Table-driven 15-CQI AWGN waterfalls + Chase combining
├── cqiFeedback_v8.m              # Heterogeneous delay & measurement noise
├── harqInit_v8.m                 # HARQ state structure
├── userClass_v8.m                # Delay and speed classification
├── calibrateFixedClass_v8.m      # FixedPU offline calibration
├── stateFeat_v8.m                # Temporal feature vector formulation
├── MultiOLLA_v8.m                # Modern multi-offset adaptive baseline
├── DeepA2C_Shared_v8.m           # Recurrent / Scheduled-credit Deep A2C (Zero BC)
├── evalPolicy_v8.m               # Evaluator across all 7 comparators
├── runComparison_v8.m            # Multi-seed evaluation & TOST equivalence testing harness
├── test_v8_smoke.m               # Automated verification smoke test
└── DATA_STATUS_REPORT_v8.md      # Comprehensive audit report of all parameters & results
```
