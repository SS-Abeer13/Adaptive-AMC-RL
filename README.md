# Deep Reinforcement Learning for Adaptive Modulation and Coding (RL-AMC)

**Codebase & Scientific Campaign Registry (v9–v17)**  
*Multi-User LTE / 5G-NR Cellular Downlink AMC under Realistic Channel Dynamics & HARQ Delay*

---

## 1. Executive Summary & Headline Findings (v17 Stack)

This repository contains the simulation harness, channel physics, learning algorithms, and pre-registered empirical evaluations investigating whether Deep Reinforcement Learning (RL) can outperform classical Outer Loop Link Adaptation (OLLA) and calibrated link-adaptation baselines in multi-user cellular downlinks.

The final campaign is **v17** (`Optimized/v17/`), evaluated on 500 fresh channel traces per case under Proportional Fair (PF) scheduling with the PF average updated at scheduling time (`env.pf_avg = 'scheduled'`), Chase-combining HARQ, feedback drain window (`env.drain = true`), and packet-capped useful-bits accounting (`env.useful_bits = true`). It is a simulation study with pre-registered decision rules; the summary below reflects the verified evidence anchor.

### Headline Results:
1. **Pre-registered WIN under realistic HARQ timing (M1, RTT = 8 TTIs, 8 processes):**
   On deadline traffic, residual A2C beat all 9 non-RL comparators (Holm-corrected Wilcoxon $p < 0.05$ and 90% CI lower bound $> 0$ for each):
   - Primary scheme (residual A2C, 3000 episodes, **mean over 10 training seeds**): **$+1.58\%$** on-time delivery vs the best calibrated rule (`Context table`), Holm $p = 9.06 \times 10^{-13}$; **$+1.87\%$** vs `Fixed`; 9 of 10 seeds above the best rule.
   - Secondary 10-seed ensemble: $+4.56\%$ vs `Context table`, Holm $p = 1.62 \times 10^{-43}$.
   - Secondary residual A2C at 800 episodes: $+0.34\%$ (Holm $p = 0.0244$); this narrow result does not survive a seed-level (hierarchical) bootstrap and is not used as support.
   - **Recalibration (G6c):** When candidate rules are recalibrated on 500 traces (`table_cal500.csv`), M1 beats all 10 comparators. vs the combined table (`Context-joint-500`): $+0.66\%$ [0.29, 1.03], but this margin is not robust to seed resampling (5/10 seeds; hierarchical 95% CI [−0.30, +1.70]). Recalibration closes about 60% of the initial margin.
   - **Non-oracle base (NR1 & NR2):** When residual A2C is trained around a non-oracle Fixed base (NR1), it achieves a pre-registered WIN (+1.77% vs M1). In the confirmatory replication (NR2, 10 fresh seeds on 500 fresh traces, `table_nr2.csv`), NR2 confirms the win: $+3.35\%$ [2.93, 3.76] vs the combined table, Holm $p = 3.8 \times 10^{-30}$, 9/10 seeds above, hierarchical 95% CI [2.22, 4.40], and $+2.58\%$ vs M1.
   - **OLLA warm-up (W1):** Cold OLLA delivers $+11.96\%$ margin for A2C; allowing OLLA to warm up before evaluation narrows the margin to $+7.49\%$ (`table_warmup.csv`), consistent with the $+7.5\%$ reported in the paper.
   - **Operating grid (G10 & NR-G10):** The M1 recipe at two neighbouring grid points (G10) does not achieve a WIN (Claim A passes, Claim B fails). However, the non-oracle recipe (NR-G10) achieves seed-robust WINs at both neighbouring points: G2 (+1.73% vs Context table, R2 lower bound 0.90) and G3 (+1.02%, R2 lower bound 0.63).
   - **Mechanism (G1 re-cut):** On scheduled users' new transmissions, residual A2C takes active non-zero offsets conditioned on channel velocity and queue slack.

2. **Replication at zero HARQ delay (M2, RTT = 0 TTIs):**
   The RTT-0 deadline gain over all comparators has been observed in four separately seeded campaigns: v13 X2 (secondary), v14 Y0, v16 K2, and v17 M2 (plus v10 E4c, noted as partly overlapping its exploratory traces). Note that v13 X1 was the pre-registered ensemble, which failed. Only v17 M2 uses the scheduling-time PF average; the earlier three used an average updated with delivered bits.
   - Primary scheme (mean over 10 seeds): $+0.43\%$ vs `Context table` (Holm $p = 0.0167$); ensemble: $+0.63\%$ ($p = 5.07 \times 10^{-5}$).
   - Recorded as a replication under project-wide multiplicity control, not as a standalone claim.

3. **No goodput win (M3 & M4, full-buffer traffic):**
   On full-buffer goodput, no RL design outperformed calibrated rules:
   - M3 (RTT = 8): $-0.88\%$ vs `Fixed` (Holm $p = 0.0072$);
   - M4 (RTT = 0): $-1.73\%$ vs `Fixed` (Holm $p = 1.72 \times 10^{-8}$).
   - In M3, the residual policy on scheduled new transmissions collapses to its base rule: exactly 100% of decisions choose action offset $\delta = 0$, making it metrically identical to `FixedPU (Oracle)`. In M4, the learned policy deviates and underperforms `Fixed`.

4. **Inference Latency & Implementation (A3c):**
   Clean single-threaded latency benchmarks (`table_a3c.csv`, `REPORT_a3c.txt`) verify that NumPy and ONNX Runtime implementations match MATLAB decisions identically, executing in under $10\ \mu\text{s}$ per decision, well within sub-millisecond slot deadlines.

---

## 2. Project Lineage & Scientific Corrective Record

The project corrected itself several times; earlier claims were withdrawn or superseded:

* **v7 / v8 claims withdrawn (mobility time-scale error):**
  v7/v8 reported $+12.8\%$ goodput vs OLLA. An internal audit (October 2026) found that user displacement was computed as $v$ metres per TTI instead of $v \cdot T_{\text{tti}}$, i.e. mobility $1000\times$ too fast. With the fix (`mob_kappa = 1`, v9) the gain disappeared (0 wins in 18 v9 cases, A2C $-4.08\%$ vs OLLA). All v7/v8 claims are withdrawn; the v7 documentation is kept in [`Docs/README_v7_historical.md`](Docs/README_v7_historical.md).
* **v10 slot-stealing reward trap:**
  A per-user goodput reward let the shared agent spend other users' slots on failing transmissions. The learned policy was bimodal (58% of decisions at offset $-3$, 35.8% at $+2$) and reached 1.38 Mbps vs OLLA's 2.92 Mbps. An opportunity-cost reward (v10b) removed the trap (2.9191 vs 2.9233 Mbps, $-0.14\%$, n.s.).
* **v15 / v16 RTT > 0 results superseded (PF averaging timing artefact):**
  With multi-process HARQ (8 processes, RTT 8), PF's average rate was updated at feedback time ($t + \text{RTT}$) instead of scheduling time ($t$). Consequently, the strongest user was repeatedly scheduled without their average rate rising for 8 TTIs. This inflated throughput for all schemes, Baseline included (about $+40\text{--}50\%$), and reduced fairness (Jain index 0.50 → 0.42). It was an evaluation artefact, not an RL-specific gain. All v15/v16 RTT > 0 cases are superseded.
* **v17 final pipeline:**
  1. PF rate averaging at scheduling time (`pf_avg = 'scheduled'`);
  2. an end-of-trace HARQ drain window (`harq_rtt` extra TTIs with no new transmissions), so all in-flight blocks are credited;
  3. `useful_bits` accounting for deadline traffic;
  4. one unified Jain-index definition across all scripts. The legacy (RTT 0) and multi-process (RTT 1) engines are bit-identical under these settings.

The full campaign history is tracked in [`Optimized/case_registry.csv`](Optimized/case_registry.csv): **67 cases and 108 scheme evaluations** (v9–v17; 49 cases from v10 onward, when the current protocol began). **7 cases (18 scheme evaluations) are superseded.** A `correction` column records known corrections beside the parsed values (e.g. v13 X1: the pre-registered scheme was the ensemble, which failed; v13 X2 was the secondary replication).

---

## 3. Quick-Start & Reproduction Guide

The complete v17 release pipeline and reproducibility scripts are located in `Optimized/v17/release/` and `release/`.

### Automated Reproduction Suite
To strictly verify all 6 publication tables (`table_core`, `table_cal500`, `table_nr2`, `REPORT_nr_g10`, `table_warmup`, and `hr_predictions`) against stored evaluation results:
```bash
python Optimized/v17/release/reproduce_tables.py
```

### Direct MATLAB Execution
```matlab
cd 'd:\Adaptive AMC A2C+QL\Optimized\v17'

% 1. Preflight sanity verification (~2-3 minutes)
fill_v17_preflight

% 2. Full pre-registered campaign (4 cases: M1, M2, M3, M4)
fill_v17_campaign

% 3. Generate summary statistics and evaluation tables
build_v17_tables
```

### Inspect Campaign Registry
To inspect the project-wide case registry and status across all versions:
```matlab
cd 'd:\Adaptive AMC A2C+QL\Optimized'
build_case_registry; % Regenerates case_registry.csv (67 unique cases, 108 rows, incl. correction column)
```

---

## 4. Primary Documentation & Links

* **Release Guide & Manifest:** [`Optimized/v17/release/README_release.md`](Optimized/v17/release/README_release.md) — Comprehensive guide to data, checkpoints, code, and table reproduction.
* **Frozen Pre-Registrations:** [`paper/proposals/FREEZE.sha256`](paper/proposals/FREEZE.sha256) — Cryptographic hashes of all pre-registered analysis protocols.
* **Final Campaign Report:** [`Optimized/v17/README_v17.md`](Optimized/v17/README_v17.md) — Pre-registered protocol, empirical results, state-conditional action breakdowns, and statistical analyses.
* **Full Case Registry:** [`Optimized/case_registry.csv`](Optimized/case_registry.csv) — Audit trail of all experimental cases, comparator baselines, Holm-adjusted p-values, and replication status from v9 to v17.
* **Historical Review Responses & Drafts:**
  - [`Docs/README_v7_historical.md`](Docs/README_v7_historical.md) — Archived v7 executive summary.
  - [`papers/v8_draft/`](papers/v8_draft/) — v8 paper drafts, reviewer response letters, and original figure assets.
