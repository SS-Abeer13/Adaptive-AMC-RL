# v6 — OLLA-Relative Link Adaptation Stack

This folder contains the v6 implementation of the Reinforcement Learning-based Adaptive Modulation and Coding (RL-AMC) project. In this version, the AI agents act relative to Outer Loop Link Adaptation (OLLA) instead of absolute channel quality states.

---

## File Mapping and System Functionality

### Entry Points & Harnesses
*   `runCase23_v6.m`: Main script to execute a single simulation run under Proportional Fair (PF) or Round Robin (RR) schedulers.
*   `runComparison_v6.m`: The core simulation harness that manages multi-seed training, evaluations, and saves output data.
*   `defaultEnv_v6.m`: Defines the simulator rules, state vectors (including the OLLA offset), and cooperative goodput rewards.
*   `evalPolicy_v6.m`: Evaluates trained A2C policies with OLLA active on held-out channel traces.

### AI Training Algorithms
*   `DeepA2C_Shared_v6.m`: Trains the Deep Advantage Actor-Critic neural network policy.
*   `QL_Shared_v6.m` / `AC_Shared_v6.m`: Trains tabular Q-Learning and tabular Actor-Critic policies.

### Parameter Sweeps
*   `sweepDelay_v6.m`: Sweeps CQI feedback delay ($0\text{--}8$ intervals) to test predictive advantage.
*   `sweepOffset_v6.m`: Sweeps standard action offset limit ($\pm 2$) vs. expanded action offset limit ($\pm 3$).
*   `sweepCoherence_v6.m`: Sweeps user velocity ($5\text{--}30$ m/s) to evaluate performance in fast fading.
*   `sweepNoise_v6.m`: Sweeps CQI measurement noise ($0\text{--}4$ dB) to evaluate robustness.

### Policy Diagnostics & Plotting
*   `measureActionUsage_v6.m`: Re-runs evaluation policies to count the frequency of actions selected relative to OLLA.
*   `generateInsightfulPlots_v6.m`: Loads sweep data and plots the final evaluation charts.
*   `saveFigures_v6.m`: Generates training learning curves and standard delayed sweep bar charts.

---

## Analysis of Generated Outputs and Figures

### Diagnostic Figures (Saved in `docs/figures_v6/`)
*   `fig13_user_tp_vs_dist.png`: **Throughput vs. Distance.** Shows that Deep A2C (green) maintains higher user speed than OLLA (red) across all base station distances.
*   `fig14_user_bler_vs_dist.png`: **BLER vs. Distance.** Shows that Deep A2C (green) keeps packet error rates stable under the $10\%$ target at the cell edge, whereas OLLA (red) fails and spikes.
*   `fig15_trace_winrate.png`: **Trace Win-Rate.** Scatter plot showing that Deep A2C beats OLLA's cell throughput in the majority of individual evaluation traces.
*   `fig16_action_dist_schedulers.png`: **Action Distribution.** Illustrates the AI dynamically shifting strategies—playing defensively under PF rules to protect quality vs. aggressively under EQ rules to force speed.
*   `fig17_throughput_vs_N.png`: **Throughput vs. Users.** Compares cell throughput as user density scales from 5 to 50 users.
*   `fig18_offset_comparison.png`: **Offset Sweep.** Shows that expanding the AI's adjustment limit from $\pm 2$ to $\pm 3$ yields a $+16.3\%$ speed boost for Deep A2C.
*   `fig19_p_values_vs_delay.png`: **Statistical Significance.** Shows raw and Holm-adjusted $p$-values vs. delay, proving that the AI's gains over OLLA are statistically significant (below the $0.05$ threshold) at delays of 2 and 6.

---

## Dataset Folder Contents and Data Interpretation

The `Dataset/` folder contains the serialized simulation outputs (`.mat`) and corresponding formatted summary logs (`.txt`) for the headline sweeps and statistical runs:

### Core Evaluation Runs ($N=10$, standard speed 5 m/s)
*   `FINAL_results_v6_N10_d4_cameraready.mat` / `.txt`: Core headline comparison data under the primary 4 TTI feedback delay. Documents the Deep A2C improvement margin over OLLA under PF.
*   `FINAL_results_v6_N10_d5_cameraready.mat` / `.txt`: Technically represents the delay-6 ($d=6$) camera-ready evaluation run (mislabelled parameter trace).
*   `FINAL_results_v6_N10_d6_cameraready.mat` / `.txt`: Verified duplicate backup of the delay-6 camera-ready evaluation run.
*   `FINAL_results_v6_N10_d6_sweeppoint.mat` / `.txt`: Detailed trace variables saved specifically during the delay-6 sweep execution.
*   `FINAL_results_v6_N10_d8_sweeppoint.mat` / `.txt`: Evaluation logs and channel state histories for the extreme 8 TTI delay run.
*   `FINAL_results_v6_N10_d4_warmed_OLLA.mat` / `.txt`: Comparison results where the OLLA loop is pre-warmed over 3 passes to guarantee steady-state convergence before evaluation.

### Congestion Scaling Sweeps ($d=4$, speed 5 m/s)
*   `FINAL_results_v6_N5_d4_cameraready.mat` / `.txt`: Low-density 5-user scenario.
*   `FINAL_results_v6_N20_d4_cameraready.mat` / `.txt`: Moderate-density 20-user scenario.
*   `FINAL_results_v6_N50_d4_cameraready.mat` / `.txt`: High-density/congested 50-user scenario.
    *   *These files are utilized to plot Figure 17 (Throughput vs N), showing that Deep A2C's advantage scales robustly with cell load.*

### Mobility Speed Sweeps ($N=10$, $d=4$)
*   `results_v6_case23_N10_speed15.mat` / `.txt`: Multi-user comparison run under medium mobility velocity (15 m/s or 54 km/h).
*   `results_v6_case23_N10_speed30.mat` / `.txt`: Multi-user comparison run under high mobility velocity (30 m/s or 108 km/h).
    *   *These files demonstrate that as channel coherence time drops relative to the feedback delay, predictive Deep A2C's throughput advantage over reactive OLLA widens.*

### Action Offset and Loop Sweeps
*   `sweepOffset_v6_results.mat`: Summary results comparing standard action space $\{-2, \ldots, +2\}$ vs. expanded action space $\{-3, \dots, +3\}$; used to plot Figure 18.
*   `results_v6_case23_N10_OLLA_step.mat` / `.txt`: Sensitivity sweeps evaluating different OLLA step adjustments.
*   `results_v6_case23_N10.mat` / `.txt`: Benchmark run evaluating baseline OLLA step dynamics.
*   `sweepDelay_v6_case23.mat`: Holds aggregated p-values and cell throughputs for the delay family sweep ($0\text{--}8$ TTI delay); used to plot Figure 19.

### Diagnostic Statistics & Text Output
*   `actionUsage_FINAL_results_v6_N10_d4_cameraready.txt` / `_d6_cameraready.txt`: Raw frequency tables tracking policy deviation from OLLA. Shows that Deep A2C active adjustments (non-zero actions) occur on 49--73% of TTIs.
*   `effectsizes_bootstrap_v6.txt`: Formatted output containing Cohen's $d_z$ effect sizes, 95% confidence intervals, and trace win-rates generated via bootsrapped resampling.
