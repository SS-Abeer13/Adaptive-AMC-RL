# Deep Reinforcement Learning for Adaptive Modulation and Coding (RL-AMC)

**Codebase & Scientific Campaign Registry (v9–v17)**  
*Multi-User LTE / 5G-NR Cellular Downlink AMC under Realistic Channel Dynamics & HARQ Delay*

---

## 1. Executive Summary & Headline Findings (v17 Stack)

This repository contains the simulation harness, channel physics, learning algorithms, and pre-registered empirical evaluations investigating whether Deep Reinforcement Learning (RL) can outperform classical Outer Loop Link Adaptation (OLLA) and calibrated link-adaptation baselines in multi-user cellular downlinks.

The final campaign is **v17** (`Optimized/v17/`), evaluated on 500 fresh channel traces per case under Proportional Fair (PF) scheduling with the PF average updated at scheduling time, Chase-combining HARQ, and HARQ round-trip times RTT $\in \{0, 8\}$ TTIs. It is a simulation study with pre-registered decision rules; the wording below follows those rules.

### Headline Results:
1. **Pre-registered WIN under realistic HARQ timing (M1, RTT = 8 TTIs, 8 processes):**
   On deadline traffic, residual A2C beat all 9 comparators (Holm-corrected Wilcoxon $p < 0.05$ and 90% CI lower bound $> 0$ for each):
   - Primary scheme (residual A2C, 3000 episodes, **mean over 10 training seeds**): **$+1.58\%$** on-time delivery vs the best calibrated rule (`Context table`), Holm $p = 9.06 \times 10^{-13}$; $+1.87\%$ vs `Fixed`; 9 of 10 seeds above the best rule. The fairness guard is clear.
   - Secondary 10-seed ensemble: $+4.56\%$ vs `Context table`, Holm $p = 1.62 \times 10^{-43}$.
   - Secondary residual A2C at 800 episodes: $+0.34\%$ (Holm $p = 0.0244$); this narrow result does not survive a seed-level (hierarchical) bootstrap and is not used as support.
   - **Mechanism:** under re-analysis. The earlier action-share description mixed in retransmissions, where the residual action has no effect. A re-cut restricted to scheduled new transmissions is pending.

2. **Replication at zero HARQ delay (M2, RTT = 0 TTIs):**
   The RTT-0 deadline gain over all comparators has now been observed in four separately seeded campaigns (v13 X2, v14 Y0, v16 K2, v17 M2). Only v17 M2 uses the scheduling-time PF average; the earlier three used a PF average updated with delivered bits.
   - 10-seed mean: $+0.43\%$ vs `Context table` (Holm $p = 0.0167$); ensemble: $+0.63\%$ ($p = 5.07 \times 10^{-5}$).
   - Recorded as a replication under project-wide multiplicity control, not as a standalone claim.

3. **No goodput win (M3 & M4, full-buffer traffic):**
   On full-buffer goodput, no RL design outperformed calibrated rules:
   - M3 (RTT = 8): $-0.88\%$ vs `Fixed` (Holm $p = 0.0072$);
   - M4 (RTT = 0): $-1.73\%$ vs `Fixed` (Holm $p = 1.72 \times 10^{-8}$).
   - In M3 the residual policy is metrically identical to its base rule (FixedPU): goodput, Jain index and 5th-percentile throughput are bit-identical on all 500 traces for all 10 seeds. In M4 it is not identical and is worse than `Fixed`.

---

## 2. Project Lineage & Scientific Corrective Record

The project corrected itself several times; earlier claims were withdrawn or superseded:

* **v7 / v8 claims withdrawn (mobility time-scale error):**
  v7/v8 reported $+12.8\%$ goodput vs OLLA. An internal audit (October 2026) found that user displacement was computed as $v$ metres per TTI instead of $v \cdot T_{\text{tti}}$, i.e. mobility $1000\times$ too fast. With the fix (`mob_kappa = 1`, v9) the gain disappeared (0 wins in 18 v9 cases, A2C $-4.08\%$ vs OLLA). All v7/v8 claims are withdrawn; the v7 documentation is kept in [`Docs/README_v7_historical.md`](Docs/README_v7_historical.md).
* **v10 slot-stealing reward trap:**
  A per-user goodput reward let the shared agent spend other users' slots on failing transmissions. The learned policy was bimodal (58% of decisions at offset $-3$, 35.8% at $+2$) and reached 1.38 Mbps vs OLLA's 2.92 Mbps. An opportunity-cost reward (v10b) removed the trap (2.9191 vs 2.9233 Mbps, $-0.14\%$, n.s.).
* **v15 / v16 RTT > 0 results superseded (PF averaging timing artefact):**
  With multi-process HARQ, the PF average was updated with ACKed bits at feedback time ($t + \text{RTT}$) instead of at scheduling time ($t$). The just-served user's average did not rise for 8 TTIs, so PF degenerated towards bursty max-rate scheduling. This inflated goodput for **every** scheme, not only RL (Baseline: 3.466 Mbps with 1 process vs 4.837 Mbps with 8 processes at RTT 8; Jain 0.50 → 0.42), and caused a 10% engine discontinuity. All v15/v16 RTT > 0 cases are superseded.
* **v17 final pipeline:**
  1. PF rate averaging at scheduling time (`pf_avg = 'scheduled'`);
  2. an end-of-trace HARQ drain window (`harq_rtt` extra TTIs with no new transmissions), so all in-flight blocks are credited;
  3. `useful_bits` accounting for deadline traffic;
  4. one Jain-index definition. The legacy (RTT 0) and multi-process (RTT 1) engines are bit-identical under these settings.

The full campaign history is tracked in [`Optimized/case_registry.csv`](Optimized/case_registry.csv): **67 cases and 108 scheme evaluations** (v9–v17; 49 cases from v10 onward, when the current protocol began). **7 cases (18 scheme evaluations) are superseded.** A `correction` column records known corrections beside the parsed values (e.g. v13 X1: the pre-registered scheme was the ensemble, which failed).

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
build_case_registry; % Regenerates case_registry.csv (67 unique cases, 108 rows, incl. correction column)
```

---

## 4. Primary Documentation & Links

* **Final Campaign Report:** [`Optimized/v17/README_v17.md`](Optimized/v17/README_v17.md) — Comprehensive pre-registered protocol, empirical results, state-conditional action breakdowns, and statistical analyses.
* **Full Case Registry:** [`Optimized/case_registry.csv`](Optimized/case_registry.csv) — Audit trail of all experimental cases, comparator baselines, Holm-adjusted p-values, and replication status from v9 to v17.
* **Historical Review Responses & Drafts:**
  - [`Docs/README_v7_historical.md`](Docs/README_v7_historical.md) — Archived v7 executive summary.
  - [`papers/v8_draft/`](papers/v8_draft/) — v8 paper drafts, reviewer response letters, and original figure assets.
