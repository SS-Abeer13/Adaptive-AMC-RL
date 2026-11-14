# Pre-registration: R1b — one-step supervised learner trained on observed ACK/NACK only

**Stage code:** `r1b_ack` (MATLAB, `Optimized/v17x/`), training script `Optimized/v17x/train_r1b_ack.py`, analysis `paper/analysis/r1b_stats.py`.
**Amendment:** 9 (`AMENDMENTS.md`). **Freeze:** v10 (`FREEZE.sha256`).
**Written:** 15 Nov 2026, after the R1–R5 results (`618eb47`) and their audits (`34ed25f`, `5b84537`) were known. R1 found that a one-step gradient-boosted predictor beats NR2 on the NR2 traces (GBT-res on-time 0.6373, GBT-full 0.6565, NR2 0.6201). R1's labels use the simulator's true SINR, which a gNB never has. R1b asks whether the result survives with labels a gNB does have.
**Independence.** No R1b log, model, output or exploration draw exists at freezing. `r1b_stats.py` was tested on synthetic data only (§8). The writing session did not open any evaluation-trace data in preparing this text.

## 1. Question
Does NR2 beat a one-step supervised learner that is trained **only on gNB-observable quantities**: the 19 observable features, the MCS chosen, the observed ACK/NACK of the first transmission and the useful bits of each candidate, and that sees the same features at deployment?

## 2. Definitions shared with R1 (unchanged)
Case configuration (M1, `env_M1` as in NR2), decisions on scheduled new transmissions only, the Fixed-500 base offset −2, the features `obs_1..obs_19` (state tier `O`; no true speed, burst flag or true delay; `R_presub_prereg.md` §2), the candidate offsets −4…+2 with rule (a) (same MCS = one action; ties → lower MCS), the on-time ratio, paired evaluation with CRN, the margin direction (positive favours NR2), and the frozen `r1`, `holm`, `seed_level` of `nr2_stats.py` and `classify` of `presub_stats.py`.

## 3. Logging with exploration (calibration traces only)
- **Traces:** the G6 calibration traces, seeds **600001–600500**, CRN **610001+**, M1 configuration. The assertions of `stage_r1_gbt.m` (no evaluation trace or CRN seed may enter) are kept.
- **Logging policy (ε-greedy around the Fixed-500 base, ε = 0.5):** at each scheduled new transmission, with probability 0.5 the offset is the base −2 (δ = 0); otherwise the offset is drawn **uniformly from the seven candidate offsets −4…+2** (δ ∈ {−2,…,+4} around the base). Draws come from a dedicated stream `rng(3050000 + j)` for trace j (one uniform for the ε test and one for the offset, in decision order), asserted disjoint from every earlier range. Retransmissions keep their MCS. This covers every action that GBT-full can choose; each non-base offset is taken on about 1/14 of decisions.
- **Logged per scheduled new transmission:** trace j, TTI, user, `obs_1..obs_19` (computed by the same code as the policy state), the offset and MCS taken, the **observed first-transmission outcome** `ack1` ∈ {0, 1} (from the HARQ feedback of that transmission, i.e. the simulator's Bernoulli draw with the CRN matrix U), the useful bits of the transmission taken, and the useful bits `ubits(a)` and MCS of all seven candidates. `ubits(a) = min(TBS(mcs(a), n_RB), bits remaining)` is computable at the gNB (TBS table, RB allocation, buffer); for full buffer ubits = TBS (not used here).
- **Not logged and not used:** true SINR, psucc, BLER, or any channel truth. The stage asserts that the training file contains none of the HR1 columns `psucc_*` or `sinr*`.

## 4. Model (frozen; no tuning)
- **p̂(ACK | x, mcs):** one `HistGradientBoostingClassifier` (log-loss) with the **gbt_a** settings: `max_iter=300, learning_rate=0.05, max_leaf_nodes=31, min_samples_leaf=40, early_stopping=False, random_state=0`. **Inputs (20):** `obs_1..obs_19` and the MCS index of the transmission (as a number). **Target:** `ack1` of the logged first transmission. Trained on all logged decisions of the 500 calibration traces (exploratory and base decisions alike). No inverse-propensity weighting.
- **Calibration diagnostics (not used for deployment):** 5-fold cross-fitted predictions on the calibration logs, folds by trace (trace index mod 5), same settings; written to `r1b_calib_xfit.csv` (`trace, mcs, p_hat, ack1, explored`).
- The deployed model is saved (`r1b_model.joblib`), hashed (SHA-256, logged) **before** any evaluation-trace run, and checked inside MATLAB as in R1 (predictions on 1 000 logged calibration decisions agree with scikit-learn to 1e-9).

## 5. Deployed schemes
At each scheduled new transmission, for every distinct candidate action a:
q̂(a) = p̂(x, mcs(a)) × ubits(a); choose the largest q̂ (ties → lower MCS).
- **GBT-res-ACK:** actions within base ±1 (offsets −3, −2, −1).
- **GBT-full-ACK:** all distinct actions in −4…+2.
Both are deterministic (no seed dimension).

## 6. Evaluation and decision rules
- **Primary:** the NR2 evaluation traces (`rng(1000000 + j)`, CRN `rng(1010000 + j)`, j = 1…500), paired with the stored NR2 per-seed values (10 seeds) and the stored Context-joint-500, Fixed-500 and Context-500. REPRO gate as in R1 (Fixed-500 and Context-joint-500 on traces 1–20, NR2 seed 1 on traces 1–20; `max_abs_diff = 0`).
- **Family:** NR2 vs {GBT-res-ACK, GBT-full-ACK}, R1 statistics with **Holm over these 2**, R2 at seed level; outcome per scheme by the frozen `classify` of `presub_stats.py` (BEATS / BEATS-TRACE / LOSES / MATCH / INCONCLUSIVE; MATCH tolerance 0.5 %).
- **Secondary (reported):** each scheme vs Context-joint-500, Fixed-500 and Context-500 (Holm over 3 per scheme); the same family on the M1 evaluation traces (500001–500500, CRN 510001+, NR2 policies re-evaluated there as in R1); and, descriptively, each ACK scheme vs its R1 counterpart (GBT-res-ACK vs GBT-res, GBT-full-ACK vs GBT-full; R1 statistics, no Holm): the cost of replacing true-SINR labels by observed ACKs.
- **Calibration of p̂ (reported):** reliability curve with 10 equal-frequency bins of p̂ (mean predicted vs observed ACK rate, with Wilson 95 % intervals), Brier score and expected calibration error (ECE, bin-weighted |mean p̂ − ACK rate|), (i) on the cross-fitted calibration predictions, overall and for explored decisions only, and (ii) on the first transmissions actually taken by GBT-full-ACK and GBT-res-ACK on the NR2 traces (`r1b_deploy_acks.csv`: `scheme, trace, mcs, p_hat, ack1`).

## 7. Wording rows
X = "the one-step supervised learner trained on observed ACK/NACK, restricted to base ±1" (GBT-res-ACK) or "… over all offsets" (GBT-full-ACK). Rows for BEATS, BEATS-TRACE, LOSES, MATCH and INCONCLUSIVE are the frozen rows of `R_presub_prereg.md` §5.2 with this X; "not run": "No learner trained on observed ACK/NACK was evaluated."

**Consequences (read together with the R1 outcome, in which both true-SINR GBT schemes beat NR2):**
| R1b pattern | Paper statement (added to C2 and the abstract) |
|---|---|
| at least one ACK scheme LOSES (beats NR2) | "A one-step supervised learner trained only on observed ACK/NACK, which a gNB can collect, also beat the RL policy: the advantage of supervised one-step learning here does not depend on simulator-only labels." |
| at least one MATCH, none LOSES | "Trained only on observed ACK/NACK, the one-step supervised learner matched the RL policy." |
| both BEATS (NR2 beats both) | "Trained only on observed ACK/NACK, the one-step supervised learner fell behind the RL policy: its advantage in R1 depended on labels a gNB does not have." |
| otherwise | "Trained only on observed ACK/NACK, the comparison with the RL policy was [not robust across seeds / inconclusive]." |
A badly calibrated p̂ (ECE > 0.05 on the cross-fitted calibration predictions) is reported next to the outcome with: "p̂ was poorly calibrated (ECE e), so this learner is a weak version of the idea."

## 8. Analysis script and validation
- `paper/analysis/r1b_stats.py`, frozen with this text; it imports `r1`, `holm`, `seed_level` (`nr2_stats.py`) and `classify`, `load_pertrace`, `get`, `check_pairing` (`presub_stats.py`).
- **Inputs:** `Optimized/v17x/Dataset/presub/pertrace.csv` (NR2, M1 and comparator rows, unchanged; also the R1 schemes), `Optimized/v17x/Dataset/presub/r1b/pertrace_r1b.csv` (same format; schemes `GBT-res-ACK`, `GBT-full-ACK`, and `NR2` seeds 1–10 on the M1 traces if not in the first file), `r1b/r1b_calib_xfit.csv`, `r1b/r1b_deploy_acks.csv`.
- **Outputs** (`paper/analysis/out/`): `r1b_R1.csv`, `r1b_secondary.csv`, `r1b_reliability.csv`, `r1b_verdicts.txt`, `r1b_pending_values.csv`.
- **Synthetic validation before freezing** (`--selftest`): outcome classes on synthetic schemes (BEATS / LOSES); the reliability table on a synthetic perfectly calibrated predictor (ECE < 0.02) and a miscalibrated one (ECE > 0.1); Brier score against a direct computation; the frozen functions are the imported ones. No real data were read.

## 9. Multiplicity
R1b adds **2 cases / 4 scheme evaluations** (the ACK pair on the NR2 traces and on the M1 traces). With Amendment 8 the project totals become **85 cases / 141 scheme evaluations**, Bonferroni pool ≤ 1 410 tests; the ledger rows (stage `presub`, `r1b`) and the project-wide Bonferroni values are updated at integration.

## 10. Compute and stage specification
- Logging 500 calibration traces (≈ 5–10 min), fit and cross-fit (minutes), equivalence gate, REPRO, evaluation of 2 schemes on 2 × 500 traces with per-decision prediction (R1 basis ≈ 1 h): **≈ 1.5–2 h**.
- `stage_r1b_ack` units: `log_explore` (assert calibration seeds; assert no truth columns), `fit` (`train_r1b_ack.py`: model, cross-fit file, hash), `equiv`, `repro`, `eval_NR2`, `eval_M1`, `export` (`pertrace_r1b.csv`, `r1b_deploy_acks.csv`). Preflight on range 1050001–1050020. Registered in `run_v17x_all.m`. Then `python3 paper/analysis/r1b_stats.py` **unchanged**.

## 11. What is not changed
All earlier frozen texts and scripts keep their hashes; R1–R5 results and verdicts stand as recorded (with the documented R5-G2 deviation). R1b does not re-tune or re-select R1 or any comparator.
