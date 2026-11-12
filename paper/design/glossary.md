# Terminology and notation glossary (use these terms consistently)

The first column is the term as used in the manuscript. "Never" lists wordings to avoid. Symbols follow the v8 draft (`papers/v8_draft/AMC_full_paper_v8_rev1_source.md`, Sections 2–3) wherever the model is unchanged. Ledger IDs show where a definition is checked.

## 1. Comparators and schemes

| Term | Definition | Never |
|---|---|---|
| **Baseline** | Open-loop CQI→MCS mapping, no outer loop | "ILLA" unless defined |
| **OLLA** | Outer-loop link adaptation: per-user SINR/CQI offset Δ updated from ACK/NACK, target BLER P_tgt = 0.10, down-step Δ_down = 0.5 dB, up-step Δ_up = Δ_down·P_tgt/(1−P_tgt) ≈ 0.056 dB, |Δ| ≤ 10 dB (S11) | "step 0.1/0.9" |
| **OLLA (tuned target)** | OLLA with the target BLER chosen on calibration traces from {0.01 … 0.50}. In M1 it selects 0.10 and equals OLLA (P04) | — |
| **Multi-OLLA** | Fast/slow two-integrator OLLA blend (our implementation) | "MO-OLLA", which is a rank-dependent scheme by Ahsen et al. |
| **Fixed** | One global CQI offset added to the OLLA reference, calibrated on calibration traces | "best constant" without saying "calibrated" |
| **FixedPU** | Per-class offset table added to the OLLA reference. Classes = {delay ≤ 4 / ≥ 5 TTI} × {speed < 10 / 10–20 / > 20 m/s}, with the **true** delay and **true mean speed**. Always called a **class oracle**: the speed class is not observable at the gNB; the delay class arguably is (S13a) | "oracle" without "class"; "per-user" |
| **Context table** | Offset per deadline-slack bin (≤ 2, 3–5, > 5 TTI) added to the OLLA reference, calibrated by coordinate ascent. Uses the slack cue only | "same-information rule" |
| **Bandit (global / delay class)** | Frozen UCB1 over offsets, global or per delay class | — |
| **Combined comparator** (G6) | Calibrated table over slack × delay class × speed class × busy-HARQ processes | — |
| **Calibrated rule** | A non-learning rule whose parameters are fitted on calibration traces disjoint from evaluation | — |
| **Calibrated rules built on the learner's cues** | The wording in force: Fixed, FixedPU and the Context table, each using part of the information the learner has. "Same-information" is allowed only if M1 beats the combined comparator (G6 §4) | "same-information" before G6 |
| **Offset action** | The learner chooses δ ∈ {−4, …, +2} CQI steps added to the OLLA reference | — |
| **Base rule** (b_i) | The calibrated offset a residual policy starts from: the better of Fixed and FixedPU on calibration traces (selectBaseRule). In M1–M4 it was FixedPU | — |
| **Residual action** | δ ∈ {−1, 0, +1} added to the base rule: effective CQI = clip(q_ref + b_i + δ) | — |
| **Residual A2C (primary)** | Shared multi-user A2C with the residual action. **Primary scheme = mean over 10 independently trained seeds** (per-seed mean) | "single-seed", "the ensemble" for the primary |
| **Ensemble** | Deterministic argmax of the mean softmax of the 10 actors; secondary scheme | — |
| **resid-800 / offset-800** | 800-episode residual / offset variants (secondary) | cite resid-800 as support |

## 2. System model and metrics

| Term | Definition |
|---|---|
| **TTI** | 1 ms. T_tti = 1 ms; trace length T = 200 TTI; burn-in 50 TTI; 150 scored TTI |
| **CQI, q** | 15-level channel quality index, reported with delay d_i ∈ {2, …, 8} TTI and 1 dB noise; q^ref_{i,t} = OLLA-corrected reference CQI |
| **Δ, Δ_up, Δ_down, P_tgt** | OLLA offset, up/down steps, target BLER |
| **ϑ_m** | SINR at which MCS m reaches 10 % BLER; TBS(m, n_RB) = transport block size |
| **HARQ, RTT, processes** | Chase combining (+2.5 dB per retransmission), max 3 retransmissions. **RTT** = TTIs from transmission to ACK/NACK (0 or 8). **Processes** = parallel stop-and-wait processes per user (1 or 8). *Realistic HARQ* = RTT 8 with 8 processes |
| **PF, scheduled-rate averaging** | Proportional-fair scheduler, one user per TTI. R̄_i(t) = (1−α)R̄_i(t−1) + α·r_i(t) with the **scheduled** rate r_i(t) at transmission time (α = 0.05) — v17 definition (S07) |
| **ACK-time (delivered-bits) averaging** | The pre-v17 variant: the average is updated with delivered bits (at t for RTT 0, at t + RTT for RTT > 0) (S08, S08a) |
| **On-time ratio** | Primary metric for deadline traffic: share of packets (12 kbit every 20 TTI, 10-TTI budget) fully delivered within the budget |
| **Goodput** | Primary metric for full-buffer traffic: delivered useful Mbps per cell |
| **Jain index** | Per-trace Jain index over per-user means, averaged over traces |
| **edge5** | 5th-percentile user throughput / on-time metric |
| **Slack** | Remaining TTIs until the packet deadline; **deadline fraction** = slack / 10 |
| **Class oracle information** | Speed and delay classes used by FixedPU and inherited by the residual agent through its base rule |

## 3. Evaluation protocol

| Term | Definition |
|---|---|
| **Case** | One (version, tag): an environment and training recipe evaluated on one trace set. 67 in the registry |
| **Scheme evaluation** | One RL variant evaluated against the comparators in one case. 108 in the registry |
| **Registry** | `case_registry.csv`: every case, role, verdict, status, and a `correction` column |
| **Calibration / validation / evaluation traces** | Disjoint trace sets (60001+, 80001+, 500001+ in M1). **Fresh** = never used in an earlier round |
| **CRN** | Common random numbers: the same outcome draws for every scheme on a trace |
| **Pre-registered** | The decision rules and wording were written in a README before the run |
| **Beats X** | Holm-adjusted two-sided Wilcoxon p < 0.05 **and** 90 % CI lower bound of the paired % margin > 0 |
| **Claim A** | Beats OLLA, OLLA (tuned target) and Multi-OLLA |
| **Claim B** | Beats Fixed, FixedPU and the Context table |
| **WIN** | Beats all nine comparators |
| **Margin** | 100·(mean RL / mean comparator − 1) in %; **pp** = absolute difference in on-time points |
| **Hierarchical bootstrap** | Resampling of seeds, then traces (B = 20,000), giving seed-level intervals |
| **Genie bound / hindsight bound / headroom** | Perfect-CSI link adaptation / best constant offset per trace in hindsight / the gap each leaves over Fixed (R26) |
| **Fairness guard** | A WIN is reported with its fairness cost if Jain falls > 0.02 or edge5 falls > 10 % vs the best rule |
| **Replication** | A result reported to show that an earlier effect recurs, never as a standalone claim (M2) |
| **Superseded / withdrawn** | *Superseded*: run under a simulator defect later fixed (v15/v16 RTT > 0). *Withdrawn*: the claim was retracted after an audit (v7/v8) |
| **Training-limited** | The margin grows when training goes from 800 to 3000 episodes (R25) |
| **Cold start / warm-up** | OLLA and related loops start at the beginning of each trace (v17) / after 200 unscored TTIs (W1) |

## 4. Cases

| Tag | Meaning |
|---|---|
| **M1** | Deadline traffic, RTT 8, 8 processes (primary result) |
| **M2** | Deadline traffic, RTT 0, 1 process (replication) |
| **M3 / M4** | Full-buffer goodput, RTT 8 / RTT 0 |
| **v9 … v17** | Campaign rounds; only v17 results are valid evidence for realistic HARQ |
| **HR1 (learnable one-step headroom)** | Per decision, for the first transmission, in expected useful bits through the link abstraction: relative gain of a cross-fitted gradient-boosted predictor (gbt_a, gbt_b; larger reported) over a calibrated table, on logged decisions (prereg HR1, Amendment 7) |
| **Residual set (HR1)** | The distinct MCS reachable from the base offset ±1, i.e. what the residual policy can choose |
| **NR-G10** | The non-oracle residual recipe at the two G10 operating points (G2, G3), pre-registered after NR2 |
| **Stage codes** | G6 re-calibration, W1 warm-up, NR1/NR2 non-oracle ablation/replication, G10/NR-G10 operating points, A1 speed breakdown, A3c decision time, HR1 headroom (Table of the robustness programme) |
