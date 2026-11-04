# Multiplicity accounting

Source: `Optimized/case_registry.csv` (108 data rows, verified 4 Nov 2026).
Copies at `Optimized/v17/case_registry.csv` and `Optimized/v17/release/case_registry.csv` are byte-identical.

## 1. Definitions used in the paper

| Term | Definition | Count |
|---|---|---|
| **Case** | One registered experimental cell: one (version, tag) pair, i.e. one environment + training recipe evaluated on one trace set. One `case_id` in the registry. | **67** (v9–v17) |
| **Scheme evaluation** | One RL scheme evaluated in one case against the 9 comparators (one registry row). | **108** |
| **Hypothesis test** | One RL scheme vs one comparator (one paired Wilcoxon). | ≤ 108 × 9 = **972** |

Recommended wording for the paper: *"Over the whole study we registered 67 cases and 108 scheme evaluations (v9–v17; registry in the supplement)."*

### Breakdown

| Version | Cases | Rows | Cases with ≥1 WIN row | Status |
|---|---|---|---|---|
| v9 | 18 | 18 | 0 | valid |
| v10 | 15 | 15 | 2 (E4c, E5_mixed_nofeat) | valid, exploratory |
| v11 | 10 | 17 | 0 | valid |
| v12 | 2 | 2 | 0 | valid |
| v13 | 3 | 6 | 2 (X1 per-seed mean, not pre-registered; X2) | valid |
| v14 | 6 | 12 | 3 (Y0_base, Y0_noshape, Y1 ensemble) | valid |
| v15 | 3 | 6 | 0 | **superseded** |
| v16 | 6 | 20 | 3 (K2 valid; K1 offset, L1 superseded) | K1, K3, L1, L3 superseded |
| v17 | 4 | 12 | 2 (M1, M2) | valid |
| **Total** | **67** | **108** | **12** (10 valid) | 60 valid, 7 superseded |

Roles across cases: 12 primary, 6 secondary, 16 robustness, 33 ablation.

## 2. Why earlier documents say 15, 17, 26, 35 or 39

The running counts in the READMEs used a narrower definition: **pre-registered or hypothesis cases from v10 onward**. Under that definition the v9 audit cases are excluded, and v10 counts as 5 (E1–E5), not 15 (the 10 cue/reward ablations are left out).

| Document | Stated count | What it counted |
|---|---|---|
| README_v12 §1, §6 | "about 15", "about 17" | v10 (5) + v11 (10) [+ v12 (2)] |
| README_v14 §7.6 | 26 | 17 + v13 (3) + v14 (6) |
| README_v16 §2 | 39 unique cases, 58 rows | registry v10–v15, all rows |
| README_v16 §C7 | "project total 35" | inconsistent with its own §2. Logged as a conflict |
| README_v17 §6.2, §6.8 | "39 … across v10–v17" | **Stale.** It reuses the v16 number (v10–v15). Registry v10–v17 = 49 cases |
| Top-level README | 67 cases / 108 rows | **Correct** for v9–v17 |

**Decision proposed:** the paper uses 67 / 108 (the widest, most conservative count). It also mentions that 49 of these are from v10 onward.

## 3. How M1 survives project-wide correction

M1 primary vs the best calibrated rule (Context table): raw two-sided Wilcoxon p = 9.06 × 10⁻¹³ (`fill_summary_v17.txt` REPLCMP L111). The within-case Holm p is the same.

| Correction family | Factor | Adjusted p | Survives α = 0.05? |
|---|---|---|---|
| Within case (Holm over 9) | (pre-registered) | 9.06 × 10⁻¹³ | yes |
| Bonferroni over cases | × 67 | 6.1 × 10⁻¹¹ | yes |
| Bonferroni over scheme evaluations | × 108 | 9.8 × 10⁻¹¹ | yes |
| Bonferroni over every test ever run | × 972 | 8.8 × 10⁻¹⁰ | yes |

The CI criterion was also checked at the strictest level. The 90 % CI [1.23, 1.94] implies SE ≈ 0.216 pp (z ≈ 7.3). The two-sided critical z at α = 0.05/972 is 4.05. The Bonferroni-level lower bound is therefore ≈ +0.71 % > 0. This uses a normal approximation, so the paper should label it as approximate.

M1 vs Fixed (+1.87 %, p = 6.74 × 10⁻¹⁷) survives by a wider margin.

**Caveat for the paper:** a test on paired per-trace differences treats the 500 traces as the unit. It conditions on the 10 trained policies (the seed mean). It does **not** cover training-seed variance. Seed-level evidence is separate: 9 of 10 seed means exceed the best rule. A one-sided sign test on that gives p ≈ 0.011. With 10 seeds this is weak but positive. See `gaps.md` G3.

## 4. How the other wins are framed

| Result | Framing | Reason |
|---|---|---|
| **M1** (v17, RTT 8) | Sole primary confirmatory claim | Pre-registered primary; survives all corrections above |
| **M2** (v17, RTT 0) | Replication, not a standalone claim | p = 0.0167 vs Context does **not** survive ×67 (→ 1.12). It replicates v13 X2, v14 Y0 and v16 K2 |
| v14 Y0_base | Earlier pre-registered confirmation (RTT 0) | Valid, but run under delivered-throughput PF averaging (see `conflicts.md` C5) |
| v16 K2 | Replication (RTT 0) | Same PF caveat |
| v13 X2 | Exploratory secondary that motivated v14 | Not pre-registered as primary; shaping confounded with seeds and traces |
| v13 X1 per-seed mean | Not a win claim | The pre-registered primary scheme was the ensemble, which failed. The registry row shows win = 1 for the per-seed mean, so it must not be quoted as a pre-registered win |
| v10 E4c | Exploratory, superseded by v12 | Evaluation traces overlapped the motivating run; failed Claim B on fresh traces only |
| v10 E5_mixed_nofeat | Exploratory ablation | WIN without the cue; never replicated. Report it in the registry table only |
| v14 Y0_noshape, Y1 ensemble | Secondary | Y0_noshape matters for the shaping discussion (unshaped also won) |
| v16 K1 offset, L1 | Superseded | PF artefact |

**"Replication count" wording.** The v17 README calls M2 the "fourth replication" (X2 → Y0 → K2 → M2). The top-level README instead lists "v10 E4c, v13 X1, v14 Y0, v16 K2", which is wrong: X1 failed, and E4c is exploratory. The paper should say: *"the RTT-0 deadline gain over all comparators has now been observed in four separately seeded campaigns (v13 X2, v14 Y0, v16 K2, v17 M2). Only the last uses the transmission-time PF average, and only v14 Y0 and v17 M2 were pre-registered as primary or confirmatory."*

## 5. Garden of forking paths: what can honestly be said

- 17 code versions. Many recipe changes (action space, reward, shaping, aggregator, training length) were chosen *after* earlier results were seen. They were not chosen on the evaluation traces of the round that tested them.
- From v12 onward each round was pre-registered, on fresh seeds and traces, with no re-tuning after results.
- The final recipe (residual + shaping + per-seed mean + 3000 episodes) was **selected over the course of the campaign**. M1 is a confirmatory test of that selected recipe on fresh data, not of a recipe fixed at v1. The paper must say this plainly.
