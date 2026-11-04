# Audit of candidate references named in the project (§4.1) and the v8 reference list

Verified = record opened on Crossref (DOI registry) or the arXiv API, or on the publisher/record page named, on 2026-11-04. Details per entry are in `verification_report.csv`.

## A. Named candidates

| Candidate (as named) | What it actually is | Status | Key |
|---|---|---|---|
| "Park 2015" | S. Park, R. C. Daniels, R. W. Heath, "Optimizing the target error rate for link adaptation," **IEEE GLOBECOM 2015** (a conference paper, not a letter). DOI 10.1109/glocom.2015.7417770 | ✅ verified | `park2015targetbler` |
| "Durán 2015" | Á. Durán, M. Toril, F. Ruiz, A. Mendo, "Self-optimization algorithm for outer loop link adaptation in LTE," **IEEE Commun. Lett.** 19(11), 2015 | ✅ verified | `duran2015selfopt` |
| "Pang 2024" | G. Pang, L. You, L. Fu, "An efficient DRL-based link adaptation for cellular networks with low overhead," **IEEE WCNC 2024** (TD3 tunes OLLA parameters) | ✅ verified | `pang2024td3olla` |
| "LOLLA 2026" | R. Wang, L. Zhang, Q. Liu, K. Yang, "LOLLA: Deep RL for closed-loop link adaptation towards a GPU-accelerated AI-RAN," arXiv 2606.23110, and **IEEE Trans. Mobile Comput.** (DOI 10.1109/tmc.2026.3740957) | ✅ verified | `wang2026lolla` |
| Saxena et al. (bandit LA, journal version) | V. Saxena, H. Tullberg, J. Jaldén, "Reinforcement learning for efficient and tuning-free link adaptation," **IEEE Trans. Wireless Commun.** 21(2), 2022 | ✅ verified | `saxena2022tuningfree` (+ `saxena2019cmab`, `saxena2021lts`) |
| Ahsen et al. ("IEEE OJ-COMS; DOI unverified") | **CORRECTED 2026-11-04 (Phase 3):** published in **IEEE OJ-COMS** vol. 7, pp. 8362–8374, 2026, DOI 10.1109/ojcoms.2026.3714148, with arXiv 2604.20459 as the preprint. The Checkpoint-2 verdict "arXiv only" was wrong: the first Crossref search was filtered to titles and missed it. It is a *rank-dependent multi-offset* OLLA. The v17 code header cites it for "Multi-OLLA", but our Multi-OLLA (fast/slow integrator blend) is a **different method** | ✅ verified as a preprint; ⚠️ **mis-attributed in `evalPolicy_v17.m` L4** | `ahsen2026moolla` |

## B. v8 draft reference list (`papers/v8_draft/AMC_full_paper_v8_rev1_source.md`, refs [1]–[22])

| # | Reference | Finding |
|---|---|---|
| [2] | Pedersen et al., VTC 2007-Fall, "doi: 10.1109/VETECF.2007.380" | ❌ **Wrong DOI**: .380 resolves to "A QoS-Guarantee Resource Allocation Scheme in Multi-User MIMO-OFDM Systems". The correct DOI is **10.1109/vetecf.2007.378** |
| [3] | Bruno et al., VTC2014-Fall | ✅ DOI correct |
| [4] | Mota et al., Globecom Wkshps 2019, arXiv:1912.04030 | ✅ (arXiv verified; workshop DOI not found in Crossref, so cite via arXiv) |
| [5] | Saxena et al., IEEE TWC 2022 | ✅ |
| [6] | Pulliyakode & Kalyani, arXiv 2017 | ✅ |
| [7] | Wiesmayr et al., SALAD, arXiv 2025 | ✅ (now v2, Mar 2026) |
| [8] | Dahlman et al., *5G NR*, Academic Press 2018, "doi: 10.1016/C2016-0-04354-9" | ⚠️ That DOI is **not in Crossref**. Chapter DOIs use 10.1016/b978-0-12-814323-0.*. Cite by ISBN or not at all → `UNVERIFIED` |
| [9] | Ahsen et al., arXiv 2026 | ✅ now published in OJ-COMS 2026; but see A: it is not the Multi-OLLA we implement |
| [12] | 3GPP TR 38.901 V17.0.0 | ✅ exists; the current version is V19.5.0 |
| [13] | Wilcoxon 1945 | ✅ |
| [14] | Holm 1979 | ✅ via bibliographic records (JSTOR page did not load). **No DOI** (10.2307/4615733 is not registered) |
| [15] | Schuirmann 1987 | ✅ |
| [16] | Gudmundson 1991 | ✅ |
| [17] | Kelly et al. 1998 | ✅ (two DOIs exist for the same article; we use 10.1057/palgrave.jors.2600523) |
| [19] | Mnih et al., ICML 2016 | ✅ |
| [22] | Watkins & Dayan 1992, doi 10.1007/BF00992698 | ✅ DOI correct (not needed in the new paper) |
| [1], [10], [11], [18], [20], [21] | TS 36.213, Altman CMDP book, Jakes book, Sutton & Barto, ALVINN, Adam | Not re-verified. Not needed for the current outline, except possibly Jakes (fading model) and Adam (optimiser). Verify before use |

## C. Phase-3 corrections

- **Doherty et al., "Hype or Hope?"**: journal version **JOCN 17(9):D1, 2025**, DOI 10.1364/jocn.559990, with **5 authors** (Doherty, Matzner, Sadeghi, Bayvel, Beghelli). The Checkpoint-2 bib entry listed 4 authors from a truncated listing. Fixed.
- **LOLLA**: arXiv 2606.23110**v1** (22 Jun 2026) is the only version. Venue: IEEE TMC (DOI 10.1109/tmc.2026.3740957, pp. 1–18, early access).
