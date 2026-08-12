# v7 — RL Link Adaptation in Heterogeneous, Non-Stationary Cells

Design rationale: `V7_DESIGN_PLAN.md`. In one line: v6 proved a constant offset
matches RL in a calm, homogeneous world; v7 adds the real-world effects (HARQ,
per-user heterogeneity, interference bursts, honest Jakes fading, steep per-MCS
BLER curves) under which a state-conditional policy is the only thing that can
keep up — while keeping every control that made v6 credible.

## Files

| File | Role |
|---|---|
| `defaultEnv_v7.m` | All parameters (HARQ, heterogeneity, bursts, tiers) |
| `generateChannel_v7.m` | Per-user Jakes fading, speed switches, burst chain |
| `cqiFeedback_v7.m` | Per-user CQI delay + measurement noise |
| `estimateBLER_v7.m` | Steep per-MCS BLER waterfalls |
| `txStep_v7.m` / `harqInit_v7.m` | Shared TTI physics: HARQ, Bernoulli delivery, OLLA update |
| `stateFeat_v7.m` | Tier-A (info-equal) / Tier-B (full) deep state |
| `userClass_v7.m` | (delay, speed) → class for the fixed-offset control |
| `evalPolicy_v7.m` | Frozen-policy eval, 7 ptypes, leakage-free warm-up |
| `QL_Shared_v7.m` / `AC_Shared_v7.m` | Tabular trainers (Tier A) |
| `DeepA2C_Shared_v7.m` | Deep A2C trainer (Tier A/B, ±3 actions, CPU) |
| `calibrateFixedClass_v7.m` | Tunes the fixed-offset comparators on calibration traces |
| `runComparison_v7.m` | Harness: 7 schemes, trace-level stats, regime-conditioned report |
| `run_v7_point.m` / `run_v7_all.bat` | Headless resumable runners, one MATLAB process per point |

Comparators in every table: Baseline · OLLA · best global fixed offset ·
per-class fixed offset · QL · Tab-AC · Deep A2C.
**Pre-registered win condition:** A2C beats converged OLLA *and* the per-class
fixed offset on PF cell throughput (paired Wilcoxon, trace level).

## How to run (step by step)

All commands from a Windows terminal in this folder
(`G:\8th Semester\Case 1\Case 1\optimized\v7`). Results land in `Dataset/`,
live log in `logs\v7_master_log.txt` (`type logs\v7_master_log.txt` to watch).

```cmd
:: 0. Pipeline check - ALWAYS FIRST (~2-5 min). Must end with "COMPLETE".
matlab -batch "run_v7_point('smoke')"

:: 1. Credibility anchor (~1 h): calm homogeneous world. EXPECT RL ~ OLLA.
matlab -batch "run_v7_point('phase0')"

:: 2. Heterogeneity family (~1 h each): does the RL gap grow with user mix?
matlab -batch "run_v7_point('hetero',0.5)"
matlab -batch "run_v7_point('hetero',1)"

:: 3. Burst family (~1 h each): does the gap grow with non-stationarity?
::    burst 9 dB doubles as the HEADLINE point.
matlab -batch "run_v7_point('burst',6)"
matlab -batch "run_v7_point('burst',9)"
matlab -batch "run_v7_point('burst',12)"

:: 4. Ablations & defenses at the headline point (~1 h each):
matlab -batch "run_v7_point('tierA')"       :: info-equal state - what does Tier B buy?
matlab -batch "run_v7_point('warm')"        :: vs CONVERGED OLLA (the v6 killer, pre-empted)
matlab -batch "run_v7_point('replicate')"   :: fresh seeds + fresh traces (the A2 lesson)
```

Or run everything unattended (skips completed points, aborts if smoke fails):

```cmd
run_v7_all.bat
```

Quick version (smoke + phase0 + headline only):

```cmd
run_v7_all.bat quick
```

## Reading the results

Each `Dataset/results_v7_<tag>.txt` prints, per scheduler: cell/edge
throughput with trace-level CIs, first-Tx BLER, Jain, **burst vs calm
throughput** (the regime-conditioned gap — where the prominent RL numbers
should appear), and the pre-registered Wilcoxon tests including **A2C vs
FixedPU**, the decisive comparison.

Decision rules, agreed in advance:
- `phase0`: A2C ≈ OLLA expected. If A2C wins big here, suspect a bug first.
- `hetero`/`burst` families: gap should grow with the knob. A2C must beat
  FixedPU, not just OLLA.
- `tierA` vs headline: the difference *is* the value of the extra state.
- `warm`: A2C must stay ≥ converged OLLA.
- `replicate`: headline must reproduce, or it doesn't get written up.

## Known constraints on this machine
MATLAB R2023a + RTX 50-series GPU → intermittent heap corruption with
figures/GPU in `-batch`. v7 therefore: never creates figures, trains CPU-only
(`env.use_gpu=false`), 300 episodes, one fresh MATLAB process per point,
everything resumable. If a run dies, just re-run the same command.
