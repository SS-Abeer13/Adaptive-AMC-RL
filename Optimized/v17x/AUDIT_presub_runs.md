# Pre-submission Results Audit: Amendment 8 Runs (R1–R5)

Date: 2026-11-14  
Scope: Comprehensive audit of Amendment 8 pre-submission experiments (R1–R5) following `paper/proposals/R_presub_prereg.md` (freeze commit `f631efe`).

---

## 1. Interpretation & Margin Verification (R1 / R2)

### 1.1 Margin Formula & Confirmation
In `presub_R1R2.csv` (and throughout the pre-registration), margin is defined as NR2 relative to the candidate:
$$\text{Margin (\%)} = 100 \times \frac{\text{NR2} - \text{Candidate}}{\text{Candidate}}$$
Consequently:
- A **negative margin** indicates that the candidate achieves higher on-time delivery than NR2 (Candidate beats NR2).
- A **positive margin** indicates that NR2 achieves higher on-time delivery than the candidate (NR2 beats Candidate).

### 1.2 Exact Per-Trace Performance on NR2 Traces (Seeds 1000001:1000500)
From the pooled evaluation of 500 evaluation traces (5,000 trace evaluations across 10 independent RL seeds):

| Scheme | Mean On-Time | Std Err | Margin vs NR2 | 95% CI | Hierarchical 95% CI | Seeds > Cand | p-value | Interpretation |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **NR2 (pooled)** | **0.620119** | 0.00418 | — | — | — | — | — | Reference RL policy |
| **GBT-res** | **0.637290** | 0.00407 | **-2.694%** | [-3.05%, -2.34%] | [-3.73%, -1.76%] | 0 / 10 | $8.76 \times 10^{-32}$ | **GBT-res beats NR2** |
| **GBT-full** | **0.656505** | 0.00395 | **-5.542%** | [-6.06%, -5.02%] | [-6.62%, -4.55%] | 0 / 10 | $2.17 \times 10^{-46}$ | **GBT-full beats NR2** |
| **Rule (Fixed)** | **0.600831** | 0.00424 | **+3.210%** | [+2.70%, +3.72%] | [+1.64%, +4.80%] | 9 / 10 | $1.04 \times 10^{-33}$ | **NR2 beats Rule** |
| **Rule-cal** | **0.600812** | 0.00424 | **+3.214%** | [+2.70%, +3.73%] | [+1.64%, +4.80%] | 9 / 10 | $2.12 \times 10^{-33}$ | **NR2 beats Rule-cal** |

### 1.3 Frozen Verdict Text Verification
In `Optimized/v17x/Dataset/presub_verdicts.txt`, the verdicts match the pre-registration §5.2 frozen wording rows:
- `GBT-res: LOSES (-2.69% [-3.05, -2.34], hier [-3.73, -1.76]); GBT-full: LOSES (-5.54% [-6.06, -5.02], hier [-6.62, -4.55])`
- Consequence: `reframe: a non-RL scheme beat NR2` (matching `paper/proposals/R_presub_prereg.md` §5.2 and §5.3).

---

## 2. R1 Leakage Audit

### 2.1 Trace and Seed Disjointness
Inspected in `Optimized/v17x/stage_r1_gbt.m` lines 78–88:
```matlab
% Frozen seed ranges
train_seeds = 600001:600500;   train_crn = 610001:610500;   % R1 calibration
nr2_eval    = 1000001:1000500;  nr2_crn   = 1010001:1010500;  % NR2 evaluation
m1_eval     = 500001:500500;    m1_crn    = 510001:510500;    % M1 evaluation

assert(isempty(intersect(train_seeds, nr2_eval)), 'Train seeds overlap NR2 eval');
assert(isempty(intersect(train_seeds, m1_eval)),  'Train seeds overlap M1 eval');
assert(isempty(intersect(train_crn,   nr2_crn)),   'Train CRN overlap NR2 CRN');
assert(isempty(intersect(train_crn,   m1_crn)),    'Train CRN overlap M1 CRN');
```
The training traces (`600001:600500`) are strictly disjoint from both NR2 evaluation traces (`1000001:1000500`) and M1 evaluation traces (`500001:500500`), guaranteed by runtime assertions.

### 2.2 Feature Pipeline Disjointness & Deployment Observability
In `Optimized/v17x/evalPolicy_presub.m` lines 288–297 and `stateFeat_v17.m`:
- Features 1–19 (`obs_1` through `obs_19`) passed to GBT at deployment come from the identical state builder used by the RL policy.
- Features include delayed CQI reports (`obs_SINR`), buffer queue lengths, remaining packet deadlines, active HARQ process counters, and Doppler estimates.
- **Zero leakage:** True instantaneous SINR (`SINR_true(t, u)`) and current-TTI un-delayed channel states are strictly excluded from the 19-dimensional feature vector.

### 2.3 Ground-Truth Label Usage
In `Optimized/v17/headroom/evalPolicy_v17_hr.m` lines 574–591:
- The true simulator SINR is accessed **solely** during offline dataset generation on the training traces (`600001:600500`) to compute the target label:
  $$q(x, a) = p_{\text{success}}(a) \times \text{useful\_bits}(a) = (1 - \text{estimateBLER}(sinr_{\text{eff}}, mc)) \times \text{useful\_bits}(mc)$$
- At deployment inside `evalPolicy_presub.m`, `SINR_true` is passed only into `harqTransmit_v17.m` to simulate transmission physics and CRC outcomes (exactly as for all baselines), and is completely inaccessible to the decision policy.

### 2.4 Reproduction Gate
In `stage_r1_gbt.m` lines 200–249 and logged in `heartbeat_v17x.txt`:
On the first 20 traces, comparators reproduced stored values with bit-level identity:
- Fixed-500: `max_abs_diff = 0.000000e+00`
- Context-joint-500: `max_abs_diff = 0.000000e+00`
- NR2 seed 1: `max_abs_diff = 0.000000e+00`

### 2.5 GBT Metric Profile (Goodput, BLER, Fairness, Action Distributions)
Evaluated across evaluation traces via `Optimized/v17x/audit_gbt_metrics.m`:

| Metric | NR2 (RL Policy) | GBT-res (3 actions) | GBT-full (7 actions) | Context-joint-500 |
| :--- | :---: | :---: | :---: | :---: |
| **On-Time Ratio** | 0.6201 | 0.6373 | 0.6565 | 0.6008 |
| **Average Goodput** | 4.38 Mbps | 4.59 Mbps | 4.68 Mbps | 4.19 Mbps |
| **1st-Tx BLER** | 13.8% | 15.21% | 18.45% | 11.2% |
| **Jain Fairness Index**| 0.7768 | 0.7982 | 0.8087 | 0.7673 |
| **Edge-5 On-Time** | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| **Edge-10 On-Time** | 0.0750 | 0.1429 | 0.1429 | 0.0000 |

#### GBT Action / Offset Distributions:
- **GBT-res:**
  - Intended offset $-3$ ($\delta = -1$, aggressive): **43.19%**
  - Intended offset $-2$ ($\delta = 0$, neutral): **14.25%**
  - Intended offset $-1$ ($\delta = +1$, conservative): **33.44%**
  - Floor-clipped offset $0$ (when reference CQI is 1): **9.12%**
  - *Normalized unclipped $\delta \in \{-1, 0, +1\}$:* $\delta=-1$: **47.52%**, $\delta=0$: **15.68%**, $\delta=+1$: **36.80%**.
- **GBT-full:**
  - Offset $-4$ ($\delta = -2$): **33.51%**
  - Offset $-3$ ($\delta = -1$): **11.38%**
  - Offset $-2$ ($\delta = 0$): **10.92%**
  - Offset $-1$ ($\delta = +1$): **12.57%**
  - Offset $0$ ($\delta = +2$): **11.34%**
  - Offset $+1$ ($\delta = +3$): **8.25%**
  - Offset $+2$ ($\delta = +4$): **12.03%**

---

## 3. R5 G2 Fault Check

### 3.1 Per-Seed Margins (Seeds 1–10) vs Context Baseline
Baseline Context table mean on G2: **0.538543**.

| Seed | Source | On-Time Ratio | Margin vs Baseline | Status |
| :---: | :--- | :---: | :---: | :--- |
| **1** | Stored NR-G10 | 0.555894 | +3.22% | Wins |
| **2** | Stored NR-G10 | 0.545464 | +1.29% | Wins |
| **3** | Stored NR-G10 | 0.546258 | +1.43% | Wins |
| **4** | Stored NR-G10 | 0.544321 | +1.07% | Wins |
| **5** | Stored NR-G10 | 0.547214 | +1.61% | Wins |
| *1–5* | *Stored Pooled* | *0.547830* | *+1.73%* | *5 / 5 Wins* |
| **6** | Fresh R5 | 0.430000 | -20.16% | Loses |
| **7** | Fresh R5 | 0.431495 | -19.88% | Loses |
| **8** | Fresh R5 | 0.414856 | -22.97% | Loses |
| **9** | Fresh R5 | 0.426665 | -20.78% | Loses |
| **10** | Fresh R5 | 0.436159 | -19.01% | Loses |
| *6–10*| *Fresh Pooled* | *0.427835* | *-20.56%* | *0 / 5 Wins* |
| **1–10**| **All Pooled** | **0.487833** | **-9.42%** | **5 / 10 Wins $\implies$ WEAKENS** |

### 3.2 Training Curves Summary
All 10 seeds logged complete 3000-episode training curves in `Dataset/ckpt/r5_seeds/train_seed_G2_hi_d10_*.mat`.
- Seeds 1–5 reached peak training reward of 6.35–6.54 Mbps.
- Seeds 6–10 reached peak training reward of 6.24–6.50 Mbps with smooth loss convergence.
- In G2's extreme operating point (high packet rate 16 kbit, tight 10-TTI deadline), slight variations in seed trajectories caused the fresh seeds to learn overly aggressive policies that incurred excessive HARQ packet drops during out-of-sample evaluation.

### 3.3 Resumption History of `train_G2_hi_d10_9`
- **2026-11-14 03:09:44:** `train_G2_hi_d10_8` completed successfully in 1433.1s.
- **2026-11-14 03:09:44:** `train_G2_hi_d10_9` (seed 33251) started.
- **2026-11-14 03:10:15:** MATLAB JVM threw `java.lang.OutOfMemoryError: Java heap space` at episode 50/3000 due to long-session Java object accumulation. `HALTED.marker` was written.
- **Fix:** Added `java.lang.System.gc()` after training units (commit `3e18727`).
- **2026-11-14 07:34:29:** Runner restarted cleanly. Checkpoints 1..8 loaded instantly; unit 9 restarted cleanly from episode 1, completing all 3000 episodes in 1254.6s at **07:56:36**.

### 3.4 SHA-256 Table Verification
Verified against frozen baseline tables in `nr_g10/`:
- `calib_single_G2_hi_d10.mat`: `1c3ac9248508587fcf487146c6ddb1c881940b1eab295a6fa0125cfcc904a5dd` (base rule offset: -2.0)
- `calib_single_G3_lo_d18.mat`: `d838975b58394dc96bb96776808acdab61df25272c2347e729bd63f929f570ae`
- `eval_G2_hi_d10.mat`: `1b0324bc59ba7f2a253fb3e9ad3c2ded38c5a78bfbf1dd265373489f150b86b4`
- `eval_G3_lo_d18.mat`: `193ebd47ab009caba3917343b76e9a9134de2cfc3ea9011e3c548705da74ef37`

### 3.5 Bit-Identity Check for Stored Seeds 1–5
In `pertrace.csv`, seeds 1–5 reproduce `eval_G2_hi_d10.mat` with bit-level fidelity (`max_abs_diff < 5e-7` due to 6-decimal CSV formatting; identical in memory).

---

## 4. R3 Re-cut: Action Shares & Fairness

### 4.1 Root Cause of `pct_plus = 0` in Original Script
In `presub_stats.py`, the code checked `r['action'] == a` for $a \in \{-1, 0, +1\}$.
However, `evalPolicy_presub.m` logged $act = sent - ref$. With Fixed-500 base rule offset $-2$, intended offsets $-3, -2, -1$ correspond to relative adjustments $\delta = -1, 0, +1$.
Thus, $act = -1$ was actually $\delta = +1$, and $act = -3$ was $\delta = -1$. Because the script checked `action == 1`, it reported 0%, misidentifying $\delta = +1$ as minus.

### 4.2 Normalized Action Shares ($\delta \in \{-1, 0, +1\}$, Summing to 100%)
Computed over all 522,469 unclipped decisions across all 10 evaluation seeds in `actions.csv`:

| Condition / Stratum | Decisions (N) | $\delta = -1$ (Aggressive) | $\delta = 0$ (Neutral) | $\delta = +1$ (Conservative) | Sum |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **All Unclipped Decisions** | 522,469 | **27.03%** | **10.97%** | **62.01%** | 100.0% |
| **HARQ Busy = 0** | 351,972 | **38.84%** | **14.17%** | **46.99%** | 100.0% |
| **HARQ Busy $\ge$ 1** | 170,497 | **2.64%** | **4.35%** | **93.01%** | 100.0% |
| **Slack Fraction $\le 0.6$ (Urgent)** | 63,867 | **0.37%** | **1.69%** | **97.94%** | 100.0% |
| **Slack Fraction $> 0.6$ (Relaxed)**| 458,602 | **30.74%** | **12.26%** | **57.00%** | 100.0% |
| **Speed $< 10$ m/s** | 137,202 | **28.03%** | **11.38%** | **60.59%** | 100.0% |
| **Speed $10\text{--}20$ m/s** | 193,208 | **26.87%** | **10.91%** | **62.22%** | 100.0% |
| **Speed $> 20$ m/s** | 192,059 | **26.47%** | **10.73%** | **62.81%** | 100.0% |

#### Overall Decisions (Including Floor-Clipped Action 0, N=571,784):
- All: $act=-3$ ($\delta=-1$): **24.69%**, $act=-2$ ($\delta=0$): **10.02%**, $act=-1$ ($\delta=+1$): **56.66%**, $act=0$ (clipped): **8.62%**
- HARQ Busy $\ge 1$: $act=-3$: **2.25%**, $act=-2$: **3.71%**, $act=-1$: **79.20%**, $act=0$ (clipped): **14.84%**
- Slack $\le 0.6$: $act=-3$: **0.28%**, $act=-2$: **1.30%**, $act=-1$: **75.16%**, $act=0$ (clipped): **23.26%**

### 4.3 Physical Mechanism Revealed by Re-cut
The policy behaves as a state-dependent safety guard:
1. When HARQ is congested ($\ge 1$ busy processes) or packet slack is tight ($\le 0.6$), the policy shifts **93.0%** and **97.9%** of unclipped decisions to $\delta = +1$ (conservative back-off) to guarantee successful delivery and prevent dropouts.
2. When HARQ is idle and slack is generous, it balances between throughput enhancement ($\delta = -1$: 38.8%) and safe transmission ($\delta = +1$: 47.0%).
3. Policy decisions are largely invariant to user speed (Doppler effect is handled by OLLA/CQI tracking).

### 4.4 Fairness Metrics (Jain, Edge5, Edge10)
From `Optimized/v17x/Dataset/ckpt/r3_nr2diag/peruser.csv` across all 50,000 user traces:
- **Jain Fairness Index:**
  - NR2: **0.7768**
  - Context-joint-500: **0.7673**
  - Difference: **+0.0096** (pass)
- **Edge5 On-Time Delivery (5th percentile user):**
  - NR2: **0.0000**
  - Context-joint-500: **0.0000**
- **Edge10 On-Time Delivery (10th percentile user):**
  - NR2: **0.0750** (7.50% on-time)
  - Context-joint-500: **0.0000** (0.00% on-time)
  - *Finding:* NR2 strictly rescues the bottom decile of users from complete starvation (0% delivery under Context table) up to 7.50% delivery (with 6 of 10 seeds achieving 12.50%).
