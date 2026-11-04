# Venue decision (Phase 3, for Checkpoint 3)

Scores run from 1 (poor) to 5 (good). "Novelty bar" scores 5 when the bar is reachable for an evaluation-led paper with one positive case. "OA cost" scores 5 when there is no mandatory fee. Evidence is in `venue_research.md` and `exemplar_template.md`.

| Criterion (weight) | TMLCN | OJ-COMS | TWC | TVT | TCOM | WCL (letter) | IEEE Access | TMLR |
|---|---|---|---|---|---|---|---|---|
| Scope fit for an evaluation-heavy RL-for-LA paper (×3) | **5**: ML methods + "performance analysis and evaluation of ML techniques"; publishes evaluation/lessons papers | 4: broad; ML listed; LA/OLLA papers published | 3: wireless-centred ✓, but method-novelty culture | 3: home of DRL-LA (Ye 2023, Ku 2024, Lin 2026) | 3 (policies unverified) | 2: pitfalls note only | 3 | 2: ML audience |
| Novelty bar vs our position (×3) | 4 | 4 | 2 | 3 | 2 | 4 | 5 | 4 ("correctness over significance") |
| Length fit, 14–15 pp + appendix (×2) | 5: no stated limit; exemplars 13–17 pp | 5: no page limit | 2: 13 pp at submission; $220/page beyond 10 | 2: 10 pp + $220/page | ? | 1 | 4 | 4 |
| Time to decision (×1) | 3: not stated | **5: 2-week review target** | 3 | 3 | 3 | 4 | 4 | 4 |
| OA cost (×1) | 2: $2,160 mandatory | 2: $2,160 mandatory | 4: hybrid; overlength fees likely (~$1k) | 4: overlength fees | ? | 4 | 2: $2,160 | 5: free |
| Policy fit: code/data, preprint, AI (×2) | **5**: advocates artefact sharing | 4: code encouraged | 3: preprint OK; no code policy | 3 | ? | 3 | 3 | 4 |
| Acceptance of evaluation / negative-leaning results (×2) | 4 | 3 | 2 | 2 | 2 | 3 | 4 | 4 |
| Prestige / visibility to the LA community (×1) | 3: young; first IF 2026 | 3 | **5** | 4 | 5 | 3 | 2 | 2 (wrong community) |
| **Weighted total (max 75)** | **63** | **58** | 41 | 43 | — (incomplete) | 43 | 54 | 53 |

## Recommendation

- **Primary: IEEE TMLCN.** It is the best scope match for a paper whose main contribution is *how* learned LA should be evaluated, with a real positive case. It accepts lessons/evaluation papers and explicitly values artefact sharing, which our registry, pre-registrations and release make concrete. It has no page squeeze and no LA competitor in 2024–2026. Risk: TMLCN reviewers may want more ML-method depth. The residual and shaping design and the G3 statistics answer that.
- **Backup 1: IEEE OJ-COMS.** Same format and APC, no page limit, a 2-week review target, and it already publishes LA/OLLA work (Ahsen 2026, Parsa 2025, Pivoto 2026). The switch costs almost nothing.
- **Backup 2: IEEE TVT.** It is the most frequent journal for DRL-LA (Ye 2023, Ku 2024, Lin 2026), so its reviewers know the topic. It needs cutting to about 12 pages (the pitfalls move to an appendix) and overlength fees.
- **Stretch option (author's choice): IEEE TWC.** It offers the highest prestige. It requires 13 pages and a method-novelty argument, which is weak after LOLLA. I advise against it as primary.
- **Fallback:** IEEE Access.

## Letter-length spin-off option

**Candidate:** a WCL letter (≤ 5 pp), "Scheduler-timing and mobility pitfalls that manufacture gains in learned link adaptation": PF-average timing under multi-process HARQ (+~40 % for every scheme; H17) and the mobility time-scale error (H01–H03).

**Assessment: do not submit before the main paper.** The pitfalls are one of the main paper's contributions. A prior letter would split the contribution and invite an overlap check. If wanted, write it *after* the main paper is accepted, as a short practitioner note citing it, or fold it into the main paper only (my recommendation).

## Changes to the novelty position from the IEEE pass

1. **New close paper: Parsa, Moghim & Shetty, IEEE OJ-COMS 2025, "QoS-aware link adaptation … DRL" (QDRLLA).** This is DRL-LA with application-specific QoS (XR/VR latency/reliability). Abstract level only; baselines described as "conventional heuristic-based methods", with calibration not described. It overlaps the "latency-aware DRL-LA" angle (as Kela 2022 does). It is **not closer than LOLLA on method, and not closer on evaluation protocol**. Add it to related work.
2. **Pivoto et al., OJ-COMS 2026** use a contextual bandit *to calibrate* service-specific SNR-to-MCS tables. This is learning used for calibration, which supports our choice of calibrated tables as comparators.
3. **Jin et al., TWC 2024 (RAMC)** is model-based (Lyapunov/MDP) retransmission-aware AMC under deterministic delay. It is the classical counterpart of our deadline + HARQ case. Cite it.
4. **Corrections to Checkpoint 2:**
   - Ahsen et al. **is** published in **IEEE OJ-COMS** (2026, 7:8362–8374).
   - "Hype or Hope?" **is** published in **JOCN 17(9):D1 (2025)** with **5 authors** (Doherty, Matzner, Sadeghi, Bayvel, Beghelli).
   - LOLLA is at arXiv **v1** and in IEEE TMC.
5. **Counts now back the comparator-gap claim.** Of **23** learning-based LA papers assessed: calibrated-rule baseline **0 yes / 3 partial / 13 no / 7 unclear**; information parity **5 yes / 1 partial / 3 no / 14 unclear**. **No paper has both.** Of the 7 read in full text, **0** compare against a calibrated rule. Proposed wording: *"Of 23 learning-based LA studies we reviewed, none compared against a rule calibrated on the same information as the learner; three varied OLLA's step or target over a few settings."* The "unclear" cells come from abstract-only reading and must be reported as such.
6. **No paper closer than LOLLA** was found on (a) RL vs calibrated rules or (b) deadline-aware RL-LA under realistic downlink HARQ. Limit: no Xplore full-text access. The Crossref venue scan covers titles and metadata only.
