# Reinforcement Learning for Adaptive Modulation and Coding (RL-AMC)

**Project:** Reinforcement-Learning-based Adaptive Modulation and Coding (AMC) for Multi-User LTE / 5G-NR Cellular Downlinks  
**Scope:** Complete simulation codebase, channel physics, evolutionary algorithms (v1 to v7), evaluation harnesses, benchmark datasets, and technical documentation.

---

## 1. Executive Summary & Core Scientific Findings

This project investigates whether Reinforcement Learning (RL) can outperform classical Outer Loop Link Adaptation (OLLA) in multi-user cellular downlinks under realistic physical-layer channel dynamics. Over seven iterative algorithm generations (v1 to v7), the system evolved from early per-user tabular networks to a centralized multi-agent Advantage Actor-Critic (A2C) architecture.

### Headline Findings (v7 Definitive Pipeline):
*   **$+12.8\%$ Throughput Gain over Standard OLLA:** Under Proportional Fair (PF) scheduling, realistic HARQ Chase combining ($+2.5\text{ dB}$), heterogeneous user speeds ($3\text{--}30\text{ m/s}$), variable delays ($2\text{--}8\text{ TTIs}$), and Markovian interference bursts ($+9\text{ dB}$), Deep A2C achieves $3.71\text{ Mbps}$ average cell throughput vs. OLLA's $3.29\text{ Mbps}$ ($p = 0.0003$, paired Wilcoxon test).
*   **Parity with Theoretical Oracle Upper Bound:** Deep A2C matches the performance of an offline-calibrated, class-specific static offset rule (`FixedPU`, $3.73\text{ Mbps}$, $-0.4\%$ difference, $p = 0.813$, statistically indistinguishable) with **zero offline calibration or pre-deployment tuning**.
*   **Mechanism Discovery (Setpoint Control):** RL's gain over OLLA is a *setpoint shift* (operating at $\text{BLER}_1 \approx 44\%$ instead of OLLA's fixed $10\%$). Chase combining heavily cushions transmission failures, making an aggressive first-transmission strategy throughput-optimal.
*   **State-Space Sufficiency:** Information-equal state (Tier-A) matches full state (Tier-B), proving standard OLLA-loop features suffice for Deep RL to discover the optimal setpoint.

---

## 2. Quick-Start & Execution Guide

The **v7 stack** (`Optimized/v7/`) is the definitive, fully audited pipeline.

### Running in MATLAB:
```matlab
cd 'Optimized/v7'

% 1. Pipeline Sanity Check (2-5 min)
run_v7_point('smoke');

% 2. Credibility Anchor (Calm homogeneous cell; RL ~ OLLA expected)
run_v7_point('phase0');

% 3. Headline Evaluation (+9 dB Markov burst, heterogeneous users)
% Yields +12.8% gain over OLLA (p=0.0003) and parity with Oracle FixedPU
run_v7_point('burst', 9);

% 4. User Heterogeneity Sweeps
run_v7_point('hetero', 0.5);
run_v7_point('hetero', 1.0);

% 5. State Ablations & Converged OLLA Defense
run_v7_point('tierA');
run_v7_point('warm');
```

### Running Headless via Windows Command Prompt:
```cmd
cd "Optimized\v7"
run_v7_all.bat
```

---

## 3. Algorithm Version Progression (v1 to v7)

```
+---------------------------------------------------------------------------------------------------------+
|                                    Evolutionary Algorithm Timeline                                      |
+---------------------------------------------------------------------------------------------------------+
| v1 (Per-User QL/AC)      --> Broken multi-user due to zero-init argmax tie-break bias                   |
| v2 (Bias Init / Shaping) --> Fixed tie-break; hit "no-offset freeze" plateau                            |
| v3 (Imitation Bonus)     --> Explored discrete action limits on multi-user GPU harness                  |
| v4 (Baseline-Relative)   --> Shared MLP parameterization; first version beating fixed CQI map           |
| v5 (Domain Randomize)    --> Imperfect CQI + PF/RR/EQ domain weights; post-audit showed parity with OLLA|
| v6 (OLLA-Relative)       --> Action 0 = OLLA; Deep A2C beat OLLA (+6.7%), matched constant offset       |
| v7 (Full SOTA Pipeline)  --> HARQ Chase combining (+2.5 dB), Markov bursts (+9 dB), user heterogeneity, |
|                              steep BLER waterfalls, Behavior Cloning warm-start + soft entropy decay.    |
|                              Result: +12.8% over OLLA (p=0.0003), matches Oracle FixedPU (p=0.813).     |
+---------------------------------------------------------------------------------------------------------+
```

---

## 4. Summary of Primary Headline Results (v7 Final Pipeline)

Evaluated across 30 held-out evaluation traces, Proportional Fair (PF) scheduling, 5 seeds, under realistic HARQ and non-stationary conditions:

| Scheme | Cell Throughput (Mbps) | Gain vs. Baseline | BLER₁ (1st Tx) | vs. Deep A2C (Wilcoxon $p$-value) | Role / Type |
|---|---|---|---|---|---|
| **Baseline (Fixed CQI)** | $3.10 \pm 0.25$ | (ref) | $0.692$ | $+19.9\%$, $p = 1.1 \times 10^{-4}$ (***) | Uncorrected lookup table |
| **OLLA (Reactive Standard)** | $3.29 \pm 0.27$ | $+6.3\%$ | $0.640$ | $+12.8\%$, $p = 2.8 \times 10^{-4}$ (***) | Industry-standard benchmark |
| **Fixed (Best Global Constant)**| $3.77 \pm 0.35$ | $+21.8\%$ | $0.444$ | $-1.6\%$, $p = 0.262$ (n.s.) | Offline-calibrated global offset |
| **FixedPU (Oracle Per-Class)** | $3.73 \pm 0.34$ | $+20.4\%$ | $0.443$ | **$-0.4\%$, $p = 0.813$ (n.s.)** | **Theoretical Oracle Upper Bound** |
| **QL v7 (Tabular)** | $3.12 \pm 0.25$ | $+0.9\%$ | $0.690$ | $+19.4\%$, $p = 2.9 \times 10^{-6}$ (***) | Underfitted discrete state table |
| **Tab AC v7 (Tabular)** | $3.11 \pm 0.21$ | $+0.4\%$ | $0.677$ | $+19.4\%$, $p = 2.9 \times 10^{-6}$ (***) | Tabular Actor-Critic baseline |
| **Deep A2C v7 (Proposed Final)**| **$3.71 \pm 0.32$** | **$+19.9\%$** | **$0.439$** | — | **Autonomous Online Calibrator** |

---

## 5. Complete File-by-File Inventory by Directory

### 5.1 Original Baseline Code (`Original/`)
Original MATLAB Live Scripts representing the initial baseline implementation of multi-user AMC:
*   `Original/case_2/`: 5 users under dynamic Proportional Fair scheduling (`BLER_Calculation.mlx`, `Calculate_SINR_Final1.mlx`, `selectTBSFromSINRDynamicScheduling.mlx`, `Throughput_Calculation.mlx`, `Read me.txt`).
*   `Original/case_3/`: 5 users under Round Robin scheduling (`BLER_Calculation.mlx`, `Calculate_SINR_Final1.mlx`, `selectTBSFromSINR_final2.mlx`, `Throughput_Calculation.mlx`, `Read me.txt`).

### 5.2 Version 1 & GPU Baselines (`Optimized/case1/`, `Optimized/case2_3/`)
*   `Optimized/case1/`: Single-user radial baseline (`runComparison_v1.m`, `randomWaypointSimulation.m`, `tbsFromMCSandRB.m`, `estimateBLER_Enhanced.m`, `calculateControlledSINR2.m`, `computeReward.m`).
*   `Optimized/case2_3/`: Multi-user GPU/CPU harnesses (v1/v3/v4 baselines, `runComparison_Multi_GPU_v1.m`, `runComparison_Multi_GPU_v3.m`, `runComparison_Multi_v4.m`, `schedule_users.m`, `createTBS_Table.m`, `computeSINR.m`).

### 5.3 Version 4 (`Optimized/v4/`)
Baseline-relative action formulation and centralized shared MLP:
*   `DeepA2C_AMC_Multi_v4.m`, `AC_AMC_Multi_v4.m`, `QL_AMC_Multi_v4.m`: Trainers for v4.
*   `defaultEnv_v4.m`, `generateChannel_v4.m`, `cqiFeedback_v4.m`, `estimateBLER_v4.m`, `evalPolicy_v4.m`, `computeReward_v4.m`, `schedule_users_v4.m`: Physical and evaluation modules.
*   `runComparison_v4.m`, `runCase1_v4.m`, `runCase23_v4.m`, `plotPolicyHeatmap_v4.m`, `README_v4.md`: Evaluation and documentation.

### 5.4 Version 5 (`Optimized/v5/`)
Clean-slate modular rewrite introducing scheduler domain randomization and Wilcoxon testing:
*   `DeepA2C_Shared_v5.m`, `AC_Shared_v5.m`, `QL_Shared_v5.m`: Multi-scheduler context-aware trainers.
*   `defaultEnv_v5.m`, `generateChannel_v5.m`, `cqiFeedback_v5.m`, `baseCQI_v5.m`, `estimateBLER_v5.m`, `evalPolicy_v5.m`: Physical simulation pipeline.
*   `sampleSched_v5.m`, `schedContext_v5.m`, `schedule_users_v5.m`, `argmaxNoOp_v5.m`, `trendBin_v5.m`, `computeReward_v5.m`: Scheduling and discretization utilities.
*   `runComparison_v5.m`, `sweepDelay_v5.m`, `sweepN_v5.m`, `replotFromResults_v5.m`, `README_v5.md`: Harnesses and parameter sweeps.

### 5.5 Version 6 (`Optimized/v6 _USE THIS_/`)
OLLA-relative action encoding ($a=0 \equiv \text{OLLA}$) and empirical action distribution analysis:
*   `DeepA2C_Shared_v6.m`, `AC_Shared_v6.m`, `QL_Shared_v6.m`: OLLA-relative trainers.
*   `defaultEnv_v6.m`, `evalPolicy_v6.m`, `runComparison_v6.m`, `runCase23_v6.m`: Simulation and evaluation harnesses.
*   `sweepDelay_v6.m`, `sweepNoise_v6.m`, `sweepOffset_v6.m`, `sweepCoherence_v6.m`, `measureActionUsage_v6.m`: Parametric sweeps and action usage analysis.
*   `generateInsightfulPlots_v6.m`, `saveFigures_v6.m`, `rebuildSweep_v6.m`, `runDelay02_and_bootstrap.m`: Diagnostic plotting and statistical bootstrap.
*   `Dataset/`: 52 `.mat` and `.txt` result files across all tested configurations.

### 5.6 Version 7 — Definitive SOTA Pipeline (`Optimized/v7/`)
The full SOTA pipeline incorporating HARQ Chase combining, non-stationary Markov interference bursts, speed/delay heterogeneity, steep BLER waterfalls, and Behavior Cloning warm-start:
*   **Core Modules:** `DeepA2C_Shared_v7.m`, `AC_Shared_v7.m`, `QL_Shared_v7.m`, `defaultEnv_v7.m`, `generateChannel_v7.m`, `cqiFeedback_v7.m`, `estimateBLER_v7.m`, `txStep_v7.m`, `harqInit_v7.m`, `stateFeat_v7.m`, `userClass_v7.m`, `calibrateFixedClass_v7.m`, `evalPolicy_v7.m`, `runComparison_v7.m`, `sweep_olla_target_v7.m`, `action_histogram_v7.m`, `generate_figures_v7.m`, `run_v7_point.m`, `run_v7_all.bat`.
*   **Documentation & Technical Reports:** `README_v7.md`, `V7_DESIGN_PLAN.md`, `DATA_STATUS_REPORT_v7.md`, `v7_technical_process_report.md`, `v7_beginners_guide.md`, `v7_beginners_guide_bn.md`.
*   **Dataset/ & Figures & Logs:** 29 campaign result datasets (`Dataset/`), 28 diagnostic figure files (`figures/`), and full runtime execution logs (`logs/v7_master_log.txt`).

### 5.7 Documentation & Reports (`Docs/`)
Master briefing documents, conference paper drafts, and parameter audit reports:
*   `Docs/v7/`: `v7_comprehensive_evaluation_report.pdf`, `v7_technical_process_report.pdf`, `v7_beginners_guide_bn.pdf`.
*   `Docs/v6/`: `v6_comprehensive_evaluation_report.pdf`, `Case1_Technical_Paper_v6_compile.pdf`, `Case1_Technical_Paper_v5.pdf`, `Case1_v6_Methodology_and_Architectural_Justification.pdf`, `Case1_A2C_Implementation_Spec.pdf`, `Case1_Parameter_Audit.pdf`.
*   `Docs/V5/`: `Case1_Methodology_v5.docx`.
*   `Docs/figures/`: High-resolution PNG plots for v5 (12 plots), v6 (20 plots), and v7 (28 plots).

---

## 6. System Requirements & Dependencies

*   **MATLAB Version:** MATLAB R2023a, R2024a, or newer.
*   **Required Toolboxes:**
    *   *Deep Learning Toolbox* (for `dlnetwork`, `dlarray`, and automatic differentiation).
    *   *Parallel Computing Toolbox* (optional, for multi-core/GPU parallelization).
    *   *Statistics and Machine Learning Toolbox* (for `signrank` Wilcoxon tests).
*   **Hardware:** Multi-core CPU (Intel Core i7/AMD Ryzen 7 or higher), 8 GB+ RAM.

---

## 7. Academic References

1. **Bruno et al. (2014)** --- *"Robust AMC Selection in LTE Systems using Reinforcement Learning"*, IEEE VTC-Fall. [DOI: 10.1109/VTCFall.2014.6966164](https://doi.org/10.1109/VTCFall.2014.6966164)
2. **Leite et al. (2015)** --- *"A Continuous-State Reinforcement Learning Strategy for Link Adaptation in OFDM Wireless Systems"*, Journal of Communication and Information Systems (JCIS). [DOI: 10.14209/jcis.2015.6](https://doi.org/10.14209/jcis.2015.6)
3. **Mota et al. (2019)** --- *"Adaptive Modulation and Coding based on Reinforcement Learning for 5G Networks"*, arXiv:1912.04030. [Link: arXiv:1912.04030](https://arxiv.org/abs/1912.04030)
4. **Zhang et al. (2018)** --- *"Deep Reinforcement Learning Based Resource Allocation in Cognitive HetNet"*, IEEE Transactions on Wireless Communications. [DOI: 10.1109/TWC.2018.2878018](https://doi.org/10.1109/TWC.2018.2878018)
5. **Pedersen et al. (2007)** --- *"Frequency Domain Scheduling for OFDMA with Limited and Noisy Channel Feedback"*, IEEE VTC-Fall. [DOI: 10.1109/VETECF.2007.380](https://doi.org/10.1109/VETECF.2007.380)
6. **Mnih et al. (2016)** --- *"Asynchronous Methods for Deep Reinforcement Learning"*, ICML. [Link: arXiv:1602.01783](https://arxiv.org/abs/1602.01783)
7. **Schulman et al. (2015)** --- *"High-Dimensional Continuous Control Using Generalized Advantage Estimation"*, ICLR. [Link: arXiv:1506.02438](https://arxiv.org/abs/1506.02438)
8. **3GPP TS 36.213** --- *"E-UTRA; Physical layer procedures"*, 3GPP Technical Specification. [Link: 3GPP Portal](https://portal.3gpp.org/desktopmodules/Specifications/SpecificationDetails.aspx?specificationId=2427)
9. **3GPP TR 38.901** --- *"Study on channel model for frequencies from 0.5 to 100 GHz"*, 3GPP Technical Report. [Link: 3GPP Portal](https://portal.3gpp.org/desktopmodules/Specifications/SpecificationDetails.aspx?specificationId=3173)
