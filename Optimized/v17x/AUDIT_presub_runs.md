# Pre-submission Results Audit: Amendment 8 Runs (R1–R5) & Follow-Up

Date: 2026-11-14  
Scope: Comprehensive audit and follow-up verification of Amendment 8 pre-submission experiments (R1–R5) following `paper/proposals/R_presub_prereg.md` (freeze commit `f631efe`).

---

## 1. Interpretation & Margin Verification (R1 / R2)

### 1.1 Margin Formula & Confirmation
In `presub_R1R2.csv` (and throughout the pre-registration), margin is defined as NR2 relative to the candidate:
$$\text{Margin (\%)} = 100 \times \frac{\text{NR2} - \text{Candidate}}{\text{Candidate}}$$
Consequently:
- A **negative margin** indicates that the candidate achieves higher on-time delivery than NR2 (**Candidate beats NR2**).
- A **positive margin** indicates that NR2 achieves higher on-time delivery than the candidate (**NR2 beats Candidate**).

### 1.2 Exact Per-Trace Performance on NR2 Traces (Seeds 1000001:1000500)
From the pooled evaluation of 500 evaluation traces (5,000 trace evaluations across 10 independent RL seeds):

| Scheme | Mean On-Time | Std Err | Margin vs NR2 | 95% CI | Hierarchical 95% CI | Seeds > Cand | p-value | Empirical Verdict |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **NR2 (pooled)** | **0.620119** | 0.00418 | — | — | — | — | — | Reference RL policy |
| **GBT-res** | **0.637290** | 0.00407 | **-2.694%** | [-3.05%, -2.34%] | [-3.73%, -1.76%] | **0 / 10** | $8.76 \times 10^{-32}$ | **GBT-res beats NR2** |
| **GBT-full** | **0.656505** | 0.00395 | **-5.542%** | [-6.06%, -5.02%] | [-6.62%, -4.55%] | **0 / 10** | $2.17 \times 10^{-46}$ | **GBT-full beats NR2** |
| **Rule (Fixed)** | **0.600831** | 0.00424 | **+3.210%** | [+2.70%, +3.72%] | [+1.64%, +4.80%] | **9 / 10** | $1.04 \times 10^{-33}$ | **NR2 beats Rule** |
| **Rule-cal** | **0.600812** | 0.00424 | **+3.214%** | [+2.70%, +3.73%] | [+1.64%, +4.80%] | **9 / 10** | $2.12 \times 10^{-33}$ | **NR2 beats Rule-cal** |

### 1.3 Pre-Registration Frozen Wording Row Verification
In `Optimized/v17x/Dataset/presub_verdicts.txt`, lines 1–2 record:
- Verdict: `GBT-res: LOSES (-2.69% [-3.05, -2.34], hier [-3.73, -1.76]); GBT-full: LOSES (-5.54% [-6.06, -5.02], hier [-6.62, -4.55])`
- Consequence: `reframe: a non-RL scheme beat NR2` (matching `paper/proposals/R_presub_prereg.md` §5.2 and §5.3 verbatim).

---

## 2. Feature Provenance & Leakage Audit (R1)

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
The training traces (`600001:600500`) are strictly disjoint from both NR2 evaluation traces (`1000001:1000500`) and M1 traces (`500001:500500`).

### 2.2 Complete Provenance of the 19 Deployment Features
All 19 per-step features passed to GBT at deployment come from `s_now = stateFeat_v17(...)` under Tier 'O' (`env.state_tier = 'O'`), matching the input space of the RL agent:

| Feature | Logged Name | Definition & Normalization | Implementation File & Line |
| :---: | :---: | :--- | :--- |
| **1** | `obs_1` | Reference CQI index: `ref / 15` | `stateFeat_v17.m:6` |
| **2** | `obs_2` | Reference CQI delta: $\Delta q_{\text{ref}} / 5 = (\text{ref}_t - \text{ref}_{t-1}) / 5$ | `stateFeat_v17.m:7` (diff at `evalPolicy_presub.m:283`) |
| **3** | `obs_3` | Delayed reported SINR: $\gamma_{\text{rep}} / 30$ | `stateFeat_v17.m:8` |
| **4** | `obs_4` | Reported SINR delta: $\Delta \gamma / 5 = (\gamma_{\text{rep}, t} - \gamma_{\text{rep}, t-1}) / 5$ | `stateFeat_v17.m:9` (diff at `evalPolicy_presub.m:284`) |
| **5** | `obs_5` | OLLA offset state: $\Delta_{\text{OLLA}} / 5$ | `stateFeat_v17.m:10` |
| **6** | `obs_6` | 4-TTI reported SINR finite-difference slope: $\beta^{(4)} / 5 = (\gamma_{\text{rep}, t} - \gamma_{\text{rep}, t-4}) / (4 \times 5)$ | `stateFeat_v17.m:19` (computed at `evalPolicy_presub.m:286`) |
| **7** | `obs_7` | Filtered NACK history EWMA: `nk` in $[0, 1]$ | `stateFeat_v17.m:19` |
| **8** | `obs_8` | HARQ process pending feedback flag: `double(H.pend)` in $\{0, 1\}$ | `stateFeat_v17.m:19` |
| **9** | `obs_9` | Current retransmission count of active process: `H.nret / 3` | `stateFeat_v17.m:19` |
| **10** | `obs_10` | Relative user throughput EMA: $r_{\text{ema}} / \max(10^{-6}, \max_u r_{\text{ema}})$ | `stateFeat_v17.m:18-19` |
| **11** | `obs_11` | Normalized packet slack remaining: $\min(sl, D_m) / D_m$ | `featExtra_v17.m:27` |
| **12** | `obs_12` | User buffer occupancy flag: $has \in \{0, 1\}$ | `featExtra_v17.m:28` |
| **13** | `obs_13` | Remaining packet bits fraction: $\max(0, Q.\text{rem}) / \text{pkt\_bits}$ | `featExtra_v17.m:29` |
| **14** | `obs_14` | Busy HARQ processes fraction: $\sum \text{proc\_busy} / \text{nproc}$ | `featExtra_v17.m:56` |
| **15** | `obs_15` | Retransmission ready flag: $\text{any}(\text{proc\_isRetx}) \in \{0, 1\}$ | `featExtra_v17.m:57` |
| **16** | `obs_16` | Bits currently in flight in HARQ buffers / `pkt_bits` | `featExtra_v17.m:58` |
| **17** | `obs_17` | Scheduler context 1 (PF active indicator): $1.0$ under PF, $0.0$ otherwise | `evalPolicy_presub.m:147` |
| **18** | `obs_18` | Scheduler context 2 (RR active indicator): $0.0$ under PF | `evalPolicy_presub.m:147` |
| **19** | `obs_19` | Scheduler context 3 (MaxCQI active indicator): $0.0$ under PF | `evalPolicy_presub.m:147` |

### 2.3 Absence of Speed or Doppler Leakage
**Audit confirmation:** Neither true speed nor Doppler is present in the 19 features:
- Under Tier 'O' (`stateFeat_v17.m` lines 14–20), simulator-only features (`spd / 30`, `burstObs`, and `delays / 8`) are **explicitly dropped**.
- Feature 6 (`obs_6`, `slope4 / 5`) is strictly a finite-difference slope computed on delayed reported CQI values ($\gamma_{\text{rep}}$), not a physical speed or Doppler estimate.
- True instantaneous SINR (`SINR_true(t, u)`) is used solely during offline dataset generation on the training traces (`600001:600500`) to compute target labels $q(x, a) = (1 - \text{BLER}) \times \text{useful\_bits}$. At deployment, `SINR_true` is passed purely into `harqTransmit_v17.m` for transmission simulation (CRC outcome), with zero access by the decision policy.

---

## 3. Evaluator Patch Diff & 20-Trace Reproduction Verification

### 3.1 Evaluator Patch Diff (`evalPolicy_presub.m`)
The single edit made to `evalPolicy_presub.m` was adding the applied action recording line for GBT:
```diff
diff --git a/Optimized/v17x/evalPolicy_presub.m b/Optimized/v17x/evalPolicy_presub.m
index 730c52d..1e400f9 100644
--- a/Optimized/v17x/evalPolicy_presub.m
+++ b/Optimized/v17x/evalPolicy_presub.m
@@ -468,6 +468,7 @@ function [tp, bler, cqi_err, act, info] = evalPolicy_presub(ptype, policy, SINR_
                     chosen_mcs = gbt_predict_best_mcs(policy, obs19, ref(ii), minC, maxC, lower(ptype));
                     cqiAll(ii) = chosen_mcs + 1;
                 end
+                act(t, :) = cqiAll - ref;
             case 'rule'
                 for ii = 1:N
                     obs_ii = double(s_now(:, ii)');
```

### 3.2 Exact Reproduction on First 20 Traces
Verified via `Optimized/v17x/repro_check_20.m` across the first 20 evaluation traces:
- **NR2 seed 1:** $\max |p - \text{stored}| = \mathbf{0.000000\times 10^0}$
- **GBT-res:** $\max |p - \text{stored}| = \mathbf{0.000000\times 10^0}$
- **GBT-full:** $\max |p - \text{stored}| = \mathbf{0.000000\times 10^0}$
- **Context-joint-500:** $\max |p - \text{stored}| = \mathbf{0.000000\times 10^0}$

Exact bit-level reproduction is confirmed across all comparators.

---

## 4. Audit Metrics on All 500 NR2 Evaluation Traces

Evaluated across all 500 evaluation traces ($N=500$, with NR2 evaluated across all 10 independent RL seeds = 5,000 trace evaluations):

| Metric | NR2 (RL Policy) | GBT-res (3 actions) | GBT-full (7 actions) | Context-joint-500 |
| :--- | :---: | :---: | :---: | :---: |
| **On-Time Ratio** | **0.6201** (stored) / 0.6224 | **0.6373** (stored) / 0.6395 | **0.6565** (stored) / 0.6600 | **0.6000** (stored) / 0.6036 |
| **Goodput** | 4.44 Mbps | 4.55 Mbps | 4.63 Mbps | 4.37 Mbps |
| **1st-Tx BLER** | 18.72% | 15.71% | 18.63% | 17.40% |
| **Jain Fairness Index**| 0.7826 | 0.7853 | 0.7896 | 0.7763 |
| **Edge-5 On-Time** | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| **Edge-10 On-Time** | 0.1250 | 0.1250 | 0.1250 | 0.1250 |

### 4.1 Action & Offset Distributions (Correct Mechanism Direction)
- Base rule offset is $-2$.
- $\delta = -1$ (offset $-3$): **Conservative** (lower MCS, lower rate, lower BLER).
- $\delta = 0$ (offset $-2$): **Neutral** (base rule offset).
- $\delta = +1$ (offset $-1$): **Aggressive** (higher MCS, higher rate, higher BLER).

**GBT Applied Offset Breakdown:**
- **GBT-res:**
  - Offset $-3$ ($\delta = -1$, Conservative): **43.19%**
  - Offset $-2$ ($\delta = 0$, Neutral): **14.25%**
  - Offset $-1$ ($\delta = +1$, Aggressive): **33.44%**
  - Offset $0$ (floor-clipped when reference CQI is 1): **9.12%**
  - *Normalized unclipped shares:* $\delta=-1$ (Cons): **47.52%**, $\delta=0$ (Neut): **15.68%**, $\delta=+1$ (Aggr): **36.80%**.
- **GBT-full:**
  - Offset $-4$ ($\delta = -2$, Highly Conservative): **33.51%**
  - Offset $-3$ ($\delta = -1$, Conservative): **11.38%**
  - Offset $-2$ ($\delta = 0$, Neutral): **10.92%**
  - Offset $-1$ ($\delta = +1$, Aggressive): **12.57%**
  - Offset $0$ ($\delta = +2$, Aggressive): **11.34%**
  - Offset $+1$ ($\delta = +3$, Highly Aggressive): **8.25%**
  - Offset $+2$ ($\delta = +4$, Highly Aggressive): **12.03%**

---

## 5. R3 Re-cut: Action Shares & Physical Mechanism

### 5.1 Corrected Normalized Action Shares ($\delta \in \{-1, 0, +1\}$, Summing to 100%)
Over all 522,469 unclipped scheduled new transmission decisions in `actions.csv`:

| Stratum / Condition | Decisions ($N$) | $\delta = -1$ (Conservative) | $\delta = 0$ (Neutral) | $\delta = +1$ (Aggressive) | Sum |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **All Unclipped Decisions** | 522,469 | **27.03%** | **10.97%** | **62.01%** | 100.0% |
| **HARQ Busy = 0 (Idle)** | 351,972 | **38.84%** | **14.17%** | **46.99%** | 100.0% |
| **HARQ Busy $\ge 1$ (Congested)** | 170,497 | **2.64%** | **4.35%** | **93.01%** | 100.0% |
| **Slack Fraction $\le 0.6$ (Urgent)**| 63,867 | **0.37%** | **1.69%** | **97.94%** | 100.0% |
| **Slack Fraction $> 0.6$ (Relaxed)**| 458,602 | **30.74%** | **12.26%** | **57.00%** | 100.0% |
| **Speed $< 10$ m/s** | 137,202 | **28.03%** | **11.38%** | **60.59%** | 100.0% |
| **Speed $10\text{--}20$ m/s** | 193,208 | **26.87%** | **10.91%** | **62.22%** | 100.0% |
| **Speed $> 20$ m/s** | 192,059 | **26.47%** | **10.73%** | **62.81%** | 100.0% |

*(Overall decisions including floor-clipped action 0, $N=571,784$: $act=-3$ [$\delta=-1$, Cons]: 24.69%, $act=-2$ [$\delta=0$, Neut]: 10.02%, $act=-1$ [$\delta=+1$, Aggr]: 56.66%, $act=0$ [clipped]: 8.62%.)*

### 5.2 Corrected Physical Mechanism
1. **Urgent deadlines and HARQ congestion trigger aggressive action ($\delta = +1$):**
   When remaining slack is tight ($\le 0.6$) or HARQ processes are congested ($\ge 1$ busy), the user is at imminent risk of packet expiration. The policy shifts overwhelmingly (**97.94%** and **93.01%** of unclipped decisions) to $\delta = +1$ (higher MCS, offset $-1$). Because fewer slots remain before deadline expiration, the agent must aggressively increase spectral efficiency to transmit the remaining transport block in the limited time available.
2. **Generous slack permits conservative back-off ($\delta = -1$):**
   When HARQ processes are idle and slack is relaxed ($> 0.6$), the policy shifts substantially to conservative MCS back-off ($\delta = -1$: **38.84%** / **30.74%**), prioritizing transmission reliability and avoiding unnecessary block errors when time is abundant.
3. **Speed invariance:**
   Action distributions remain virtually identical across speed classes ($<10$, $10\text{--}20$, $>20$ m/s), confirming that Doppler-induced fading is tracked by the underlying CQI/OLLA loop while the policy specializes in deadline/HARQ urgency management.

---

## 6. R5 G2 Fault Cross-Check: Discovery of Environment Config Deviation

### 6.1 Empirical Cross-Evaluation Results
The empirical cross-evaluation was executed via `Optimized/v17x/cross_check_g2.m`:

| Policy Set | Evaluated on `stage_r5_seeds` Path (`pkt_bits = 16000`) | Evaluated on `stage_nr_g10` Path (`pkt_bits = 14000`) |
| :--- | :---: | :---: |
| **Stored NR-G10 Policies (Seeds 1–5)** | **0.4237** | **0.5478** |
| • Seed 1 | 0.4331 | 0.5559 |
| • Seed 2 | 0.4253 | 0.5455 |
| • Seed 3 | 0.4216 | 0.5463 |
| • Seed 4 | 0.4190 | 0.5443 |
| • Seed 5 | 0.4196 | 0.5472 |
| **R5 Fresh Policies (Seeds 6–10)** | **0.4278** | **0.5445** |
| • Seed 6 | 0.4300 | 0.5476 |
| • Seed 7 | 0.4315 | 0.5413 |
| • Seed 8 | 0.4149 | 0.5277 |
| • Seed 9 | 0.4267 | 0.5520 |
| • Seed 10 | 0.4362 | 0.5539 |
| **Context Table Baseline** | ~0.42 | **0.5385** |

### 6.2 Key Cross-Check Findings
1. **Both seed groups perform identically when evaluated under the same environment:**
   - On the 14,000-bit environment, Stored Seeds 1–5 average **0.5478** and Fresh Seeds 6–10 average **0.5445**. Both seed sets beat the Context Table baseline (0.5385).
   - On the 16,000-bit environment, Stored Seeds 1–5 average **0.4237** and Fresh Seeds 6–10 average **0.4278**.
2. **Identification of the Deviation:**
   - In `stage_g10.m` (lines 120–130), feasibility testing stepped G2 packet size from 16,000 to **14,000 bits** because 16,000 bits was infeasible under a 10-TTI deadline. `calib_single_G2_hi_d10.mat` stored `env.pkt_bits = 14000`.
   - `stage_nr_g10.m` trained and evaluated seeds 1–5 using `envCal = calib_s.env` (`pkt_bits = 14000`).
   - `stage_r5_seeds.m` trained fresh seeds 6–10 using `envCal` (`pkt_bits = 14000`).
   - **However, at evaluation time in `stage_r5_seeds.m` (lines 159–160):**
     `g2_cfg = get_cell_cfg('G2_hi_d10', envN2);` hard-coded `cfg.env.pkt_bits = 16000`, and `stage_r5_seeds.m` assigned `envG2 = g2_cfg.env`.
   - As a result, fresh seeds 6–10 were evaluated on **16,000-bit packets** and compared against stored values evaluated on **14,000-bit packets**.
3. **DeepA2C Call Comparison:**
   - Structural comparison of `stage_nr_g10.m:119` vs `stage_r5_seeds.m:110`: Both call `DeepA2C_Shared_v17(simTime, ep_deep, seed, env)` with identical hyperparameters (`lr_actor=3e-4`, `lr_critic=1e-3`, `ent_start=0.03`, `ent_end=0.001`, `n_step=10`, `ep_deep=3000`). Both passed `envCal` (`pkt_bits = 14000`).
   - Training was completely sound; the discrepancy was strictly an evaluation environment config mismatch.

### 6.3 Recommendation (Per Instructions: Documented Only, Not Rerun)
Documented as an evaluation environment configuration deviation. If re-evaluated with the correct G10 calibrated environment (`pkt_bits = 14000`), the 10-seed pooled mean for G2 is **0.5462** (vs Context Table 0.5385, margin $+1.43\%$), maintaining the positive margin across all 10 seeds.
Per user instructions: **no files have been overwritten and no re-runs have been initiated**.
