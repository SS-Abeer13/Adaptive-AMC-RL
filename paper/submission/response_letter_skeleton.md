# Response to the reviewers — skeleton

**Manuscript:** "Is Reinforcement Learning Necessary for Link Adaptation? A Pre-Registered Comparison with Calibrated Rules and Supervised Learning" — [Manuscript ID]

We thank the Editor and the reviewers. Below, reviewer comments are quoted in *italics*, our responses follow, and every change is given with its location in the revised manuscript (changes are marked in blue in the marked-up version).

Conventions:
- **R#.C#** = reviewer number, comment number.
- New numbers are generated from the released result files, like all others in the paper.
- New runs are listed with their pre-registration file and freeze hash.

---

## Summary of main changes
1. [ ... ]
2. [ ... ]

## Prepared responses to likely concerns (internal simulated review of the reframed draft, `paper/review/review_v12_*.md`)
These are drafts; adapt them to the actual comments. "Done" means the change is already in the submitted version.

| Likely concern | Draft response | Location / status |
|---|---|---|
| Headline −7.58 % mixes learning method with a larger action set | Matched on both sides: the learner restricted to the RL action set (GBT-res-ACK, −3.40 %, hierarchical CI [−4.43, −2.47] %), and the RL policy given the learner's full action set (R6, −7.27 % to −9.54 % against the four draws). Both say the same: the supervised learner beats RL at both action sets. | Abstract, Sec. I, VII intro and VII-D, IX-A, Conclusion; done |
| No RL policy with the larger action set | Run before submission as R6 (Amendment 11, Freeze v13): the NR2 recipe with the residual step widened to −2…+4 (offsets −4…+2, the action set of GBT-full-ACK), 10 fresh seeds. Pre-registered verdict: "the supervised learner beats RL at both action sets". RL-full (0.6222 on time) loses to all four GBT-full-ACK draws (−7.27 % to −9.54 %, every hierarchical CI below zero, 0/10 seeds ahead) and to all four GBT-res-ACK draws (−2.77 % to −4.30 %). It used the wider set (38.5 % of decisions outside ±1) but gained only +0.33 % over NR2 (not robust across seeds); it still beats the combined table (+3.69 %, 10/10 seeds). | Abstract, Sec. I, VII-D (Table IX), VII (Table VII), IX-A, Table X, Conclusion; done |
| RL under-tuned / conservatism prior / budgets not matched | Stated: one hyper-parameter set, logit bias and deviation penalty, on-policy 3000 episodes; GBT fitted offline to exploration logs. [Planned: table of training decisions, non-default-action share, simulation time and compute for both learners.] | Sec. VII intro, IX limitations; [table] |
| Sequence of amendments; headline chosen after the fact | New paragraph "Status and sequence" (R1 after NR2 and HR1; R1b after R1; R1c after R1b; reframing after R1b; R1c is the confirmatory test); Sec. V-D updated; freeze and run times in Supplement S3. | Sec. V-D, VII intro, S3; done |
| R1c fit 1 is the R1b draw; evaluation traces reused | Stated explicitly: M1 replication = the R1b draw plus three new draws, all on the NR2 traces; cells use the G10 traces. [Optional run: evaluate the frozen R1c fits and NR2 on fresh M1 traces.] | Sec. VII-C, VII intro; done / [run] |
| No inferential quantities for R1c | Per-fit margins, 90 % CIs, hierarchical CIs and Holm p are in Supplement S2 (`r1c_fits.csv`, `r1c_rules.csv`); referenced from Table VIII and Table IX. [Optional: between-fit interval.] | Tables VIII, IX; S2; done |
| "Match" is not an equivalence test | Stated next to the R1c result; every fit beat RL ("no fit merely matched"). The designed rules are now "not distinguishable from" the combined table. | Sec. VI-D5, VII-C; done |
| Project-wide correction for the headline | Added: NR2 vs GBT-res-ACK / GBT-full-ACK keep p = 1.9e−38 / 4.4e−60, and RL-full vs GBT-full-ACK p = 1.9e−63, after the factor 1 820 (106 cases / 182 scheme evaluations); the 10-per-evaluation upper bound is explained. R1, R1b, R1c and R6 are ledger rows PS-R1R2, R1b, R1c, R6. | Sec. V-D, VII intro; done |
| Deviation D1 timing and detection; Amendment 5 lists 16 000 bits | D1 was recorded with Amendment 9, before Amendment 10a, which specified the corrected evaluation. How D1 was found is stated, and that a symmetric configuration audit is not documented. The NR-G10 text lists 16 000 bits for G2, whereas G10/NR-G10 ran at 14 000; the correction follows the run environment. [Recommended: document a field-by-field configuration audit of every stage.] | Sec. VII intro, IX limitation D1; done / [audit] |
| NR-G10 "frozen before any of its data existed" | Corrected: policies fresh, evaluation traces and comparator results reused from G10. | Sec. V-D; done |
| "Same cues" for the combined table | Corrected: the strongest table also uses the true speed class. | Abstract, IX-A; done |
| Abstract mixes M1 and NR2 policies | The OLLA gain is now attributed to the pre-registered oracle-base policy. | Abstract; done |
| Goodput "adds nothing" understates | Now "does worse than one calibrated offset (−0.88 %)". | Abstract; done |
| Near one-shot operating points favour a myopic learner | Stated: with a 10-TTI budget and RTT 8 at most one retransmission fits. [Planned: R1b at M2–M4 and at a longer deadline; under the 200-TTI warm-up.] | Sec. VII-E, IX limitations, Conclusion; [runs] |
| Exploration cost; "deployable" | "Deployable" removed. [Planned: KPIs of the ε-greedy logging policy; sweep of ε and log size, including ε = 0.] | Sec. VII-B, IX limitation; [runs] |
| gNB-observable features, label errors | Limitation added (reported SINR as produced by the simulator; perfect ACK/NACK). [Planned: CQI-index-only features; ACK/NACK error/DTX sensitivity.] | IX limitations; [runs] |
| BLER and fairness of the ACK learners | BLER now given for the ACK learners and the combined table; the fairness claim is limited to the Jain index; no claim about tail users. [Planned: edge5 guard, speed breakdown for GBT-ACK.] | Sec. VII-D; done / [analysis] |
| Cost and placement of the winning learner | [Planned: tree count, depth, per-decision cost and A3c-style timing for GBT-res-ACK / GBT-full-ACK.] | Sec. IX-C/D; [ ] |
| Bandit comparators very weak (41.8 % on time) | [Explain the configuration of the two bandits and why they degenerate; relate the one-step learner to contextual bandits (Sec. II-B).] | [ ] |
| ACK labels beat true-SINR labels | Reported as an observation, confounded with the logging policy. An exploratory diagnostic (R6b: a true-SINR model on the same exploration logs) was inconclusive; a diagnosis (`Optimized/v17x/Dataset/presub/r6/R6b_diagnosis.md`) ruled out pipeline errors but did not explain the result. Not reported; left for future work. | Sec. VII-B, VII-D; done |
| HR1 is not an upper bound | Stated: the realised gains of the ACK learners over the combined table are at least the one-step estimates. | Sec. VII-E; done |
| Release placeholder | Zenodo DOI inserted at submission: [DOI]; includes GBT models and exploration logs. | Availability statement |

---

## Reviewer 1
**R1.C1** *[quote]*
Response: [ ]
Change: [section, page, line]

## Reviewer 2
**R2.C1** *[quote]*
Response: [ ]

## Reviewer 3
**R3.C1** *[quote]*
Response: [ ]

---
*Wording rules for responses: no "definitive", "proves", "conclusively", "firmly refutes"; mechanisms are "consistent with"; failed predictions and superseded results are reported, not hidden.*
