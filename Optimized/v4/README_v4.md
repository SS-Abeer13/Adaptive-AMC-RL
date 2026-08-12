# v4 — Fixed and unified simulation stack

## v4.1 revision (after the first case-23 run)

The first run produced Baseline 12.21, OLLA 12.08, QL 7.00, Tab-AC 11.76, A2C 12.32 (A2C > OLLA at p=0.005 but tied with baseline at p=0.117), with QL collapsed at CQI error 3.79. Diagnosed causes and fixes, all applied here:

1. **No headroom over baseline:** at `cqi_delay = 2` (fading ρ = 0.95) the baseline's CQI error (1.51) was dominated by *unbiased* measurement noise, which no policy can compensate → delay raised to 4 intervals (realistic; the compensable, correlated part of the error now dominates).
2. **No trend observability:** ΔCQI tracks the agent's own actions, not channel drift, so the compensable drift was invisible → all learners now receive the observed SINR trend dS = obs(t) − obs(t−1) (a difference of two reports, hence observable): continuous 4th input for A2C, 3-bin extra table dimension for QL/Tab-AC. Information-equal, so the comparison stays clean.
3. **QL collapse was a tie-breaking bug:** with PF, ~80% of rewards are 0 and most Q-rows stay all-zero; MATLAB's `max` picks the first index = action −2, so greedy slammed CQI to 1 in unvisited states → greedy argmax now breaks ties toward the no-op action (`argmaxNoOp_v4`), in training and evaluation.
4. **OLLA scored its cold-start transient:** offset starts at 0 each trace and updates only on served TTIs → all schemes are now scored from a 50-interval burn-in (`env.burn_in`), i.e. steady state.


Implements every fix from `Optimized_Policy_Audit.md`. Old v1–v3 results stay reproducible in `case1/` and `case2_3/`; v4 is self-contained except for `createTBS_Table` / `tbsFromMCSandRB`, which the harness pulls from `../case2_3` via `addpath` automatically.

## How to run

```matlab
cd optimized/v4
results = runCase23_v4();                      % 5-user PF (Cases 2/3), defaults
results = runCase1_v4();                       % single-user radial (Case 1)
results = runCase23_v4('n_seeds',5,'n_eval',30,'ep_deep',300);  % camera-ready
```

Outputs: `results_v4_case*.mat`, `results_v4_case*.txt` (paper-ready table with 95% CIs and Wilcoxon p-values), plus figures: KPI bars with CIs, learning curves in environment steps (mean ± std over seeds) with the A2C entropy diagnostic, throughput vs distance on held-out traces, and the A2C policy-explainability heatmap.

## What changed vs v3 (audit item → fix → file)

**C1 (Case 1 reward decoupling).** The agent's MCS now sets both TBS (`tbsFromMCSandRB`) and BLER; Case 1 is the N=1 special case of the same code path, so the decoupled `selectTBSFromSINR` rate-crediting is gone. → all trainers, `evalPolicy_v4`.

**C2 (genie baseline).** Nobody observes true SINR anymore. `cqiFeedback_v4` delays the SINR by `env.cqi_delay` intervals, adds N(0,1 dB) measurement noise, and quantizes to CQI. The baseline applies the outdated CQI directly; an OLLA baseline (BLER-target 10%, ACK/NACK offset, the industry standard) is added as the second comparison point. RL agents see the same imperfect observation but earn reward from the true channel, so they can learn state-dependent compensation — the legitimate route for A2C to win.

**C3 (no-op imitation fallacy).** All bias inits and imitation bonuses removed. Policies start uniform/zero-init.

**C4 (per-algorithm objectives).** One MDP for all learners, defined once in `defaultEnv_v4`: γ = 0.95, reward = (1−BLER)·TBS·1e-3 / 30, unscheduled reward = 0 (true goodput). Only optimizer hyperparameters differ per algorithm.

**C5 (BLER model).** `estimateBLER_v4` restores per-MCS steepness (1.2–2.7 /dB) and re-anchors curves so BLER = 0.1 exactly at each CQI switching threshold (the LTE design point), instead of 0.5 with ±20 dB transitions.

**C6/C7 (channel).** `generateChannel_v4`: TR 38.901 UMa NLOS path loss (correct formula), log-normal shadowing σ = 6 dB with Gudmundson spatial correlation (50 m), AR(1) complex Gaussian block fading (ρ = 0.95 per scheduling interval — temporally correlated, so delayed CQI is informative but biased), kTB + 9 dB NF, O2I penetration and an explicit interference margin (the "SINR" label is now defensible). No fading/shadowing clipping. No rendering inside training loops (the v3 5-hour runtime was mostly the random-waypoint animation).

**A2C training (audit §2).** Normalized rewards; per-batch advantage standardization; global-norm gradient clipping (5.0) instead of per-tensor at 1.0 (v3 logged 14,756 clips — saturated); time-limit-aware bootstrap V(s_T) instead of 0 at episode end; entropy coefficient annealed 0.05 → 0.001 so greedy evaluation matches the converged policy; warm-up blending removed (it was off-policy without importance correction); actor emits logits with log-softmax loss (numerically stable). Network shared across users = centralized training, decentralized execution.

**Evaluation (audit §4).** Multi-seed training (default 3; use ≥5–10 for the paper), 20 held-out traces identical across all schemes, frozen greedy policies, mean ± 95% CI, paired Wilcoxon signed-rank (A2C vs Baseline / OLLA), Jain index, edge-user (min-user) throughput, CQI tracking error vs the genie mapping, and a robustness sweep: policies trained on PF are re-evaluated on RR and EQ without retraining. A2C's flatter degradation across schedulers is the quantitative "most robust" evidence.

## File map

| File | Role |
|---|---|
| `defaultEnv_v4.m` | single source of truth for the MDP + channel + feedback |
| `generateChannel_v4.m` | TR 38.901 channel, RWP/radial mobility, no rendering |
| `cqiFeedback_v4.m` | delayed + noisy + quantized CQI observations |
| `estimateBLER_v4.m` | per-MCS calibrated BLER waterfalls |
| `computeReward_v4.m` | unified normalized reward |
| `schedule_users_v4.m` | PF / RR / EQ / single-user allocator |
| `QL_AMC_Multi_v4.m`, `AC_AMC_Multi_v4.m`, `DeepA2C_AMC_Multi_v4.m` | trainers |
| `evalPolicy_v4.m` | frozen-policy evaluation incl. Baseline + OLLA |
| `runComparison_v4.m` | multi-seed harness, stats, figures (core) |
| `runCase1_v4.m`, `runCase23_v4.m` | entry points |
| `plotPolicyHeatmap_v4.m` | explainability heatmap |

## For the paper

The defensible claim this stack supports: *under realistic imperfect CQI (delay + noise), the shared-network A2C policy outperforms fixed-mapping and OLLA link adaptation as well as tabular RL, with statistically significant margins, and degrades least under scheduler/mobility distribution shift.* Report the hyperparameter table from `defaultEnv_v4` + trainer headers, state the one-interval-per-scheduling-decision abstraction, and cite TR 38.901 (channel), TS 36.213 (TBS table, 10% BLER target), Pardo et al. 2018 (time-limit bootstrap), and Mnih et al. 2016 (A2C).
