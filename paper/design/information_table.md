# Information table: which signals each scheme uses (for Section III or V of the paper)

Code-verified on 2026-11-04 against `Optimized/v17/evalPolicy_v17.m`, `stateFeat_v17.m`, `featExtra_v17.m`, `slackOf_v17.m`, `userClass_v17.m` and `Bandit_v17.m` (ledger S11, S13, S13a). ✓ = uses the signal; — = does not. **"Oracle"** marks information that comes from the simulator's ground truth rather than from a gNB measurement.

| Scheme | Reported CQI (delayed 2–8 TTI, noisy) | ACK/NACK history (via OLLA loop) | Deadline slack / remaining bits | Delay class (d ≤ 4 / ≥ 5) | Speed class (< 10 / 10–20 / > 20 m/s) | HARQ-process state (busy procs, retx-ready, in-flight bits) | Other | Calibrated on |
|---|---|---|---|---|---|---|---|---|
| Baseline (open-loop CQI) | ✓ | — | — | — | — | — | — | — |
| OLLA (10 % target) | ✓ | ✓ | — | — | — | — | — | — (standard) |
| OLLA, tuned target | ✓ | ✓ | — | — | — | — | — | target grid, 10 calib. traces |
| Multi-OLLA (fast/slow blend) | ✓ | ✓ | — | — | — | — | CQI trend, cell NACK EMA (blend weight) | — |
| Fixed (global offset on OLLA) | ✓ | ✓ | — | — | — | — | — | offset grid, 20 traces |
| **FixedPU, a class oracle** (offset per class on OLLA) | ✓ | ✓ | — | ✓ (true delay; arguably gNB-known, since the gNB configures CQI reporting) | ✓ **oracle** (true mean speed over the trace) | — | — | per-class grid, 20 traces |
| Context table (offset per slack bin on OLLA) | ✓ | ✓ | ✓ (3 bins: ≤ 2, 3–5, > 5 TTI) | — | — | — | — | coordinate ascent, 10 traces |
| Bandit, global (frozen UCB offset) | ✓ | ✓ | — | — | — | — | — | trained on RL episodes |
| Bandit, delay class | ✓ | ✓ | — | ✓ (true delay) | — | — | — | trained on RL episodes |
| A2C, offset action | ✓ | ✓ | ✓ | — | — | ✓ | ΔCQI, observed SINR and Δ, OLLA offset, CQI trend, cell NACK EMA, HARQ pending/retx count, normalised PF rate; 3 stacked frames | 800 episodes × 10 seeds |
| **Residual A2C (primary)** | ✓ | ✓ | ✓ | ✓ **via base rule (FixedPU)** | ✓ **oracle, via base rule (FixedPU)** | ✓ | as offset A2C | 3000 episodes × 10 seeds |
| *Combined table (G6, proposed)* | ✓ | ✓ | ✓ (3 bins) | ✓ | ✓ (oracle, as FixedPU) | ✓ (busy procs: 0 / ≥ 1) | — | 500 traces (as other -500 rules) |

## Text for the paper (draft)
> Table X lists the signals each scheme uses. The RL state contains only quantities observable at the gNB. It excludes the true speed and true feedback delay. However, the residual policy acts on top of FixedPU. FixedPU is a *class oracle*: its offsets are indexed by the true delay class (arguably known at the gNB, which configures CQI reporting) and by the true mean-speed class (not observable at the gNB). The residual policy therefore inherits this class information through its base rule. The single-cue calibrated rules each see part of the learner's information: FixedPU sees the class, the Context table sees the deadline slack. A rule combining slack, class and HARQ-process state is evaluated in Section VI-X (G6).

## Consistency with the paper's recommendation
The pitfalls section recommends reporting **what each learner observes** (with the LOLLA observation-set ablation as a neutral example). This table is that recommendation applied to our own study.
