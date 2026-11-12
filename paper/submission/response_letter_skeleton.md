# Response to the reviewers — skeleton

**Manuscript:** "When Does Deep Reinforcement Learning Help Link Adaptation? A Pre-Registered Evaluation Against Calibrated Rules" — [Manuscript ID]

We thank the Editor and the reviewers. Below, reviewer comments are quoted in *italics*, our responses follow, and every change is given with its location in the revised manuscript (changes are marked in blue in the marked-up version).

Conventions:
- **R#.C#** = reviewer number, comment number.
- New numbers are generated from the released result files, like all others in the paper.
- New runs are listed with their pre-registration file and freeze hash.

---

## Summary of main changes
1. [ ... ]
2. [ ... ]

## Prepared responses to likely concerns (from the internal simulated review, `paper/review/`)
These are drafts; adapt them to the actual comments.

| Likely concern | Draft response | Location / status |
|---|---|---|
| "Pre-registered/confirmatory" too strong | We now state that for the non-oracle recipe only NR2 and NR-G10 are confirmatory; M1 was confirmatory for the original recipe; NR1 was exploratory on M1 traces. | Sec. V-D; done in v10b |
| Trace-level p-values (10⁻²⁷) over-read | Removed from the contributions; qualified as conditional on the trained policies; seed-level intervals are primary. | Sec. I, V-D; done |
| HR1 over-interpreted | Abstract sentence made non-causal; headroom check recommended only as a necessary condition; HR1 does not explain the NR2 advantage (stated). | Abstract, Sec. I, VI-G, VII-E; done |
| No non-RL control on same features | [Planned R1/R2: GBT one-step policy and hand-written rule, pre-registered.] | `paper/proposals/R1_revision_runs_proposal.md` |
| Bandits degenerate / duplicate rows | [Explain the bandit result; report the number of distinct comparators; Holm family unchanged as pre-registered.] | [ ] |
| Cluster bootstrap with 10 seeds | Limitation added; [planned R4 seed-level t/BCa and power analysis]. | Sec. VIII-E; [ ] |
| "58 %" conflates re-calibration and richer table | Decomposed in the text (Context table alone: +1.58 → +1.43 %). | Sec. VIII-B; done |
| Ensemble result | Estimand stated as single-policy deployment; ensemble value reported. [Planned R10.] | Sec. VIII-B |
| NR2 diagnostics missing | [Planned R3 from logged data.] | [ ] |
| Single simulator, no link-level BLER | Limitation; [planned R8 in sionna_env]. | Sec. VIII-E |
| Latency of recommended policy, placement | FLOP count and A3c CDF with caveats; [planned R9 timing of the non-oracle policy, ideally in an OAI MAC]. | Sec. VIII-C/D |
| Release placeholder | Zenodo DOI inserted at submission: [DOI]. | Availability statement |

---

## Reviewer 1
**R1.C1** *[quote]*
Response: [ ]
Change: [section, page, line]

**R1.C2** *[quote]*
Response: [ ]

## Reviewer 2
**R2.C1** *[quote]*
Response: [ ]

## Reviewer 3
**R3.C1** *[quote]*
Response: [ ]

## Reviewer 4
**R4.C1** *[quote]*
Response: [ ]

---
*Wording rules for responses: no "definitive", "proves", "conclusively", "firmly refutes"; mechanisms are "consistent with"; failed predictions and superseded results are reported, not hidden.*
