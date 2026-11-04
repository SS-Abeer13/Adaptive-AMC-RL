# Venue research (Phase 3, 2026-11-04)

Policies come from each journal's own pages, opened on 2026-11-04 (URLs in §3). "Not stated" means the official page does not say. "Unverified" means only third-party sources were available. Metrics are a sanity check only.

Recent-paper lists come from the venue-restricted Crossref scan (`paper/lit/search_raw/venue_scan_2024_2026.txt`, `venue_scan_tmlcn_ojcoms.txt`), which stands in for IEEE Xplore. Xplore blocks scripted access (HTTP 418), even for open-access PDFs.

## 1. Candidate venues

### IEEE Transactions on Machine Learning in Communications and Networking (TMLCN)
- **Scope:** "high-quality manuscripts on advances in machine learning and artificial intelligence (AI) methods" in communications and networking. The topic list includes **performance analysis and evaluation of ML techniques**. The journal "advocates for reproducible and public sharing of codes, datasets, software, and other artefacts".
- **Fit for us:** high. It publishes evaluation-led papers (Raca et al. 2024, "Lessons from a real-world evaluation"; Baur et al. 2025, evaluation metrics) and deadline-constrained DRL (Robaglia et al. 2024).
- **Length:** not stated on the policy or home pages (IEEE template). Published exemplars run 13–17 pages.
- **Review:** single-anonymous, ≥ 2 reviewers. Time to decision not stated.
- **OA / APC:** fully OA (CC BY). APC **US$2,160** (2026 submissions), with 5 % / 20 % IEEE / Society member discounts.
- **Code / data:** authors of accepted papers are "strongly encouraged" to give a GitHub link or submit artefacts (IEEE DataPort, Code Ocean).
- **AI policy:** IEEE PSPB Operations Manual §8.2.1. The IEEE Author Center requires disclosure in the acknowledgments (secondary summaries; see §3).
- **Preprints:** not addressed on the page. IEEE policy allows preprints (see TWC wording below).
- **Metrics:** first Journal Impact Factor in the 2025 JCR (IEEE announcement). The value is 4.9 on an aggregator (**unverified**).
- **Recent relevant papers (2024–2026):**
  - Robaglia, Coupechoux, Tsilimantos, DRL for UL scheduling in NOMA-URLLC (10.1109/tmlcn.2024.3437351);
  - Raca et al., device-based throughput prediction: lessons from a real-world evaluation (10.1109/tmlcn.2024.3352541);
  - Baur et al., evaluation metrics for generative models in the PHY (10.1109/tmlcn.2025.3571026);
  - Jadoon et al., learning random-access schemes with MARL (10.1109/tmlcn.2023.3345273);
  - Doanis & Spyropoulos, sample-efficient multi-agent DQNs for 5G+ inter-slice orchestration (10.1109/tmlcn.2024.3420268);
  - Hasan et al., GNN-Transformer radio link failure prediction in 5G RAN (10.1109/tmlcn.2025.3575368);
  - Lotfi et al., sharpness-aware O-RAN resource management with MARL (10.1109/tmlcn.2025.3634994).
  - **No link-adaptation paper was found in TMLCN 2024–2026.** That cuts both ways: no direct competitor, but no LA precedent either.

### IEEE Open Journal of the Communications Society (OJ-COMS)
- **Scope:** "advances in the state of the art of telecommunications systems and networks". Machine learning for communications is listed explicitly.
- **Length:** **"NO page limits"**. Papers over 25 pages are treated as long survey papers.
- **Review:** single-anonymous, ≥ 2 reviewers. **Target review time 2 weeks** for manuscripts of 25 pages or fewer.
- **OA / APC:** fully OA. APC **US$2,160** (2026).
- **Code / data:** encouraged (Code Ocean, IEEE DataPort).
- **AI policy:** IEEE PSPB §8.2.1. **Preprints:** not addressed on the page.
- **Metrics:** not verified.
- **Recent relevant papers:**
  - **Ahsen et al., MO-OLLA for XR tethering groups (10.1109/ojcoms.2026.3714148)**;
  - **Parsa, Moghim, Shetty, QoS-aware DRL link adaptation (10.1109/ojcoms.2025.3593836)**;
  - Pivoto et al., contextual-bandit LA for SDR backhaul (10.1109/ojcoms.2026.3738497);
  - Bayram & Seçinti, FALCON flight-aware LA (10.1109/ojcoms.2026.3734042);
  - Delay-violation probability modelling for 5G with HARQ (10.1109/ojcoms.2026.3745967);
  - ensemble-DRL scheduling for 5G-TSN (10.1109/ojcoms.2026.3659198);
  - Sharifi et al., DRL HAPS user scheduling (10.1109/ojcoms.2023.3337044).
  - **This venue already publishes LA and OLLA work, including DRL-LA.**

### IEEE Transactions on Wireless Communications (TWC)
- **Scope:** wireless communications. Out of scope if "not centered around a wireless communications problem" or if fading/interference play no prominent role. We qualify.
- **Length:** **13 double-column pages at submission, 16 on revision**, including references. Voluntary US$110/page for the first 10 pages; **mandatory US$220/page beyond 10**.
- **Review:** single-anonymous. Revisions are due within 8 weeks. Overall time not stated.
- **OA:** hybrid. Optional APC US$2,800 (2026).
- **Preprints:** allowed, with the IEEE notice "This work has been submitted to the IEEE for possible publication."
- **Code / data:** not addressed. **AI:** IEEE PSPB §8.2.1.
- **Recent relevant papers:**
  - Saxena et al. 2022 (bandit LA; 10.1109/twc.2021.3098972);
  - Jin et al. 2024, retransmission-aware AMC for deterministic delay (10.1109/twc.2024.3456188);
  - Zhang et al. 2024, constrained risk-sensitive DRL for eMBB-URLLC scheduling (10.1109/twc.2024.3373722);
  - Göktepe et al. 2024, ML early HARQ feedback prediction (10.1109/twc.2023.3275296);
  - Ye, Zhou, Fu 2024, DRL scheduling for NR-U/WiGig (10.1109/twc.2023.3275945);
  - DRL dynamic slicing for eMBB/URLLC 2026 (10.1109/twc.2025.3634476).

### IEEE Transactions on Vehicular Technology (TVT)
- **Length (official VTS page):** regular papers 10 pages, then **US$220 per extra page** (mandatory). Correspondence 5 pages. From 1 July 2026 a VTS-member corresponding author gets 2 extra free pages. The initial submission cap (14 pages, per third-party guides) is **unverified**.
- **Recent relevant papers:**
  - **Ye, Yu, Fu 2023 DRLLA (10.1109/tvt.2023.3236791)**;
  - **Ku & Lee 2024, CMAB LA for URLLC (10.1109/tvt.2024.3431613)**;
  - Lin et al. 2026, meta-DRL LA (10.1109/tvt.2026.3698387);
  - Zhang et al. 2025, DRL UL/DL resource allocation for URLLC (10.1109/tvt.2024.3510548);
  - Bai et al. 2025, MARL scheduling + beamforming (10.1109/tvt.2024.3494049).
  - **TVT is the most frequent home of DRL-LA papers.**

### IEEE Transactions on Communications (TCOM)
- The official policies page returned **404**, so policies are not verified.
- **Recent:**
  - Liang et al. 2024, DRL LA for IDET (10.1109/tcomm.2024.3407204);
  - Le et al. 2026, WiFi-CUTS bandit rate adaptation on a testbed (10.1109/tcomm.2025.3628731);
  - Wang et al. 2024, DRL resource allocation for delay-tolerance-aware IIoT (10.1109/tcomm.2023.3322736);
  - Gunes Reyhan & Coleri 2025, safe DRL with AoI guarantees (10.1109/tcomm.2025.3591167).

### IEEE Wireless Communications Letters (WCL) / IEEE Communications Letters (CL): letter option
- **WCL:** **5-page limit**, including references. Pages 1–4 carry no charge; a 5th page costs US$220. **No major revisions**: the outcome is accept-with-minor or reject.
- **Recent:**
  - Giwa et al. 2026, QPPG policy-gradient LA (10.1109/lwc.2026.3694465);
  - Gautam et al. 2026, CQI-based interference prediction for LA (10.1109/lwc.2025.3649500);
  - Park & Baek 2021, two-stage TS OLLA (WCL);
  - Durán et al. 2015 (CL).

### Fallbacks and the ML-side option
- **IEEE Access:** APC US$2,160. No hard page limit (fewer than 20 pages recommended). Broad scope. Fallback only.
- **IEEE TMC:** LOLLA (2026) and Ye & Fu 2024 appear there. It is systems-oriented. Not researched further.
- **Elsevier Computer Networks:** the guide-for-authors page returned **403**, so policies are not verified. Recent: Parsa et al. 2022 (DRL power + MCS), Zhao et al. 2024 (LA for underwater optical).
- **Elsevier Physical Communication, Computer Communications; Springer EURASIP JWCN, Wireless Networks:** not verified. The venue scan found few or no relevant 2024–2026 LA papers (JWCN: 0).
- **TMLR:** double-blind on OpenReview. It "emphasizes technical correctness over subjective significance", which suits a rigour-heavy paper, but the audience is ML rather than wireless. Fit only for a methodology-only spin-off.

## 2. Pattern in what these venues accept (exemplars, see `exemplar_template.md`)
- In the exemplars, baselines are almost never tuned heuristics: TMLCN Robaglia uses random/grant-free/DRL baselines; OJ-COMS Ahsen uses conventional OLLA.
- Statistics are light: Jadoon uses "3 random seeds and the best performances are shown"; Bayerlein uses Monte Carlo over 1,000 scenarios. None uses hypothesis tests.
- Code links are common but not universal (Bayerlein: GitHub).
- Our protocol would stand out in either TMLCN or OJ-COMS.

## 3. Sources (opened 2026-11-04)
- TMLCN policies: https://www.comsoc.org/publications/journals/ieee-tmlcn/policies-guidelines
- TMLCN home: https://www.comsoc.org/publications/journals/ieee-tmlcn
- OJ-COMS submit: https://comsoc.org/publications/journals/ieee-ojcoms/ieee-open-journal-communications-society-submit-manuscript
- OJ-COMS policies: https://www.comsoc.org/publications/journals/ieee-ojcoms/policies-guidelines
- TWC policies: https://www.comsoc.org/publications/journals/ieee-twc/policies-guidelines
- WCL submit: https://comsoc.org/publications/journals/ieee-wcl/submit-manuscript
- TVT page charges: https://vtsociety.org/publication/ieee-transactions-vehicular-technology/guidelines-authors/instructions/page-charges
- IEEE Access guidelines: https://ieeeaccess.ieee.org/authors/submission-guidelines/
- TMLR: https://jmlr.org/tmlr/
- IEEE first impact factors 2026: https://open.ieee.org/ten-ieee-journals-receive-first-impact-factors-in-2026/
- Blocked or failed: TCOM policies (404), Elsevier ComNet guide (403), IEEE Xplore (418), Google Scholar (403). The IEEE AI-disclosure rule (acknowledgments) is confirmed only through secondary summaries and must be checked in the IEEE Author Center at submission.
