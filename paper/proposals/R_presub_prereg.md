# Pre-registration: pre-submission attribution and robustness runs (R1–R5)

**Stage codes:** `r3_nr2diag`, `r1_gbt`, `r2_rule`, `r5_seeds` (MATLAB, `Optimized/v17x/`), plus the analysis `paper/analysis/presub_stats.py` (R1, R2, R3 summaries, R4, R5).
**Amendment:** 8 (`AMENDMENTS.md`). **Freeze:** v9 (`FREEZE.sha256`).
**Written:** 13 Nov 2026, after every result in the paper was known (M1, W1, G6, NR1, NR2, G10, NR-G10, A1, A3c, A6, HR1) and after the simulated review of draft v10 (`paper/review/`), which motivates it.
**Independence.** No R1–R5 trace, model, threshold or output exists at freezing. The analysis script was tested on synthetic data only (§9). The writing session did not open any evaluation-trace data in preparing this text.

## 1. Questions

The NR2 policy (residual A2C on the non-oracle Fixed base) beats the frozen combined table robustly. The reviewers' common concern is **attribution**: does the gain need *reinforcement learning*, or would any learner (or a designed rule) that sees the same gNB-observable features capture it?

- **R1.** Does NR2 beat a **one-step supervised learner** (gradient-boosted trees, GBT) that sees the same 19 observable features?
- **R2.** Does NR2 beat a **hand-designed state rule** on the same base, as written and with calibrated thresholds?
- **R3.** Does NR2 show the same diagnostics as the original M1 policy (speed breakdown, warm-up, fairness, action shares)? Descriptive only.
- **R4.** How sensitive are the seed-level conclusions to the interval method? Sensitivity analysis only; the decision rules are unchanged.
- **R5.** Do the NR2 and NR-G10 conclusions hold with more training seeds? Reported next to the frozen verdicts, which stand.

## 2. Common definitions

- **Case configuration:** M1 (deadline traffic, RTT 8, 8 HARQ processes, PF scheduling at scheduling time), exactly as in NR2 (`stage_nr2.m`, `env_M1`); G2/G3 as in NR-G10 (`stage_nr_g10.m`).
- **Decisions:** all schemes in this text act only on **scheduled new transmissions**; retransmissions keep their MCS, as for every scheme in the paper.
- **Base offset:** the frozen Fixed-500 offset of G6 (`cal500_tables.txt`, hash-checked), **−2**, which is also NR2's base (asserted in code).
- **Observable features:** `obs_1`…`obs_19` of the current frame, exactly as logged by the HR1 evaluator (`Optimized/v17/headroom/evalPolicy_v17_hr.m`, comment of `COLS`): `obs_1..5` = reference CQI/15, ΔCQI/5, reported SINR/30, one-TTI change of the reported SINR/5, OLLA offset/5; `obs_6` = 4-TTI slope of the reported SINR/5; `obs_7` = NACK average (EMA); `obs_8` = HARQ pending flag; `obs_9` = retransmission count/3; `obs_10` = normalised PF rate; `obs_11` = min(slack, D)/D; `obs_12` = has-packet flag; `obs_13` = bits remaining/packet bits; `obs_14` = busy HARQ processes/8; `obs_15` = retransmission-ready flag; `obs_16` = bits in flight/packet bits; `obs_17..19` = the scheduler candidate cues of the M1 state (as in the HR1 log). No feature is simulator truth (state tier `O`: no true speed, no burst flag, no true delay). The class oracle (speed class) is **not** an input of any scheme in this text, as for NR2.
- **Candidate offsets:** −4…+2 around the reported CQI, clipped; offsets that map to the same MCS are one action (HR1 rule (a)); ties go to the lower MCS.
- **On-time ratio** per trace: `sum(okU)/sum(resU)` over users after burn-in (the paper's primary metric).
- **Paired evaluation:** every scheme on a trace set uses that set's channel seeds and CRN matrix U, so all schemes are paired per trace.
- **Statistics (R1, R2, R5)** use the frozen functions of `paper/analysis/nr2_stats.py`, imported unchanged: `r1` (margin, 90 % t-interval, two-sided Wilcoxon), `holm`, and `seed_level` (hierarchical seed × trace bootstrap, B = 20 000, RNG seeds 20261104/20261105; seed-mean bootstrap; sign test).
- **Margin direction:** margin = 100 · mean(NR2 − X) / mean(X); positive favours NR2.

## 3. R1 — one-step supervised learner (GBT)

### 3.1 Training data (calibration traces only)
- **Traces:** the G6 calibration traces, seeds **600001–600500**, CRN **610001+**: the same 500 traces on which the combined table and the -500 rules were calibrated.
- **Behaviour policy** (generates the logged states): the **Fixed-500 rule** (offset −2, δ = 0 always), run through the HR1 instrumented evaluator in M1. Logged per scheduled new transmission: `obs_1..19`, and for every candidate offset the success probability `psucc` and useful bits `ubits` of the first transmission through the link abstraction.
- **Labels:** q(x, a) = psucc(a) × ubits(a), the expected useful bits of the first transmission. **The labels use the simulator's true SINR. They are training targets only**, as the RL reward also comes from the simulator. At deployment the GBT sees only `obs_1..19`.
- **Assertion in code:** no trace seed of any evaluation range (500001–570500, 1000001–1000500, 720000–750500, and their CRN ranges) may enter the training logs; the stage stops otherwise.

### 3.2 Model (frozen; no tuning)
- One `HistGradientBoostingRegressor` per candidate offset (7 models), with the **gbt_a** settings of HR1: `max_iter=300, learning_rate=0.05, max_leaf_nodes=31, min_samples_leaf=40, early_stopping=False, random_state=0`. Inputs `obs_1..19`; target q(·, a). Fitted once on all calibration decisions (no cross-fitting is needed: evaluation is on other traces).
- The fitted models are saved (`gbt_models.joblib`) and hashed (SHA-256, logged) **before** any evaluation-trace run.
- **Deployment inside the MATLAB evaluator:** by a Python call (pyenv) or by an exported tree dump evaluated in MATLAB, at the implementer's choice. **Equivalence gate:** predictions on 1 000 logged calibration decisions must agree with scikit-learn to 1e-9 (max abs). The GBT is deterministic; it has **no seed dimension**.

### 3.3 Two deployed schemes
- **GBT-res:** at each decision, predicted q for the actions within base ±1 (offsets −3, −2, −1, after rule (a)); choose the largest (ties → lower MCS). Same action set as NR2.
- **GBT-full:** the same over all distinct actions in −4…+2.

### 3.4 Evaluation
- **Primary:** the **NR2 evaluation traces** (`rng(1000000 + j)` channel, `rng(1010000 + j)` CRN, j = 1…500), paired with the stored NR2 per-seed values (10 seeds) and the stored comparators Context-joint-500, Fixed-500 and Context-500.
- **Secondary:** the M1 evaluation traces (500001–500500, CRN 510001+), paired with the stored G6 comparators (`ckpt/g6c/eval.mat`) and the 10 NR2 policies **re-evaluated** on these traces.
- **REPRO gate** (before any GBT evaluation): Fixed-500 and Context-joint-500 re-evaluated on traces 1–20 of each trace set, and NR2 seed 1 on NR2 traces 1–20, must reproduce the stored per-trace values exactly (`max_abs_diff = 0`).

## 4. R2 — hand-designed state rule

### 4.1 Rule as written ("Rule")
On the Fixed-500 base (−2), for each scheduled new transmission:
> δ = +1 if **(busy HARQ processes ≥ 1)** or **(has a packet and slack fraction ≤ 0.6)** or **(reported-SINR drop)**; otherwise δ = 0.

- busy ≥ 1 ⇔ `obs_14` ≥ 1/8 − 1e-9;
- slack clause ⇔ `obs_12` = 1 and `obs_11` ≤ 0.6;
- **interference proxy (observable):** reported-SINR drop ⇔ 4-TTI slope of the reported SINR ≤ −1.0 dB/TTI, i.e. 5·`obs_6` ≤ −1.0. The burst state itself is **not** observable; this proxy flags a recent fall of the reported SINR (a burst adds 9 dB of interference) and is crude by design.
- The three clauses follow the patterns reported for the M1 policy (Section VI-F of the paper); δ is clipped so that the offset stays in −4…+2.

### 4.2 Calibrated version ("Rule-cal")
- Same form (OR of three clauses, δ ∈ {0, +1}, Fixed-500 base), thresholds searched **exhaustively** on the **G6 calibration traces 600001–600500** (CRN 610001+) with the G6 objective (`sum(okU)/sum(resU)` over users and calibration traces after burn-in).
- **Grid (160 combinations):** busy threshold B ∈ {1, 2, 3, off} (clause true if busy processes ≥ B); slack threshold S ∈ {0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, off}; drop threshold θ ∈ {0.5, 1.0, 1.5, 2.0, off} dB/TTI. "off" removes the clause; (off, off, off) is the Fixed-500 rule itself.
- **Ties:** the fewest active clauses, then lexicographic order (B, S, θ) with "off" last.
- The chosen thresholds and the full grid of objectives are written to `r2_thresholds.txt` and hashed (SHA-256, logged) **before** any evaluation-trace run.

### 4.3 Evaluation
As §3.4 (primary NR2 traces, secondary M1 traces, the same REPRO gate).

## 5. Decision rules and wording (R1 and R2)

### 5.1 Primary family
NR2 (per-seed mean, 10 seeds) against **X ∈ {GBT-res, GBT-full, Rule, Rule-cal}** on the NR2 traces: R1 statistics with **Holm over these 4**; R2 at seed level via `seed_level(NR2 seeds, X)` (X has no seeds).

For each X, the **first** matching outcome:
| Outcome | Condition |
|---|---|
| **BEATS** | Holm p < 0.05, 90 % CI lower bound > 0, **and** hierarchical 95 % lower bound > 0 |
| **BEATS-TRACE** | Holm p < 0.05 and 90 % CI lower bound > 0, but hierarchical 95 % lower bound ≤ 0 |
| **LOSES** | Holm p < 0.05 and 90 % CI upper bound < 0 |
| **MATCH** | \|margin\| ≤ 0.5 % and the 90 % CI covers 0 |
| **INCONCLUSIVE** | none of the above |

### 5.2 Wording rows (X stands for the scheme's paper name: "the one-step supervised learner restricted to base ±1", "the one-step supervised learner over all offsets", "the designed rule", "the designed rule with calibrated thresholds")
| Outcome | Paper statement |
|---|---|
| BEATS | "NR2 also beat X, which sees the same gNB-observable features (+x %, 90 % CI [a, b] %, hierarchical 95 % CI [c, d] %): the gain needs more than X." |
| BEATS-TRACE | "NR2 beat X at trace level (+x %, 90 % CI [a, b] %), but not robustly across training seeds (hierarchical 95 % CI [c, d] %)." |
| LOSES | "X, which sees the same gNB-observable features, beat NR2 (NR2 margin x %, 90 % CI [a, b] %)." |
| MATCH | "X, which sees the same gNB-observable features, matched NR2 (margin x %, 90 % CI [a, b] %): on these features, X captures the gain." |
| INCONCLUSIVE | "The comparison of NR2 with X was inconclusive (margin x %, 90 % CI [a, b] %)." |
| not run | "No non-RL learner or designed rule on the same features was evaluated." |

### 5.3 Consequences for the paper (C2 and the abstract)
| Pattern over the four X | Consequence |
|---|---|
| all four BEATS | C2 keeps the residual-RL claim and adds: "The gain needs more than a one-step supervised learner or a designed rule on the same features." |
| at least one MATCH, none LOSES | C2 is reframed: "Learning on the learner's cues helps; on these features [X] matches the RL policy, so deep RL is not needed for this gain." The abstract says so. |
| at least one LOSES | C2 is reframed around the stronger method: "[X] beat the RL policy"; the recommendation names it, and the abstract says so. |
| otherwise (mixed BEATS / BEATS-TRACE / INCONCLUSIVE) | C2 keeps its claim with the qualifier: "Against non-RL learners and designed rules on the same features the advantage is [not robust across seeds / inconclusive] for [X]." |

### 5.4 Secondary comparisons (reported; no consequence for C2)
- Each X against Context-joint-500, Fixed-500 and Context-500 on the NR2 traces: R1 with Holm over 3 per X. Sentence: "X [beat / did not beat] the combined table (+x %, 90 % CI [a, b] %)."
- The same four primary comparisons on the M1 traces (Holm over 4), labelled secondary (the M1 traces were used during development).

## 6. R3 — NR2 diagnostics (descriptive; no decision rule)

On the NR2 evaluation traces:
1. **Speed breakdown:** NR2 (per-seed mean) vs Context-joint-500 and vs Context-500 by user mean speed (< 10, 10–20, > 20 m/s), pooled user-traces, with hierarchical seed × trace 95 % CIs, as A1. Inputs: the stored `okU`/`resU`/`speeds` arrays.
2. **Warm-up:** OLLA warmed up for 200 TTIs (the W1 recipe) evaluated on the NR2 traces; NR2 vs warm OLLA and vs cold OLLA (R1 statistics, no Holm).
3. **Fairness guard:** Jain index over per-user on-time ratios and the 5th-percentile user, per trace, NR2 vs Context-joint-500 (the guard of the paper: Jain drop > 0.02 or edge5 drop > 10 % is flagged).
4. **Action shares:** the share of δ = −1/0/+1 on scheduled new transmissions, pooled over seeds and with the min/max over seeds, by busy HARQ (0 vs ≥ 1), slack fraction (≤ 0.6 vs > 0.6), speed class and burst state. The burst state and the speed class are taken from the simulator **as analysis variables only**.

If a quantity is not in the stored NR2 output, the **stored** NR2 policies are re-evaluated on the NR2 traces with the instrumented evaluator; bit-identity with the stored per-trace values on traces 1–20 is required (`max_abs_diff = 0`).
Wording: descriptive sentences in the style of Section VI-F; no claim beyond "consistent with".

## 7. R4 — seed-level sensitivity analysis (analysis only)

For **M1 vs Context-joint-500** (M1 traces, 10 seeds), **NR2 vs Context-joint-500** (NR2 traces, 10 seeds) and **NR-G10 per cell vs its best single-cue rule** (the single-cue rule with the highest mean on that cell's traces; the Context table in the frozen NR-G10 result) (5 seeds per cell), with the per-seed margin m_s = 100 · (mean_t x_st / mean_t c_t − 1):
- the **t-interval** (95 %, df = n − 1) of the mean seed margin;
- the **BCa** bootstrap 95 % interval of the mean seed margin (B = 20 000, RNG seed 20261113; jackknife acceleration);
- an **exact sign-flip permutation test** of mean m_s = 0 (all 2^n sign patterns; two-sided p);
- **power:** the smallest true mean seed margin detectable with 80 % power by a two-sided one-sample t-test at α = 0.05, using the observed seed SD, for n = 10 and n = 5; and the power at the observed mean for the actual n.

Reported as a table next to the frozen R2 results. **The decision rules and verdicts are unchanged.** Sentence: "With a t-interval [a, b] %, a BCa interval [c, d] % and an exact sign-flip test (p = p), the seed-level conclusion for [comparison] is [unchanged / weaker / stronger]; with n seeds, a mean seed margin below e % could not be detected reliably (80 % power)." The category is "unchanged" if both new intervals agree with the hierarchical interval on whether the lower bound is above zero, "weaker" if the hierarchical lower bound is above zero and either new lower bound is not, "stronger" in the reverse case.

## 8. R5 — more seeds (second analysis next to the frozen one)

- **NR2:** 10 fresh training seeds, `base_seed = 25042`, seed blocks **+211…+220** (seeds 25253–25262), 3000 episodes, the NR2 recipe unchanged; evaluated on the NR2 traces. Decision draws for the added seeds: `rng(2040000 + 100 j + s')`, s' = 1…10.
- **NR-G10:** 5 fresh seeds per cell, `base_seed + 206…210` (G2: 33248–33252; G3: 34248–34252), 3000 episodes; evaluated on the G10 traces of each cell. Decision draws `rng(2140000 + 100 j + s')` (G2) and `rng(2240000 + 100 j + s')` (G3).
- **Disjointness** of the seeds and draw ranges from every earlier range is asserted in code.
- **Analysis:** NR2 with 20 seeds (per-seed mean over 20) against the NR2 family of 8 (R1, Holm over 8) and R2 vs Context-joint-500; NR-G10 with 10 seeds per cell against its family of 9 (R1, Holm over 9 per cell) and R2 vs the best single-cue rule (defined as in §7). The verdict logic of the frozen NR2 and NR-G10 texts is applied unchanged.

| Outcome | Paper statement |
|---|---|
| NR2-20: CONFIRM | "With 20 training seeds the result holds (+x %, hierarchical 95 % CI [a, b] %)." |
| NR2-20: TRACE, REVERSE or NULL | "With 20 training seeds the result weakens: [trace-level margin +x %, hierarchical 95 % CI [a, b] %]." |
| NR-G10-10: both cells pass R1 and R2 | "With ten training seeds per point, the gain at the two neighbouring operating points holds." |
| NR-G10-10: otherwise | "With ten training seeds per point, the gain at [cell] weakens (+x %, hierarchical 95 % CI [a, b] %)." |

The frozen verdicts (NR2 CONFIRM/WIN; NR-G10 ALL) **stand as recorded**; R5 is a second analysis.

## 9. Analysis script and validation
- `paper/analysis/presub_stats.py`, frozen with this text. It imports `r1`, `holm` and `seed_level` from the frozen `nr2_stats.py`.
- **Inputs** (written by the stages; long format, one row per value) in `Optimized/v17x/Dataset/presub/`:
  - `pertrace.csv`: `trace_set, scheme, seed, trace, value` (trace_set ∈ {NR2, M1, G2, G3}; seed = 0 for deterministic schemes). Scheme names: `NR2` (seeds 1–10 frozen, 11–20 R5), `M1` (M1 policies, M1 traces), `NRG10` (seeds 1–5 frozen, 6–10 R5), `GBT-res`, `GBT-full`, `Rule`, `Rule-cal`, `olla_warm200`, and the comparators under the keys of `nr2_stats.FAMILY` (`baseline, olla, olla_tuned500, multi_olla, fixed500, fixedpu500, ctx500, ctxj500`) for NR2 and M1, and `Baseline, OLLA, OLLA (tuned target), Multi-OLLA, Fixed, FixedPU (Oracle), Context table, Bandit (global), Bandit (delay class)` for G2 and G3.
  - `peruser.csv` (R3): `scheme, seed, trace, user, ok, res, speed_mps` on the NR2 traces.
  - `actions.csv` (R3): `seed, trace, busy, slack_frac, has_packet, speed_mps, burst, action` for scheduled new transmissions of the NR2 policies on the NR2 traces.
- **Outputs** (`paper/analysis/out/`): `presub_R1R2.csv`, `presub_R1R2_secondary.csv`, `presub_R3_speed.csv`, `presub_R3_warm.csv`, `presub_R3_fair.csv`, `presub_R3_actions.csv`, `presub_R4.csv`, `presub_R5.csv`, `presub_verdicts.txt`, `presub_pending_values.csv`.
- A missing input skips that part and is written to `presub_verdicts.txt` as "not run"; nothing is imputed.
- **Validation before freezing (synthetic data only):** `python3 paper/analysis/presub_stats.py --selftest` generates synthetic inputs with known effects (a scheme that NR2 beats by about 3 %, one it matches, one that beats NR2, a noisy one) and checks that the outcomes are BEATS, MATCH, LOSES and INCONCLUSIVE; that the exact sign-flip p-value equals a brute-force count; that the BCa interval of a symmetric sample is close to the percentile interval; that the power calculation reproduces the noncentral-t closed form; that `r1`, `holm` and `seed_level` are the frozen functions; and it runs R3–R5 end to end on synthetic inputs (R5 must return CONFIRM / PASS for a synthetic +3 % / +2 % effect). No real data were read.

## 10. Multiplicity
- R1 and R2 add **4 cases / 8 scheme evaluations** (GBT pair and Rule pair, each on the NR2 and M1 traces); R5 adds **3 cases / 3 scheme evaluations** (NR2-20, G2-10, G3-10). R3 and R4 add none.
- Project totals become **83 cases / 137 scheme evaluations**, Bonferroni pool ≤ 1 370 tests (rows × 10). The rows are added to `paper/ledger/robustness_cases.csv` (stage `presub`) when the results are integrated, and the project-wide Bonferroni p-values for the headlines (M1 vs the Context table, M1 vs the combined table, NR2 vs the combined table) are recomputed by `build_numbers.py`.

## 11. Compute estimate (basis: NR2, HR1 and G6 runs on the same PC)
| Stage | Work | Estimate |
|---|---|---|
| `r3_nr2diag` | instrumented re-evaluation of 10 NR2 policies on 500 traces (HR1: ≈ 0.66 s/trace for 10 seeds); warm OLLA on 500 traces | ≈ 10 min |
| `r1_gbt` | Fixed-500 logging on 500 calibration traces (≈ 5 min); 7 GBT fits (minutes); 2 schemes × 2 trace sets × 500 traces, with per-decision prediction overhead; NR2 re-evaluation on M1 traces | ≈ 1–1.5 h |
| `r2_rule` | 160 grid points × 500 calibration traces × ≈ 0.07 s; 2 schemes × 2 trace sets | ≈ 1.6–2 h |
| `r5_seeds` | 20 trainings × 3000 episodes (NR2: 1044–2123 s per seed, median ≈ 1450 s; 2 workers) + evaluations | ≈ 4–6 h |
| **Total** | | **≈ 7–10 h** |

## 12. Stage specifications (`Optimized/v17x/`)
Each stage has a preflight (`stage_<name>_preflight.m`, using only a preflight range 1050001–1050020 that is asserted disjoint), heartbeat lines, per-unit checkpoints and the watchdog, and is registered in `run_v17x_all.m`. Order: `r3_nr2diag, r1_gbt, r2_rule, r5_seeds`.
- **`r3_nr2diag`:** units `repro` (NR2 seeds on NR2 traces 1–20 vs stored, bit-identical), `instr_seed_K` (K = 1…10), `warm_olla`, `export`. Writes `peruser.csv`, `actions.csv` and the warm-OLLA rows of `pertrace.csv`.
- **`r1_gbt`:** units `log_calib` (assert calibration seeds only), `fit` (Python; writes and hashes `gbt_models.joblib`), `equiv` (1e-9 gate), `repro`, `eval_NR2`, `eval_M1` (incl. the 10 NR2 policies on M1 traces), `export`.
- **`r2_rule`:** units `grid_chunk_K` (calibration traces only), `select` (writes and hashes `r2_thresholds.txt`), `repro`, `eval_NR2`, `eval_M1`, `export`.
- **`r5_seeds`:** units `train_nr2_K` (K = 11…20), `train_G2_K`, `train_G3_K` (K = 6…10), `eval`, `export`. Also exports the stored frozen per-seed values (NR2 seeds 1–10 and the 8 comparators; M1 seeds and G6 comparators; NR-G10 seeds 1–5 and the 9 comparators per cell) into `pertrace.csv`, so that `presub_stats.py` reads a single file.
- After all stages: `python3 paper/analysis/presub_stats.py` **unchanged**.

## 13. What is not changed
All earlier frozen texts and scripts keep their hashes. The verdicts of M1, G6, NR1, NR2, G10, NR-G10 and HR1 stand as recorded. R1–R5 neither re-select nor re-tune any earlier scheme or comparator.
