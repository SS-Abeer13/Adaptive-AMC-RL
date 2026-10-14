# RL-AMC v8: Characterization, Specification & Peer-Review Audit Report

**Date:** September 19, 2026  
**Subject:** Full Mathematical & Engineering Specification of RL-AMC v8  
**Venue Target:** IEEE Transactions on Wireless Communications / IEEE TVT (Q1)  
**Parent Study:** Comprehensive Evaluation of Deep RL for Downlink Link Adaptation  

---

## 1. Executive Summary

This report documents **v8** of the Reinforcement Learning-Based Adaptive Modulation and Coding (RL-AMC) framework. v8 represents a foundational architectural, methodological, and statistical overhaul initiated in direct response to the unanimous **Major Revision** verdict returned by the independent multi-agent peer-review panel (**alfa**, **bravo**, and **charlie** / Alignment Forum critic).

v8 completely resolves the 10 vulnerabilities identified in v7:
1. **Elimination of Circular Behavior Cloning:** Pure autonomous RL from random initialization (`bc_warm_eps = 0`).
2. **Resolution of Steady-State Confound:** Rigorous dual-regime evaluation across both transient ($T = 200\text{ TTIs}$) and asymptotic steady-state ($T = 1000\text{--}2000\text{ TTIs}$) horizons.
3. **Calibrated Baseline Integrators:** Dynamic step-size scaling for OLLA sweeps to eliminate loop saturation.
4. **Resolution of Multi-Agent Credit Assignment Noise:** Policy gradients update exclusively on scheduled user transmissions, discarding uninformative non-scheduled transitions.
5. **Temporal POMDP Memory:** Multi-frame autoregressive sequence state representation ($L = 3$) resolving delayed observation ambiguity.
6. **Unconstrained Action Space & Dynamic Retransmissions:** Expanded dynamic range $\Delta \in \{-6, \dots, +4\}$ and continuous outer-loop tracking through HARQ retries.
7. **Equitable Baseline Suite:** Real-world online heuristic comparator (`Fixed-Online`) evaluated alongside the theoretical offline oracle ceiling (`FixedPU`).
8. **Statistical Rigor & Equivalence Testing:** Expanded evaluation on $N \ge 100$ held-out traces across multiple random seeds with formal **Two One-Sided Tests (TOST)** for statistical equivalence claims ($\epsilon = \pm 2\%$).
9. **Full Mathematical & Hyperparameter Transparency:** Exhaustive disclosure of all equations, loss functions, learning rates, and optimizer configurations.
10. **Modern Link-Adaptation Baselines & Attribution:** Integration of state-of-the-art **Multi-Offset OLLA** (`Multi-OLLA`, Ahsen et al. [arXiv:2604.20459]) and thorough attribution of HARQ operating economics.

---

## 2. Peer-Review Issue-by-Issue Resolution Matrix

| # | Peer Review Concern | Originating Reviewers | Severity | Status in v7 | v8 Resolution | File / Implementation |
|---|---|---|---|---|---|---|
| **1** | **Circular Behavior Cloning** | `alfa`, `bravo`, `charlie` | **Critical** | Parity achieved only via BC on `FixedPU` | `bc_warm_eps = 0`; 100% autonomous RL from scratch | `DeepA2C_Shared_v8.m` |
| **2** | **Steady-State OLLA Defeating RL** | `bravo`, `charlie` | **Critical** | `Warm OLLA` beat Deep A2C by 5.9% ($p=0.0003$) | Dual-regime scoring ($T=200$ and $T=1000$ TTIs); temporal sequence modeling | `defaultEnv_v8.m`, `evalPolicy_v8.m` |
| **3** | **Saturated OLLA Target Sweep** | `bravo`, `charlie` | **Major** | BLER1 stuck at 65% across all targets | Proportional step scaling: $d_{\text{down}} = \delta_0 / \sqrt{T}$, $d_{\text{up}} = d_{\text{down}} \frac{P_{\text{tgt}}}{1-P_{\text{tgt}}}$ | `txStep_v8.m` |
| **4** | **Credit Assignment Noise** | `alfa`, `charlie` | **Major** | All 10 users received cell reward every TTI | Masked updates: only scheduled transmissions update actor-critic | `DeepA2C_Shared_v8.m` (lines 114–128) |
| **5** | **Feedforward POMDP Limits** | `charlie` | **Major** | 2-layer MLP without memory failed Tier-B | Autoregressive multi-frame temporal state stacking ($L=3$) | `DeepA2C_Shared_v8.m`, `stateFeat_v8.m` |
| **6** | **Structural Action Handicaps** | `alfa` | **Major** | Offset bounds $\pm 3$; locked HARQ MCS | Expanded actions $\Delta \in \{-6, \dots, +4\}$; dynamic retransmission tracking | `defaultEnv_v8.m`, `txStep_v8.m` |
| **7** | **Unlevel Oracle Comparator** | `bravo` | **Major** | `FixedPU` had offline oracle class partition | Added `Fixed-Online` heuristic baseline driven by online Doppler/delay | `userClass_v8.m`, `evalPolicy_v8.m` |
| **8** | **Seed Instability & Low Power** | `alfa`, `bravo`, `charlie` | **Major** | $N=30$ traces; single-seed 4% swings; $p=0.06$ mislabeled | $N \ge 100$ traces, 5–10 seeds, formal TOST equivalence ($\pm 2\%$) | `runComparison_v8.m` |
| **9** | **Missing MDP & Hyperparameters** | `alfa`, `charlie` | **Major** | Reward math, $\gamma$, and optimizer missing | Full mathematical disclosure in Section 3 & 4 | `DATA_STATUS_REPORT_v8.md`, `DeepA2C_Shared_v8.m` |
| **10** | **Missing PHY & Literature Context** | `alfa`, `charlie` | **Minor/Major** | Omitted bandwidth, RBs, MCS tables; missing prior art | Complete 3GPP PHY parameter table; `Multi-OLLA` baseline integrated | `defaultEnv_v8.m`, `MultiOLLA_v8.m` |

---

## 3. Physical Layer Simulation Specification (3GPP LTE/5G NR Macrocell)

### 3.1 Network Topology & Propagation Constants
$$\begin{array}{|l|l|l|l|}
\hline
\textbf{Parameter} & \textbf{Symbol} & \textbf{Value} & \textbf{3GPP Specification Reference} \\
\hline
\text{Carrier Frequency} & f_c & 2.0\text{ GHz} & \text{3GPP TR 38.901 (Band n1/n65)} \\
\text{System Bandwidth} & BW & 20.0\text{ MHz} & \text{3GPP TS 36.104 / TS 38.104} \\
\text{Resource Block Allocation} & N_{\text{RB}} & 100\text{ RBs} & 100\text{ PRBs in 20 MHz (12 subcarriers/RB)} \\
\text{Subcarrier Spacing} & \Delta f & 15\text{ kHz} & \text{3GPP Numerology } \mu = 0 \\
\text{Transmission Time Interval (TTI)} & T_{\text{tti}} & 1.0\text{ ms} & 1\text{ ms subframe (14 OFDM symbols)} \\
\text{BS Antenna Height} & h_{\text{BS}} & 25.0\text{ m} & \text{3GPP UMa Macrocell} \\
\text{UE Antenna Height} & h_{\text{UE}} & 1.5\text{ m} & \text{3GPP Standard Outdoor Pedestrian/Vehicle} \\
\text{BS Transmit Power} & P_{\text{tx}} & 43.0\text{ dBm (20 W)} & \text{3GPP Macrocell Downlink Power} \\
\text{BS Antenna Gain} & G_{\text{BS}} & 8.0\text{ dBi} & \text{Omnidirectional Sectorized Equivalent} \\
\text{Building Penetration Loss} & L_{\text{O2I}} & 20.0\text{ dB} & \text{3GPP TR 36.873 High Loss Model} \\
\text{Implementation Margin} & L_{\text{IM}} & 6.0\text{ dB} & \text{Standard Practical RF Implementation} \\
\text{UE Noise Figure} & NF & 9.0\text{ dB} & \text{3GPP TS 36.101 User Equipment Specs} \\
\text{Thermal Noise Density} & N_0 & -174.0\text{ dBm/Hz} & \text{Boltzmann Constant Equivalent at 290 K} \\
\textbf{Thermal Noise Floor} & P_{\text{noise}} & \mathbf{-92.0\text{ dBm}} & -174 + 10\log_{10}(20\times 10^6) + 9\text{ dB} \\
\text{Shadow Fading Standard Dev.} & \sigma_{\text{SF}} & 6.0\text{ dB} & \text{Log-normal Shadowing} \\
\text{Shadow Fading Correlation Dist.} & d_{\text{corr}} & 50.0\text{ m} & \text{Gudmundson Autocorrelation Model} \\
\hline
\end{array}$$

### 3.2 15-Level 3GPP Modulation and Coding Scheme (MCS) Table
All link adaptation algorithms select an integer index $m \in \{0, \dots, 14\}$ corresponding to 3GPP TS 36.213 Table 7.2.3-1:

$$\begin{array}{|c|c|c|c|c|c|}
\hline
\textbf{CQI Index} & \textbf{Modulation} & \textbf{Approx. Code Rate} & \textbf{Spectral Eff. (bits/s/Hz)} & \textbf{SINR Threshold (10\% BLER)} & \textbf{Steepness } k_m \\
\hline
1 & \text{QPSK} & 0.076 & 0.1523 & -6.7\text{ dB} & 3.0 \\
2 & \text{QPSK} & 0.117 & 0.2344 & -5.0\text{ dB} & 3.2 \\
3 & \text{QPSK} & 0.188 & 0.3770 & -3.2\text{ dB} & 3.4 \\
4 & \text{QPSK} & 0.301 & 0.6016 & -1.5\text{ dB} & 3.6 \\
5 & \text{QPSK} & 0.438 & 0.8770 & +0.8\text{ dB} & 3.8 \\
6 & \text{16QAM} & 0.295 & 1.1758 & +2.0\text{ dB} & 4.0 \\
7 & \text{16QAM} & 0.370 & 1.4766 & +4.5\text{ dB} & 4.2 \\
8 & \text{16QAM} & 0.478 & 1.9141 & +6.8\text{ dB} & 4.4 \\
9 & \text{16QAM} & 0.602 & 2.4063 & +9.2\text{ dB} & 4.6 \\
10 & \text{64QAM} & 0.455 & 2.7305 & +11.5\text{ dB} & 4.8 \\
11 & \text{64QAM} & 0.554 & 3.3223 & +14.0\text{ dB} & 5.0 \\
12 & \text{64QAM} & 0.650 & 3.9023 & +16.3\text{ dB} & 5.2 \\
13 & \text{64QAM} & 0.753 & 4.5234 & +18.7\text{ dB} & 5.4 \\
14 & \text{64QAM} & 0.853 & 5.1152 & +20.5\text{ dB} & 5.6 \\
15 & \text{64QAM} & 0.926 & 5.5547 & +21.8\text{ dB} & 5.8 \\
\hline
\end{array}$$

The AWGN block error rate is governed by the steepened sigmoidal waterfall link abstraction:
$$\text{BLER}(\gamma, m) = \frac{1}{1 + \exp\left(k_m \cdot (\gamma - c_m)\right)}, \quad c_m = \text{SINR}_{\text{threshold}, m} - \frac{\ln(9)}{k_m}$$

---

## 4. Formal Reinforcement Learning MDP Specification

### 4.1 State Formulation
For each user $i$ at TTI $t$, the single-frame state vector $\mathbf{s}_{i,t} \in \mathbb{R}^{16}$ contains:
1. Normalized OLLA Reference CQI: $\text{CQI}_{\text{ref}, i, t} / 15$
2. Normalized 1-TTI CQI Differential: $(\text{CQI}_{\text{ref}, i, t} - \text{CQI}_{\text{ref}, i, t-1}) / 5$
3. Normalized Delayed Observed SINR: $\gamma_{\text{obs}, i, t} / 30$
4. Normalized 1-TTI Observed SINR Differential: $(\gamma_{\text{obs}, i, t} - \gamma_{\text{obs}, i, t-1}) / 5$
5. Normalized Integrated OLLA Offset: $\Delta_{\text{OLLA}, i, t} / 5$
6. Normalized 4-TTI SINR Derivative Slope: $(\gamma_{\text{obs}, i, t} - \gamma_{\text{obs}, i, t-4}) / 20$
7. EMA NACK Event Frequency: $\bar{n}_{k, i, t} \in [0, 1]$
8. Pending Retransmission Flag: $\mathbb{I}_{\text{HARQ}, i, t} \in \{0, 1\}$
9. Normalized Retransmission Attempt Counter: $n_{\text{retx}, i, t} / 3$
10. Normalized User Velocity: $v_{i, t} / 30$
11. Delayed Interference Burst Indicator: $\hat{b}_{i, t} \in \{0, 1\}$
12. Normalized Uplink Reporting Delay: $d_i / 8$
13. Normalized Historical Proportional Fair Rate: $\bar{R}_{\text{EMA}, i, t} / \max_j \bar{R}_{\text{EMA}, j, t}$
14–16. Active Scheduler Context: One-Hot Vector $\mathbf{c}_{\text{sched}} \in \{\text{PF}, \text{RR}, \text{EQ}\}$

To resolve the partially observable Markov decision process (POMDP) arising from feedback delays and Markov bursts, the network receives an autoregressive temporal stack across the last $L = 3$ consecutive frames:
$$\mathbf{S}_{i,t} = \left[\mathbf{s}_{i,t}^T, \; \mathbf{s}_{i,t-1}^T, \; \mathbf{s}_{i,t-2}^T\right]^T \in \mathbb{R}^{48}$$

### 4.2 Action Space
Action $a_{i,t} \in \mathcal{A} = \{-6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4\}$ ($|\mathcal{A}| = 11$).  
The chosen MCS for scheduled transmission is:
$$\text{MCS}_{i,t} = \max\left(0, \min\left(14, \text{CQI}_{\text{ref}, i, t} + a_{i,t} - 1\right)\right)$$

### 4.3 Scheduled Credit Assignment & Reward Function
Unlike v7's broadcast reward that caused severe multi-agent gradient pollution, v8 restricts learning updates strictly to scheduled transmissions:
$$R(s_{i,t}, a_{i,t}, s'_{i,t}) = \begin{cases}
\frac{\text{TBS}_{i,t}}{S_R} - \lambda_{\text{drop}} \cdot \mathbb{I}_{\text{drop}, i, t} - \lambda_{\text{retx}} \cdot \mathbb{I}_{\text{NACK}, i, t}, & \text{if } RB_i > 0 \\
\text{Masked (No Gradient)}, & \text{if } RB_i = 0
\end{cases}$$
where $S_R = 30$, $\lambda_{\text{drop}} = 0.50$, and $\lambda_{\text{retx}} = 0.05$.

### 4.4 Training Hyperparameters
$$\begin{array}{|l|l|l|}
\hline
\textbf{Hyperparameter} & \textbf{Symbol} & \textbf{Value} \\
\hline
\text{Actor Learning Rate} & \eta_a & 5.0 \times 10^{-4} \\
\text{Critic Learning Rate} & \eta_c & 1.0 \times 10^{-3} \\
\text{Discount Factor} & \gamma & 0.95 \\
\text{Entropy Regularization Schedule} & \beta_{\text{ent}}(t) & \text{Linear decay from } 0.08 \to 0.005 \\
\text{Rollout Step Horizon} & n_{\text{step}} & 10\text{ TTIs} \\
\text{Gradient L2 Clipping Norm} & \|\mathbf{g}\|_{\max} & 5.0 \\
\text{Optimizer} & \text{Adam} & \beta_1 = 0.9, \beta_2 = 0.999, \epsilon = 10^{-8} \\
\text{Actor Hidden Architecture} & \text{MLP} & [128, 96] \text{ with ReLU activations} \\
\text{Critic Hidden Architecture} & \text{MLP} & [128, 96] \text{ with ReLU activations} \\
\text{Behavior Cloning Warm-Start} & \text{bc\_warm\_eps} & \mathbf{0\text{ (Strictly Autonomous)}} \\
\hline
\end{array}$$

---

## 5. Comparator Suite Definition

Every evaluation in v8 compares **eight** distinct transmission schemes:
1. **`Baseline`**: Open-loop CQI mapping using delayed channel estimates with zero outer-loop adjustment.
2. **`OLLA`**: Standard 3GPP outer loop link adaptation with proportional step-size scaling ($d_{\text{down}} = 0.5\text{ dB}$, $P_{\text{tgt}} = 0.10$).
3. **`Warm-OLLA`**: Steady-state OLLA pre-converged over 1000 independent warm-up TTIs to establish true asymptotic classical performance.
4. **`Multi-OLLA`**: Modern dual-integrator outer-loop controller (Ahsen et al. [arXiv:2604.20459]) with fast tracking ($d_{\text{fast}} = 0.8\text{ dB}$) and slow tracking ($d_{\text{slow}} = 0.2\text{ dB}$) for bursty regimes.
5. **`Fixed`**: Global best static offset discovered via offline grid search.
6. **`Fixed-Online`**: Realistic online heuristic classifier using estimated Doppler and ACK feedback latency to select per-class offsets.
7. **`FixedPU (Oracle)`**: Theoretical offline oracle ceiling with perfect partition knowledge of user velocity and feedback delay classes.
8. **`Deep A2C v8`**: Autonomous Recurrent/Temporal Deep Actor-Critic network with scheduled credit assignment and zero behavior cloning.

---

## 6. Statistical Validation Protocol

To guarantee reproducibility and eliminate underpowered claims:
- **Trace Budget:** $N \ge 100$ independent held-out channel traces (each evaluated across all comparators under identical fading and burst seeds).
- **Multi-Seed Replication:** Training conducted across $S = 5\text{--}10$ independent random seeds.
- **Statistical Significance:** Paired Wilcoxon signed-rank tests ($p < 0.05$) with Holm-Bonferroni multi-comparison corrections.
- **Formal Equivalence Testing (TOST):** Two One-Sided Tests evaluated within a pre-declared equivalence boundary ($\epsilon = \pm 0.10\text{ Mbps}$, approximately $\pm 2.5\%$). A comparator is declared statistically equivalent to RL *only* if TOST $p < 0.05$.
- **Regime-Conditioned Metrics:** Separate reporting of throughput during calm fading ($S_{\text{calm}}$) versus Markov interference bursts ($S_{\text{burst}}$) to quantify transient agility.
