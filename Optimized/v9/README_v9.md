# v9 campaign — corrections from the internal review of the v8 paper (19 Oct 2026)

## What changed relative to v8
| Item | Where | Default in v9 |
|---|---|---|
| **Mobility time scale.** v7/v8 moved users `v` metres per TTI (1000× too fast). The displacement per TTI is now `v * T_tti * mob_kappa`. | `generateChannel_v9.m` | `mob_kappa = 1` (set 1000 to reproduce v8) |
| **Common random numbers.** One uniform per user per TTI is drawn for each trace (`rng(50000+j)`), and warm-up segments use their own draws. Every scheme on a trace sees the same outcome draws, so identical controllers now give identical numbers. The warm-up segment seed is now unique per trace (`meta.trace_id`). | `txStep_v9`, `MultiOLLA_v9`, `evalPolicy_v9`, `runComparison_v9`, `calibrateFixedClass_v9`, fill_* scripts | `crn = true` |
| **Matched steady state.** Training episodes and Fixed/FixedPU calibration can start after the same pure-OLLA warm-up as evaluation. | `DeepA2C_Shared_v9` (`train_warm_ttis`), `calibrateFixedClass_v9` (`calib_warm`) | off. The `steady_match` point turns it on. |
| **Bandit baselines.** UCB1 over the 11 residual offsets: global, and per observable delay class. Reward is goodput per transmission opportunity normalized by the OLLA-reference TBS. They are trained on the same episodes as A2C, frozen, and evaluated greedily. | `Bandit_v9.m`, plus schemes 9 and 10 in `runComparison_v9` | always on |
| **Per-scheduler calibration.** Fixed/FixedPU are calibrated on the evaluated scheduler (RR/EQ points). | `runComparison_v9`, `calibrateFixedClass_v9` | automatic |
| Holm family | `runComparison_v9`, `fill_stats_v9` | now 9 comparisons (7 classical + 2 bandits) |

The schemes are Baseline, OLLA, Warm-OLLA, Multi-OLLA, Fixed, Fixed-Online, FixedPU, Deep A2C, Bandit (global) and Bandit (delay class).

## How to run (headless)
Pick one of these:
- Double-click `run_v9_headless.bat`.
- From a Windows terminal:
  ```
  "C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "run('D:\Adaptive AMC A2C+QL\Optimized\v9\run_v9_all.m')" -logfile "D:\Adaptive AMC A2C+QL\Optimized\v9\logs\matlab_batch.log"
  ```

`run_v9_all.m` runs `fill_v9_preflight.m` first, using tiny sizes and taking a few minutes. The full campaign `fill_v9_campaign.m` starts only if no preflight check reports `_FAIL`. To run only the preflight: `matlab -batch "run('...\v9\fill_v9_preflight.m')"`.

## Logs to monitor
| File | Content |
|---|---|
| `logs/fill_v9_preflight.txt` | `PREFLIGHT_*_OK` or `_FAIL` lines with the stack trace, plus `CRNCHECK` (OLLA vs Fixed(0) must say `identical=1`) and `MOBCHECK` (max step ≤ 0.03 m) |
| `logs/fill_v9.log` | Full console diary: per-seed training progress, calibration, and evaluation tables |
| `logs/matlab_batch.log` | Raw MATLAB `-logfile` output, which also captures crashes outside the diary |
| `Dataset/fill_summary_v9.txt` | Compact numbers per point: `STEP|tag|start/done`, `SCHEME`, `CMP`, `BCMP`, `BARMS`, `ACT`, `SWEEP`, `CONST`, `RAND`, `BC`, `ERROR` |
| `Dataset/results_v9_<tag>.mat` | Full results per point |

## Points, in run order
| Tag | Purpose |
|---|---|
| `gp_O` | Primary (Tier-O, goodput reward, PF ranks on the OLLA reference). Also runs the action histogram, OLLA target sweep, random control and constant-offset landscape. |
| `steady_match` | 1000-TTI warm-up and 950 scored TTIs; learner trained, and Fixed/FixedPU calibrated, after the same warm-up |
| `steady_cold` | Same horizon, cold-start training and calibration (the v8 design), for comparison |
| `rr_O`, `eq_O` | Round Robin / Equal Share: trained, calibrated and evaluated on that scheduler |
| `burst6_O`, `burst12_O`, `h0_O`, `h05_O` | Interference and heterogeneity sweep |
| `gp_A`, `gp_B` | State ablation |
| `pen_O/A/B` | Penalised-reward variant (λretx = 0.05, λdrop = 0.5) |
| `orig_O/A/B` | Original scheduler input (PF ranks on the agent's MCS), penalised. O and B also run the random control. |
| `bcdiag_gp`, `bcdiag_pen` | Behaviour-cloning diagnostic (5 seeds, 150 cloning + 300 RL episodes) |
| `orig_O_long1500` | Longer training (3 seeds × 1500 episodes) |

Every point is wrapped in try/catch: a failure writes an `ERROR|tag|...` line and the campaign moves on to the next point. Expected wall time is about 4–5 h. This estimate scales the v8 timings, adding the two bandits and their evaluation.
