# Amendment 14: FT seed ranges (supersedes §3 seed ranges of `FT_fresh_trace_prereg.md`)

Status: to be frozen (hashed in `FREEZE.sha256`) **before any FT trace is generated**.
Author: SS-Abeer13. Date: 25 Nov 2026.

## 1. Reason

The disjointness assertion required by §3 of `FT_fresh_trace_prereg.md` (frozen in Amendment 13, `4ec1d23`) failed before any FT trace was generated. Two of the three frozen ranges overlap ranges used by R1c in the G2 cell (`stage_r1c.m`, lines 91–92):
- the FT CRN range `4100000 + j`;
- the FT decision-draw range `4200000 + 100 j + s`.

The check worked as intended. **No FT trace, CRN stream or decision draw has been generated, and no FT result exists.**

## 2. Change

Only the three seed ranges in §3 are replaced:

| Stream | Amendment 13 (void) | Amendment 14 (in force) | Span |
|---|---|---|---|
| Evaluation traces | `rng(4000000 + j)` | `rng(7000000 + j)`, j = 1…500 | 7,000,001–7,000,500 |
| CRN | `rng(4100000 + j)` | `rng(7100000 + j)`, j = 1…500 | 7,100,001–7,100,500 |
| Decision draws | `rng(4200000 + 100 j + s)` | `rng(7200000 + 100 j + s)`, s = scheme index ≤ 99 | 7,200,101–7,250,099 |

The three new ranges are disjoint from each other and lie above every range in use (the largest is 4,603,500).

## 3. Unchanged

Everything else in `FT_fresh_trace_prereg.md` stands exactly as frozen:
- the objects and their hashes (`FT_objects.sha256`);
- the scenario and environment, the evaluator and the accounting modes;
- the comparisons, the symmetric decision rule, the bootstrap, the families and the verdicts;
- the wording rows;
- S-SYM, T-GBT and the multiplicity;
- the compute and stop rules;
- `paper/analysis/ft_stats.py`.

## 4. Strengthened check

The disjointness assertion is widened as follows:
- **Scope:** every `rng(` and `randi`/`RandStream` seed expression in **all** `.m` and `.py` files under `Optimized/`, including `v17/`, `v17x/` and every older version folder, and in the recorded seed ranges of `case_registry.csv`.
- **Report:** the full list of occupied ranges.
- **Failure:** any overlap with the three ranges above stops the stage, as before.
