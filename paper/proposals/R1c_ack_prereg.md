# Pre-registration: R1c — calibration-set replication and operating-cell generalization of the ACK-trained learner

**Stage code:** `r1c` (MATLAB, `Optimized/v17x/`), training script `Optimized/v17x/train_r1c_ack.py`, analysis `paper/analysis/r1c_stats.py`.
**Amendment:** 10 (`AMENDMENTS.md`). **Freeze:** v11 (`FREEZE.sha256`).
**Written:** 15 Nov 2026, after R1b (`5183a89`) found that a one-step supervised learner trained only on observed first-transmission ACK/NACK beats NR2 on the NR2 confirmatory traces (GBT-res-ACK on-time 0.6420, margin −3.40 %, 0/10 seeds; GBT-full-ACK on-time 0.6710, margin −7.58 %, 0/10 seeds; ECE ≤ 0.021; twin margins over simulator true-SINR labels +0.73 % / +2.21 %).
**Independence:** No R1c exploration draw, calibration log, model, or evaluation output exists at freezing. `r1c_stats.py` was validated on synthetic data only (§8). The writing session did not open any evaluation data in preparing this text.

## 1. Questions
1. **Calibration-set replication:** Does the advantage of the ACK-trained learner over NR2 replicate across fresh, independent calibration trace sets, or was the R1b outcome an artifact of the single 500-trace calibration sample?
2. **Operating-cell generalization:** Does the ACK-trained learner generalize across operating cells (the neighbouring NR-G10 cells G2 at 14 kbit and G3), or is its advantage over the RL policy and calibrated heuristic rules restricted to the primary M1 operating point?

## 2. Definitions & Model Settings (shared with R1b)
- **Features (20 inputs):** the 19 gNB-observable features (`obs_1..obs_19`, state tier `O`; no true channel, true speed, burst flag, or queue clairvoyance) plus the candidate transmission MCS index.
- **Model:** `HistGradientBoostingClassifier` (log-loss objective) with the frozen **gbt_a** settings:
  `max_iter=300, learning_rate=0.05, max_leaf_nodes=31, min_samples_leaf=40, early_stopping=False, random_state=0`.
- **Target:** observed binary outcome `ack1` ∈ {0, 1} of the first transmission.
- **Decision scoring:** $q̂(a) = p̂(\text{ACK} \mid x, \text{mcs}(a)) \times \text{ubits}(a)$, with $\text{ubits}(a) = \min(\text{TBS}(\text{mcs}(a), n_{\text{RB}}), \text{bits remaining})$. Ties broken to lower MCS.
- **Schemes:**
  - `GBT-res-ACK`: candidate offsets within base ±1 (offsets −3, −2, −1 around base −2 in M1/NR2 and G2; offsets −4, −3, −2 around base −3 in G3).
  - `GBT-full-ACK`: all candidate offsets in −4…+2.
  Both schemes are deterministic (no policy seed dimension).

## 3. Calibration Sets & Replication (4 Fits)
To test sensitivity to calibration data, the exploration-logging protocol of R1b (ε-greedy around the Fixed base with ε = 0.5; offset drawn uniformly from −4…+2 with probability 0.5, otherwise base offset; draws `rng(stream_base + j)`) is applied across 4 independent, disjoint calibration sets of 500 traces each:
- **Fit 1:** Traces 600001–600500, CRN 610001–610500, exploration `rng(3050000 + j)` (trained in stage `r1b_ack`).
- **Fit 2:** Traces 620001–620500, CRN 630001–630500, exploration `rng(3060000 + j)`.
- **Fit 3:** Traces 640001–640500, CRN 650001–650500, exploration `rng(3070000 + j)`.
- **Fit 4:** Traces 660001–660500, CRN 670001–670500, exploration `rng(3080000 + j)`.

All trace ranges, CRN seeds, and exploration RNG streams are asserted disjoint from each other, from preflight (1050001+), and from all evaluation ranges (500001+, 720001+, 740001+, 1000001+). No true SINR or channel truth is logged or used.

Each fit model is hashed (SHA-256) and verified against scikit-learn tree predictions (equivalence gate: max abs diff $\le 10^{-9}$ on 1,000 decisions) before evaluation.

## 4. Evaluation Protocol

### 4.1 NR2 Confirmatory Traces (Replication)
- **Traces:** the 500 NR2 confirmatory traces (seeds 1000001–1000500, CRN 1010001+).
- **Comparators:** the 10 stored NR2 policy seeds (pooled mean $0.6201$), Fixed-500, and Context-joint-500. REPRO gate on traces 1–20 (`max_abs_diff = 0`).
- **Evaluation:** all 4 fits deployed as `GBT-res-ACK` and `GBT-full-ACK`.
- **Statistics reported:**
  - Per-fit mean on-time, margin vs NR2, 90 % CI, and seed-level rule R2 against the 10 NR2 seeds (`hier95_lo`, `seeds_above`).
  - Fit-level mean across the 4 fits: $\bar{\mu} = \frac{1}{4} \sum_{k=1}^4 \mu_k$.
  - Fit-level interval: min, max, and Student-$t$ 95 % confidence interval $\bar{\mu} \pm t_{0.975, 3} \frac{s}{\sqrt{4}}$.
  - Worst-fit analysis: the fit $k$ with lowest on-time delivery ratio for each scheme is evaluated against NR2 under Rule R1 (Holm over the 2 schemes) and Rule R2.

### 4.2 Operating Cells G2 and G3 (Generalization)
The 4 fits are evaluated at the two neighbouring operating cells from the pre-registered NR-G10 operating grid:
1. **Cell `G2_hi_d10`:**
   - Traffic: $N = 10$, packet size = **14,000 bits** (corrected per Deviation D1), deadline = 10 TTIs, load = high, period = 20 TTIs.
   - Base offset: `Fixed -2` (frozen NR-G10 base).
   - Evaluation traces: 300 held-out traces (seeds 720001–720300, CRN 730001+).
2. **Cell `G3_lo_d18`:**
   - Traffic: $N = 10$, packet size = 8,000 bits, deadline = 18 TTIs, load = low, period = 20 TTIs.
   - Base offset: `Fixed -3` (frozen NR-G10 base).
   - Evaluation traces: 300 held-out traces (seeds 740001–740300, CRN 750001+).
- **Comparators per cell:**
  - The cell's RL policies from NR-G10 (`NRG10`, seeds 1–5 or 1–10; seed-level rule R2 for the RL side).
  - The 9 frozen calibrated single-cue comparators from G10 (`G_FAMILY`: Baseline, OLLA, OLLA tuned, Multi-OLLA, Fixed, FixedPU, Context table, Bandit global, Bandit delay class), with Holm adjustment over the 9 comparators.
- **Statistics reported:** per-fit on-time, margin vs RL policy, margin vs best single-cue rule, 4-fit mean and range, and worst fit vs RL.

## 5. Pre-registered Wording Rows
The final verdict synthesizes replication across the 4 calibration fits and generalization across the 2 operating cells:

| Outcome Key | Condition | Paper Statement |
|---|---|---|
| `holds across all 4 fits and both cells` | All 4 fits beat or match NR2 on NR2 traces, AND in both cells G2 and G3 all 4 fits beat or match the cell's RL policy and beat the calibrated rules. | "The superiority of the one-step supervised learner over the RL policy holds across all 4 calibration fits and across both operating cells (G2 at 14 kbit and G3): the advantage does not depend on calibration-trace chance or on the specific operating point." |
| `fit-dependent` | On the NR2 traces, outcomes differ across calibration fits (some fits beat NR2 while others lose or are inconclusive), showing dependence on the training draw. | "The comparison between the one-step supervised learner and the RL policy is fit-dependent: performance varies across calibration sets, so the advantage observed in R1b was an artifact of the particular calibration trace draw." |
| `operating-point dependent` | All 4 fits consistently beat or match NR2 on NR2 traces, but in at least one neighbouring cell (G2 or G3) the learner fails against the RL policy or calibrated rules. | "The advantage of the one-step supervised learner over the RL policy is operating-point dependent: it holds consistently across calibration fits at the primary M1 operating point, but does not generalize to neighbouring operating cells (G2 / G3), where the RL policy and calibrated rules prevail." |
| `neither holds nor generalizes` | The learner fails to replicate on NR2 across fits and fails to generalize across operating cells. | "The one-step supervised learner neither reliably replicates across calibration sets nor generalizes across operating cells." |
| `not run` | Stage r1c was not executed. | "No calibration replication or operating-cell generalization run was performed." |

## 6. Multiplicity Accounting
R1c adds **11 cases / 22 scheme evaluations**:
- NR2 traces (calibration replication): 3 new fits × 2 schemes (`res`, `full`) = +3 cases / +6 evaluations.
- Cell G2 (14 kbit): 4 fits × 2 schemes = +4 cases / +8 evaluations.
- Cell G3: 4 fits × 2 schemes = +4 cases / +8 evaluations.
*(Alternative grouping by cell: +5 cases / +22 evaluations).*

With Amendment 9 (85 cases / 141 evaluations), the project totals become:
- **Cases:** 85 + 11 = **96 cases** (or 90 grouped).
- **Scheme evaluations:** 141 + 22 = **163 scheme evaluations**.
- **Bonferroni pool:** $\le 1,630$ tests ($163 \times 10$).

## 7. Compute & Stage Specification
- **Stage code:** `r1c` in `Optimized/v17x/stage_r1c.m`, registered in `run_v17x_all.m`.
- **Execution units:**
  1. `log_explore_fits`: log 3 calibration sets (Fits 2, 3, 4; 500 traces each) with $\epsilon = 0.5$ ($\approx 4\text{ min}$).
  2. `fit_models`: train `HistGradientBoostingClassifier` for Fits 2, 3, 4 and write SHA-256 manifest ($\approx 3\text{ min}$).
  3. `equiv_gate`: verify tree equivalence for all models ($\le 10^{-9}$ max abs diff, $\approx 10\text{ s}$).
  4. `repro_gate`: verify exact reproduction on NR2 traces 1–20 ($\approx 18\text{ s}$).
  5. `eval_nr2`: evaluate Fits 2, 3, 4 on 500 NR2 traces; combine with Fit 1 from R1b ($\approx 4.9\text{ h}$).
  6. `eval_g2`: evaluate Fits 1–4 on 300 G2 traces at 14 kbit ($\approx 3.7\text{ h}$).
  7. `eval_g3`: evaluate Fits 1–4 on 300 G3 traces ($\approx 3.7\text{ h}$).
  8. `export`: write `pertrace_r1c_nr2.csv`, `pertrace_r1c_g2.csv`, `pertrace_r1c_g3.csv`, `REPORT_r1c.txt`, and mark `stage_r1c.done` ($\approx 10\text{ s}$).
- **Total compute estimate:** $\approx 12.3\text{ h}$ (roughly 12–14 hours).
- **Post-run analysis:** `python3 paper/analysis/r1c_stats.py` executed **unchanged**.

## 8. Analysis Script & Validation
- Script: `paper/analysis/r1c_stats.py`.
- Validation before freezing: `--selftest` executes three synthetic datasets, verifying:
  - synthesis of all three pre-registered wording rows (`holds across all 4 fits and both cells`, `operating-point dependent`, `fit-dependent`);
  - fit-level mean, min, max, Student-$t$ 95 % confidence interval, and worst-fit extraction;
  - Holm adjustment across worst fits and seed-level rule R2 evaluation.
  - Passes with exit code 0 (`SELFTEST PASS`). No real evaluation data were opened.

## 9. What is Not Changed
All prior frozen texts (`G6`, `W1`, `NR1`, `G10`, `A6`, `NR2`, `NR_G10`, `HR1`, `R_presub`, `R1b_ack`, `common_rules.md`, `checkpoint5_list.md`, `compute_basis.md`) maintain their specifications and hashes. All prior results and verdicts stand as recorded.
