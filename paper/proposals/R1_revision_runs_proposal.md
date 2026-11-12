# Proposal: runs and analyses suggested by the simulated review (draft v10)

Status: **proposal only, nothing run, nothing frozen.** Written 2026-11-12 after the four-reviewer simulated review (paper/review/). Text-only fixes were applied to the manuscript in the same round; the items below need data and must be pre-registered before they run.

| # | Item | Reviewers | Cost | Type | Why |
|---|---|---|---|---|---|
| R1 | **GBT one-step policy as a comparator.** Deploy the HR1 gbt_a predictor (trained on M1 calibration-trace logs only, not on evaluation traces) as a scheme in M1 and NR2 traces; same CRN. | alfa, bravo, charlie | low (no RL training; one evaluation pass) | new run, pre-register | Separates "learning a policy with RL" from "more information on the same features". Main attribution gap. |
| R2 | **Hand-written rule** on the Fixed base: δ=+1 if busy≥1 or slack≤0.6 or burst, else 0; plus a calibrated version (thresholds searched on calibration traces). | bravo | low | new run, pre-register | Cheapest test of "learned vs designed". |
| R3 | **NR2 diagnostics from logged data**: speed breakdown vs combined table, warm-up comparison, Jain/edge5, action analysis. | all four | none (logged) | analysis, pre-register wording | Recommended policy currently has fewer diagnostics than the original. |
| R4 | **Seed-level re-analysis**: t / BCa interval on per-seed means, permutation test, power for n=10 and n=5; align R1/R2 levels as a sensitivity (decision rules unchanged). | alfa, charlie | none | analysis | Cluster-bootstrap coverage with 10 (5) clusters. |
| R5 | **More seeds** for NR2 (+10) and NR-G10 (+5 per cell) on fresh seeds, same traces. | alfa, charlie | ~3–6 h | new run | Seed evidence for the recommendation. |
| R6 | **Component ablation** of the non-oracle recipe: no frame stacking; no HARQ features; no logit bias; no deviation penalty; no shaping (one at a time, 10 seeds). | bravo, charlie | ~15 h | new run | Which part does the work. |
| R7 | **Combined-table robustness**: wider offset range than [−4,+2] where cells sit at the boundary; more starts to convergence; a non-oracle combined table (no speed class) for NR2. | charlie, delta | ~25–50 h | new run | Comparator strength and information match. |
| R8 | **Second environment**: replicate NR2 vs combined table vs OLLA in sionna_env with link-level BLER. | alfa, charlie, delta | large | new run | External validity. |
| R9 | **Timing of the recommended policy** (ONNX/C, per-slot loop incl. state construction), ideally inside an OAI MAC process. | delta | medium | new measurement | Placement/latency for the venue. |
| R10 | **Ensemble as a scheme**: several disjoint 5-seed ensembles for a seed-level interval. | alfa | ~3 h | new run | Estimand question. |

Suggested order if one round is allowed before submission: R3 + R4 (no compute) → R1 + R2 (cheap, highest attribution value) → R5. R6–R10 belong to a revision.

Text-only fixes already applied (v10 → v10b): abstract HR1 sentence made non-causal; the 4.6e-27 trace-level p-value removed from the contributions and qualified in Sec. V-D; confirmatory status of the non-oracle recipe limited to NR2/NR-G10; "58 %" decomposed (combined table vs re-calibration); single-policy estimand stated with the ensemble value; headroom recommendation softened to a necessary-condition check; limitations on percentile cluster-bootstrap coverage and on the missing non-RL learned control; stage codes added to the terms table.
