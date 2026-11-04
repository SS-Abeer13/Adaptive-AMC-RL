# Gap analysis: where this paper is new and where it overlaps (Phase 2, Checkpoint 2)

Basis: 84 verified references (`bibliography.bib`, `lit_matrix.csv`). Full texts were read for the 10 closest arXiv papers; the other close IEEE-only papers were read at abstract level (see `search_log.md` §4). Our own numbers cite ledger IDs.

## 1. What the literature reports for learned link adaptation vs OLLA

| Work | Setting | Reported gain vs OLLA | How OLLA was configured |
|---|---|---|---|
| Saxena et al., TWC 2022 (LTS bandit) | link-level, single link, retransmissions ignored | "up to 100 %" vs state of the art | standard OLLA; untuned |
| Ye et al., TVT 2023 (DRLLA) | LTE/NR sim, outdated CQI | higher throughput + lower BLER | not described as tuned (abstract) |
| Demirel et al. 2025 (Ericsson, arXiv) | system sim, 5 benchmarks | ≈ 10 % (≈ 20 % high mobility) | industry LA baseline |
| SALAD 2025 (non-RL learning) | OAI sim + over-the-air, 1 UE | up to 15 % (8.8–25.5 % by regime) | 3 fixed NACK steps, target 0.1 |
| You et al. 2026 (DC-DQN, arXiv) | sim + USRP/srsRAN, parallel HARQ | +70 % (mobile); slight (static) | srsRAN default; one step size picked on the testbed |
| LOLLA, IEEE TMC 2026 (PPO; arXiv 2606.23110v1) | GPU-accelerated NR stack, 3GPP TDL channels, **uplink**, round-robin, 1–8 UEs. The RL policy observes 13-D PHY/MAC telemetry that OLLA does not use | 15–92 % at f_d = 50–400 Hz; within 3 % at 10 Hz (nearly static) | default (0.1 / 1.0 dB) only |
| Kela et al., EuCNC 2022 (Q-learning OLLA, XR) | system sim, UL, packet delay budget | "outperforms OLLA" at high reliability | traditional OLLA |
| **This study, v17 M1** (deadline, RTT 8) | system sim, DL, 10 users, PF | **+11.96 %** on-time (R06) | OLLA, tuned-target OLLA and Multi-OLLA |
| **This study, v17 M1 vs best calibrated rule** | same | **+1.58 %** (R03) | Context table calibrated on the same cue |
| **This study, v17 M3/M4** (goodput) | same | +1.32 % / +0.15 % vs OLLA; **−0.88 % / −1.73 % vs Fixed** (R19–R21) | same |

**Reading.** Published gains over OLLA are typically 10–100 %. Our gain over OLLA (+12 % on deadline traffic) sits inside that range. **But 83–86 % of it is already captured by a calibrated constant or context offset on top of the same OLLA loop.** In M1, Fixed − OLLA = 5.42 pp and Context − OLLA = 5.59 pp, against A2C − OLLA = 6.54 pp (ledger R02; derived, to be added as R33). The comparison that decides whether RL helps is therefore against calibrated rules, and that comparison is missing in the papers we read.

## 2. How often baselines are tuned

- **Counts (lit_matrix.csv, columns `calibrated_rule_baseline`, `information_parity`).** Of 23 learning-based LA papers, 0 / 3 / 13 / 7 have a calibrated-rule baseline (yes / partial / no / unclear), and 5 / 1 / 3 / 14 have information parity (yes / partial / no / unclear). **None has both.** Of the 7 read in full text, none uses a calibrated-rule baseline.
- In none of the papers read is the learned scheme compared with (i) a calibrated fixed offset, (ii) a per-class oracle table, or (iii) a same-information contextual rule calibrated on disjoint traces.
- OLLA is usually run at a default step and a 10 % target. LOLLA, SALAD and You et al. say so explicitly. Saxena et al. argue that OLLA is *hard to tune* and use that as motivation for learning.
- The classical OLLA literature shows that tuning matters (Park 2015: dynamic target, up to ~30 %; Durán 2015: initial-offset self-optimisation; eOLLA, NOLLA, d-OLLA). These tuned or calibrated variants are rarely used as RL baselines.
- Closest methodological precedent, **outside wireless**: Doherty, Matzner, Sadeghi, Bayvel, Beghelli, *JOCN* 17(9):D1, 2025 (arXiv 2502.12804). They re-ran five landmark RL resource-allocation studies in optical networks and found that **tuned heuristics equal or beat the reported RL results in every case**. Use it as an **anchor in related work and the discussion, not as the paper's identity**. Our result is more nuanced: RL does win in one well-defined regime, so the paper asks *when* RL helps.
- The same "strong-baseline" lesson appears elsewhere in ML (Ferrari Dacrema et al., RecSys 2019; McGreivy & Hakim, *Nat. Mach. Intell.* 2024). Wireless-specific evidence: Mangal, Fund & Panwar, SIGCOMM 2026 (reproducing wireless-ML studies; leakage inflates results) and Kela, Liu & Valcarce 2024 (an earlier DRL scheduler performed on par with PF). No wireless or RAN paper we found runs the systematic "tuned rule vs RL" re-evaluation that Doherty et al. do.

## 3. How often HARQ timing is realistic

- **Instantaneous or no HARQ** is the norm: Saxena 2022 (first transmission only), Mota 2019 (none), LOLLA 2026 (uplink CRC outcome, no feedback delay).
- **You et al. 2026** explicitly model ACK/NACK delay, retransmissions and parallel HARQ processes, and claim to be the first practical DRL-LA to do so. **We are therefore not the first to include multi-process HARQ.** We do add two things they do not report:
  1. a controlled RTT 0 vs RTT 8 ablation against calibrated rules (R28);
  2. evidence that the **PF-average timing under multi-process HARQ** can inflate every scheme by about 40 % (H17). No published LA paper we found discusses this.

## 4. Deadline / latency-aware learned LA

- **Kela et al. 2022** (Nokia): Q-learning/DQN OLLA that minimises resources within a packet delay budget for XR uplink. Compared only with traditional OLLA. They also note multi-agent "greediness" problems, which are related to our slot-stealing trap (H07).
- Ku & Lee 2024 (TVT): contextual-bandit LA for bursty URLLC. Pocovi et al. 2018: classical load-adaptive BLER target for URLLC.
- **So deadline-aware LA with RL is not new.** What is new: a downlink deadline result under RTT 8 / 8 processes that beats **calibrated same-information rules**, under pre-registration and project-wide multiplicity control.

## 5. Residual learning on top of a classical rule

- **LOLLA 2026 (IEEE TMC)** learns a residual continuous SINR offset on the OLLA/LUT mapping and proves that its policy class contains OLLA. **This is the closest methodological overlap with our residual action.** Positioning (agreed at Checkpoint 2): its setting differs. It uses a GPU NR stack with TDL channels up to 400 Hz Doppler, an RL agent given telemetry OLLA lacks, and round-robin scheduling. We do **not** suggest its gains are artefacts. We state what our protocol adds: same-information calibrated comparators (Fixed, FixedPU, Context table), realistic multi-process downlink HARQ, multi-user PF scheduling, and pre-registration with multiplicity accounting. A fair tie-in for the pitfalls discussion: LOLLA's gains concentrate at high Doppler and are within 3 % at 10 Hz, and our gains vanished once mobility was physically correct. Both point to **reporting results by mobility regime**. Pang et al. 2024 (TD3 tunes OLLA parameters) and Pulliyakode & Kalyani 2017 (bandit over OLLA offsets) are also learning-on-top-of-OLLA designs. In robotics: Johannink 2019, Silver 2018.
- Our differences: a discrete ±1 residual on a **calibrated** base rule (FixedPU) rather than on raw OLLA; a shaped on-time reward; downlink with HARQ delay; and the finding that the residual collapses exactly onto the base rule on full-buffer traffic (R19a).
- **Consequence:** a method-led framing (option B, "residual deep RL for deadline-aware LA") has a **weak novelty bar** after LOLLA. The evaluation-led framing (option A) is better supported.

## 6. Statistical rigour

- Best practice among the papers read: LOLLA reports 20 seeds, mean ± 1 sd, and no tests. SALAD reports medians over 30 trajectories and no CIs. The others report no seeds, CIs or tests.
- **None** pre-registers decision rules, corrects for multiplicity, or reports the number of configurations tried. The RL-methodology literature asks for all of this (Henderson 2018, Colas 2018, Agarwal 2021, Patterson 2024), as does open-science practice (Nosek 2018, the NeurIPS pre-registration workshop in PMLR vol. 181).
- Our protocol (CRN, disjoint calibration/validation/evaluation traces, Holm over 9 comparators plus a CI bound, a fairness guard, a registry of 67 cases, project-wide Bonferroni, a hierarchical seed × trace bootstrap) is, as far as we found, **unique in the LA literature**.

## 7. Simulator and evaluation artefacts

- General credibility literature: Pawlikowski 2002 (telecom simulation credibility), Kurkowski 2005 (MANET "incredibles"), Kapoor & Narayanan 2023 (ML leakage).
- We found **no LA paper** reporting: (i) a mobility time-scale error that manufactures RL gains (H01–H03); (ii) a shared-reward credit trap (only the related "greediness" note in Kela 2022); or (iii) PF-averaging timing under multi-process HARQ (H17, S08). These three pitfalls, with diagnoses and fixes, look new as concrete LA-simulation lessons.

## 8. Does a prior paper already make our main point? (revised after Checkpoint 2)

- **In cellular link adaptation: not that we found.** No paper reports that learned LA is matched by calibrated simple rules, or limits an RL gain to a traffic type after such a comparison.
- **In a neighbouring field: yes, but less nuanced.** Doherty et al. (JOCN 2025) make the "tuned heuristics match RL" point for optical networks. We cite it as the closest methodological precedent. Our paper's question is *when* learned LA helps, and the answer includes one surviving positive regime (M1).
- **Caveat:** our search had no IEEE Xplore full-text access, and the Crossref ranking is noisy. A final targeted check of TMLCN / OJ-COMS / TWC / TVT issues from 2024–2026 is recommended before submission.

## 9. Proposed novelty position (input to Checkpoint 4)

0. **Thesis (agreed at Checkpoint 2):** against OLLA, RL gains look large, and we see that too (+11.96 % vs tuned OLLA in M1). Against calibrated rules that use the same information, the gain shrinks to about +1.6 %. It survives only for deadline traffic under realistic HARQ with a residual policy. Goodput shows no gain.
1. **First pre-registered, multiplicity-controlled evaluation of deep RL link adaptation** against calibrated same-information rules. It shows that most of the gain over OLLA (83–86 % in M1, R33) is reached by calibration alone. *New.*
2. **A surviving positive case:** deadline traffic under realistic downlink HARQ timing (RTT 8, 8 processes). Residual A2C beats every comparator (+1.58 % vs the best rule, hierarchical 95 % CI [+0.62, +2.62] %). The positive case is new in this setting. *Deadline-aware RL-LA (Kela 2022) and realistic HARQ (You 2026) each exist separately; their combination against calibrated rules is new.*
3. **A negative result on full-buffer goodput** under the same protocol, with exact collapse onto the base rule (R19a). *New as a rigorous negative.*
4. **Three simulation and design pitfalls** that manufacture or hide RL gains: mobility time scale, shared-reward slot stealing, and PF-average timing under multi-process HARQ, each with a diagnosis and a fix. *New as LA-specific lessons.* The PF-definition sign flip of Baseline vs OLLA (S08a, R22) serves as an example.
5. **Residual-on-calibrated-rule design:** overlaps with LOLLA and TD3-OLLA. Present it as an engineering choice, not as a headline contribution.

## 10. Top 30 references (ranked by importance to the paper)

| # | Key | Why |
|---|---|---|
| 1 | `wang2026lolla` | Closest method (residual offset, PPO); untuned OLLA; uplink with no HARQ delay |
| 2 | `you2026sim2real` | Closest on realistic HARQ in DRL-LA |
| 3 | `kela2022delayolla` | Closest on deadline-aware RL-LA; multi-agent greediness |
| 4 | `saxena2022tuningfree` | Main bandit-LA journal paper; the "OLLA is hard to tune" argument |
| 5 | `doherty2025hypehope` | Same methodological point in optical networks |
| 6 | `ye2023drlla` | Most-cited DRL-LA journal paper (TVT) |
| 7 | `wiesmayr2025salad` | Strong non-RL learned LA; OLLA baseline practice |
| 8 | `pang2024td3olla` | RL tuning OLLA (learning on top of a rule) |
| 9 | `demirel2025genrl` | Industry RL-LA gains and generalisation |
| 10 | `pulliyakode2017rlolla` | Bandit over OLLA offsets |
| 11 | `nakamura2002olla` | Origin of OLLA |
| 12 | `park2015targetbler` | Target-BLER optimisation (tuned-target comparator) |
| 13 | `duran2015selfopt` | OLLA self-optimisation (calibration) |
| 14 | `blanquez2016eolla` | OLLA variants |
| 15 | `saxena2019cmab` | Contextual-bandit LA (Context table analogue) |
| 16 | `ku2024cmaburllc` | Bandit LA for bursty/URLLC traffic |
| 17 | `pocovi2018jointlaurllc` | Latency-aware LA via BLER target |
| 18 | `kushner2004pf` | PF definition (averaging timing pitfall) |
| 19 | `jalali2000pf` | PF origin |
| 20 | `ng1999shaping` | Potential-based shaping |
| 21 | `johannink2019residual` | Residual RL |
| 22 | `henderson2018matters` | Seeds and reporting in deep RL |
| 23 | `agarwal2021precipice` | Interval estimates, few runs |
| 24 | `colas2018seeds` | Number of seeds |
| 25 | `nosek2018prereg` | Pre-registration |
| 26 | `pawlikowski2002credibility` | Simulation credibility (telecom) |
| 27 | `kapoor2023leakage` | Reproducibility pitfalls in ML science |
| 28 | `foerster2018coma` | Credit assignment, shared policies (slot stealing) |
| 29 | `brueninghaus2005l2s` | Link-to-system abstraction (limitations) |
| 30 | `tr38901` / `ts38214` | Channel model / MCS tables (limitations) |

## 11. Update from the Phase 3 IEEE venue pass (2026-11-04)

- **New related papers:**
  - Parsa, Moghim & Shetty, OJ-COMS 2025 (QoS-aware DRL-LA, XR/VR; abstract level). It overlaps the latency-aware angle with Kela 2022 but is not closer than LOLLA on method or protocol.
  - Pivoto et al., OJ-COMS 2026 (contextual bandit used to calibrate service-specific LUTs).
  - Jin et al., TWC 2024 (model-based retransmission-aware AMC under deterministic delay).
  - Liang et al., TCOM 2024; Giwa et al., WCL 2026 (DRL/PG LA, venue evidence).
- **Corrections:** Ahsen et al. is published in OJ-COMS (2026). "Hype or Hope?" is in JOCN (2025, 5 authors). LOLLA is at arXiv v1 and in IEEE TMC.
- **No paper closer than LOLLA** was found on (a) RL vs calibrated rules or (b) deadline-aware RL-LA under realistic downlink HARQ. The novelty position in §9 stands, with item 0 added.
