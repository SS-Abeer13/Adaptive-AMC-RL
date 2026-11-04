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
| LOLLA, IEEE TMC 2026 (PPO) | GPU NR stack, **uplink**, 1–8 UEs | 15–92 % | default (0.1 / 1.0 dB) only |
| Kela et al., EuCNC 2022 (Q-learning OLLA, XR) | system sim, UL, packet delay budget | "outperforms OLLA" at high reliability | traditional OLLA |
| **This study, v17 M1** (deadline, RTT 8) | system sim, DL, 10 users, PF | **+11.96 %** on-time (R06) | OLLA, tuned-target OLLA and Multi-OLLA |
| **This study, v17 M1 vs best calibrated rule** | same | **+1.58 %** (R03) | Context table calibrated on the same cue |
| **This study, v17 M3/M4** (goodput) | same | +1.32 % / +0.15 % vs OLLA; **−0.88 % / −1.73 % vs Fixed** (R19–R21) | same |

**Reading.** Published gains over OLLA are typically 10–100 %. Our gain over OLLA (+12 % on deadline traffic) sits inside that range. **But 83–86 % of it is already captured by a calibrated constant or context offset on top of the same OLLA loop.** In M1, Fixed − OLLA = 5.42 pp and Context − OLLA = 5.59 pp, against A2C − OLLA = 6.54 pp (ledger R02; derived, to be added as R33). The comparison that decides whether RL helps is therefore against calibrated rules, and that comparison is missing in the papers we read.

## 2. How often baselines are tuned

- In **none of the papers read** is the learned scheme compared with (i) a calibrated fixed offset, (ii) a per-class oracle table, or (iii) a same-information contextual rule calibrated on disjoint traces.
- OLLA is usually run at a default step and a 10 % target. LOLLA, SALAD and You et al. say so explicitly. Saxena et al. argue that OLLA is *hard to tune* and use that as motivation for learning.
- The classical OLLA literature shows that tuning matters (Park 2015: dynamic target, up to ~30 %; Durán 2015: initial-offset self-optimisation; eOLLA, NOLLA, d-OLLA). These tuned or calibrated variants are rarely used as RL baselines.
- Closest methodological precedent, **outside wireless**: Doherty et al. 2025 ("Hype or Hope?", optical networks) re-ran five landmark RL resource-allocation studies and found that **tuned heuristics equal or beat the reported RL results in every case**. This makes our main methodological point, in a different domain. We should cite it prominently and position ourselves as the first such study for cellular LA that also finds a positive, protocol-surviving case.

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

- **LOLLA 2026 (IEEE TMC)** learns a residual continuous SINR offset on the OLLA/LUT mapping and proves that its policy class contains OLLA. **This is the closest methodological overlap with our residual action.** Pang et al. 2024 (TD3 tunes OLLA parameters) and Pulliyakode & Kalyani 2017 (bandit over OLLA offsets) are also learning-on-top-of-OLLA designs. In robotics: Johannink 2019, Silver 2018.
- Our differences: a discrete ±1 residual on a **calibrated** base rule (FixedPU) rather than on raw OLLA; a shaped on-time reward; downlink with HARQ delay; and the finding that the residual collapses exactly onto the base rule on full-buffer traffic (R19a).
- **Consequence:** a method-led framing (option B, "residual deep RL for deadline-aware LA") has a **weak novelty bar** after LOLLA. The evaluation-led framing (option A) is better supported.

## 6. Statistical rigour

- Best practice among the papers read: LOLLA reports 20 seeds, mean ± 1 sd, and no tests. SALAD reports medians over 30 trajectories and no CIs. The others report no seeds, CIs or tests.
- **None** pre-registers decision rules, corrects for multiplicity, or reports the number of configurations tried. The RL-methodology literature asks for all of this (Henderson 2018, Colas 2018, Agarwal 2021, Patterson 2024), as does open-science practice (Nosek 2018, the NeurIPS pre-registration workshop in PMLR vol. 181).
- Our protocol (CRN, disjoint calibration/validation/evaluation traces, Holm over 9 comparators plus a CI bound, a fairness guard, a registry of 67 cases, project-wide Bonferroni, a hierarchical seed × trace bootstrap) is, as far as we found, **unique in the LA literature**.

## 7. Simulator and evaluation artefacts

- General credibility literature: Pawlikowski 2002 (telecom simulation credibility), Kurkowski 2005 (MANET "incredibles"), Kapoor & Narayanan 2023 (ML leakage).
- We found **no LA paper** reporting: (i) a mobility time-scale error that manufactures RL gains (H01–H03); (ii) a shared-reward credit trap (only the related "greediness" note in Kela 2022); or (iii) PF-averaging timing under multi-process HARQ (H17, S08). These three pitfalls, with diagnoses and fixes, look new as concrete LA-simulation lessons.

## 8. Does a prior paper already make our main point?

- **In cellular link adaptation: not that we found.** No paper reports that learned LA is matched by calibrated simple rules, or limits an RL gain to a traffic type after such a comparison.
- **In a neighbouring field: yes.** Doherty et al. 2025 make the "tuned heuristics match RL" point for optical-network resource allocation. We must say so plainly and position the paper as the cellular-LA counterpart. Our addition is that one pre-registered case survives (M1).
- **Caveat:** our search had no IEEE Xplore full-text access, and the Crossref ranking is noisy. A final targeted check of TMLCN / OJ-COMS / TWC / TVT issues from 2024–2026 is recommended before submission.

## 9. Proposed novelty position (input to Checkpoint 4)

1. **First pre-registered, multiplicity-controlled evaluation of deep RL link adaptation** against calibrated same-information rules. It shows that most of the reported-style gain over OLLA (83–86 % in M1) comes from calibration, not learning. *New.*
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
