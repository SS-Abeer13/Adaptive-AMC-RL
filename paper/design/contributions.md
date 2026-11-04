# Contributions, novelty statement, and corrective-history placement

## 1. Contribution list (each tied to ledger claims)

**C1. A pre-registered evaluation of deep-RL link adaptation against calibrated comparators that include the learner's cues.**
- *What:* 9 comparators (OLLA family, Fixed, FixedPU, Context table, bandits), calibrated on traces disjoint from evaluation, with CRN.
- *Rules:* paired Wilcoxon + Holm + a CI bound; Claim A/B/WIN rules fixed before each run.
- *Multiplicity:* a public registry of 67 cases and 108 scheme evaluations; project-wide multiplicity reported.
- *Evidence:* P01–P04, M01–M06, R33 ("calibration captures 83–86 % of the gain over OLLA").
- *Literature contrast:* 0 of 23 learning-LA studies compare against a calibrated rule (lit_matrix).

**C2. A positive result that survives the protocol: deadline traffic under realistic downlink HARQ.**
- *Setting:* RTT 8 with 8 processes, PF averaged at scheduling time.
- *Result:* residual A2C beats every comparator: **+1.58 %** vs the best rule [1.23, 1.94], Holm 9.06e-13 (R03); +1.87 % vs Fixed (R04); +11.96 % vs tuned OLLA (R06).
- *Robustness:* hierarchical seed × trace 95 % CI [+0.62, +2.62] % (G3a); 9/10 seeds above the best rule (R09); survives Bonferroni over 972 tests (M04); no fairness cost (R12); no goodput cost (R13).
- *Training:* training-limited at 800 episodes (R25), with the 800-episode win fragile (G3d).

**C3. Where RL does not help, under the same protocol.**
- *Goodput:* no gain on full-buffer goodput at RTT 0 or RTT 8 (−0.88 % / −1.73 % vs Fixed; R19–R20). The residual policy is bit-identical to its base rule in all 5,000 seed × trace cells at RTT 8 (R19a).
- *RTT 0 deadline:* the gain is small (+0.43 % vs Context, hierarchical 95 % CI [−0.03, +0.87]; G3e). It is reported only as a replication of earlier campaigns run under another PF variant (S08b).
- *Headroom:* static per-trace hindsight bounds (R26) show how little room a static rule leaves.

**C4. Three simulation and design pitfalls that manufactured or masked RL gains, with diagnosis and fix.**
1. A mobility time-scale error (v metres per TTI): a +12.8 % gain that vanished when fixed (H01–H04).
2. Slot stealing under a shared per-user reward: a bimodal policy at 1.38 vs 2.92 Mbps, removed by an opportunity-cost reward (H07).
3. PF-average timing under multi-process HARQ: updating with ACKed bits at t + RTT inflated *every* scheme by ~40 % and cut fairness (H17, R30).

Plus a protocol-sensitivity example: the sign of "open-loop vs OLLA" flips with the PF averaging definition (S08a, R22).

**C5. Practical guidance and open artefacts.**
- *Reporting checklist:* calibrated same-cue comparators, CRN, disjoint splits, seed-level intervals, results by mobility regime and HARQ timing, a registry of all cases.
- *Cost:* inference complexity of ~20 k parameters and ~20 k MACs per decision (S16).
- *Artefacts:* code, data summaries, pre-registrations and registry released (R32; DOI at submission).

*(C5 can merge into C1 if a 4-item list reads better on page 1.)*

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
