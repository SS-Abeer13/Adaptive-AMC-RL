# Exemplar study and structural template (top two venues: TMLCN, OJ-COMS)

Full texts come from arXiv versions; published page counts come from Crossref page ranges. Published IEEE PDFs could not be fetched (Xplore 418). Preprint figure and word counts are approximate.

## 1. Exemplars

| Venue | Paper | Pub. pages | Sections | Figs / tables / refs | Contribution statement | Baselines (tuned?) | Statistics | Reproducibility | Limitations |
|---|---|---|---|---|---|---|---|---|---|
| TMLCN 2024 | Robaglia et al., DRL UL scheduling NOMA-URLLC (strict deadlines) | 17 | Intro · System model · Problem formulation · DRL approach · Experiments · Conclusion | 6 / 3 / ~64 | Bulleted "Our contributions" in the Intro | Random, grant-free SA-NOMA-SIC, BDQ, iDRQN (not tuned) | Not stated | Not stated | In conclusion / future work |
| TMLCN 2024 | Jadoon et al., MARL random access | 15 | Intro · Related work · System model & formulation · Traffic models · Suitability of MARL · RL env & algorithms · Results & discussion · Conclusion & future work | ~10 / 0 / ~51 | Bulleted list | BEB backoff (standard) | "3 random seeds … best performances shown" | Not stated | Brief, in conclusion |
| TMLCN 2025 | Baur et al., evaluation metrics for generative PHY models | 13 | Intro · Preliminaries · Evaluation metrics & methods · Evaluation on real data · Concluding remarks & future work | ~9 / 0 / ~46 | Evaluation framework stated as the contribution | Several generative models compared | Metric-based | Real measurement data | "Future work" section |
| TMLCN 2024 | Raca et al., throughput prediction: lessons from a real-world evaluation (abstract only) | 17 | — | — | **Lessons/challenges as contributions** | — | — | — | — |
| OJ-COMS 2026 | Ahsen et al., MO-OLLA (XR tethering groups) | 13 | Intro · System model · LA for TGr · Performance evaluation (A. Evaluation methodology) · Conclusion | 8 / 1 / ~36 | Bulleted "main contributions" | Conventional single-offset OLLA; ideal-link upper bound | 3GPP-aligned SLS; not stated | Not stated | In text |
| OJ-COMS 2021 | Bayerlein et al., multi-UAV DRL path planning | 17 | Intro · System model · … · Simulations · Conclusion | 7 / 4 / ~42 | Bulleted list | Architecture variants | Monte Carlo, 1,000 scenarios; averages and 99 % quantiles | **Code on GitHub** | Future-work paragraph |
| OJ-COMS 2025 | Parsa et al., QoS-aware DRL LA (abstract only) | 15 | — | — | — | "conventional heuristic-based methods" | — | — | — |

## 2. What the exemplars teach

1. **Length:** 13–17 published pages is normal in both venues. Neither imposes a page limit. **Target: 14–16 pages of main text plus appendices**, with the registry and extra tables in the supplement.
2. **Shape:** a classic IEEE transactions structure. Intro with a **bulleted contribution list on page 1**, system model, formulation, method, evaluation, conclusion. Related work is either a separate section (Jadoon) or folded into the Intro (Robaglia, Ahsen).
3. **Evaluation-led papers are acceptable in TMLCN.** Raca and Baur present a framework or lessons as the contribution. That is the slot for framing (A/C).
4. **Rigour bar:** statistics are light in all exemplars (no tests, few seeds). Our protocol will be a differentiator. It must be explained compactly (one "Evaluation protocol" section), or reviewers used to lighter papers will find it heavy.
5. **Figures:** 6–10 figures and 0–4 tables. That matches the plan of about 8 figures and 5 tables.
6. **Reproducibility statements are rare.** A code/data availability paragraph plus a release DOI will stand out positively, especially at TMLCN, which advocates artefact sharing.

## 3. Structural template for our paper (TMLCN primary; also valid for OJ-COMS)

| # | Section | Pages | Content (ledger links) |
|---|---|---|---|
| — | Abstract | ~0.3 | Scope sentence; thesis (large gains vs OLLA, small vs same-information calibrated rules; survives only for deadline traffic under RTT 8 with a residual policy; none on goodput); effect sizes with CIs; protocol (pre-registered, 67 cases) |
| I | Introduction | 1.5 | Motivation; the comparator gap (literature counts: 0 of 23 learning-LA papers compare with calibrated same-information rules); **bulleted contributions**; thesis figure |
| II | Related work | 1.0 | Classical LA/OLLA tuning; learned LA (LOLLA, You 2026, Saxena, Ye, Kela, Parsa); evaluation rigour (Doherty JOCN 2025, Ferrari Dacrema, McGreivy, Mangal, Henderson, Agarwal) |
| III | System model | 2.0 | Cell, channel, CQI delay/noise, HARQ (RTT 0 / RTT 8 × 8 processes), **PF averaging definition**, traffic, metrics (S01–S16) |
| IV | Problem formulation and learning method | 1.5 | MDP; offset vs residual action; on-time reward with potential shaping; shared A2C; complexity (S13–S16) |
| V | Evaluation protocol | 1.5 | Comparators and calibration (incl. same-information Context table); CRN; disjoint splits; pre-registration; decision rules (Claim A/B/WIN); fairness guard; headroom bounds; multiplicity (P01–P04, M01–M06) |
| VI | Results | 3.5 | A: deadline RTT 8 (M1, R01–R15, G3a–b); B: RTT 0 replication (M2, G3e); C: goodput negative (M3/M4, R19–R22); D: training length (R25, G3d); E: headroom (R26–R27); F: fairness (R12); G: policy behaviour (**after G1**) |
| VII | Pitfalls and corrective findings | 1.5 | Mobility time scale; slot stealing; PF timing under multi-process HARQ; PF-definition sign flip (H01–H07, H17, S08a); results by mobility regime (LOLLA tie-in, neutral wording) |
| VIII | Discussion and limitations | 1.0 | When RL helps; deployment; threats to validity; limitations (G11–G17) |
| IX | Conclusion | 0.3 | — |
| — | Availability, AI disclosure, acknowledgments | 0.2 | Code/data DOI; pre-registrations; IEEE AI-disclosure in acknowledgments |
| App. | Appendices | 1–2 | Hyper-parameters; full comparator tables; superseded-results subsection; supplement: registry (108 rows) |

**Total main text ≈ 14–15 pages.** That is within the exemplar range for both venues. A TWC version would need cutting to 13 pages at submission, by moving pitfalls to the appendix and the per-case tables to the supplement.
