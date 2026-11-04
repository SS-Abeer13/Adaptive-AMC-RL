# Contributions, novelty statement, and corrective-history placement

## 1. Contribution list (four items, approved at Checkpoint 4)

**C1. Evaluation protocol and open artefacts.**
- *What:* a pre-registered evaluation of deep RL link adaptation against nine comparators. Comparators are calibrated on traces disjoint from evaluation; the calibrated ones are built on the learner's cues (information table).
- *Statistics:* CRN; paired Wilcoxon + Holm + a CI bound; Claim A/B/WIN rules fixed before each run.
- *Artefacts:* a public registry of 67 cases and 108 scheme evaluations, with project-wide multiplicity reported; code, data summaries, pre-registrations and registry released (DOI at submission).
- *Evidence:* P01–P04, M01–M06, R32, R33. *Literature contrast:* 0 of 23 learning-LA studies compare against a calibrated rule (lit_matrix).

**C2. A positive result that survives the protocol: deadline traffic under realistic downlink HARQ.** *(Wording conditional on G6; see the rule below.)*
- *Setting:* RTT 8, 8 processes, PF averaged at scheduling time.
- *Result:* residual A2C beats every comparator by **+1.58 %** vs the best rule [1.23, 1.94], Holm 9.06e-13 (R03); +0.95 pp absolute (R34).
- *Robustness:* hierarchical 95 % CI [+0.62, +2.62] % (G3a); 9/10 seeds (R09); Bonferroni over 972 tests (M04); no fairness or goodput cost (R12, R13); training-limited (R25, G3d).
- **Seed-level condition (added at Checkpoint 5; `common_rules.md` R2):** if a claim passes at trace level but its hierarchical 95 % lower bound is ≤ 0, it is stated with "not robust to seed resampling". For M1 vs Context and vs Fixed all seed-level lower bounds are > 0 (+0.72, +0.48, +0.62 vs Context; ledger G3g, G3h), so no qualifier applies at present.
- **Conditional wording rule (frozen in `proposals/G6_calibration_budget_prereg.md` §4):**
  - If M1 also beats the **combined comparator** (slack × class × busy HARQ processes) on Holm plus the 90 % CI lower bound, C2 reads "beats all calibrated comparators", and "same-information" may be used.
  - If not, C2 reads **"beats the OLLA family and the single-cue calibrated rules"**, and the combined table is reported as matching RL.
  - G6's re-calibrated single-cue rules apply the same logic to Claim B.

**C3. Where RL does not help, under the same protocol.**
- *Goodput:* no gain (−0.88 % / −1.73 % vs Fixed; R19–R20). The residual policy is bit-identical to its base rule at RTT 8 (R19a).
- *RTT 0 deadline:* marginal, reported only as a replication across PF variants (G3e, S08b).
- *Headroom:* bounds (R26).

**C4. Pitfalls and recommendations.**
- *Pitfalls:* three simulation and design pitfalls that manufactured or masked RL gains, with diagnosis and fix: mobility time scale (H01–H04), slot stealing under a shared per-user reward (H07), and PF-average timing under multi-process HARQ (H17, R30). Plus the PF-definition sign flip as a protocol-sensitivity example (S08a, R22).
- *Recommendations:*
  - same-cue calibrated comparators, CRN and disjoint splits;
  - seed-level intervals and a case registry;
  - results reported by mobility regime, HARQ timing **and observation set**. Our information table applies this; LOLLA's Table V(a) observation ablation is cited as a neutral example.
  - complexity reporting (S16).

## 2. Novelty statement (one paragraph, for the Introduction and the cover letter)

> Prior learned link-adaptation schemes report large gains over OLLA. These include bandit methods (Saxena et al., TWC 2022), DQN-based DRLLA (Ye et al., TVT 2023), deadline-aware Q-learning OLLA (Kela et al., EuCNC 2022), DRL with parallel HARQ on a software-radio testbed (You et al., 2026), and LOLLA, a residual DRL offset on the OLLA lookup table evaluated on a GPU-accelerated NR stack (Wang et al., TMC 2026). Their comparators are OLLA at default settings, the open-loop table, or other learners. Rules calibrated on the learner's own cues are not used. We do not question these results in their settings. We ask a different question: how much of a learned gain remains when the classical comparators are calibrated on the same cues, under realistic downlink HARQ timing and multi-user PF scheduling, with pre-registered decision rules and project-wide multiplicity control? The closest methodological precedent comes from optical networking, where tuned heuristics matched published RL results (Doherty et al., JOCN 2025). Our finding is more nuanced. Calibration accounts for most of the gain, yet a residual policy retains a statistically robust advantage for deadline traffic under realistic HARQ timing.

## 3. How to present the corrective history (concise, as self-correction)

| Element | Placement | Length |
|---|---|---|
| Mobility time-scale error, slot stealing, PF timing (C4) | **Section VII "Pitfalls and corrective findings"**: one paragraph each (symptom → diagnosis → fix → effect size), plus one summary table | ~1.2 pp |
| PF-definition sign flip (open-loop vs OLLA) | One paragraph in VII, framed as protocol sensitivity | 0.2 pp |
| "Results withdrawn or superseded during this study" | Subsection VII-D: a 5-row table (v7/v8 withdrawn; v10 E4c exploratory; v12 replication failed; v13 X1 failed; v15/v16 RTT > 0 superseded) with reasons | 0.3 pp |
| Pre-registrations, failed secondary predictions (C4 misses) | Results VI-A (one sentence) + Protocol V (where pre-registrations are archived) | 2 sentences |
| Full registry (108 rows) and per-version history | **Supplementary material** (CSV + PDF table), cited in V and VII | — |
| Multiplicity counts | Protocol V, approved paragraph (multiplicity.md §6) | 0.3 pp |

**Tone rule:** every corrective element is reported as a protocol outcome ("our registry records…", "the pre-registered test failed…"). Never "unfortunately" or "we mistakenly". Wording limits follow the pre-registrations: no "definitive", "proves" or "firmly".
