# Pre-registration: R1c — calibration-draw replication and per-cell test of the ACK-trained learner

**Stage code:** `r1c` (MATLAB, `Optimized/v17x/stage_r1c.m`), training script `Optimized/v17x/train_r1c_ack.py`, analysis `paper/analysis/r1c_stats.py`.
**Amendment:** 10, revised by **10a** before any run (`AMENDMENTS.md`). **Freeze:** v12 (`FREEZE.sha256`; the Amendment 10 text is kept in git history at `85b0518`, and its hash list as `FREEZE_v11.sha256`).
**Written:** 15 Nov 2026, after R1b (`5183a89`) found that a one-step supervised learner trained only on observed first-transmission ACK/NACK beats NR2 on the NR2 confirmatory traces (GBT-res-ACK on-time 0.6420, NR2 margin −3.40 %, 0/10 seeds; GBT-full-ACK 0.6710, −7.58 %, 0/10 seeds; ECE ≤ 0.021).
**Independence:** No R1c exploration draw, calibration log, model or evaluation output exists at freezing. `r1c_stats.py` was validated on synthetic data only (§9). The writing session did not open any evaluation data in preparing this text; it read only the frozen G10 calibration files, to state the cell parameters of §4.

## 1. Questions
1. **Calibration-draw replication (M1 / NR2 traces).** Does the advantage of the ACK-trained learner over NR2 replicate across four independent calibration draws, or does it depend on the particular 500-trace calibration sample of R1b?
2. **Per-cell test (primary for generalization).** Trained on each neighbouring cell's own calibration traces, does the ACK-trained learner beat or match that cell's RL policy and beat the cell's calibrated comparators, at G2 and at G3?
3. **Transfer (secondary).** Do the M1-trained models, unchanged, do the same in the cells?

## 2. Definitions and model (unchanged from R1b)
- **Features (20 inputs):** `obs_1..obs_19` (state tier `O`; no true channel, true speed, burst flag or true delay), plus the MCS index of the candidate transmission.
- **Model:** `HistGradientBoostingClassifier` (log-loss), frozen **gbt_a** settings `max_iter=300, learning_rate=0.05, max_leaf_nodes=31, min_samples_leaf=40, early_stopping=False, random_state=0`. **Target:** the observed outcome `ack1` ∈ {0, 1} of the first transmission. No true-SINR quantity is logged or used (asserted as in R1b).
- **Scoring:** q̂(a) = p̂(ACK | x, mcs(a)) × ubits(a), with ubits(a) = min(TBS(mcs(a), n_RB), bits remaining); ties go to the lower MCS.
- **Schemes:** `GBT-res-ACK` (base offset ±1 of the cell's frozen base) and `GBT-full-ACK` (all distinct actions in −4…+2). Both are deterministic.
- **Logging policy (as R1b):** ε-greedy around the trace set's frozen base offset with ε = 0.5. With probability 0.5 the base offset is used; otherwise the offset is drawn uniformly from −4…+2. Draws come from the stated stream, `rng(stream + j)` for trace j. Retransmissions keep their MCS.
- **Equivalence gate:** each fitted model is hashed (SHA-256) and checked inside MATLAB against scikit-learn on 1 000 logged decisions (max abs diff ≤ 1e-9), before any evaluation-trace run.

## 3. M1 fits (replication on the NR2 traces; transfer to the cells)
Four disjoint M1 calibration draws of 500 traces each, M1 configuration (`env_M1`), base −2:
| Fit | Traces | CRN | Exploration stream |
|---|---|---|---|
| M1 fit 1 | 600001–600500 | 610001–610500 | `rng(3050000 + j)` (the R1b model, not retrained) |
| M1 fit 2 | 620001–620500 | 630001–630500 | `rng(3060000 + j)` |
| M1 fit 3 | 640001–640500 | 650001–650500 | `rng(3070000 + j)` |
| M1 fit 4 | 660001–660500 | 670001–670500 | `rng(3080000 + j)` |

## 4. Cell fits (primary per-cell test)
### 4.1 Cell environments, read from the frozen files (never typed)
The environment of each cell is loaded from **`Optimized/v17x/Dataset/ckpt/g10/calib_single_<cell>.mat`** (`out.env`, and `out.fixed_offset` for the base offset). These files are hash-checked against the hashes recorded in the R1–R5 audit. The stage **asserts**, against the file, before any logging or evaluation:
- `pkt_bits`; for G2 additionally `pkt_bits == 14000` (Deviation D1);
- `pkt_deadline`, `pkt_period` and `N`;
- the offered load, N × pkt_bits / pkt_period (bits per TTI);
- the base offset `out.fixed_offset`, which must equal `out.env.fixed_offset` and the base used by the stored NR-G10 policies.

For reference only, the values read on 15 Nov 2026 were:
- G2_hi_d10: pkt_bits 14000, deadline 10, period 20, N 10, base −2;
- G3_lo_d18: pkt_bits 8000, deadline 18, period 20, N 10, base −3.

**The stage asserts against the file, not against this text.** `get_cell_cfg` (the cause of D1) is not used anywhere in `r1c`.

### 4.2 Fresh disjoint calibration traces per cell
Four fits per cell, 500 traces each, cell environment as in 4.1, ε-greedy logging around the cell's base offset, the same model settings.
| Cell | Fit k (k = 1…4) traces | CRN | Exploration stream |
|---|---|---|---|
| G2 | 4100000 + 1000 (k − 1) + j | 4200000 + 1000 (k − 1) + j | `rng(4300000 + 1000 (k − 1) + j)` |
| G3 | 4400000 + 1000 (k − 1) + j | 4500000 + 1000 (k − 1) + j | `rng(4600000 + 1000 (k − 1) + j)` |

with j = 1…500. All ranges in §3 and §4 are asserted disjoint from each other and from every range used so far:
- evaluation 500001–570500, 1000001–1010500, 720001–750500, and their CRN ranges;
- G6 calibration 600001–610500;
- G10 calibration 901000–912500;
- the preflight ranges 1030001–1030020 and 1050001–1050020;
- the R5 decision draws 2040000–2270100.

## 5. Evaluation
### 5.1 Trace sets and the RL comparator
- **NR2 traces** (1000001–1000500, CRN 1010001+): the 10 stored NR2 seeds; REPRO on traces 1–20 (`max_abs_diff = 0`).
- **Cells:** the 300 held-out traces of each cell (G2: 720001–720300, CRN 730001+; G3: 740001–740300, CRN 750001+). The RL comparator is the cell's **NR-G10 policy with 10 seeds**:
  - seeds 1–5 frozen NR-G10;
  - seeds 6–10 from R5;
  - for **G2, seeds 6–10 are the corrected 14 kbit re-evaluation of Deviation D1** (`presub/pertrace_G2corrected.csv`). The faulty 16 kbit values are never used.
- REPRO in each cell, on traces 1–20 (`max_abs_diff = 0`): the stored Fixed and Context table, and NR-G10 seed 1.
- **Comparator family per cell:** the 9 frozen G10 comparators (Baseline, OLLA, OLLA tuned target, Multi-OLLA, Fixed, FixedPU, Context table, Bandit global, Bandit delay class), stored per trace with the same traces and CRN.

### 5.2 Decision rules (per trace set; margin = RL vs learner, positive favours RL)
- **Learner vs RL:** R1 statistics (`r1` of `nr2_stats.py`), with **Holm over the 8 comparisons** of the trace set (4 fits × 2 schemes), separately for cell fits and for transferred M1 fits. R2 at seed level against the 10 RL seeds (`seed_level`). Outcome per fit and scheme, first match:
  - **BEATS** (RL beats the learner): Holm p < 0.05, 90 % CI lower bound > 0, and hierarchical 95 % lower bound > 0. If the hierarchical lower bound is ≤ 0, the outcome is **BEATS-TRACE**.
  - **LOSES** (the learner beats RL): Holm p < 0.05 and 90 % CI upper bound < 0.
  - **MATCH:** Holm p ≥ 0.05 (not significant) **and** |margin| < 0.5 %.
  - **INCONCLUSIVE:** otherwise.
- **"Beats rules"** (cells only): the learner meets R1 against **every** member of the cell's family of 9, with **Holm over 9** for that fit and scheme.
- **Favourable fit:**
  - NR2 traces: the outcome vs RL is LOSES or MATCH.
  - Cells: the outcome vs RL is LOSES or MATCH, **and** the fit beats rules.
- **State of a trace set, per scheme:**
  - **holds:** all 4 fits are favourable;
  - **fails:** no fit is favourable;
  - **split:** otherwise.
  - Primary states use the M1 fits on the NR2 traces and the **cell fits** in G2 and G3. The transferred M1 fits in the cells are reported with the same statistics as a **secondary "transfer" analysis**, without effect on the verdict.
- **Reported in addition:** per fit and scheme, the on-time ratio, the margin with its 90 % CI and the hierarchical CI; per trace set, the 4-fit mean, minimum and maximum, and the worst fit.

## 6. Wording rows (verdict per scheme; first matching row)
| Key | Condition (primary states: NR2, G2, G3) | Paper statement |
|---|---|---|
| `holds across all fits and both cells` | holds, holds, holds | "Across four independent calibration draws, the one-step learner trained on observed ACK/NACK beat or matched the RL policy on the NR2 traces, and, trained on each neighbouring cell's own calibration traces, beat or matched the cell's RL policy and beat all nine calibrated comparators in both cells." |
| `cells hold, fit-dependent` | split, holds, holds | "In both neighbouring cells the cell-trained learner held across all four calibration draws, but on the NR2 traces the comparison with the RL policy depends on the calibration draw." |
| `depends on the calibration draw` | any other pattern with a split | "The comparison between the one-step learner and the RL policy depends on the calibration draw: the four independent draws gave different outcomes." |
| `replicates across fits, cell-dependent` | holds on NR2; exactly one cell holds and the other fails | "The result was consistent across the four calibration draws in every trace set, but cell-dependent: the learner beat or matched the RL policy on the NR2 traces and in [cell], not in [other cell]." |
| `operating-point dependent` | holds on NR2; both cells fail | "The result was consistent across the four calibration draws, but held only at the M1 operating point: in neither neighbouring cell did the cell-trained learner both beat or match the RL policy and beat all nine calibrated comparators." |
| `neither` | otherwise (NR2 fails, no split) | "The one-step learner trained on observed ACK/NACK neither held against the RL policy across calibration draws nor generalized to the neighbouring cells." |
| `not run` | the stage was not run or is incomplete | "No calibration-draw replication or per-cell test of the ACK-trained learner was run." |

The transfer analysis is reported as: "Trained at M1 and applied unchanged, the learner [held / failed / depended on the calibration draw] in [cell]."

## 7. Multiplicity
R1c adds:
- **NR2 traces:** 3 new M1 fits × 2 schemes → +3 cases / +6 scheme evaluations.
- **Each cell:** 4 cell fits × 2 schemes (primary) + 4 M1 fits × 2 schemes (transfer) → +8 cases / +16 scheme evaluations, so +16 / +32 for the two cells.

**Total: +19 cases / +38 scheme evaluations.** With Amendment 9 (85 / 141) the project totals become **104 cases / 179 scheme evaluations**, Bonferroni pool ≤ 1 790 tests. The ledger rows (stage `presub`, `r1c`) and the project-wide Bonferroni values are updated at integration.

## 8. Compute and stage specification
**Units of `stage_r1c`** (preflight on range 1050001–1050020; heartbeat, per-unit checkpoints, watchdog; registered in `run_v17x_all.m`):
1. `load_cells`: load and hash-check `calib_single_<cell>.mat`, and run the §4.1 assertions.
2. `log_m1_k` (k = 2…4): ε-greedy logging on the M1 calibration draws.
3. `log_<cell>_k` (k = 1…4, both cells): ε-greedy logging on the fresh cell calibration draws.
4. `fit`: `train_r1c_ack.py`, which writes 3 M1 models and 8 cell models with a SHA-256 manifest.
5. `equiv`: the equivalence gate for all 11 models.
6. `repro`: NR2 traces 1–20 and each cell's traces 1–20.
7. `eval_nr2`: M1 fits 2–4, both schemes, 500 traces.
8. `eval_<cell>_cellfit`: cell fits 1–4, both schemes, 300 traces.
9. `eval_<cell>_transfer`: M1 fits 1–4, both schemes, 300 traces.
10. `export`: writes `presub/r1c/pertrace_r1c.csv`, with schemes `<S>-M1fit<k>` and `<S>-cellfit<k>`, and `REPORT_r1c.txt`.

**Estimate** (basis: the Amendment 10 estimate and the R1b run):
| Work | Time |
|---|---|
| Logging, 11 draws × 500 traces | ≈ 45 min |
| 11 fits | ≈ 10 min |
| Gates | ≈ 2 min |
| NR2 evaluation | ≈ 4.9 h |
| Cell-fit evaluations, both cells | ≈ 7.4 h |
| Transfer evaluations, both cells | ≈ 7.4 h |
| **Total** | **≈ 20.5 h (about 20–22 h)** |

If time is short, the transfer units (secondary) may be run last. If they are not run, they are reported as "not run"; the primary verdict does not need them.

**Post-run:** `python3 paper/analysis/r1c_stats.py` **unchanged**.

## 9. Analysis script and validation
- `paper/analysis/r1c_stats.py` imports the frozen `r1`, `holm`, `seed_level` (`nr2_stats.py`) and `load_pertrace`, `get`, `check_pairing`, `write` (`presub_stats.py`).
- It refuses to run without `pertrace_G2corrected.csv`; it never reads the G2 RL values of `pertrace.csv`.
- Outputs: `r1c_fits.csv`, `r1c_rules.csv`, `r1c_summary.csv`, `r1c_verdicts.txt`, `r1c_pending_values.csv`.
- `--selftest` (synthetic data only) checks:
  - that each of the six wording rows is produced by a synthetic pattern built for it;
  - the MATCH definition and the order of the outcome classes;
  - the refusal without the corrected G2 file;
  - that the statistics functions are the frozen ones.

  It passes (`SELFTEST PASS`). No real evaluation data were opened.

## 10. What is not changed
All earlier frozen texts and scripts keep their hashes, apart from this file and `r1c_stats.py` (revised by Amendment 10a before any R1c run) and `AMENDMENTS.md`. All earlier results and verdicts stand as recorded, with Deviation D1.
