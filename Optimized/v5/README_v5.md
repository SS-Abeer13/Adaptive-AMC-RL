# v5 — Merged stack (baseline-relative encoding + corrected training/eval)

v5 unifies the two v4 lines into one pipeline:

- **From `case2_3` v4:** *baseline-relative CQI encoding.* The action is an **offset** from the CQI a fixed mapping picks on the observed SINR (`sent_CQI = clip(baseCQI(obs_SINR) + offset)`). Offset 0 **is** the baseline, so every learner starts at baseline performance and only has to learn a correction. Also adopts **shared parameters across N users** (one Q-table / one θ / one network), giving the deep agent an N× sample-efficiency advantage and supporting arbitrary N.
- **From `optimized/v4`:** imperfect CQI (delay + noise + quantization), calibrated per-MCS BLER, TR 38.901 channel, unified normalized reward, **all A2C training fixes**, and the rigorous multi-seed / held-out / CI / Wilcoxon / robustness evaluation. No imitation bonus, no bias init, no warmup blend.

## Why this is the version that can beat the baseline

The baseline transmits at `baseCQI(obs_SINR)` — a CQI that is delayed (`cqi_delay=4`) and noisy. When the channel is rising, that CQI under-shoots; when falling, it over-shoots and the block errors. The learner observes the SINR trend `dS = obs(t) − obs(t−1)` and learns the offset that corrects the stale baseline — a real, citable advantage (outdated-CQI compensation). Because the encoding is relative, the policy's whole job is the correction, which is far easier to learn than re-deriving the mapping (the failure mode of the differential v4).

## Run

```matlab
cd optimized/v5
results = runCase23_v5();                  % N=5 PF, defaults (3 seeds x 20 traces)
results = runCase23_v5('N',50);            % shared-parameter scale study
results = runCase1_v5();                   % single-user radial
results = runCase23_v5('N',50,'n_seeds',5,'n_eval',30,'ep_deep',300);  % camera-ready
```

Outputs `results_v5_caseX_NY.mat/.txt` (table with 95% CIs + Wilcoxon p) and figures: KPI bars with CIs, learning curves in environment steps + A2C entropy, throughput vs distance, and the baseline-relative policy heatmap (left: learned offset vs baseline; right: offset for rising/flat/falling trend — the compensation made explicit).

## Expected signature of success

Baseline and OLLA sit below the genie ceiling because their CQI is outdated; A2C recovers part of that gap via trend-aware offsets and should clear both with `p<0.05`; the shared Q-table/θ lift QL and Tab-AC well above the per-user v3/v4 tables but below A2C (no interpolation across unvisited cells); A2C degrades least across PF→RR→EQ. If the A2C margin is thin, sweep `env.cqi_delay ∈ {0,2,4,6,8}` — the margin should widen monotonically with delay, which is the headline figure.

## File map

| File | Role |
|---|---|
| `defaultEnv_v5.m` | MDP + channel + feedback (takes `caseId`, optional `N`) |
| `generateChannel_v5.m` | TR 38.901 channel, RWP/radial, arbitrary N, no rendering |
| `cqiFeedback_v5.m` | delayed + noisy + quantized CQI |
| `baseCQI_v5.m` | observed-SINR → baseline CQI (relative-action reference) |
| `estimateBLER_v5.m` | calibrated per-MCS BLER |
| `computeReward_v5.m` | unified normalized reward |
| `schedule_users_v5.m` | all / rr / pf / eq |
| `trendBin_v5.m`, `argmaxNoOp_v5.m` | shared helpers |
| `QL_Shared_v5.m`, `AC_Shared_v5.m`, `DeepA2C_Shared_v5.m` | shared-parameter trainers |
| `evalPolicy_v5.m` | frozen eval incl. Baseline + OLLA |
| `runComparison_v5.m` | multi-seed harness, stats, figures |
| `runCase1_v5.m`, `runCase23_v5.m` | entry points |
| `plotPolicyHeatmap_v5.m` | explainability |

Depends on `../case2_3/createTBS_Table.m` and `tbsFromMCSandRB.m` (added to path automatically by the harness).

## v5.1 — scheduler domain randomization + sweeps

The first N=50 run showed A2C significantly beating Baseline/OLLA on PF but becoming the *least* scheduler-robust (worst under RR/EQ), because it trained on PF only and overfit to PF's served-user distribution. Fix: `env.train_schedulers = {'pf','rr','eq'}`; each trainer (QL/AC/A2C) samples one scheduler per episode, so the policy sees all served-user distributions. Set `env.train_schedulers = {'pf'}` to reproduce the old behavior. Evaluation is unchanged (still PF primary + RR/EQ robustness columns), so the robustness table now measures genuine generalization.

New sweep drivers:

```matlab
S = sweepDelay_v5([0 2 4 6 8]);            % A2C margin vs CQI delay (headline figure)
S = sweepDelay_v5([0 2 4 6 8], 23, struct('N',10,'n_seeds',3));
S = sweepN_v5([5 10 20 50]);               % A2C margin vs number of users
```

Both re-run the full multi-seed/held-out comparison per point (slow — reduce `n_seeds`/`ep_deep` to scan) and save a `.mat` + figure. `runComparison_v5` now accepts `opts.cqi_delay`, `opts.speed`, `opts.train_schedulers` overrides.

## v5.2 — observable scheduler context + per-scheduler output

The domain-randomized v5.1 run fixed RR/EQ robustness but regressed on PF (A2C fell below baseline) because one policy had to average across three regimes it couldn't see. v5.2 makes the scheduler regime **observable**:

- `env.sched_list = {'pf','rr','eq'}`; `schedContext_v5` maps the active scheduler to an index/one-hot. Tabular learners gain a scheduler dimension in their tables; the deep agent gets the one-hot appended to its input (`nFeat = 4 + nSched`). All learners get the same context, so the comparison stays information-equal and each can now **specialize per regime** instead of compromising.
- Training mix is **PF-weighted** (`env.train_sched_weights = [0.50 0.25 0.25]`, sampled via `sampleSched_v5`) so the deployment-primary scheduler keeps priority while RR/EQ robustness is retained.
- `ep_deep` default raised to **400** (three regimes share the budget).
- **Per-scheduler output:** `runComparison_v5` now prints the full metric table (Cell Tp, Δ vs baseline, Edge Tp, BLER, Jain, CQIerr, best-in-column markers, Wilcoxon) for **every** evaluation scheduler, not just the primary — followed by the cross-scheduler robustness summary. The `.txt` file contains one labelled section per scheduler.

To revert to single-regime behaviour: `env.train_schedulers = {'pf'}` (context still present but constant).

## Relationship to earlier versions

v3 (imitation-shaped) and the two v4 lines remain on disk for reproducibility. v5 supersedes both v4 lines; cite v5 numbers in the paper. The defensible claim it supports: *under realistic imperfect CQI, a shared-network A2C learning baseline-relative offsets outperforms fixed-mapping and OLLA link adaptation and tabular RL, with statistically significant margins, and degrades least under scheduler shift.*
