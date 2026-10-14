```
SEED: 55954361eadc0bbada69d9d3da7ad92f
AXIS: Overclaimed novelty (prior art mischaracterised or missing)
STANCE: Steelman-then-press (state the strongest version of the paper, then attack the steelmanned version)
```

### Summary
The paper evaluates an autonomous Advantage Actor-Critic (Deep A2C) policy for outer-loop link adaptation (OLLA) in a 10-user 3GPP LTE/NR macrocell undergoing non-stationary Markov interference bursts (+9 dB). The study claims to resolve ten critical vulnerabilities from a prior v7 manuscript by removing behavior cloning warm-starts (`bc_warm_eps = 0`), filtering credit assignment to scheduled users only, expanding the discrete action grid to $[-6, \dots, +4]$ dB, adding Chase combining, and implementing formal Two One-Sided Tests (TOST) with a $\pm 0.10$ Mbps margin. The steelmanned version of this paper is that it identifies a genuine failure mode in classical telecommunications heuristics: while linear integrators effectively track stationary channels, their fixed step-down bounds cause integration lag during violent interference bursts, whereas an unconstrained neural policy with large negative actions can instantly execute single-step backoffs ($-6$ dB), yielding 2.23 Mbps during bursts compared to 0.92 Mbps for OLLA and 0.60 Mbps for Warm-OLLA, while improving cell-edge fairness. Pressing on this steelmanned version, however, reveals that the paper's headline parity claims are propped up by selective reporting, the method operates at an operationally catastrophic 53% initial block error rate, the reported sample size ($N=100$) is flatly contradicted by the paper's own data logs ($N=30$ and $N=15$), and its novelty claims rest on a severe mischaracterisation of cited prior art alongside the omission of foundational literature.

### Belief update
Prior to reading, my subjective probability that deep reinforcement learning provides a net operational benefit over well-tuned multi-loop heuristics in standard cellular link adaptation was $P \approx 0.15$, given the high risk of over-fitting, training instability, and signaling overhead in telecommunication physical layers. This paper shifted that probability downward to $P \le 0.05$ for general deployment: Deep A2C places 6th out of 8 schemes in aggregate cell throughput under Proportional Fair scheduling (3.55 Mbps vs. 3.80 Mbps for Fixed) and incurs an intolerable 53% first-transmission block error rate (BLER1 = 0.530). Conversely, my belief that deep RL policies can find non-linear jump policies during high-amplitude non-stationary interference bursts that outperform fixed-step integrators shifted upward from $P \approx 0.30$ to $P \approx 0.60$. However, my belief that this specific paper establishes an empirical advance is virtually zero ($P \le 0.02$) until the authors provide fair ablations against jump-capable baselines, fix the 53% BLER failure mode, and accurately attribute their prior art.

---

### Framework Audit (Explicit Section-by-Section Check)

1. **Narrative**
   - *Concrete claims:* The paper claims Deep A2C learns link adaptation autonomously from scratch, matches OLLA in 1000-TTI steady state, delivers +218% throughput during +9 dB bursts, and doubles user fairness. These are concrete, but heavily qualified by omissions.
   - *Overclaiming in abstract/intro:* The Executive Summary highlights a "+218% burst advantage" and "+145% over FixedPU" while completely omitting that Deep A2C finishes 6th of 8 schemes in overall cell throughput under standard Proportional Fair scheduling (Major Concern 4).
2. **Novelty**
   - *Belief update:* The paper offers a narrow update on burst dynamics, but fails to justify general utility.
   - *Prior works correctly attributed or missing:* Critical failure on primary AXIS. The authors mischaracterise Ahsen et al. [2604.20459] to disguise a bespoke, broken heuristic, while omitting foundational literature on RL for OLLA dating to Pulliyakode & Kalyani [1708.00994] (Major Concern 8). Routine bug fixes from v7 are also dressed up as theoretical novelties (Major Concern 7).
3. **Evidence**
   - *Distinguishing test:* The experiments fail to differentiate whether Deep A2C's burst performance is driven by learned non-stationary sequence tracking or merely by having access to a single-step $-6$ dB action that baseline OLLA was denied (Major Concern 5).
   - *Cherry-picking:* No qualitative individual UE time-series traces are provided to inspect policy dynamics; only aggregate distributions are shown. Check produced no separate major concern, but noted.
   - *Pre-registration vs post-hoc:* Equivalence bounds ($\pm 0.10$ Mbps) were asserted post-hoc without external pre-registration. More critically, the authors switch from Proportional Fair to Round-Robin scheduling specifically to find a steady-state TOST-equivalent result (Major Concern 2).
   - *Statistical rigor:* Severe discrepancy: Section 1 and Appendix B claim evaluation was scaled to $N=100$ independent traces to achieve power $>0.92$, but raw execution headers in Appendices C and D reveal the code ran on only $N=30$ traces (PF 200 TTI) and $N=15$ traces (Steady 1000 TTI) (Major Concern 1).
   - *Baselines:* The newly added "Multi-OLLA" dual-integrator baseline collapses to 1.57 Mbps in steady state (far below even the 3.00 Mbps non-adaptive Baseline), indicating a severely degraded strawman rather than a tuned modern baseline (Major Concern 6).
   - *Ablations:* Missing temporal stacking ablation ($L=3$ vs. $L=1$), missing action space ablation ($[-6, +4]$ vs. $[-3, +3]$), and missing baseline jump-action ablations (Major Concern 5).
   - *Alternative explanations:* Deep A2C's high Jain fairness (0.851) and burst goodput are consistent with a crude high-risk policy that chronically under-adapts for cell-center UEs while taking massive backoffs, driving BLER1 to 53% and equalizing throughput downward rather than optimizing multi-user capacity.
   - *Quality vs quantity:* The entire empirical case relies on a single simulated synthetic macrocell scenario with full buffers; check produced no independent major concern beyond limitations.
4. **Reproducibility**
   - *Code:* MATLAB code files are referenced cleanly (`Optimized/v8/`).
   - *Seeds:* `Seeds=2` is reported in dataset headers, but specific integer RNG seeds are omitted from the text (Minor concern).
   - *Hyperparameters:* Neural architecture dimensions and discount factors are documented; policy entropy regularization schedules are omitted from the main description (Minor concern).
   - *Compute budget:* Direct BLAS forward-pass acceleration (86.9x speedup, 0.0164 s per 200 calls) is thoroughly profiled. *Check produced nothing further.*
5. **Limitations**
   - *Honest enumeration:* The authors claim all 10 reviewer concerns from v7 are "RESOLVED", presenting a triumphant narrative with zero acknowledged trade-offs or operational deficiencies.
   - *Unaddressed failure modes:* Deep A2C's 53% initial block error rate (BLER1 = 0.530) is an operational disaster for physical-layer control channels and HARQ buffers, completely ignored in the discussion (Major Concern 3).
6. **Presentation**
   - *Clarity:* Mathematical derivations of TOST and Chase combining are clear and well-written.
   - *Deceptive figures:* Figures 1–6 are cited as publication-grade figures on pages 4–6, but are provided only as one-line placeholder captions without actual graphic plots (Minor concern).
   - *Jargon:* The narrative relies heavily on hype phrasing ("RL's Genuine Moat", "Fully Verified", "Decisive Burst Advantage") that distracts from cold empirical evaluation. *Check produced nothing further.*

---

### Major concerns

1. **[Evidence — statistical rigor & narrative]**
   - **Issue:** The paper asserts that evaluation power was scaled to $N=100$ independent traces, but the embedded empirical run logs prove the headline benchmarks were evaluated on only $N=30$ and $N=15$ traces.
   - **Where:** Section 1 (lines 87–88), Appendix B (lines 529–531) vs. Appendix C (line 560) and Appendix D (line 610).
   - **Why it matters:** In addressing v7 Concern C6 ("Low Statistical Power"), the authors state: *"Scaled evaluation harness to N=100 independent channel realization traces... At N=100, statistical power for detecting a 2.5% throughput shift exceeds 1 - beta = 0.92."* Yet the actual raw dataset logs printed in Appendix C show `Seeds=2 | Traces=30 | SimTime=200`, and Appendix D shows `Seeds=2 | Traces=15 | SimTime=1000`. Asserting the statistical confidence of an $N=100$ sample while running only 15 to 30 traces is a severe breach of empirical rigor that invalidates the claimed statistical power.
   - **What would address it:** Execute the evaluation suite across the promised $N=100$ independent seeds, report empirical confidence intervals and power calculations computed from that full sample, and reconcile the text with the actual execution logs.

2. **[Evidence — pre-registration vs post-hoc & selective reporting]**
   - **Issue:** The authors claim steady-state equivalence with OLLA by post-hoc switching to Round-Robin scheduling, hiding that OLLA significantly outperforms Deep A2C under Proportional Fair scheduling.
   - **Where:** Section 3 (lines 219–221) vs. Appendix D (lines 623–630).
   - **Why it matters:** In Section 3, the authors announce: *"Steady-State TOST Equivalence Disproves OLLA Superiority Claim: Under the 1000-TTI horizon with Round-Robin scheduling, Deep A2C matches OLLA (2.23 vs. 2.25 Mbps) with formal TOST equivalence ($p < 10^{-6}$)."* However, under the primary Proportional Fair scheduler at 1000 TTIs (Appendix D), OLLA decisively beats Deep A2C (2.23 Mbps vs. 2.12 Mbps, Wilcoxon $p = 0.0015$, TOST $p = 0.6577$, `[NON-EQUIVALENT]`), and Fixed beats Deep A2C ($p = 6.1 \times 10^{-5}$). Shifting from PF to RR solely to manufacture a headline TOST equivalence claim is post-hoc cherry-picking of experimental conditions.
   - **What would address it:** Transparently report both PF and RR 1000-TTI results in Section 2 and Section 3, retract the claim that OLLA's steady-state superiority is disproved under realistic scheduling, and explain why Deep A2C suffers asymptotic tracking deficits under Proportional Fair resource allocation.

3. **[Limitations — unaddressed failure modes & physical viability]**
   - **Issue:** Deep A2C operates at an unviable 53% initial block error rate (BLER1 = 0.530) under Proportional Fair scheduling, which is completely unaddressed in the text.
   - **Where:** Section 2 (line 202), Table in Section 2, Appendix C (line 572).
   - **Why it matters:** 3GPP cellular networks are engineered to operate around a 10% BLER target to prevent HARQ retransmission stall, buffer bloat, and control signaling (PDCCH/PUCCH) exhaustion. Deep A2C exhibits a catastrophic 53.0% BLER1 under PF (and 45.1% under RR), whereas standard baselines achieve 18.0%–29.7%. A link adaptation policy that drops or retransmits more than half of its initial transport blocks would immediately violate QoS SLAs and exhaust scheduling grants in any physical deployment. The paper ignores this failure mode entirely.
   - **What would address it:** Formulate the objective as a constrained Markov Decision Process (CMDP) or incorporate an explicit Lagrange multiplier penalizing BLER above the 10% 3GPP target, and demonstrate that Deep A2C can maintain its burst and fairness gains while meeting standard cellular reliability constraints.

4. **[Narrative — overclaiming in abstract & executive summary]**
   - **Issue:** The Executive Summary headlines a "+218% burst advantage" while concealing that Deep A2C finishes 6th out of 8 schemes in aggregate cell throughput under Proportional Fair scheduling.
   - **Where:** Executive Summary (lines 23–25) vs. Section 2 Table (lines 138–207).
   - **Why it matters:** The Executive Summary frames Deep A2C as a dominant breakthrough across the board. In reality, under standard macrocell conditions (PF, 200 TTI), Deep A2C (3.55 Mbps) is outperformed by Fixed (3.80 Mbps, $p = 0.014$), FixedPU Oracle (3.71 Mbps), Multi-OLLA (3.66 Mbps), Fixed-Online (3.64 Mbps), and basic OLLA (3.58 Mbps). Cherry-picking a sub-state metric (+218% in burst) to headline the report while burying the overall 6th-place throughput ranking is misleading narrative compression.
   - **What would address it:** Rewrite the Executive Summary to honestly state that Deep A2C achieves lower aggregate throughput than fixed and adaptive heuristics under standard conditions, positioning the architecture specifically as a niche burst-protection mechanism rather than a superior general-purpose link adapter.

5. **[Evidence — distinguishing tests & missing ablations]**
   - **Issue:** The evaluation fails to isolate whether burst resilience is an emergent property of deep policy optimization or an artifact of giving the RL agent an expanded $-6$ dB action space that baselines were denied.
   - **Where:** Section 1 (lines 98–105), Section 3.2 (lines 339–343).
   - **Why it matters:** In v8, the authors expanded the action space to $\{-6, \dots, +4\}$ dB to solve Concern C8, explaining that $-6$ dB allows a 1-step backoff during $+9$ dB interference surges. However, baseline OLLA is constrained to its traditional slow linear step-down ($\delta_{down} \approx 0.1$ to $0.8$ dB). If standard OLLA were equipped with a simple thresholded emergency jump (e.g., jump $-6$ dB upon 2 consecutive NACKs), would it achieve the same 2.23 Mbps burst throughput without a neural network? Furthermore, there is no ablation comparing $L=3$ temporal stacking against $L=1$ Markovian input.
   - **What would address it:** Implement an ablated baseline (Jump-OLLA) that has access to an instantaneous $-6$ dB step upon burst detection, and conduct an ablation isolating the contribution of temporal history length $L \in \{1, 2, 3, 5\}$.

6. **[Novelty & Evidence — weak baselines and missing tuning]**
   - **Issue:** The newly implemented "Multi-OLLA" dual-integrator baseline collapses to 1.57 Mbps in steady state, functioning as a crippled strawman rather than a competitive modern benchmark.
   - **Where:** Section 3.4 (lines 350–355), Appendix D (line 618).
   - **Why it matters:** In 1000-TTI steady state under PF scheduling (Appendix D), Multi-OLLA drops to 1.57 Mbps—drastically below basic single-loop OLLA (2.23 Mbps), Baseline (3.00 Mbps), and Deep A2C (2.12 Mbps). A multi-loop link adapter should never underperform a single-loop integrator by 30% in steady state. This catastrophic collapse indicates that the authors' hand-crafted blending equation ($\alpha(t) \Delta_{fast} + (1-\alpha(t))\Delta_{slow}$) with uncalibrated parameters ($\delta_{fast}=0.8, \delta_{slow}=0.2$) was never properly tuned, producing an under-tuned strawman.
   - **What would address it:** Calibrate the Multi-OLLA fast/slow integration parameters via systematic grid search across step sizes and blending coefficients, ensuring its steady-state performance matches or exceeds single-loop OLLA as reported in the literature.

7. **[Novelty — dressed-up bug fixes & attribution of baseline ML hygiene]**
   - **Issue:** The authors brand the removal of their own circular behavior cloning and the correction of an elementary credit assignment bug as major scientific novelties.
   - **Where:** Executive Summary (lines 17–20), Section 2.1 (lines 288–294), Section 2.2 (lines 295–314).
   - **Why it matters:** In v7, the authors had warm-started their network on the oracle (`bc_warm_eps = 0.08`) and credited unselected users with cell rewards, injecting 90% noise. Enforcing `bc_warm_eps = 0` (random weight initialization) and updating replay buffers only on actual physical transmissions is basic implementation hygiene in applied RL. Framing these routine bug corrections as headline architectural pillars ("Strict Zero-BC Autonomous Learning" and "Scheduled Per-User Credit Assignment") inflates novelty by claiming credit for fixing self-inflicted methodological errors.
   - **What would address it:** Reframe Zero-BC and scheduled credit buffering in the methodology section as standard experimental hygiene corrections, stripping the promotional claims of algorithmic novelty from the Executive Summary.

8. **[Novelty — gross mischaracterisation of prior art & missing foundational literature]**
   - **Issue:** The authors falsely attribute an ad-hoc fast/slow heuristic to an unrelated XR tethering preprint by Ahsen et al. `[2604.20459]`, while failing to cite foundational prior art that established reinforcement learning for outer-loop link adaptation.
   - **Where:** Section 1 (lines 68–73), Section 3.4 (lines 350–355), Appendix B (lines 474–484).
   - **Why it matters:** The authors claim they implemented *"state-of-the-art dual-loop link adaptation (Ahsen et al. [arXiv:2604.20459]): $\Delta_{eff}(t) = \alpha(t) \Delta_{fast}(t) + (1 - \alpha(t)) \Delta_{slow}(t)$"*. In reality, Ahsen et al. `[2604.20459]` (*"Rank-Aware Link Adaptation for XR Tethering Groups with Realistic Tethering Link: A Multi-Offset OLLA Framework"*) investigates rank-aware link adaptation for multi-connected XR devices under point-to-multipoint tethering constraints. It contains no such Doppler-blended dual fast/slow scalar AMC offset integrator. Fabricating the theoretical lineage of a bespoke heuristic by attaching a superficially related preprint citation is unacceptable academic practice. Concurrently, the paper presents RL for OLLA as an unprecedented conceptual advance, completely ignoring foundational prior art—specifically Pulliyakode & Kalyani (2017) `[1708.00994]`, *"Reinforcement learning techniques for Outer Loop Link Adaptation in 4G/5G systems"*, who formalized OLLA as a reinforcement learning problem with discrete offset actions and ACK/NACK rewards nearly ten years ago. Mischaracterising the baseline's source while ignoring the foundational literature fundamentally undermines the paper's claims of novelty.
   - **What would address it:** Remove the false citation and attribution of the dual-integrator formula to Ahsen et al. `[2604.20459]`, cite and benchmark genuine multi-loop OLLA literature, and comprehensively situate Deep A2C within the existing lineage of RL-based link adaptation established by Pulliyakode & Kalyani `[1708.00994]`.

---

### Minor concerns

- **Chase combining equation inconsistency:** In Section 3.3 (line 347), Chase combining is correctly specified in the linear domain as $\gamma_{comb}(m) = 10\log_{10}\left(\sum_{k=1}^m 10^{\gamma_k/10}\right)$, but in Appendix B Section 2.4 (line 492), it is erroneously written as a direct sum of dB values: $\gamma_{comb}(m) = \sum_{k=1}^m \gamma_k$.
- **Missing graphical figures:** Figures 1 through 6 on pages 4–6 are formatted merely as single-sentence captions without actual rendered figure plots, axes, error bands, or legends.
- **Corrupted typography and precision in text:** Line 220 contains unrendered unicode glyphs (`p < 10■■`), and TOST $p$-values toggle arbitrarily between scientific notation (`8.466e-06`) and exact integers (`TOST p = 1`).
- **Unspecified RNG seeds:** While run metadata specifies `Seeds=2`, the exact integer seeds used for pseudo-random channel realization generation are omitted.
- **Incomplete policy entropy details:** The report states in Figure 5 that "entropy annealing" occurred, but fails to provide the exact entropy regularization coefficient $\beta_{ent}$ or its decay schedule in the hyperparameter listings.

---

### Verdict

**Major revision** — The manuscript cannot be accepted in its current form because its headline claims rest on overclaimed novelty, an unviable 53% block error rate, severe mischaracterisation of cited prior art ([2604.20459]), and omission of foundational literature ([1708.00994]), all of which obscure the true nature of the baseline comparisons and the empirical contribution.
