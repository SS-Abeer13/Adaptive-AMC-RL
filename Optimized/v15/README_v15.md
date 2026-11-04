# v15 — Realistic HARQ Round-Trip Time: Pre-Registered Robustness and Realism Confirmation

**Status: PRE-REGISTERED (27 Oct 2026).** All Stage A multi-process HARQ modules, Stage B unit tests (Tests B1–B6), Stage 0 feasibility checks across calibration traces, and preflight integration tests are complete. Autonomous training campaign is pending user approval before launch.

---

## 1. Context and Motivation (Surviving the Realism Gap)

In v14, residual A2C with potential-based reward shaping and a conservative fixed-offset base rule confirmed the WIN hypothesis on fresh data under instantaneous HARQ feedback (`harq_rtt = 0`, single stop-and-wait process `nproc = 1`):
- Primary case `Y0_base` achieved an on-time delivery ratio of **0.8521** vs Fixed **0.8484** (+0.44%, Holm $p = 4.75 \times 10^{-7}$, 90% CI $[+0.31\%, +0.56\%]$), statistically outperforming all 9 non-RL comparators.
- In the paired shaping test, unshaped `ontime` collapsed to 93.5% inaction ($\delta = 0$), whereas shaped `ontime_shaped` explored actively (29.1% $\delta = -1$, 64.4% $\delta = 0$, 6.5% $\delta = +1$), generating a +0.23% paired gain ($p = 1.18 \times 10^{-5}$).
- However, the robustness grid across load and latency revealed an **operating-point specific** verdict: while A2C maintained consistent gains over the OLLA family (+1.0% to +5.5%), it tied the strongest calibrated static rules on tight deadlines (+0.08%, non-significant) and fell behind on loose deadlines (-0.77% to -1.73%), where static conservative backoffs or context tables suffice.

### The Realism Gap: HARQ Round-Trip Time
In real 3GPP LTE and 5G NR systems, HARQ feedback is **not instantaneous**:
1. **Feedback Latency ($RTT > 0$):** Transport block ACK/NACK feedback requires processing time at the UE and transmission on the uplink PUCCH/PUSCH. In standard LTE FDD, feedback arrives $k = 4$ TTIs later, and retransmissions occur at $k = 8$ TTIs ($RTT = 8$ TTIs / 8 ms). In fast TDD/NR configurations, minimum RTT is 4 TTIs.
2. **Multi-Process Stop-and-Wait ($N_{\text{proc}} = 8$):** To saturate the downlink channel while awaiting feedback, the gNB maintains up to 8 parallel stop-and-wait HARQ processes per user. Multiple transport blocks from the same packet can be simultaneously in flight.
3. **Delayed Credit Assignment:** When RL takes an action at TTI $t$, whether the transport block succeeds or completes the packet is unknown until $t + \text{RTT}$. Rewards and potential shaping bonuses cannot be observed immediately.

**v15 Question:** Does the residual A2C advantage over calibrated rules survive this realism gap when HARQ feedback is delayed and parallel processes operate simultaneously?

---

## 2. Pre-Registered Cells & Feasibility Verification (`feasibility_v15.txt`)

To ensure that each evaluation operating point presents an active, learnable link-adaptation problem without baseline collapse, the pre-registered C2 feasibility rule requires that Fixed offset on-time delivery falls within $[0.50, 0.97]$ on calibration traces (60000+).

### Feasibility Rule (C2)
- If Fixed on-time ratio is outside $[0.50, 0.97]$, substitute packet size towards 12000 bits ($8000 \to 10000$ or $16000 \to 14000$).
- If still outside, report cell as infeasible and do not run.
- Record substitutions before launch.

### Recorded Feasibility Results (`Dataset/feasibility_v15.txt`)
All 3 cells were evaluated across 20 calibration traces (60000+) using `feasibility_v15.m`:

| Cell | Operating Point | RTT | $N_{\text{proc}}$ | Packet Bits | Deadline | OLLA On-Time | Fixed On-Time | Hindsight Bound | Genie Bound | Substitution | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **`Z1_rtt8`** | **Primary Confirmation** | 8 | 8 | 12000 | 10 | 0.5131 | **0.5624** | 0.5958 | 0.8178 | None | **FEASIBLE** |
| **`Z2_rtt4`** | Robustness 1 (Fast RTT) | 4 | 8 | 12000 | 10 | 0.7260 | **0.7776** | 0.8042 | 0.9214 | None | **FEASIBLE** |
| **`Z3_rtt8_loose`** | Robustness 2 (Loose DL) | 8 | 8 | 12000 | 20 | 0.7987 | **0.8692** | 0.8934 | 0.9522 | None | **FEASIBLE** |

**Findings from Calibration:**
- All 3 cells fall strictly within the $[0.50, 0.97]$ feasibility envelope (**zero substitutions required**).
- Under 8-TTI RTT with a 10-TTI deadline (`Z1_rtt8`), only 1 transmission round-trip is possible before deadline expiry. This creates a severe penalty for block failure (Fixed on-time drops from 0.8484 in v14 to 0.5624).
- Substantial headroom exists across all cells: Genie reaches 0.8178 in Z1, representing a **+0.255 absolute headroom gap (+45.4% relative)** over Fixed (0.5624), confirming ample headroom for intelligent link adaptation.

---

## 3. Architecture and Methodological Upgrades for Realistic HARQ

1. **Multi-Process HARQ Physics Engine (`harqInit_v15`, `harqFeedback_v15`, `harqTransmit_v15`):**
   - Per-user matrix tracking of $N_{\text{proc}}$ parallel processes (`proc_busy`, `proc_ready_t`, `proc_isRetx`, `proc_nret`, `proc_mcs`, `proc_tbs`, `proc_bits`, `proc_ok`, `proc_dec_id`).
   - Chase combining soft gain (+2.5 dB per retry) applies upon retransmission.
2. **TTI Execution Sequence:**
   - **Step 1 (Feedback Arrival):** Processes with `ready_t == t` mature. ACKs credit useful bits to `Q.rem` and apply OLLA up-steps. NACKs apply down-steps and mark process retx-ready (or drop if `nret > 3`, returning untransmitted bits to `Q.tx_rem`). Emits `fbList`.
   - **Step 2 (Traffic Pre):** Checks packet deadlines ($t > Q.dl$). Expired packets flush all associated in-flight and retx processes. New arrivals admitted.
   - **Step 3 (Scheduling Eligibility):** Users eligible only if active packet AND (has retx-ready process OR (has free process AND `Q.tx_rem > 0`)). Retransmissions prioritized.
   - **Step 4 (Transmission):** Scheduled users allocate free process or execute retx, setting `ready_t = t + max(harq_rtt, 1)`.
3. **RL Delayed Credit Assignment:**
   - At transmission ($t$), immediate action penalty $-0.02 \cdot |\delta|$ is recorded in `bufR` associated with unique `dec_id`.
   - At feedback maturity ($t + \text{RTT}$), completion bonus $+1.0$ and potential shaping bonus $F = 0.5 \cdot (\text{rem\_frac}_{\text{pre}} - \gamma \cdot \text{rem\_frac}_{\text{post}})$ are routed to `bufR(dec_id)`.
   - If `dec_id` was already flushed by an n-step actor-critic update, credit falls back safely to `pendR(u)` and is included in the next decision.
   - Fraction of delayed credits falling back to `pendR` is formally logged via `late_credit_frac` (`LATECREDIT|` output).
4. **Observable State Space (`feat_extra = {'slack', 'harqx'}`):**
   - Added 3 HARQ-specific features via `featExtra_v15.m`:
     1. Fraction of busy processes: $\sum \text{busy} / N_{\text{proc}}$.
     2. Retransmission-ready flag: $1$ if user has a retransmission waiting.
     3. Bits currently in flight: $\sum \text{bits}_{\text{flight}} / \text{pkt\_bits}$.
5. **Entropy Tracking:**
   - For the 3-action residual set $\{-1, 0, 1\}$, maximum entropy is $\ln(3) \approx 1.0986$. `fill_stats_v15` logs `max_entropy = log(nA_eff) = 1.0986`.
6. **Primary Scheme:**
   - Pre-registered primary scheme: `Deep A2C v15` (per-seed mean over independently trained actors).
   - Secondary schemes: `Deep A2C v15 (ensemble)` and `Deep A2C v15 (best-on-val)`.

---

## 4. Pre-Registered Cases, Seeds, and Traces (Table S1.7)

All seed and trace ranges are completely disjoint from rounds v9–v14. As pre-registered in PLAN_v15 §C, all three cells evaluate over **10 seeds and 500 eval traces** with `pkt_period = 20`:

| Tag | Role | RTT | $N_{\text{proc}}$ | Packet Bits | Deadline | Period | Seeds ($K$) | Base Seed | Eval Traces | CRN Draws |
|---|---|---|---|---|---|---|---|---|---|---|
| **`Z1_rtt8`** | **Primary Confirmation** | 8 | 8 | 12000 | 10 | 20 | 10 | 11042 | 500: 300001–300500 | 310001–310500 |
| **`Z2_rtt4`** | Robustness 1 (Fast RTT) | 4 | 8 | 12000 | 10 | 20 | 10 | 12042 | 500: 320001–320500 | 330001–330500 |
| **`Z3_rtt8_loose`** | Robustness 2 (Loose DL) | 8 | 8 | 12000 | 20 | 20 | 10 | 13042 | 500: 340001–340500 | 350001–350500 |

### Dynamic Base-Rule Selection
Following PLAN_v15 §C2, `selectBaseRule_v15.m` dynamically evaluates both `Fixed` and `FixedPU` on 20 calibration traces (60000+) to select the superior baseline before residual actor training in each cell.

### Pre-Registered Decision Rules (C4)
- **Primary Case (`Z1_rtt8`, Primary Scheme `Deep A2C v15`):**
  - **Claim A:** Beats OLLA, tuned OLLA, and Multi-OLLA (Holm-corrected $p < 0.05$ across all 9 non-RL comparators AND 90% CI lower bound $> 0$).
  - **Claim B:** Beats Fixed, FixedPU (Oracle), and Context table (Holm $p < 0.05$ AND 90% CI lower bound $> 0$).
  - **WIN:** Beats all 9 comparators simultaneously.
- **Robustness Verdict (`Z1`–`Z3`):**
  - Summary rule: "**robust**" if Claim A passes in all 3 feasible cells AND mean difference vs the best calibrated rule is $\ge 0$ in $\ge 2$ cells. Otherwise "**operating-point specific**".
- **Cross-Cell Analysis (`RTTEFF`):**
  - `analyze_v15_rtteff.m` logs `RTTEFF|` records isolating RTT latency degradation ($Z2 \to Z1$) and deadline slack absorption ($Z1 \to Z3$).

### Pre-Registered Wording Table (C4 / C5)

| Result | Paper May Say |
|---|---|
| **Z1 WIN** | *"Under realistic multi-process HARQ with standard round-trip time (RTT = 8 TTIs), residual A2C with potential-based shaping confirmed the win over all 9 comparators, achieving +X.XX% on-time delivery over the strongest calibrated baseline (Holm p < 0.05)."* |
| **Z1 Claim B fails, Claim A passes** | *"Under realistic HARQ latency, gains over calibrated fixed-offset rules did not confirm; the gain over the standard OLLA family (+X.XX%) remains robust."* |
| **Z1 Claim A fails** | *"The link-adaptation gain did not survive realistic HARQ feedback latency."* The paper shifts to an analysis of the delayed-observation realism boundary. |
| **Robust vs. Operating-Point Specific** | One sentence and Table S1.7 reporting whether RL adaptivity generalizes across fast RTT (4 TTIs) and loose deadlines (20 TTIs). |

### Multiplicity Accounting
v15 adds 3 cases (1 primary, 2 robustness), bringing the cumulative project case count to **29 cases**. Every claim is reported alongside cumulative case counts and explicit historical context (v12 failure, v13 secondary, v14 confirmation under zero-RTT).

---

## 5. Pre-Flight & Sanity Verification (Stage B)

All unit tests and integration sanity checks were executed and passed headless in MATLAB:

1. **Test B1: Equivalence (`test_equivalence_v15.m`) — PASS**
   - Verified that when `harq_rtt = 0` and `harq_nproc = 1`, v15 reproduces v14 bit-for-bit across all 5 comparators on 3 traces and 5 episodes of DeepA2C training ($d\text{LearningCurve} = 0$, $d\text{EntropyCurve} = 0$).
2. **Test B2: Feedback Timing (`test_timing_v15.m`) — PASS**
   - Verified that transmissions at $t$ modify OLLA offsets and mature processes at exactly $t + \text{RTT}$. No premature updates occur during TTIs $t+1 \dots t+\text{RTT}-1$. Retransmissions occur no earlier than $t + \text{RTT}$.
3. **Test B3: Process Limit (`test_proclimit_v15.m`) — PASS**
   - With $N_{\text{proc}} = 2$ and $\text{RTT} = 8$, verified that user cannot exceed 2 blocks in flight. When both processes are busy and none retx-ready, user is marked ineligible and allocated 0 RBs.
4. **Test B4: Deadline Expiry (`test_expiry_v15.m`) — PASS**
   - Verified that when packet deadline expires ($t > Q.dl$), in-flight blocks are immediately discarded and flushed. Late feedback arriving after the deadline is strictly ignored without credit.
5. **Test B5: Bit Conservation (`test_conservation_v15.m`) — PASS**
   - Across 20 independent traces, verified that total delivered bits $\le$ total offered bits ($Q.resU \times \text{pkt\_bits}$) with zero bit leakage.
6. **Test B6: Delayed Credit Routing (`test_delayedcredit_v15.m`) — PASS**
   - Verified that rewards, completion bonuses, and potential shaping increments route to `bufR(dec_id)`. Completed 3 toy training episodes under delayed feedback without error.
7. **Test B7: Mini-Preflight (`fill_v15_preflight.m`) — PASS**
   - End-to-end execution across all 3 cases (`Z1_rtt8`, `Z2_rtt4`, `Z3_rtt8_loose`) with 2 seeds, 2 episodes, 6 eval traces. All `PREFLIGHT_OK`, `REPL`, `LATECREDIT`, `RTTEFF`, and `FEAS` records parsed successfully.

---

## 6. Pre-Registered Campaign Results

> [!WARNING]
> **SUPERSEDED NOTE (3 Nov 2026):**
> Cases `Z1_rtt8`, `Z2_rtt4`, and `Z3_rtt8_loose` in this section were evaluated with $RTT > 0$ under an **ACK-time PF averaging artefact**: `R_emas` was updated with ACKed bits at feedback arrival ($t + \text{RTT}$), leaving in-flight users eligible with unpenalized PF metrics and causing the scheduler to degenerate into bursty max-rate scheduling. These cases and conclusions are superseded and replaced by **v17** (`Optimized/v17/PLAN_v17.md`, `README_v17.md`), which enforces transmission-time scheduled PF rate updates (`pf_avg = 'scheduled'`). See `case_registry.csv`.

**Campaign finished 2026-10-28 04:08:24. Total elapsed (both runs): 124.9 + 263.8 + 71.0 ≈ 459.7 min of case time; wall-clock 21:41:31 (27 Oct) → 04:08:24 (28 Oct), with one restart.**

### 6.1 Restart
One native MATLAB crash occurred during `Z3_rtt8_loose`; `run_v15_headless.bat` auto-restarted
at **02:57** (`logs/restarts_v15.txt`: start 1 at 21:40:42 27 Oct, start 2 at 02:57:00 28 Oct).
`Z1_rtt8` and `Z2_rtt4` had already written their `STEP|done` lines before the crash and were
reloaded from `Dataset/ckpt/`; no seed was re-trained.

### 6.2 REPL — all three aggregators, all three cells

| Case | Scheme | a2c | claimA | claimB | win |
|---|---|---|---|---|---|
| `Z1_rtt8` (primary) | Deep A2C v15 (**primary scheme**) | 0.5708 | 1 | 0 | 0 |
| `Z1_rtt8` | Deep A2C v15 (ensemble) | 0.5658 | 1 | 0 | 0 |
| `Z1_rtt8` | Deep A2C v15 (best-on-val) | 0.5742 | 1 | 0 | 0 |
| `Z2_rtt4` | Deep A2C v15 | 0.8019 | 1 | 0 | 0 |
| `Z2_rtt4` | Deep A2C v15 (ensemble) | 0.8036 | 1 | 0 | 0 |
| `Z2_rtt4` | Deep A2C v15 (best-on-val) | 0.8061 | 1 | **1** | **1** |
| `Z3_rtt8_loose` | Deep A2C v15 | 0.8475 | 1 | 0 | 0 |
| `Z3_rtt8_loose` | Deep A2C v15 (ensemble) | 0.8495 | 1 | 0 | 0 |
| `Z3_rtt8_loose` | Deep A2C v15 (best-on-val) | 0.8501 | 1 | 0 | 0 |

Claim A passes for every aggregator in every cell. Claim B / WIN pass only once: the
**best-on-val** aggregator in `Z2_rtt4` (fast RTT) beats all 9 comparators
(`REPL|Z2_rtt4|pf|scheme=Deep A2C v15 (best-on-val)|...|claimB_calibrated_rules=1|win_all=1`).
This is a secondary aggregator in a robustness cell, not the pre-registered primary
(`Z1_rtt8`, per-seed mean) — reported here for completeness, not as the headline result.

### 6.3 REPLCMP — primary scheme vs. each comparator, primary case `Z1_rtt8`

| vs. | pct | Holm p | beats |
|---|---|---|---|
| Baseline | +14.62% | 3.2e-68 | 1 |
| OLLA | +10.21% | 8.2e-58 | 1 |
| OLLA (tuned target) | +10.21% | 8.2e-58 | 1 |
| Multi-OLLA | +10.28% | 4.8e-57 | 1 |
| Fixed | **−1.35%** | 9.1e-06 | **0 (loses)** |
| FixedPU (Oracle) | +0.82% | 5.6e-12 | 1 |
| Context table | **−2.16%** | 2.1e-12 | **0 (loses)** |
| Bandit (global) | +50.28% | 1.2e-82 | 1 |
| Bandit (delay class) | +50.28% | 1.2e-82 | 1 |

`REPLSEED|Z1_rtt8`: seed means `[0.566 0.5699 0.5773 0.5656 0.5662 0.5657 0.5682 0.5849 0.5717
0.572]`; only **1/10** seeds exceed the best calibrated rule (Context table, 0.5834).

### 6.4 RTTEFF — cross-cell HARQ/deadline effect
```
RTTEFF|Z1_rtt8|rtt=8|dl=10|a2c=0.5708|fixed=0.5786|gain=-0.0078|gain_pct=-1.35%
RTTEFF|Z2_rtt4|rtt=4|dl=10|a2c=0.8019|fixed=0.8036|gain=-0.0017|gain_pct=-0.21%
RTTEFF|Z3_rtt8_loose|rtt=8|dl=20|a2c=0.8475|fixed=0.8496|gain=-0.0021|gain_pct=-0.25%
RTTEFF|DELTA_RTT_EFFECT|fixed_drop=-0.2250|a2c_drop=-0.2311|rtt_resilience=-0.0062
RTTEFF|DELTA_DL_EFFECT|fixed_gain=0.2710|a2c_gain=0.2767|loose_dl_slack=0.0057
```
Going from fast (RTT 4) to standard (RTT 8) feedback, Fixed drops 0.2250 and A2C drops 0.2311 —
A2C is marginally **less** resilient to added feedback delay than the calibrated rule
(`rtt_resilience = -0.0062`). Going from a tight (10-TTI) to a loose (20-TTI) deadline at
RTT 8, Fixed gains 0.2710 and A2C gains 0.2767 — a small (+0.0057) edge for A2C when slack is
plentiful, consistent with Y2/Y4 in v14. Neither effect changes the sign of the A2C-vs-Fixed
margin in any cell (all three are negative, §6.5).

### 6.5 LATECREDIT
`mean_late_frac = 0.0000` and `max_late_frac = 0.0000` in all three cells, for every seed. No
delayed credit ever fell back to `pendR` in this campaign (the n-step buffer never flushed
between a transmission and its feedback at the RTTs and flush cadence used here); the
delayed-credit path exists but was not exercised under load in these runs.

### 6.6 Decision outcome (C4) — primary case `Z1_rtt8`, primary scheme
`claimA_olla_family = 1`, `claimB_calibrated_rules = 0`, `win_all = 0` → **"Claim B fails,
Claim A passes."**

> *"Under realistic HARQ latency, gains over calibrated fixed-offset rules did not confirm;
> the gain over the standard OLLA family (+10.2%) remains robust."*

Note the margin against Fixed specifically is not a tie but a **significant loss** (−1.35%,
Holm p = 9.1e-06) — stronger than a non-confirmation.

### 6.7 Robustness verdict (C4, `Z1`–`Z3`, primary scheme)
Claim A passes in all 3 feasible cells. Mean difference vs. the best calibrated rule in each
cell: Z1 −2.16% (vs Context table), Z2 −0.21% (vs Fixed), Z3 −0.25% (vs Fixed) — **all three
negative**, so the "≥ 0 in ≥ 2 cells" condition fails.

**Verdict: "operating-point specific."** The OLLA-family gain generalises across RTT (4 vs 8)
and deadline slack (10 vs 20 TTI); the gain over calibrated fixed-offset rules does not, and is
in fact a loss at every point tested with the pre-registered primary aggregator.

### 6.8 Deviation
The requested re-run of `feasibility_v15.m` for `Z3_rtt8_loose` after its `pkt_period` was
changed from 25 to 20 (to match `Z1_rtt8`/`Z2_rtt4`'s period, so the three cells differ only in
RTT and deadline, not in arrival rate) was **not done before launch**. `Z3_rtt8_loose` ran with
`pkt_period = 20` (confirmed in `V13ENV|Z3_rtt8_loose|...` above), so the code used the
corrected value; only the feasibility **re-check** on calibration traces was skipped. See §6.9
for the post-hoc result.

### 6.9 Post-hoc Z3 feasibility check (run 28 Oct 2026, after the campaign)
`feasibility_v15.m` was run for `Z3_rtt8_loose` (as part of its normal 3-cell pass) on the same
20 calibration traces (60000+), using `v15_setup.m` as it stands today (`pkt_period = 20`,
`pkt_deadline = 20`, RTT 8, 8 processes, 12000 bits):

```
FEAS|cell=Z3_rtt8_loose|pkt_bits=12000|deadline=20|olla=0.7642|fixed=0.8135|hindsight=0.8387|genie=0.9360|subst=none|status=FEASIBLE
```

- **Fixed (0.8135) is inside [0.50, 0.97]** — the gate passes; `status=FEASIBLE`, `subst=none`.
  **The substitution rule would not have changed anything.**
- **These numbers do not match §2's pre-registration table** (which lists
  `olla=0.7987, fixed=0.8692, hindsight=0.8934, genie=0.9522` for the same cell name).
  `calibrateFixedClass_v15` picks the same offset both times (`fixed_offset = -2`), so the
  calibration procedure itself is unchanged; the most likely explanation is that §2's table was
  computed before the `pkt_period` 25→20 edit landed in `v15_setup.m`, and was never
  regenerated afterward — which is exactly the deviation this entry exists to flag. The two
  numbers are a genuine discrepancy between what §2 documents and what the code now runs, not
  calibration noise.
- **Does this change the campaign result?** No. The actual `Z3_rtt8_loose` campaign (§6.2–6.4)
  was evaluated on the 500 **evaluation** traces (340001+) with the config `v15_setup.m` has
  *now* (`pkt_period = 20`, confirmed: its calibrated `fixed_offset = -2` and `BASE_RULE` line
  match this post-hoc calibration run exactly) — i.e. the campaign and this post-hoc check used
  the same corrected configuration; only §2's **descriptive** feasibility table is stale, not
  the campaign itself. Still, since feasibility was never re-verified at the corrected setting
  *before* launch, this is reported as a procedural deviation rather than asserted
  retroactively as "no issue."
