# Amendment 13: fresh-trace confirmation of the frozen policies (FT), symmetric seed check (S-SYM), supervised-learner timing (T-GBT)

Status: to be frozen (hashed in `FREEZE.sha256`) **before any FT trace is generated**.
Author: SS-Abeer13. Date: 24 Nov 2026.

## 1. Purpose

The headline comparison (supervised one-step learner vs residual A2C) was designed after the NR2 confirmation and evaluated on the NR2 traces. It is therefore a test across training draws, not a confirmation on a fresh sample (external review, issue 1). FT evaluates the **already frozen** policies once on a new trace bank. **Nothing is retrained, refitted or re-tuned.**

S-SYM re-analyses frozen results with a decision rule that treats both directions alike (review, issue 4). T-GBT times the supervised learner (review, smaller corrections). Neither adds a case or a verdict.

## 2. Frozen objects (loaded by hash; any mismatch stops the stage)

| Object | Source | Role |
|---|---|---|
| NR2 residual A2C, seeds 1–10 | NR2 stage outputs | RL, restricted actions |
| R6a RL-full, seeds 1–10 | R6 stage outputs | RL, full actions |
| GBT-res-ACK, fits 1–4 | R1c (fit 1 = R1b model) | supervised, restricted |
| GBT-full-ACK, fits 1–4 | R1c (fit 1 = R1b model) | supervised, full |
| Context-joint-500 (combined table) | G6 frozen table | rule |
| Fixed-500, Context-500, OLLA-tuned-500 | G6 frozen tables | rules |
| Designed rule (as written, calibrated) | R2 | rules |
| OLLA, Multi-OLLA, Baseline | v17 code | rules |

The SHA-256 of every policy, fit and table file is listed in `FT_objects.sha256`. That list is committed with this amendment.

## 3. Data

- **Scenario:** the main scenario only. The environment is exactly NR2's (deadline traffic, RTT 8, 10-TTI budget, Fixed base) and is checked field by field against the frozen NR2 env.
- **Traces:** 500 fresh evaluation traces, `rng(4000000 + j)`, j = 1…500.
- **CRN:** `rng(4100000 + j)`.
- **Decision draws (where any scheme draws):** `rng(4200000 + 100 j + s)`, s = seed or fit index.
- **Disjointness:** the stage asserts in code that all three ranges are disjoint from every range used so far. That includes calibration (60001+, 62000+), validation (80001+), M1 evaluation (500001+), G6 and GBT calibration (600001–600500, and the R1c draws), NR2 (1000000+), G10/NR-G10, R5, R6 and all decision-draw ranges. The asserted list is printed in the report.
- **Evaluator:** the frozen `evalPolicy_presub.m` path, unchanged. RL acts greedily (largest logit), as frozen.
- **Accounting:**
  - Primary: as run.
  - Secondary: the Amendment 12 end-of-trace `'resolved'` mode, run only if the `_eot` evaluator passed its bit-identity gate. It is reported next to the primary result and never replaces it.

## 4. Comparisons and decision rules

**Margin:** RL relative to the comparator, paired per trace, in percent; a negative value favours the supervised learner.

**Symmetric rule, applied per fit:**
- **SUP-BEATS:** Holm-adjusted two-sided Wilcoxon p < 0.05 over the family, **and** the 90 % trace-level t-interval of the margin below zero, **and** the 95 % hierarchical interval below zero.
- **RL-BEATS:** the same three conditions, with both intervals above zero.
- **INCONCLUSIVE:** otherwise.

**Hierarchical bootstrap:** 10,000 replicates. Each replicate draws one shared sample of trace IDs (with replacement) and one sample of RL seeds (with replacement). The margin is computed on that crossed seed × trace sample. The supervised fit is held fixed; variation between fits enters only through the four fits.

| ID | Comparison | Family (Holm) | Status |
|---|---|---|---|
| FT-H1 | GBT-res-ACK fits 1–4 vs NR2 | 4 | **primary** |
| FT-H2 | GBT-full-ACK fits 1–4 vs RL-full | 4 | **primary** |
| FT-H3 | NR2 vs Context-joint-500 (RL rule of NR2, unchanged) | 1 | **primary** |
| FT-S1 | GBT-full-ACK vs NR2; GBT-res-ACK vs RL-full | 8 | secondary |
| FT-S2 | NR2 vs the other frozen rules | 8 | secondary |

**Verdict per primary family (H1, H2):**
- **holds on fresh traces:** all 4 fits SUP-BEATS;
- **fit-dependent:** 1–3 fits SUP-BEATS and none RL-BEATS;
- **does not replicate:** 0 fits SUP-BEATS and none RL-BEATS;
- **reverses:** any fit RL-BEATS.

**H3** uses NR2's frozen verdict rule, CONFIRM / TRACE / NULL / REVERSE, unchanged.

## 5. Wording rows (selected by the verdict; the text may not go beyond them)

| Verdict | Wording |
|---|---|
| H1 and H2 hold | "On a fresh trace bank, evaluated once after all policies were frozen, every fit of the supervised learner again beat RL, with the same action set and with the full one." |
| H1 or H2 fit-dependent | "On a fresh trace bank, the supervised learner beat RL for some calibration draws but not all; the ranking depends on the draw." |
| H1 or H2 does not replicate | "On a fresh trace bank, the difference between the supervised learner and RL was not significant; the headline ranking did not replicate." |
| H1 or H2 reverses | "On a fresh trace bank, RL beat the supervised learner for at least one draw; the headline ranking reversed." |
| H3 | the NR2 wording rows, with "fresh evaluation traces" replaced by "a second fresh trace bank" |

If H1 or H2 does not hold, the abstract and Section 6 must state it, and the title is reconsidered.

## 6. S-SYM (sensitivity, analysis only, no new data)

Apply the symmetric rule of §4 to the stored per-trace results of R1c (NR2 traces and both cells) and R6a. Report each frozen verdict next to its symmetric verdict, and state for each interval whether each bootstrap replicate shared one trace-ID sample across RL seeds. The frozen verdicts stand as recorded.

## 7. T-GBT (descriptive)

Time the complete supervised decision (feature build, scoring of every candidate MCS, the argmax) with the A3c protocol: the same CPU, single thread, high priority, timer floor subtracted. Use calibration traces only. Report the median and the noise-corrected p99.9 for GBT-res-ACK and GBT-full-ACK next to the stored A3c values for residual A2C, and the share of TTIs within the slot at 15/30/60/120 kHz.

## 8. Multiplicity

- FT adds one case (`FT`) to the ledger.
- FT-H1 to H3 add 9 tests to the project-wide Bonferroni pool; the secondary families add 16.
- S-SYM and T-GBT add none.
- The ledger and `multiplicity.md` are updated in the same commit as the results.

## 9. Compute and stop rules

- **Estimate:** a preflight on 5 calibration traces times one evaluation per scheme. Projected total = 500 traces × (10 + 10 + 4 + 4 + 9 rule/OLLA schemes); the 1.5× rule applies.
- **REPRO gate (hard stop):** before any FT trace, traces 1–20 of the NR2 set must reproduce the stored per-trace values exactly for every scheme in §2.
- **Rule R6:** one retry, then halt.
- **No peeking:** FT per-trace outputs are not summarised, plotted or printed before all schemes have finished on all 500 traces.
