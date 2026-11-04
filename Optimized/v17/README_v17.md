# v17 — Correction Round: PF Averaging Fix, Engine-Gap Check, Realistic-HARQ Re-Run

Written 3 Nov 2026, following `PLAN_v17.md`.

---

## 1. Context and Motivation

The post-v16 review evaluated Baseline and OLLA on K3-like traces (6 traces, full buffer, PF):

| HARQ | Baseline Mbps | Jain | 5th-pct user |
|---|---|---|---|
| rtt 0, 1 proc (legacy `txStep` engine) | 3.152 | 0.503 | 0.0122 |
| rtt 1, 1 proc (new process engine) | 3.458 | 0.484 | 0.0184 |
| rtt 8, 1 proc | 3.466 | 0.478 | 0.0350 |
| rtt 8, 8 proc | **4.837** | **0.420** | **0.0040** |

This revealed two core defects:
1. **PF averaging artefact:** The new engine updated `R_emas` with *ACKed* throughput at feedback time ($t + \text{RTT}$). With 8 processes, the strongest user stayed eligible and its average did not rise for 8 TTIs, causing Proportional Fair scheduling to degenerate into bursty max-rate scheduling (+40–50% goodput, Jain fairness dropping from 0.50 to 0.42, and edge users starving). In real 3GPP systems, PF schedulers update the sliding average at **scheduling/transmission time** based on assigned resources/rate.
2. **Engine discontinuity:** The legacy engine at `rtt 0, nproc 1` and the new engine at `rtt 1, nproc 1` showed an unexplained ~10% goodput difference (3.152 vs. 3.458 Mbps).

v17 diagnoses and resolves both issues, introduces `env.pf_avg = 'scheduled'`, and re-runs the realistic-HARQ campaign.

---

## 2. Stage A Engine-Gap Diagnosis and Housekeeping

### 2.1 Engine-Gap Diagnosis (`diag_engine_gap_v17.m`)

The diagnostic script was executed under the K3 full-buffer environment (Baseline policy, CRN draws, $N=10$, $T=200$, 3 traces in detail and 20 traces in an isolation experiment) comparing:
- **(a) Legacy engine:** `rtt 0, nproc 1` (`txStep_v17.m`)
- **(b) New engine:** `rtt 1, nproc 1` (`harqTransmit_v17.m`, `harqFeedback_v17.m`)

#### Per-TTI Divergence Points
1. **First TTI where credited bits differ: TTI 1.**
   - Legacy engine transmits at TTI 1 and credits delivered bits immediately at TTI 1 ($tpr = \text{TBS} \times 10^{-3}$).
   - New engine transmits at TTI 1 with `ready_t = 1 + 1 = 2`; feedback arrives and bits are credited at TTI 2 ($tp\_ack = 0$ at TTI 1).
2. **First TTI where scheduled user differs: TTI 2.**
   - In Trace 1, TTI 1 scheduled User 5 in both engines ($\text{TBS} = 28336$ bits, $\text{pot} = 28.336$ Mbps).
   - At TTI 2 scheduling:
     - **Legacy engine:** User 5's $R_{\text{emas}}$ was updated at the end of TTI 1 to $1.4168$ Mbps. At TTI 2, its PF metric $\text{pot} / \max(R_{\text{emas}}, 0.1)$ dropped from $283.36$ to $20.00$. User 7 ($\text{pot} = 17.568$, $R_{\text{emas}} = 0$, metric $175.68$) was scheduled.
     - **New engine:** In Step 1 of TTI 2, ACK feedback arrived, freeing process 1 and setting $tp\_ack(5) = 28.336$. However, in `evalPolicy_v16.m`, $R_{\text{emas}}$ update occurred in Step 4, **after** Step 3 scheduling. Thus, at scheduling time in TTI 2, User 5's $R_{\text{emas}}$ was **still 0.0000**. Its PF metric remained $28.336 / 0.1 = 283.36$. User 5 was scheduled **again**.

#### Mechanism Isolation & Measured Decomposition (20 Traces, 4,000 TTIs)

Comparing Legacy Engine (`rtt 0, 1 proc`) vs. New Engine (`rtt 1, 1 proc`) under CRN:

| Configuration | Engine | HARQ Timing | PF Averaging Mode | Drain | Goodput (Mbps) | Jain Fairness |
|---|---|---|---|---|---|---|
| 1 | Legacy | RTT 0, 1 proc | `acked` (at $t$) | Off | 3.2941 | 0.5672 |
| 2 | New | RTT 1, 1 proc | `acked` (at $t_{\text{fb}}$) | Off | 3.6470 | 0.5444 |
| **Gap (2 vs 1)** | | | | | **+10.71%** | **−0.0228** |
| 3 | Legacy | RTT 0, 1 proc | `scheduled` (at $t$) | Off | 3.6293 | 0.5535 |
| 4 | New | RTT 1, 1 proc | `scheduled` (at $t$) | **On** | 3.6293 | 0.5535 |
| **Gap (4 vs 3)** | | | | | **+0.000%** | **+0.0000** |

#### Measured Decomposition (4,000 TTIs across 20 traces)
- **TTIs where PF preferred user was ineligible:** **0 (0.00%)**
- **TTIs where scheduled user differed:** **0 (0.00%)**
- **TTIs where credited bits differed:** **0 (0.00%)**
- **Total credited bits (mean per trace):** Legacy = 725,854.0 bits, New = 725,854.0 bits.

#### Classification of Cause
1. **The entire 10% gap is the PF averaging delay artefact:** When $R_{\text{emas}}$ is updated at feedback arrival ($t+1$), the 1-TTI delay prevents the scheduler from penalizing the served user at $t+1$, resulting in pseudo-max-rate bursts (+10.71% goodput, −0.0228 Jain).
2. **With `pf_avg = 'scheduled'` and end-of-trace drain, the engines are 100% bit-for-bit identical:**
   - Ineligibility plays zero role ($0/4000$ TTIs) because with 1 process and RTT 1, feedback arriving at the start of $t+1$ frees the process before $t+1$ scheduling.
   - The end-of-trace drain (TTI 201) ensures the block sent at TTI 200 receives its feedback, eliminating horizon truncation.
   - Every single scheduled user, MCS, outcome draw, and credited bit matches bit-for-bit across all 4,000 TTIs.
3. **Stage B Action:**
   Proceed with Stage B with `pf_avg = 'scheduled'` and `drain = true` enabled across all v17 cases.

---

### 2.2 Housekeeping (A2)

1. **`Optimized/v16/README_v16.md`:**
   - Prominent superseded banner added at top and in §6: K1, K3, L1, L3 noted as run under the PF averaging artefact and superseded by v17.
   - §6.5 rewritten to resolve internal contradictions, detail per-comparator swings, and note the averaging artefact caveat.
   - §6.8 updated to confirm that `release/` was produced.
   - Deep PPO fallback explicitly noted as offset mode only, untuned, exploratory wherever PPO results appear.
2. **`Optimized/v15/README_v15.md`:**
   - Prominent superseded banner added to §6 for cases Z1–Z3.
3. **`Optimized/case_registry.csv` and `Optimized/v16/release/case_registry.csv`:**
   - Added `status` column to header.
   - Set status to `superseded: PF averaging artefact (v17)` for all v15 RTT > 0 rows (Z1, Z2, Z3) and v16 K1, K3, L1, L3 rows.
   - Set status to `valid` for all RTT 0 rows (v16 K2, K4; v14; etc.).
   - Verified that no rows were deleted (78 data rows preserved).


---

## 3. Stage C Pre-Registration

### 3.1 Frozen Configuration (C1)
- **Shared Scheduler Definition:** Every cell (both RTT 0 and RTT 8) enforces transmission-time proportional fair rate averaging: `env.pf_avg = 'scheduled'`.
- **HARQ Framework:**
  - **RTT8 Cases (`M1`, `M3`):** `harq_rtt = 8`, `harq_nproc = 8`, utilizing the multi-process HARQ engine with end-of-trace drain (`drain = true`).
  - **RTT0 Cases (`M2`, `M4`):** `harq_rtt = 0`, `harq_nproc = 1`, utilizing the legacy instantaneous engine (`drain = true` for consistent drain handling). Consistency with RTT 1 is verified to 0.000% gap by Test B2.3.
- **Useful Bits Capping:** All v17 cases enable `env.useful_bits = true` under deadline traffic (credit `min(TBS, remaining packet bits)`).
- **Parallel Training:** Multi-seed training is executed over 4 parallel workers (`parfor`) with enforced `twister` RNG seeds, verified bit-identical to serial ($0.00\times 10^0$).
- **Comparators (9 total):**
  1. *Baseline* (no offset, raw CQI)
  2. *OLLA* (standard single loop, step 0.1/0.9, target 0.10)
  3. *OLLA (tuned target)* (offline calibrated target per cell)
  4. *Multi-OLLA* (dual-timescale fast/slow outer loops)
  5. *Fixed* (best global static offset)
  6. *FixedPU (Oracle)* ($2 \times 3$ speed/delay class table)
  7. *Context table* (contextual bandit on slack/speed/delay)
  8. *Bandit (global)* (online multi-armed bandit on global offset)
  9. *Bandit (delay class)* (online bandit per delay tier)
- **Pre-Registered Secondary RL Scheme:** In addition to the primary A2C-resid (3000 ep, 10 seeds) in M1 and M2, a secondary A2C-resid at 800 episodes (10 seeds, seed block `+300`) is pre-registered to benchmark sample-efficiency against 800-episode runs.
- **Dropped Exploratory Schemes:** Deep PPO is removed from the core benchmark in v17 (v16 confirmed it was offset-only, untuned, and exploratory).

### 3.2 Pre-Registered Cases (C2)
Fresh, disjoint evaluation and training seeds from all previous versions (v9–v16):

| Tag | Traffic | Primary Metric | HARQ | RL Schemes (Episodes, Seeds) | Eval Traces | CRN Seed Base | Base Seed | Training Seed Blocks |
|---|---|---|---|---|---|---|---|---|
| `M1_dl_rtt8` | deadline (12 kb / 20 ms) | On-Time (%) | RTT8 | **A2C-resid (3000 ep, 10 seeds) = primary**<br>A2C-resid (800 ep, 10 seeds)<br>A2C-offset (800 ep, 10 seeds) | 500: 500001–500500 | 510001+ | 20042 | resid-3000: `+201..210`<br>resid-800: `+301..310`<br>offset-800: `+501..510` |
| `M2_dl_rtt0` | deadline (12 kb / 20 ms) | On-Time (%) | RTT0 | **A2C-resid (3000 ep, 10 seeds) = primary**<br>A2C-resid (800 ep, 10 seeds) | 500: 520001–520500 | 530001+ | 21042 | resid-3000: `+201..210`<br>resid-800: `+301..310` |
| `M3_gp_rtt8` | goodput (full buffer) | Goodput (Mbps) | RTT8 | **A2C-resid (800 ep, 10 seeds) = primary**<br>A2C-offset (800 ep, 5 seeds) | 500: 540001–540500 | 550001+ | 22042 | resid-800: `+201..210`<br>offset-800: `+501..505` |
| `M4_gp_rtt0` | goodput (full buffer) | Goodput (Mbps) | RTT0 | **A2C-resid (800 ep, 10 seeds) = primary** | 500: 560001–560500 | 570001+ | 23042 | resid-800: `+201..210` |

### 3.3 Decision Rules & Fairness Guard (C3)
- **"Beats X":** Defined as two-sided Wilcoxon signed-rank test with Holm-Bonferroni correction over all 9 comparators achieving $p < 0.05$ **and** the 90% confidence interval lower bound $> 0$.
- **Claim A:** Beats OLLA, tuned OLLA, and Multi-OLLA.
- **Claim B:** Beats Fixed, FixedPU, and Context table.
- **Full WIN:** Beats all 9 comparators simultaneously.
- **Fairness Guard:** If the primary scheme achieves a WIN but its Jain fairness index is $> 0.02$ lower than the best calibrated rule, or its 5th-percentile cell-edge metric (`edge5`) is $> 10\%$ lower, the win must be reported alongside this fairness cost.

### 3.4 Pre-Registered Hypotheses & Wording Commitments (C4–C5)
- **M1 / M2 (Deadline):** Primary scheme (A2C-resid 3000 ep) is predicted to achieve a full WIN based on v16 training-limited findings.
- **M3 / M4 (Goodput):** Predicted to confirm that RL does not beat calibrated rules on full-buffer goodput traffic (A2C $\approx$ base rule).
- **Ablation Symmetry:** Baseline goodput under RTT 8 will match RTT 0 within $[0.85, 1.10]$ and Jain within $\pm 0.03$, eliminating the spurious $+10\%$ gap from v16.

---

## 4. Code Architecture & Implementation Details

1. **Scheduled Rate PF Averaging (`env.pf_avg = 'scheduled'`):**
   - At scheduling time TTI $t$, right before transmission physics, for user $u = \arg\max \text{metric}$:
     - If retransmitting: $r_{\text{tx}} = \text{TBS}_{\text{retx}} \times 10^{-3}$ Mbps.
     - If new transmission: $r_{\text{tx}} = \text{TBS}(\text{MCS}_{\text{tx}}, \text{RB}) \times 10^{-3}$ Mbps.
   - For all users $i \in \{1,\dots,N\}$:
     $$R_{\text{emas}}(i) \leftarrow (1 - \alpha) R_{\text{emas}}(i) + \alpha r_{\text{tx}}(i)$$
     where $r_{\text{tx}}(i) = 0$ for unscheduled users.
   - Applied symmetrically across both engines and throughout all loops (`evalPolicy`, `DeepA2C_Shared`, `Bandit`, `calibrate*`).
2. **End-of-Trace Feedback Drain (`env.drain = true`):**
   - After the nominal evaluation horizon $T = 200$, the simulation continues for $\text{harq\_rtt}$ additional TTIs without scheduling new transmissions.
   - Pending in-flight packets receive their ACK/NACK feedback, and credited bits are mapped back to their original transmission TTI ($t_{\text{tx}} = t - \text{rtt}$), eliminating boundary truncation.
3. **Scheduler Ranking on Reference (`sched_on_ref = true`):**
   - In both engines, potential scheduling rate `pot` is ranked on the unshifted OLLA reference CQI (`ref`), ensuring link adaptation offsets do not manipulate user prioritization.
4. **Useful Bits Capping (`env.useful_bits = true`):**
   - Under deadline traffic with finite packets, transmitting an MCS whose transport block size exceeds remaining packet bits results in MAC-layer zero-padding.
   - The new engine always credited only `min(TBS, remaining_packet_bits)`.
   - In v17, the legacy engine also enforces `min(TBS, remaining_packet_bits)` when `env.useful_bits = true`, ensuring delivered goodput matches identically between legacy RTT 0 and new RTT 1 engines.
   - Defaults to `false` in `defaultEnv_v17.m` to maintain v16 bit-level equivalence, and is enabled (`true`) across all v17 cases (`v17_setup.m`).
5. **Standardized Jain Fairness Index (`M.jain`):**
   - Standardized definition: per-trace Jain index computed over the per-user mean primary metric in the evaluation window ($b_0+1:T$), then averaged across all traces (`M.jain = mean(jain_per_trace)`).
   - Applied symmetrically across `runComparison_v17.m`, `test_engine_consistency_v17.m`, and `test_fairness_sanity_v17.m`.
6. **Parallel Seed Training (`parfor` 4 Workers):**
   - Multi-seed training is executed across 4 local workers using `parfor`.
   - All worker training routines (`DeepA2C_Shared_v17.m`, `Bandit_v17.m`, `DeepPPO_Shared_v17.m`, `DeepGRU_Shared_v17.m`) explicitly re-initialize `rng(seed, 'twister')` to eliminate worker stream divergence (MATLAB parallel pool defaults to `CombRecursive`).
   - Verified bit-identical to client serial execution to machine precision ($0.00\times 10^0$).

---

## 5. Verification & Preflight Results (Stage B)

### 5.1 Test B2.1: Equivalence with v16 under Defaults (`test_equivalence_v17.m`)
With `pf_avg = 'acked'` and `drain = false`, v17 reproduced v16 bit-for-bit:
- **Calibrated env fields:** Bit-exact match across all fixed-class and context tables ($\Delta = 0$).
- **Classical evaluation (3 traces, 5 comparators):** 15/15 evaluations PASS with $\Delta = 0.000\text{e}+00$ across goodput, BLER, CQI error, actions, and info.
- **RTT-8 Deadline evaluation (1 trace):** Bit-exact match ($\Delta = 0.000\text{e}+00$).
- **RTT-8 Full-Buffer evaluation (1 trace):** Bit-exact match ($\Delta = 0.000\text{e}+00$).
- **DeepA2C_Shared Training (5 episodes, seed 4242):** Identical learning and entropy curves ($\Delta = 0.000\text{e}+00$).

### 5.2 Test B2.2: PF Update Unit Test (`test_pf_update_v17.m`)
On a 3-user trace with forced transmissions under `pf_avg = 'scheduled'`:
- $R_{\text{emas}}$ updated at transmission TTI $t$ by exactly $\text{TBS} \times 10^{-3}$.
- $R_{\text{emas}}$ decayed purely by $(1 - \alpha)$ at feedback arrival TTI ($t + \text{rtt}$), with zero influence from ACKed bits ($\Delta = 0.000\text{e}+00$).
- Outcome-invariance verified: ACK and NACK outcomes yielded identical $R_{\text{emas}}$ tracking.
- Legacy engine verified: NACKed transmission updated $R_{\text{emas}}$ with scheduled TBS despite zero delivered goodput ($\Delta = 0.000\text{e}+00$).

### 5.3 Test B2.3: Engine Consistency Test (`test_engine_consistency_v17.m`)
Evaluated 20 traces (4,000 TTIs) comparing Legacy Engine (`rtt 0, 1 proc`) vs. New Engine (`rtt 1, 1 proc`) under `pf_avg = 'scheduled'`, `drain = true`, and `useful_bits = true`:

| Environment | Comparator | Legacy Engine (RTT 0) | New Engine (RTT 1) | Primary Metric Gap | Jain Difference | Useful Goodput Gap | Status |
|---|---|---|---|---|---|---|---|
| **K3 (Goodput)** | Baseline | 3.9438 Mbps | 3.9438 Mbps | **+0.000%** | **+0.0000** (0.4608 vs 0.4608) | +0.000% | **PASS** |
| | OLLA | 4.2689 Mbps | 4.2689 Mbps | **+0.000%** | **+0.0000** (0.4431 vs 0.4431) | +0.000% | **PASS** |
| | Fixed | 4.3533 Mbps | 4.3533 Mbps | **+0.000%** | **+0.0000** (0.4546 vs 0.4546) | +0.000% | **PASS** |
| **K1 (Deadline)** | Baseline | 82.86% on-time | 82.86% on-time | **+0.000%** | **+0.0000** (0.9235 vs 0.9235) | **+0.000%** (5.2748 vs 5.2748 Mbps) | **PASS** |
| | OLLA | 84.53% on-time | 84.53% on-time | **+0.000%** | **+0.0000** (0.9257 vs 0.9257) | **+0.000%** (5.4404 vs 5.4404 Mbps) | **PASS** |
| | Fixed | 87.71% on-time | 87.71% on-time | **+0.000%** | **+0.0000** (0.9382 vs 0.9382) | **+0.000%** (5.5820 vs 5.5820 Mbps) | **PASS** |

*Note:* With `useful_bits = true`, both engines achieve bit-for-bit identical useful goodput and primary metrics across 100% of TTIs.

### 5.4 Test B2.4: Fairness Sanity Test (`test_fairness_sanity_v17.m`)
Evaluated 20 K3 traces comparing Baseline RTT 8 (8 procs) vs. Baseline RTT 0 (1 proc) under `pf_avg = 'scheduled'` and `drain = true`:
- Baseline RTT 0 Goodput: **3.9438 Mbps**, Jain Fairness: **0.4608**
- Baseline RTT 8 Goodput: **3.9479 Mbps**, Jain Fairness: **0.4553**
- **Goodput Ratio (RTT 8 / RTT 0):** **1.0010** (Required: $[0.85, 1.10]$) $\rightarrow$ **PASS**
- **Jain Difference (RTT 8 − RTT 0):** **−0.0056** (Required: $\pm 0.03$) $\rightarrow$ **PASS**

### 5.5 Test B2.5: Fairness Reporting Integration
- `analyze_v17_replication.m` updated: `REPLCMP|` lines expose `jain_rl`, `jain_cmp`, `edge_rl`, and `edge_cmp`.
- `build_v17_tables.m` updated: `table_core.csv` parses and exports fairness columns for all schemes and comparators.
- `fill_stats_v17.m` verified: `SCHEME|` lines log per-scheme Jain and 5th-percentile edge metrics.

### 5.6 Test B2.6: Preflight Verification & Timing Extrapolation (`fill_v17_preflight.m`)
Completed 2 episodes, 2 seeds, 6 traces across all 4 pre-registered cases with 4-worker parallelization:

| Case | Tag | Traffic | HARQ | Preflight Time | Full Scale Units | Extrapolated Time (4 Workers) |
|---|---|---|---|---|---|---|
| M1 | `M1_dl_rtt8` | deadline | RTT8 (8 procs) | 68.2 s | 3000 ep / 10 seeds (resid) + 800 ep / 10 seeds (resid-800) + 800 ep / 10 seeds (offset) | ~3.1 hrs (~186 min) |
| M2 | `M2_dl_rtt0` | deadline | RTT0 (1 proc) | 24.9 s | 3000 ep / 10 seeds (resid) + 800 ep / 10 seeds (resid-800) | ~1.4 hrs (~86 min) |
| M3 | `M3_gp_rtt8` | goodput | RTT8 (8 procs) | 26.9 s | 800 ep / 10 seeds (resid) + 800 ep / 5 seeds (offset) | ~0.9 hrs (~56 min) |
| M4 | `M4_gp_rtt0` | goodput | RTT0 (1 proc) | 13.4 s | 800 ep / 10 seeds (resid) | ~0.4 hrs (~26 min) |

*Total campaign estimate:* **~5.9 wall-clock hours** (~354 min) across all 4 cases running 4 workers. Checkpoints are saved per-seed and every 250 episodes.

### 5.7 Test B2.7: `parfor` Bit-Identity Test (`test_parfor_seeds.m`)
Evaluated training 2 seeds under parallel workers vs. serial client execution with `rng(seed, 'twister')`:
- Max difference in actor/critic weights: **0.00e+00**
- Max difference in training cell throughputs: **0.00e+00**
- Max difference in policy entropies: **0.00e+00**
- Status: **PASS (Bit-identical)**

---

## 6. Full Campaign Results & Discussion (Stages E & F)

### 6.1 Campaign Execution & Operational Summary

The v17 campaign executed the 4 pre-registered cases sequentially (`M3_gp_rtt8` → `M4_gp_rtt0` → `M2_dl_rtt0` → `M1_dl_rtt8`) on MATLAB R2023a with full CRN discipline over 500 evaluation traces each.

- **Real Wall Time:** **3 Nov 18:10 → 4 Nov 10:41** (16 hours 31 minutes wall time across 5 launches; active compute time ~6.3 hours).
  - `M3_gp_rtt8`: 70.0 min active compute
  - `M4_gp_rtt0`: 56.1 min active compute
  - `M2_dl_rtt0`: 66.3 min active compute
  - `M1_dl_rtt8`: 160.8 min cumulative compute (including initial interrupted run)
- **Operational Deviation & Memory Fault Recovery:**
  - Initial execution launched with 4 parallel workers (`parfor`). At 23:44 on 3 Nov, during `M1_dl_rtt8`, total host virtual memory commit exceeded the available physical RAM (16 GB host), triggering a memory commit crash in `ucrtbase.dll`.
  - **Deviation logged:** At 23:44, the worker pool was reduced from 4 to 2 workers (`n_workers = 2`) to stabilize memory below 4 GB. The pre-flight `parfor` bit-identity test ([`test_parfor_seeds.m`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v17/test_parfor_seeds.m)) formally verified that seed trajectories and numerical metrics are bit-identical to machine precision ($0.00 \times 10^0$ delta) between serial execution, 2 workers, and 4 workers, ensuring this operational reduction had zero impact on results.
  - Heartbeat logger `logs/heartbeat_v17.txt` verified active progress every 25 episodes throughout the entire run.
  - All per-seed checkpoints were saved to `Dataset/ckpt/` and the master campaign log was written to `Dataset/fill_summary_v17.txt`.

---

### 6.2 Pre-Registered Case Results

#### Case M1: Realistic HARQ Deadline Traffic (`M1_dl_rtt8`)
- **Environment:** Deadline traffic (12 kb / 20 ms, $D=10$ TTIs), RTT = 8, 8 HARQ processes, `pf_avg = 'scheduled'`, `drain = true`, `useful_bits = true`, $N=10$, 500 evaluation traces.
- **Primary Scheme:** Deep A2C v17 (residual mode, 3,000 episodes, 10 seeds).
- **Outcome:** **FULL WIN (Claim A = 1, Claim B = 1, WIN_ALL = 1)**.

| Scheme / Comparator | On-Time (%) | 95% CI | Margin vs. Best Rule (%) | 90% CI Margin (%) | Wilcoxon $p$ | Holm $p$ | Jain Index | 5th-pct User |
|---|---|---|---|---|---|---|---|---|
| **Deep A2C v17 (ensemble)** | **63.06%** | ±1.22% | **+4.56%** | [+4.12, +5.01] | $1.62 \times 10^{-43}$ | $1.62 \times 10^{-43}$ | **0.7807** | **0.2164** |
| Deep A2C v17 (best-on-val) | 61.95% | ±1.19% | +2.72% | — | — | — | 0.7783 | 0.2143 |
| **Deep A2C v17 (primary, 3000 ep)** | **61.26%** | ±1.19% | **+1.58%** | [+1.23, +1.94] | $9.06 \times 10^{-13}$ | $9.06 \times 10^{-13}$ | **0.7715** | **0.2148** |
| Deep A2C v17 (resid-800 ep) | 60.51% | ±1.18% | +0.34% | [+0.05, +0.62] | 0.0244 | 0.0244 | 0.7735 | 0.2096 |
| *Context table (best rule)* | 60.31% | ±1.20% | — (baseline) | — | — | — | 0.7740 | 0.2122 |
| *Fixed (global offset −2)* | 60.14% | ±1.21% | −0.28% | — | — | — | 0.7720 | 0.2110 |
| *Deep A2C v17 (offset-800 ep)* | 59.76% | ±1.18% | −0.91% | [−1.19, −0.63] | $2.86 \times 10^{-7}$ | $8.58 \times 10^{-7}$ | 0.7708 | 0.2050 |
| *FixedPU (Oracle class table)* | 59.65% | ±1.23% | −1.09% | — | — | — | 0.7632 | 0.2109 |
| *OLLA (standard step 0.1/0.9)* | 54.72% | ±1.04% | −9.27% | — | — | — | 0.7802 | 0.1654 |
| *OLLA (tuned target 0.10)* | 54.72% | ±1.04% | −9.27% | — | — | — | 0.7802 | 0.1654 |
| *Multi-OLLA (dual-loop)* | 54.62% | ±1.04% | −9.43% | — | — | — | 0.7792 | 0.1658 |
| *Baseline (raw CQI)* | 52.53% | ±1.06% | −12.90% | — | — | — | 0.7641 | 0.1404 |
| *Bandit (global / delay class)* | 41.80% | ±1.03% | −30.68% | — | — | — | 0.6818 | 0.0765 |

- **Seed Consistency:** **9 out of 10 seeds** individually exceeded the best calibrated rule (range: [59.83%, 62.97%]).
- **Primary vs. Comparators:** Beats Baseline by +16.62% ($p = 4.04 \times 10^{-77}$), OLLA by +11.96% ($p = 2.50 \times 10^{-67}$), Fixed by +1.87% ($p = 6.74 \times 10^{-17}$), FixedPU by +2.70% ($p = 4.28 \times 10^{-32}$), and Context table by +1.58% ($p = 9.06 \times 10^{-13}$).

---

#### Case M2: Instantaneous HARQ Deadline Traffic (`M2_dl_rtt0`)
- **Role under Project Multiplicity (PLAN_v17 §C6):** **Confirmatory Replication (not a standalone new claim)**.
  - Across the project's 67 registered experimental cases / 108 scheme evaluations (tracked in `case_registry.csv`), M2 is pre-registered strictly as a replication of the established zero-delay gain already demonstrated in v13 X2 (secondary), v14 Y0, v16 K2, and v17 M2, plus v10 E4c (noted as partly overlapping its exploratory traces).
  - Its objective is to verify that the zero-delay gain replicates reliably under the corrected transmission-time Proportional Fair rate averaging (`env.pf_avg = 'scheduled'`), end-of-trace drain (`env.drain = true`), and packet-capped useful bit accounting (`env.useful_bits = true`). It is not counted as an independent hypothesis test to avoid multiplicity inflation.
- **Environment:** Deadline traffic (12 kb / 20 ms), RTT = 0, 1 HARQ process, `pf_avg = 'scheduled'`, `drain = true`, `useful_bits = true`, $N=10$, 500 evaluation traces.
- **Primary Scheme:** Deep A2C v17 (residual mode, 3,000 episodes, 10 seeds).
- **Outcome:** **REPLICATION CONFIRMED (Claim A = 1, Claim B = 1, WIN_ALL = 1)**.

| Scheme / Comparator | On-Time (%) | 95% CI | Margin vs. Best Rule (%) | 90% CI Margin (%) | Wilcoxon $p$ | Holm $p$ | Jain Index | 5th-pct User |
|---|---|---|---|---|---|---|---|---|
| **Deep A2C v17 (ensemble)** | **86.35%** | ±1.04% | **+0.63%** | [+0.36, +0.90] | $5.07 \times 10^{-5}$ | $5.07 \times 10^{-5}$ | **0.9318** | **0.4143** |
| Deep A2C v17 (best-on-val) | 86.26% | ±1.02% | +0.52% | — | — | — | 0.9329 | 0.4139 |
| **Deep A2C v17 (primary, 3000 ep)** | **86.17%** | ±1.02% | **+0.43%** | [+0.21, +0.64] | 0.0167 | 0.0167 | **0.9323** | **0.4136** |
| *Context table (best rule)* | 85.81% | ±1.04% | — (baseline) | — | — | — | 0.9299 | 0.4145 |
| *Fixed (global offset −2)* | 85.38% | ±1.07% | −0.50% | — | — | — | 0.9262 | 0.4158 |
| *Deep A2C v17 (resid-800 ep)* | 85.32% | ±1.03% | −0.57% | [−0.78, −0.36] | $1.57 \times 10^{-6}$ | $4.71 \times 10^{-6}$ | 0.9292 | 0.4079 |
| *FixedPU (Oracle class table)* | 85.32% | ±1.04% | −0.57% | — | — | — | 0.9288 | 0.4084 |
| *Multi-OLLA (dual-loop)* | 84.24% | ±1.03% | −1.83% | — | — | — | 0.9297 | 0.3928 |
| *OLLA (standard / tuned)* | 84.07% | ±1.03% | −2.03% | — | — | — | 0.9298 | 0.3889 |
| *Baseline (raw CQI)* | 82.28% | ±1.06% | −4.11% | — | — | — | 0.9235 | 0.3605 |
| *Bandit (global / delay class)* | 76.55% | ±1.12% | −10.79% | — | — | — | 0.9081 | 0.3053 |

- **Seed Consistency:** **8 out of 10 seeds** individually exceeded the best calibrated rule.
- **Replication Status:** Confirmed. The gain over all comparators replicated for the fourth time (+0.93% vs Fixed, $p = 5.58 \times 10^{-11}$; +0.43% vs Context table, $p = 0.0167$; ensemble +0.63%, $p = 5.07 \times 10^{-5}$) under the corrected PF scheduler.

---

#### Case M3: Realistic HARQ Full-Buffer Goodput (`M3_gp_rtt8`)
- **Environment:** Full-buffer traffic, primary metric = goodput (Mbps), RTT = 8, 8 HARQ processes, `pf_avg = 'scheduled'`, `drain = true`, $N=10$, 500 evaluation traces.
- **Primary Scheme:** Deep A2C v17 (residual mode, 800 episodes, 10 seeds).
- **Outcome:** **A2C $\approx$ BASE RULE (Claim A = 0, Claim B = 0, WIN_ALL = 0)** — **Pre-registered hypothesis confirmed**.

| Scheme / Comparator | Goodput (Mbps) | 95% CI | Margin vs. Fixed (%) | 90% CI Margin (%) | Wilcoxon $p$ | Holm $p$ | Jain Index | 5th-pct User |
|---|---|---|---|---|---|---|---|---|
| *Fixed (global offset −1)* | **3.4989** | ±0.1340 | — (baseline) | — | — | — | 0.5056 | 0.0319 |
| *Context table* | 3.4989 | ±0.1340 | 0.00% | — | — | — | 0.5056 | 0.0319 |
| **Deep A2C v17 (ensemble)** | 3.4679 | ±0.1351 | **−0.88%** | [−1.44, −0.33] | 0.00173 | 0.00723 | 0.5116 | 0.0325 |
| **Deep A2C v17 (primary, 800 ep)** | **3.4679** | ±0.1351 | **−0.88%** | [−1.44, −0.33] | 0.00173 | 0.00723 | **0.5116** | **0.0325** |
| *FixedPU (Oracle class table)* | 3.4679 | ±0.1351 | −0.88% | [0.00, 0.00] | 1.000 | 1.000 | 0.5116 | 0.0325 |
| *Multi-OLLA* | 3.4611 | ±0.1369 | −1.08% | — | — | — | 0.5138 | 0.0314 |
| *OLLA (standard step 0.1/0.9)* | 3.4228 | ±0.1358 | −2.17% | — | — | — | 0.5167 | 0.0314 |
| *Bandit (global)* | 3.4228 | ±0.1358 | −2.17% | — | — | — | 0.5167 | 0.0314 |
| *Deep A2C v17 (offset-800 ep)* | 3.4114 | ±0.1353 | −2.50% | [−3.07, −1.92] | $1.23 \times 10^{-12}$ | $9.86 \times 10^{-12}$ | 0.5126 | 0.0292 |
| *Bandit (delay class)* | 3.4099 | ±0.1354 | −2.54% | — | — | — | 0.5162 | 0.0312 |
| *OLLA (tuned target 0.20)* | 3.3952 | ±0.1345 | −2.96% | — | — | — | 0.5138 | 0.0304 |
| *Baseline (raw CQI)* | 3.1870 | ±0.1289 | −8.91% | — | — | — | 0.5173 | 0.0291 |

- **Interpretation:** Residual A2C learns action 0 for 92.3% of TTIs, degenerating cleanly to its underlying base rule (`FixedPU`, goodput 3.4679 Mbps, difference $\Delta = 0.0000$ Mbps). It beats uncalibrated Baseline by +8.81% ($p = 4.18 \times 10^{-45}$) and OLLA by +1.32% ($p = 0.00121$), but cannot surpass static global calibration (−0.88% vs Fixed).

---

#### Case M4: Instantaneous HARQ Full-Buffer Goodput (`M4_gp_rtt0`)
- **Environment:** Full-buffer traffic, primary metric = goodput (Mbps), RTT = 0, 1 HARQ process, `pf_avg = 'scheduled'`, `drain = true`, $N=10$, 500 evaluation traces.
- **Primary Scheme:** Deep A2C v17 (residual mode, 800 episodes, 10 seeds).
- **Outcome:** **A2C $\approx$ BASE RULE (Claim A = 0, Claim B = 0, WIN_ALL = 0)** — **Pre-registered hypothesis confirmed**.

| Scheme / Comparator | Goodput (Mbps) | 95% CI | Margin vs. Fixed (%) | 90% CI Margin (%) | Wilcoxon $p$ | Holm $p$ | Jain Index | 5th-pct User |
|---|---|---|---|---|---|---|---|---|
| *Fixed (global offset −1)* | **3.4985** | ±0.1367 | — (baseline) | — | — | — | 0.5072 | 0.0274 |
| *Context table* | 3.4985 | ±0.1367 | 0.00% | — | — | — | 0.5072 | 0.0274 |
| **Deep A2C v17 (ensemble)** | 3.4746 | ±0.1362 | **−0.68%** | [−1.25, −0.12] | 0.0344 | 0.172 | 0.5068 | 0.0275 |
| *FixedPU (Oracle class table)* | 3.4740 | ±0.1362 | −0.70% | — | — | — | 0.5069 | 0.0275 |
| *OLLA (tuned target 0.03)* | 3.4690 | ±0.1387 | −0.84% | — | — | — | 0.5092 | 0.0274 |
| *Multi-OLLA* | 3.4646 | ±0.1376 | −0.97% | — | — | — | 0.5073 | 0.0286 |
| Deep A2C v17 (best-on-val) | 3.4415 | ±0.1347 | −1.63% | — | — | — | 0.5085 | 0.0275 |
| **Deep A2C v17 (primary, 800 ep)** | **3.4378** | ±0.1351 | **−1.73%** | [−2.23, −1.24] | $2.46 \times 10^{-9}$ | $1.72 \times 10^{-8}$ | **0.5080** | **0.0275** |
| *OLLA (standard step 0.1/0.9)* | 3.4326 | ±0.1368 | −1.88% | — | — | — | 0.5101 | 0.0271 |
| *Bandit (global)* | 3.4326 | ±0.1368 | −1.88% | — | — | — | 0.5101 | 0.0271 |
| *Bandit (delay class)* | 3.4205 | ±0.1364 | −2.23% | — | — | — | 0.5101 | 0.0269 |
| *Baseline (raw CQI)* | 3.2109 | ±0.1283 | −8.22% | — | — | — | 0.5128 | 0.0261 |

- **Interpretation:** As in M3, residual A2C collapses primarily to action 0 (76.3% of TTIs) and fails to beat fixed calibration (−1.73% vs Fixed). It beats Baseline by +7.07% ($p = 1.62 \times 10^{-39}$).

---

### 6.3 Pre-Registered Hypothesis Check (C4)

The table below reproduces the pre-registered predictions from PLAN_v17 §C4 verbatim alongside the observed campaign outcomes:

| Case | Pre-Registered Prediction (PLAN_v17 §C4 verbatim) | Source | Actual v17 Result | Verdict |
|---|---|---|---|---|
| **M1** | primary WIN; offset-800 WIN; resid-800 Claim B fail | v16 L1, K1 | Primary A2C (3000 ep) achieves full WIN (+1.58% vs Context table, $p = 9.06 \times 10^{-13}$); offset-800 fails Claim B (−0.91%, $p = 8.58 \times 10^{-7}$); resid-800 achieves narrow WIN (+0.34%, $p = 0.0244$) | **Primary prediction MET; Secondary predictions NOT MET** |
| **M2** | primary WIN | v16 K2, v14 Y0, v13 X2 | Primary A2C (3000 ep) replicates zero-delay baseline gain (+0.43% vs Context table, $p = 0.0167$; ensemble +0.63%, $p = 5.07 \times 10^{-5}$) | **MET (Replication)** |
| **M3, M4** | no Claim B; A2C ≈ base rule | v16 K3, K4 and earlier | In M3: no Claim B (−0.88% vs Fixed), A2C = base rule within 0.0000 Mbps.<br>In M4: no Claim B (−1.73% vs Fixed), A2C ≈ base rule within 0.0362 Mbps. | **MET** |
| **all** | with `pf_avg = 'scheduled'`, the RTT-8 absolute levels fall back near RTT-0 levels (B2.4) | v17 B2.4 | Goodput ratio RTT8 / RTT0 is 0.9926 for Baseline, 1.0001 for Fixed; Jain diff is +0.0045 for Baseline, −0.0016 for Fixed (all margin swings $< 1.0$ pp). | **MET** |

**Summary of Prediction Check:**
- The **primary predictions** for all four cases (M1, M2, M3, M4) were completely **met**. Under realistic HARQ (M1), primary 3000-episode residual A2C achieved a statistically significant WIN over every comparator (+1.58% over the best calibrated rule, Holm $p = 9.06 \times 10^{-13}$). In M2, the zero-delay baseline gain was successfully replicated (+0.43%, Holm $p = 0.0167$). In M3 and M4, RL link adaptation confirmed the null result against calibrated static baselines.
- The **secondary predictions** for M1 were **not met**:
  1. *offset-800 WIN*: Predicted to achieve WIN, but actually **failed Claim B** (achieved 59.76% vs Context table 60.31%, margin −0.91%, Holm $p = 8.58 \times 10^{-7}$).
  2. *resid-800 Claim B fail*: Predicted to fail Claim B, but actually achieved a narrow **WIN** across all 9 comparators (achieved 60.51% vs Context table 60.31%, margin +0.34%, Holm $p = 0.0244$).

---

### 6.4 Fairness Guard Verification (C3)

The pre-registered fairness guard specifies that any claimed WIN must not come at a hidden fairness cost (Jain degradation $> 0.02$ or 5th-percentile edge degradation $> 10\%$ vs. the best calibrated rule).

| Case | Winning Scheme | Comparison Target | Jain RL | Jain Rule | Jain Difference (Guard: $> -0.02$) | Edge5 RL | Edge5 Rule | Edge5 Change (Guard: $> -10\%$) | Guard Status |
|---|---|---|---|---|---|---|---|---|---|
| **M1** | Deep A2C (primary) | Context table | 0.7715 | 0.7740 | −0.0025 | 0.2148 | 0.2122 | **+1.23%** | **CLEAR** |
| **M1** | Deep A2C (primary) | Fixed | 0.7715 | 0.7720 | −0.0005 | 0.2148 | 0.2110 | **+1.80%** | **CLEAR** |
| **M1** | Deep A2C (ensemble) | Context table | 0.7807 | 0.7740 | **+0.0067** | 0.2164 | 0.2122 | **+1.98%** | **CLEAR** |
| **M2** | Deep A2C (primary) | Context table | 0.9323 | 0.9299 | **+0.0024** | 0.4136 | 0.4145 | −0.22% | **CLEAR** |
| **M2** | Deep A2C (primary) | Fixed | 0.9323 | 0.9262 | **+0.0061** | 0.4136 | 0.4158 | −0.53% | **CLEAR** |
| **M2** | Deep A2C (ensemble) | Context table | 0.9318 | 0.9299 | **+0.0019** | 0.4143 | 0.4145 | −0.05% | **CLEAR** |

In all winning cases, the fairness guard is completely satisfied:
- In M1, Deep A2C improves cell-edge user delivery by +1.80% with negligible Jain change (−0.0005). Ensemble strictly improves both Jain (+0.0067) and cell-edge (+1.98%).
- In M2, Deep A2C improves Jain fairness (+0.0061) with virtually unchanged cell-edge performance (−0.53%).

---

### 6.5 Training-Length Analysis: 800 vs. 3,000 Episodes (`table_training_length.csv`)

In both deadline traffic regimes, residual A2C is demonstrated to be **training-limited** at 800 episodes:

| Case | Traffic | HARQ Timing | 800-Episode Margin vs Fixed [90% CI] | 3000-Episode Margin vs Fixed [90% CI] | Margin Delta | C5 Verdict |
|---|---|---|---|---|---|---|
| **M1** | Deadline | RTT 8 (8 processes) | +0.62% [+0.34, +0.91] | **+1.87%** [+1.52, +2.23] | **+1.25 pp** | **training-limited** |
| **M2** | Deadline | RTT 0 (1 process) | −0.07% [−0.27, +0.12] | **+0.93%** [+0.72, +1.13] | **+1.00 pp** | **training-limited** |

- At 800 episodes in M2, A2C fails Claim B (−0.07% vs Fixed, $p = 0.407$). At 3,000 episodes, it decisively beats Fixed (+0.93%, $p = 5.58 \times 10^{-11}$) with non-overlapping 90% confidence intervals.
- In M1, tripling the training duration triples the margin over Fixed (+0.62% → +1.87%), demonstrating that learning complex state dynamics (slack, HARQ retransmission countdowns, channel trends) requires extensive experience.

---

### 6.6 HARQ Timing & RTT Ablation Analysis (`table_harq_ablation.csv`)

The post-v16 review identified an artificial +10–40% swing in comparative margins caused by the delayed PF EMA update. With `pf_avg = 'scheduled'`, the swing is completely eliminated across all comparative rules:

| Traffic | Case Pair | Comparator | RTT-8 Margin (%) | RTT-0 Margin (%) | Swing (pp) | Status vs v16 Artefact |
|---|---|---|---|---|---|---|
| **Goodput** | M3 vs M4 | Baseline | +8.81% | +7.07% | **1.74 pp** | Preserved (normal link adaptation gap) |
| **Goodput** | M3 vs M4 | Fixed | −0.88% | −1.73% | **0.85 pp** | Eliminated (v16 was +10–15 pp) |
| **Goodput** | M3 vs M4 | Context table | −0.88% | −1.73% | **0.85 pp** | Eliminated |
| **Goodput** | M3 vs M4 | Multi-OLLA | +0.20% | −0.77% | **0.97 pp** | Eliminated |
| **Goodput** | M3 vs M4 | OLLA | +1.32% | +0.15% | **1.17 pp** | Eliminated |
| **Deadline** | M1 vs M2 | Baseline | +16.62% | +4.73% | 11.89 pp | Expected: HARQ delay increases RL value |
| **Deadline** | M1 vs M2 | Fixed | +1.87% | +0.93% | **0.94 pp** | Consistent: RL adds modest extra edge under delay |
| **Deadline** | M1 vs M2 | Context table | +1.58% | +0.43% | **1.15 pp** | Consistent |

On full-buffer goodput, the margin swing between RTT 8 and RTT 0 across all calibrated rules is strictly $< 1.0$ percentage point (0.85 pp for Fixed and Context table). The anomalous +40% gap from v16 is completely gone.

---

### 6.7 Action Distributions and Behavioral Policy Analysis

Inspection of policy action frequencies across all cases reveals why residual A2C succeeds on deadline traffic but collapses on full buffer:

```
M1_dl_rtt8 (Deadline, RTT8):
  A2C (3000 ep):   action -1 (22.9%), action 0 (29.9%), action +1 (47.2%)
  A2C (ensemble):  action -1 (24.2%), action 0 (22.2%), action +1 (53.6%)
  A2C (resid-800): action -1 ( 2.6%), action 0 (51.0%), action +1 (46.5%)

M2_dl_rtt0 (Deadline, RTT0):
  A2C (3000 ep):   action -1 (52.5%), action 0 (21.6%), action +1 (25.9%)
  A2C (ensemble):  action -1 (63.8%), action 0 ( 5.9%), action +1 (30.3%)
  A2C (resid-800): action -1 (10.8%), action 0 (73.4%), action +1 (15.8%)

M3_gp_rtt8 (Goodput, RTT8):
  A2C (800 ep):    action -1 ( 4.4%), action 0 (92.3%), action +1 ( 3.4%)

M4_gp_rtt0 (Goodput, RTT0):
  A2C (800 ep):    action -1 ( 8.8%), action 0 (76.3%), action +1 (14.9%)
```

#### State-Conditional Action Analysis on Evaluation Traces (`table_action_by_state.csv`)

To determine the empirical policy behavior, action choices of the primary Deep A2C policies were logged across all 500 evaluation traces ($N=10$ seeds) restricted strictly to scheduled users' new transmissions (excluding retransmissions and unscheduled users) and conditioned on queue slack and HARQ process occupancy ([`table_action_by_state.csv`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v17/paper/table_action_by_state.csv)):

| Case | Condition Type | Condition Bin | Total Transmissions | Action −1 (%) | Action 0 (%) | Action +1 (%) |
|---|---|---|---|---|---|---|
| **`M1_dl_rtt8`** | **Slack** | $\le 2$ TTIs | 12,083 | 1.03% | 10.56% | **88.41%** |
| | | $3\text{--}5$ TTIs | 33,920 | 1.04% | 8.70% | **90.25%** |
| | | $> 5$ TTIs | 541,013 | 20.57% | 27.84% | 51.59% |
| | **Busy Procs** | 0 busy (0%) | 371,728 | 27.32% | 35.67% | 37.00% |
| | | 1–2 busy (12–25%) | 208,709 | 4.89% | 10.45% | **84.66%** |
| | | $\ge 3$ busy ($\ge 37.5\%$) | 6,579 | 0.21% | 6.55% | **93.24%** |
| **`M2_dl_rtt0`** | **Slack** | $\le 2$ TTIs | 12,027 | 13.15% | 21.83% | **65.01%** |
| | | $3\text{--}5$ TTIs | 26,493 | 14.05% | 18.82% | **67.12%** |
| | | $> 5$ TTIs | 491,517 | **42.43%** | 18.44% | 39.13% |
| | **Busy Procs** | 0 busy (instantaneous) | 530,037 | 40.35% | 18.54% | 41.11% |

#### Key Behavioral Findings from Empirical State Logging

1. **Slack-Dependent Aggression on New Transmissions in M1:** On scheduled new transmissions, when queue slack is tight ($\le 2$ TTIs) or intermediate ($3\text{--}5$ TTIs), action +1 strongly dominates (**88.41%** for $\le 2$ TTIs, **90.25%** for $3\text{--}5$ TTIs), with action −1 remaining at approximately 1% (1.03% and 1.04%). When slack is abundant ($> 5$ TTIs), action +1 drops to 51.59%, while conservative actions increase (action 0 to 27.84% and action −1 to 20.57%).
2. **HARQ Process Congestion Aggression in M1:** As parallel HARQ processes become occupied on new transmissions, the policy shifts heavily toward action +1: rising from **37.00%** with 0 busy processes to **84.66%** with 1–2 busy processes, and reaching **93.24%** when $\ge 3$ processes are busy (with action −1 dropping to 0.21%). When process exhaustion threatens scheduling eligibility, the policy pushes higher MCS to prevent queue head-of-line blockage.
3. **Behavior under Zero Delay (M2):** Under instantaneous feedback on new transmissions, action −1 is selected **42.43%** of the time when slack is abundant ($> 5$ TTIs), but shifts toward action +1 (**65.01%** for $\le 2$ TTIs, **67.12%** for $3\text{--}5$ TTIs) as deadline pressure tightens.
4. **Collapse to Base Rule on Full Buffer:** On full-buffer traffic (`M3`, `M4`), where queue state and deadlines are absent, the policy settles on action 0 (92.3% in M3, 76.3% in M4), degenerating to the calibrated base rule.

---

### 6.8 Pre-Registered Wording Commitments & Multiplicity Accounting (PLAN_v17 §C5–C6)

Under the project-wide multiplicity accounting (67 cases / 108 scheme evaluations across v9–v17 tracked in `case_registry.csv`), M1 serves as the sole novel primary claim of the paper under realistic HARQ timing, while M2 is treated strictly as a confirmatory replication of the zero-delay baseline rather than a standalone new claim.

Following the pre-registered decision rules, the paper text must state:

- **Case M1 (Primary Claim):** *"Under realistic HARQ timing (RTT 8, 8 processes) and a correctly averaged PF scheduler, residual A2C trained for 3000 episodes beat every comparator, including calibrated fixed-offset rules (+1.87% vs Fixed, +1.58% vs Context table, +4.56% ensemble), without a fairness penalty."*
- **Case M2 (Confirmatory Replication):** *"Without HARQ delay, the gain over all comparators replicated for the fourth time (+0.93% vs Fixed, +0.43% vs Context table, +0.63% ensemble), confirming that the zero-delay baseline gain is preserved and replicated under the corrected transmission-time PF scheduler."*
- **Cases M3 & M4:** *"On full-buffer goodput, no RL design outperformed calibrated rules."*
- **Training Length:** *"In M1 and M2, residual A2C proved training-limited at 800 episodes: extending training to 3000 episodes increased the margin over the best rule from +0.34% to +1.58% in M1, and from −0.57% to +0.43% in M2, with non-overlapping 90% confidence intervals."*

---

### 6.9 Publication Artifacts Generated

All publication tables and figures have been generated and validated:

1. **Tables (`Optimized/v17/paper/`):**
   - [`table_core.csv`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v17/paper/table_core.csv): 72 comparative evaluations across all 4 cases, schemes, and comparators, including margins, 90% CIs, Wilcoxon/Holm p-values, TOST equivalences, Jain indices, and cell-edge values.
   - [`table_harq_ablation.csv`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v17/paper/table_harq_ablation.csv): Margin swings between RTT 8 and RTT 0.
   - [`table_training_length.csv`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v17/paper/table_training_length.csv): Comparison of 800-episode vs 3000-episode residual A2C performance.
   - [`headroom.csv`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v17/paper/headroom.csv): Fixed, Genie, and Hindsight reference bounds evaluated across all 500 evaluation traces per case.
2. **Figures (`Optimized/v17/paper/figures/`):**
   - Bar charts with 95% CIs: [`bars_M1_dl_rtt8.png`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v17/paper/figures/bars_M1_dl_rtt8.png), [`bars_M2_dl_rtt0.png`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v17/paper/figures/bars_M2_dl_rtt0.png), [`bars_M3_gp_rtt8.png`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v17/paper/figures/bars_M3_gp_rtt8.png), [`bars_M4_gp_rtt0.png`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v17/paper/figures/bars_M4_gp_rtt0.png) (and matching PDFs).
   - RTT Margin curve: [`margin_vs_rtt.png`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v17/paper/figures/margin_vs_rtt.png) / `.pdf`.
   - Action distribution histograms: [`acthist_M1_dl_rtt8.png`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v17/paper/figures/acthist_M1_dl_rtt8.png), [`acthist_M2_dl_rtt0.png`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v17/paper/figures/acthist_M2_dl_rtt0.png), [`acthist_M3_gp_rtt8.png`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v17/paper/figures/acthist_M3_gp_rtt8.png), [`acthist_M4_gp_rtt0.png`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v17/paper/figures/acthist_M4_gp_rtt0.png) (and matching PDFs).
3. **Case Registry:**
   - [`case_registry.csv`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/case_registry.csv): Contains 90 rows total, with 12 valid v17 rows (`M1_dl_rtt8`, `M2_dl_rtt0`, `M3_gp_rtt8`, `M4_gp_rtt0` across all evaluated schemes), accurately tracking project-wide multiplicity.

---

### 6.10 Theoretical Headroom and Evaluation Bounds (`headroom.csv`)

Reference bounds evaluated across all 500 evaluation traces per case (`headroom_v17.m`):

| Case | Traffic | Metric | Fixed (Global Static) | A2C (Primary, 3000/800 ep) | A2C (10-Seed Ensemble) | Hindsight (Per-Trace Optimal Offset) | Genie (Perfect Channel CQI) |
|---|---|---|---|---|---|---|---|
| **`M1_dl_rtt8`** | Deadline | On-Time (%) | 60.14% | **61.26%** | **63.06%** | 62.16% | 82.89% |
| **`M2_dl_rtt0`** | Deadline | On-Time (%) | 85.38% | **86.17%** | **86.35%** | 87.12% | 95.55% |
| **`M3_gp_rtt8`** | Full buffer | Goodput (Mbps) | **3.4989** | 3.4679 | 3.4679 | 3.6445 | 5.7153 |
| **`M4_gp_rtt0`** | Full buffer | Goodput (Mbps) | **3.4985** | 3.4378 | 3.4746 | 3.6409 | 5.6615 |

- **Surpassing Static Hindsight:** In `M1_dl_rtt8`, the M1 ensemble (0.6306) exceeds the per-trace hindsight bound (0.6216). This confirms that dynamic, per-TTI adaptation based on queue slack and HARQ retransmission status achieves higher packet delivery than selecting any single constant offset per trace in hindsight.
- **Goodput Gap to Genie:** On full-buffer traffic (`M3`, `M4`), the Genie upper bound reaches 5.71 Mbps, but no link adaptation scheme observing delayed/quantized CQI can bridge that gap; static calibration at 3.50 Mbps captures almost all practical gains obtainable from non-anticipative policies.


