# Reinforcement Learning for Adaptive Modulation and Coding (RL-AMC)

Project: Reinforcement-Learning-based Adaptive Modulation and Coding (AMC) for Multi-User LTE / 5G-NR Cellular Downlinks  
Scope: Complete simulation codebase, channel physics, evolutionary algorithms (v1 to v7), evaluation harnesses, benchmark datasets, and technical documentation.

----------------------------------------------------------------------------------------------------
1. Executive Summary & Core Scientific Findings
----------------------------------------------------------------------------------------------------
This project investigates whether Reinforcement Learning (RL) can outperform classical Outer Loop Link Adaptation (OLLA) in multi-user cellular downlinks under realistic physical-layer channel dynamics. Over seven iterative algorithm generations (v1 to v7), the system evolved from early per-user tabular networks to a centralized multi-agent Advantage Actor-Critic (A2C) architecture.

Headline Findings (v7 Definitive Pipeline):
* +12.8% Throughput Gain over Standard OLLA: Under Proportional Fair (PF) scheduling, realistic HARQ Chase combining (+2.5 dB), heterogeneous user speeds (3-30 m/s), variable delays (2-8 TTIs), and Markovian interference bursts (+9 dB), Deep A2C achieves 3.71 Mbps average cell throughput vs. OLLA's 3.29 Mbps (p = 0.0003, paired Wilcoxon test).
* Parity with Theoretical Oracle Upper Bound: Deep A2C matches the performance of an offline-calibrated, class-specific static offset rule (FixedPU, 3.73 Mbps, -0.4% difference, p = 0.813, statistically indistinguishable) with ZERO offline calibration or pre-deployment tuning.
* Mechanism Discovery (Setpoint Control): RL's gain over OLLA is a setpoint shift (operating at BLER1 ~44% instead of OLLA's fixed 10%). Chase combining heavily cushions transmission failures, making an aggressive first-transmission strategy throughput-optimal.
* State-Space Sufficiency: Information-equal state (Tier-A) matches full state (Tier-B), proving standard OLLA-loop features suffice for Deep RL to discover the optimal setpoint.

----------------------------------------------------------------------------------------------------
2. Quick-Start & Execution Guide
----------------------------------------------------------------------------------------------------
The v7 stack (Optimized/v7/) is the definitive, fully audited pipeline.

Running in MATLAB:
>> cd 'Optimized/v7'
>> run_v7_point('smoke');       % 1. Pipeline Sanity Check (2-5 min)
>> run_v7_point('phase0');      % 2. Credibility Anchor (Calm cell; RL ~ OLLA expected)
>> run_v7_point('burst', 9);    % 3. Headline Point (+9 dB burst -> +12.8% over OLLA)
>> run_v7_point('hetero', 0.5); % 4. User Heterogeneity Sweeps
>> run_v7_point('tierA');       % 5. State Ablation (Tier-A vs Tier-B)
>> run_v7_point('warm');        % 6. Converged OLLA Defense (1000 TTIs)

Running Headless via Windows Command Prompt:
> cd "Optimized\v7"
> run_v7_all.bat

----------------------------------------------------------------------------------------------------
3. Algorithm Version Progression (v1 to v7)
----------------------------------------------------------------------------------------------------
- v1 (Per-User QL/AC): Suffered from zero-init argmax tie-break bias in multi-user setups.
- v2 (Bias Init / Shaping): Fixed tie-break; hit "no-offset freeze" plateau.
- v3 (Imitation Bonus): Explored discrete action limits on multi-user GPU harness.
- v4 (Baseline-Relative): Shared MLP parameterization; first version beating fixed CQI map.
- v5 (Domain Randomize): Imperfect CQI + PF/RR/EQ domain weights; post-audit showed parity with OLLA.
- v6 (OLLA-Relative): Action 0 = OLLA; Deep A2C beat OLLA (+6.7%), matched constant offset.
- v7 (Full SOTA Pipeline): HARQ Chase combining (+2.5 dB), Markov bursts (+9 dB), user heterogeneity, steep BLER waterfalls, Behavior Cloning warm-start + soft entropy decay. Result: +12.8% over OLLA (p=0.0003), matches Oracle FixedPU (p=0.813).

----------------------------------------------------------------------------------------------------
4. Summary of Primary Headline Results (v7 Final Pipeline)
----------------------------------------------------------------------------------------------------
- Baseline (Fixed CQI): 3.10 Mbps, BLER1 0.692, +19.9% gain for Deep A2C (p = 1.1e-4)
- OLLA (Reactive Standard): 3.29 Mbps, BLER1 0.640, +12.8% gain for Deep A2C (p = 2.8e-4)
- Fixed (Best Global Constant): 3.77 Mbps, BLER1 0.444, -1.6% vs Deep A2C (p = 0.262, n.s.)
- FixedPU (Oracle Per-Class): 3.73 Mbps, BLER1 0.443, -0.4% vs Deep A2C (p = 0.813, parity)
- QL v7 (Tabular): 3.12 Mbps, BLER1 0.690, +19.4% gain for Deep A2C (p = 2.9e-6)
- Tab AC v7 (Tabular): 3.11 Mbps, BLER1 0.677, +19.4% gain for Deep A2C (p = 2.9e-6)
- Deep A2C v7 (Proposed Final): 3.71 Mbps, BLER1 0.439 (Autonomous Online Calibrator)

----------------------------------------------------------------------------------------------------
5. Complete File-by-File Inventory by Directory
----------------------------------------------------------------------------------------------------

5.1 Original Baseline Code (Original/):
  - Original/case_2/ (5 Users, Proportional Fair):
      * BLER_Calculation.mlx: Block error rate lookup calculation.
      * Calculate_SINR_Final1.mlx: Geometric distance and initial SINR routines.
      * selectTBSFromSINRDynamicScheduling.mlx: Dynamic PF scheduling and TBS mapping.
      * Throughput_Calculation.mlx: User and cell throughput calculation.
      * Read me.txt: Baseline run instructions.
  - Original/case_3/ (5 Users, Round Robin):
      * BLER_Calculation.mlx: BLER routines for Round Robin.
      * Calculate_SINR_Final1.mlx: SINR computation for 5 users.
      * selectTBSFromSINR_final2.mlx: Round Robin scheduling and MCS selection.
      * Throughput_Calculation.mlx: Round Robin throughput calculation.
      * Read me.txt: Baseline run instructions.

5.2 Version 1 & GPU Baselines (Optimized/case1/, Optimized/case2_3/):
  - Optimized/case1/ (Single-User Radial):
      * calculateControlledSINR2.m: Radial path loss and controlled SINR calculation.
      * computeReward.m: Step reward evaluation function.
      * estimateBLER_Enhanced.m: Sigmoid BLER estimation model.
      * randomWaypointSimulation.m: 2D RWP mobility generator.
      * runComparison_v1.m: Single-user baseline evaluation harness.
      * tbsFromMCSandRB.m: Standard LTE TBS lookup table.
  - Optimized/case2_3/ (Multi-User GPU/CPU v1/v3/v4):
      * calculateControlledSINR2.m: Multi-user SINR calculation.
      * computeReward.m: Multi-user reward computation.
      * computeSINR.m: Vectorized SINR computation.
      * createTBS_Table.m: Generates binary .mat tables for TBS lookups.
      * estimateBLER_Enhanced.m: Shared BLER sigmoid function.
      * randomWaypointSimulation.m: Vectorized RWP mobility for N users.
      * runComparison_Multi_GPU_v1.m: Multi-user GPU evaluation harness (v1).
      * runComparison_Multi_GPU_v3.m: Multi-user harness with imitation bonus (v3).
      * runComparison_Multi_v4.m: CPU/GPU harness for shared-network baseline (v4).
      * schedule_users.m: Multi-user PF and RR scheduler.
      * selectTBSFromSINR.m: SINR-to-MCS/TBS selection.
      * tbsFromMCSandRB.m: Standard 3GPP TBS table lookup function.
      * comparison_log.txt, training_log.txt, multi_results_gpu_pf.mat: Archived logs.

5.3 Version 4 (Optimized/v4/):
  - AC_AMC_Multi_v4.m: Tabular Actor-Critic trainer.
  - DeepA2C_AMC_Multi_v4.m: Centralized Deep A2C trainer processing all users through shared MLP.
  - QL_AMC_Multi_v4.m: Multi-user shared tabular Q-Learning trainer.
  - defaultEnv_v4.m: Environment hyperparameter definition.
  - generateChannel_v4.m: 3GPP channel generator with shadowing and fading.
  - cqiFeedback_v4.m: Uplink feedback model with delay and noise.
  - estimateBLER_v4.m: Sigmoid BLER error model.
  - evalPolicy_v4.m: Evaluation loop across test traces.
  - computeReward_v4.m: Cell goodput reward evaluation.
  - schedule_users_v4.m: RB allocation across scheduled users.
  - runComparison_v4.m, runCase1_v4.m, runCase23_v4.m: Test harnesses.
  - plotPolicyHeatmap_v4.m: Generates 2D policy heatmaps.
  - README_v4.md, results.txt, results_v4_case23.mat: Documentation and results.

5.4 Version 5 (Optimized/v5/):
  - DeepA2C_Shared_v5.m: Deep A2C trainer with multi-scheduler one-hot context.
  - AC_Shared_v5.m: Tabular Actor-Critic trainer with scheduler conditioning.
  - QL_Shared_v5.m: Tabular Q-Learning trainer with discretized trend and scheduler bins.
  - defaultEnv_v5.m: Master environment parameter definition.
  - generateChannel_v5.m: 3GPP channel generator with spatially correlated shadowing.
  - cqiFeedback_v5.m: Uplink feedback model with configurable delay and noise.
  - baseCQI_v5.m: Maps reported SINR to 3GPP Reference CQI.
  - estimateBLER_v5.m: Parameterized BLER waterfall function.
  - evalPolicy_v5.m: Vectorized evaluation harness scoring throughput, fairness, and BLER.
  - sampleSched_v5.m: Weighted categorical sampler for domain randomization (PF, RR, EQ).
  - schedContext_v5.m: Converts active scheduler mode to one-hot context vector.
  - schedule_users_v5.m: Standardized RB allocation module (PF, RR, EQ).
  - argmaxNoOp_v5.m: Deterministic tie-breaking utility biased toward no-op actions.
  - trendBin_v5.m: Discretizes continuous SINR trends into categorical bins.
  - computeReward_v5.m: Normalized cell-wide goodput reward function.
  - runComparison_v5.m, runCase1_v5.m, runCase23_v5.m: Execution runners.
  - sweepDelay_v5.m, sweepN_v5.m: Parametric sweeps across delay and user counts.
  - replotFromResults_v5.m, plotPolicyHeatmap_v5.m: Visualization scripts.
  - README_v5.md, 0_README.txt: Documentation and audit notes.

5.5 Version 6 (Optimized/v6 _USE THIS_/):
  - DeepA2C_Shared_v6.m: Deep A2C trainer with OLLA offset as state input.
  - AC_Shared_v6.m: Tabular Actor-Critic trainer with OLLA-relative encoding.
  - QL_Shared_v6.m: Tabular Q-Learning trainer with OLLA-relative encoding.
  - defaultEnv_v6.m: Environment definition with OLLA step sizes and targets.
  - evalPolicy_v6.m: Evaluates RL policies, reactive OLLA, and fixed-offset baselines.
  - runComparison_v6.m, runCase23_v6.m: Main evaluation harnesses.
  - sweepDelay_v6.m: Sweeps CQI feedback delay (0 to 8 TTIs).
  - sweepNoise_v6.m: Sweeps CQI measurement noise (0 to 3 dB).
  - sweepOffset_v6.m: Grid-search optimization for static constant offset baselines.
  - sweepCoherence_v6.m: Evaluates performance vs. user velocity and coherence time.
  - measureActionUsage_v6.m: Analyzes empirical action probability distribution.
  - generateInsightfulPlots_v6.m, saveFigures_v6.m: Publication-ready figures generator.
  - rebuildSweep_v6.m, runDelay02_and_bootstrap.m: Statistical bootstrap routines.
  - README.md, 0_README.txt, effectsizes_bootstrap_v6.txt, holm_bonferroni_v6.txt: Documentation and stats.
  - Dataset/: 52 .mat and .txt result files across delays, noises, speeds, and seeds.

5.6 Version 7 — Definitive SOTA Pipeline (Optimized/v7/):
  - Core Modules:
      * DeepA2C_Shared_v7.m: Multi-task Deep A2C trainer with 150-ep Behavior Cloning warm-start, soft BC entropy (beta=0.03), and smooth decay (0.01 -> 0.001).
      * AC_Shared_v7.m: Tabular Actor-Critic trainer for Tier-A baseline.
      * QL_Shared_v7.m: Tabular Q-Learning trainer for Tier-A baseline.
      * defaultEnv_v7.m: Environment parameters (HARQ, bursts, heterogeneity, Jakes, steep BLER).
      * generateChannel_v7.m: Channel generator with Jakes AR(1) fading, Markov bursts (+9 dB), and speed transitions.
      * cqiFeedback_v7.m: Uplink feedback model with heterogeneous per-user delays (2-8 TTIs).
      * estimateBLER_v7.m: Steep per-MCS waterfall BLER curves (k_m in [3.0, 5.8]).
      * txStep_v7.m: One TTI transmission physics: Type-I Chase-combining HARQ (+2.5 dB/retry), Bernoulli delivery, slot accounting, and OLLA outer-loop updates.
      * harqInit_v7.m: Initializes per-user HARQ pending buffers, retry counters, and TBS trackers.
      * stateFeat_v7.m: Constructs Tier-A (8 dims, info-equal) and Tier-B (14 dims, full physical state) feature vectors.
      * userClass_v7.m: Classifies users into a 2x3 delay-speed grid for oracle evaluation.
      * calibrateFixedClass_v7.m: Offline grid search calibrating the Theoretical Oracle Upper Bound (FixedPU).
      * evalPolicy_v7.m: Evaluates 7 schemes across test traces under frozen policy weights.
      * runComparison_v7.m: Main evaluation harness collecting trace-level statistics and Wilcoxon tests.
      * sweep_olla_target_v7.m: Sweeps OLLA target BLER (10%-50%) to rule out baseline mis-tuning.
      * action_histogram_v7.m: Measures decision-by-decision action distributions.
      * generate_figures_v7.m: Automated generation of all 13 publication figures.
      * run_v7_point.m, run_v7_all.bat, run_v7_remaining.bat: Headless batch runners.
  - Documentation & Reports:
      * README_v7.md: Operational instructions.
      * V7_DESIGN_PLAN.md: Architectural justification and hypothesis pre-registration.
      * DATA_STATUS_REPORT_v7.md: Complete empirical results and root-cause audit.
      * v7_technical_process_report.md: Exhaustive 325-line report detailing every decision, bug audit, and iteration.
      * v7_beginners_guide.md: First-principles textbook on wireless link adaptation and RL control.
      * v7_beginners_guide_bn.md: Bengali translation of the beginner's guide.
  - Dataset/ & figures/ & logs/:
      * Dataset/: 29 .mat and .txt result files across all 9 pre-registered points, replications, and sweeps.
      * figures/: 28 plot files (.fig and .png) covering all evaluation dimensions.
      * logs/: v7_master_log.txt and v7_olla_sweep_log.txt.

5.7 Documentation & Reports (Docs/):
  - Docs/v7/:
      * v7_comprehensive_evaluation_report.pdf: Master evaluation report for v7.
      * v7_technical_process_report.pdf: Compiled PDF of technical process and diagnostic audit.
      * v7_beginners_guide_bn.pdf: Compiled beginner's guide in Bengali.
  - Docs/v6/:
      * v6_comprehensive_evaluation_report.pdf: Master briefing document for v6.
      * Case1_Technical_Paper_v6_compile.pdf: IEEE conference paper draft for v6.
      * Case1_Technical_Paper_v5.pdf: IEEE paper draft for v5.
      * Case1_v6_Methodology_and_Architectural_Justification.pdf: Full v1-v6 audit report.
      * Case1_A2C_Implementation_Spec.pdf: Neural network specification.
      * Case1_Parameter_Audit.pdf: Physical parameter audit document.
  - Docs/V5/: Case1_Methodology_v5.docx: v5 methodology document.
  - Docs/figures/: High-resolution PNG plots for v5 (12 plots), v6 (20 plots), and v7 (28 plots).

----------------------------------------------------------------------------------------------------
6. System Requirements & Dependencies
----------------------------------------------------------------------------------------------------
- MATLAB Version: MATLAB R2023a, R2024a, or newer.
- Required Toolboxes: Deep Learning Toolbox, Parallel Computing Toolbox, Statistics and Machine Learning Toolbox.
- Hardware: Multi-core CPU (Intel Core i7/AMD Ryzen 7 or higher), 8 GB+ RAM.

----------------------------------------------------------------------------------------------------
7. Academic References
----------------------------------------------------------------------------------------------------
1. Bruno et al. (2014) --- "Robust AMC Selection in LTE Systems using Reinforcement Learning", IEEE VTC-Fall. DOI: 10.1109/VTCFall.2014.6966164
2. Leite et al. (2015) --- "A Continuous-State Reinforcement Learning Strategy for Link Adaptation in OFDM Wireless Systems", JCIS. DOI: 10.14209/jcis.2015.6
3. Mota et al. (2019) --- "Adaptive Modulation and Coding based on Reinforcement Learning for 5G Networks", arXiv:1912.04030
4. Zhang et al. (2018) --- "Deep Reinforcement Learning Based Resource Allocation in Cognitive HetNet", IEEE Trans. Wireless Commun. DOI: 10.1109/TWC.2018.2878018
5. Pedersen et al. (2007) --- "Frequency Domain Scheduling for OFDMA with Limited and Noisy Channel Feedback", IEEE VTC-Fall. DOI: 10.1109/VETECF.2007.380
6. Mnih et al. (2016) --- "Asynchronous Methods for Deep Reinforcement Learning", ICML. arXiv:1602.01783
7. Schulman et al. (2015) --- "High-Dimensional Continuous Control Using Generalized Advantage Estimation", ICLR. arXiv:1506.02438
8. 3GPP TS 36.213 --- "E-UTRA; Physical layer procedures", 3GPP Technical Specification.
9. 3GPP TR 38.901 --- "Study on channel model for frequencies from 0.5 to 100 GHz", 3GPP Technical Report.
