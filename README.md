# Deep Reinforcement Learning for Adaptive Modulation and Coding (RL-AMC)

**Codebase & Scientific Campaign Registry (v9–v17)**  
*Multi-User LTE / 5G-NR Cellular Downlink AMC under Realistic Channel Dynamics & HARQ Delay*

---

## 1. Executive Summary & Headline Findings (v17 Stack)

This repository contains the simulation harness, channel physics, learning algorithms, and pre-registered empirical evaluations investigating whether Deep Reinforcement Learning (RL) can outperform classical Outer Loop Link Adaptation (OLLA) and calibrated link-adaptation baselines in multi-user cellular downlinks.

The primary audited campaign is **v17** (`Optimized/v17/`), evaluated across 500 independent channel traces under Proportional Fair (PF) scheduling, Chase combining HARQ, and feedback round-trip times (RTT $\in \{0, 8\}$ TTIs).

### Headline Results:
1. **Statistically Significant WIN under Realistic HARQ Feedback Delay (M1, RTT = 8 TTIs):**
   Under realistic feedback delay (RTT = 8 TTIs) and deadline-constrained traffic, **Deep A2C achieves a statistically significant victory** over all classical and calibrated baselines:
   - Primary (mean over 10 seeds) Deep A2C: **$+1.58\%$** on-time throughput over the strongest non-RL comparator (`Context table`), Holm-adjusted $p = 9.06 \times 10^{-13}$.
   - 10-seed Ensemble Policy: **$+4.56\%$** on-time throughput over `Context table`, Holm-adjusted $p = 1.62 \times 10^{-43}$.
   - Secondary pre-registered A2C-resid (800 ep): $+0.34\%$ ($p = 0.0244$), confirming the advantage is structural.
   - **Mechanism:** Under delay on new transmissions, the agent discovers state-dependent risk modulation—biasing aggressively ($+1$ offset, 88–90% share) during deadline urgency (slack $\le 5$ TTIs) and buffer congestion / busy HARQ processes (85–93% share) to avoid deadline drops, while selecting conservative choices (actions 0 and −1) primarily when slack is abundant ($> 5$ TTIs) and processes are idle.

2. **Fourth Replication at Zero Delay (M2, RTT = 0 TTIs):**
   Under instantaneous feedback (RTT = 0 TTIs), Deep A2C replicates the zero-delay deadline win across multiple campaigns: v13 X2 (secondary), v14 Y0, v16 K2, and v17 M2, plus v10 E4c (noted as partly overlapping its exploratory traces):
   - Primary (mean over 10 seeds): $+0.43\%$ ($p = 0.0167$); Ensemble: $+0.63\%$ ($p = 5.07 \times 10^{-5}$).
   - Recorded as a confirmatory replication under project-wide multiplicity control.

3. **No Goodput Win (M3 & M4, Pure Rate Maximization):**
   RL achieves **no gain over calibrated fixed setpoints** under pure unconstrained goodput traffic:
   - M3 (RTT = 8): $-0.88\%$ vs `Fixed` ($p = 0.0072$);
   - M4 (RTT = 0): $-1.73\%$ vs `Fixed` ($p = 1.72 \times 10^{-8}$).
   - The learned policy collapses directly onto the calibrated base rule (selecting action 0 for 92.3% of TTIs in M3 and 76.3% in M4). This indicates that RL does not discover opportunistic channel prediction under rate maximization, bounding the RL advantage strictly to queue/deadline dynamics.

---

## 2. Project Lineage & Scientific Corrective Record

The project underwent rigorous retrospective validation and bug identification, leading to the withdrawal and supersession of earlier claims:

* **v7 / v8 Claims Withdrawn (Mobility Time-Scale Discrepancy):**
  Early versions (v7/v8) reported large throughput gains ($+12.8\%$) under goodput traffic. In October 2026, an internal audit identified that spatial displacement had been computed as $v$ meters per TTI rather than $v \cdot T_{\text{tti}}$, scaling user mobility $1000\times$ faster than physical reality. When corrected (`mob_kappa = 1` in v9), the goodput gain completely vanished ($0/18$ wins in v9). All v7/v8 claims were formally withdrawn. The historical v7 documentation is preserved in [`Docs/README_v7_historical.md`](Docs/README_v7_historical.md).
* **v15 / v16 RTT Claims Superseded (PF Denominator Feedback Artefact):**
  In v15 and v16, evaluations at RTT $> 0$ were affected by an implementation artefact in the scheduler: Proportional Fair's average throughput was updated at feedback time rather than transmission time. With 8 parallel HARQ processes, the strongest user was repeatedly scheduled before its feedback arrived. That inflated goodput for all schemes, Baseline included (about +40–50%), and reduced fairness (Jain 0.50 → 0.42). It was not an RL-specific gain.
* **v17 Corrected Pipeline:**
  v17 resolved this by:
  1. Updating PF rate averaging at transmission time (`pf_avg = 'scheduled'`);
  2. Introducing an end-of-trace HARQ drain window (`harq_rtt` extra TTIs with zero new transmissions) to credit all in-flight blocks fairly;
  3. Enforcing `useful_bits` accounting across all deadline policies.

The full campaign history across all 67 experimental cases and 108 scheme evaluations is tracked in [`Optimized/case_registry.csv`](Optimized/case_registry.csv).

---

## 3. Quick-Start & Reproduction Guide

The complete v17 release pipeline is located in `Optimized/v17/`.

### Headless Reproduction (Windows Command Prompt / PowerShell)
To execute the automated campaign runner with memory protection, heartbeats, and resume capabilities:
```cmd
cd "d:\Adaptive AMC A2C+QL\Optimized\v17"
run_v17_headless.bat
```

### Direct MATLAB Execution
```matlab
cd 'd:\Adaptive AMC A2C+QL\Optimized\v17'

% 1. Preflight sanity verification (~2-3 minutes)
fill_v17_preflight

% 2. Full pre-registered campaign (4 cases: M1, M2, M3, M4)
fill_v17_campaign

% 3. Generate summary statistics and evaluation tables
fill_stats_v17
```

### Inspect Campaign Registry
To inspect the project-wide case registry and status across all versions:
```matlab
cd 'd:\Adaptive AMC A2C+QL\Optimized'
build_case_registry; % Regenerates case_registry.csv (67 unique cases, 108 scheme evaluations)
```

---

## 4. Primary Documentation & Links

* **Campaign Report:** [`Optimized/v17/README_v17.md`](Optimized/v17/README_v17.md) — Comprehensive pre-registered protocol, empirical results, state-conditional action breakdowns, and statistical analyses.
* **Full Case Registry:** [`Optimized/case_registry.csv`](Optimized/case_registry.csv) — Audit trail of all 67 experimental cases and 108 scheme evaluations, comparator baselines, Holm-adjusted p-values, and replication status from v9 to v17.
* **Historical Review Responses & Drafts:**
  - [`Docs/README_v7_historical.md`](Docs/README_v7_historical.md) — Archived v7 executive summary.
  - [`papers/v8_draft/`](papers/v8_draft/) — v8 paper drafts, reviewer response letters, and original figure assets.
