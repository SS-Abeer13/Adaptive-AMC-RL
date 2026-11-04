---
title: "Deep Reinforcement Learning for Link Adaptation in Heterogeneous and Non-Stationary Cellular Downlinks"
subtitle: "Full manuscript draft (v8 corrected results), revised after internal review, 19 October 2026"
---

[DRAFT NOTE: Based on the corrected v8 code and the MATLAB re-run of 3–4 October 2026 (`Optimized/v8/Dataset/fill_summary_*.txt`). Author 1's v3 drafts (abstract, 1.1, 1.2, 1.4, 1.5, 4.3, 4.4, 6.1, 6.3, 6.4, 7) are included as written. The other authors' writeups (1.3, 3.1–3.5, 4.1, 4.2, 4.5, 4.6, 5.6) keep their text, with numbers and model descriptions updated to v8. Sections 2, 3.0, 4.0, 5.1–5.5 and 6.2 are new drafts written from the v8 code and results and need an owner's review. All figures were regenerated from the v8 result files (`AMC writeups/v8_figures`). Revised on 19 October 2026 after the internal review of the v8 draft; the point-by-point response is in `AMC writeups/AMC_v8_review_response.md`.]{custom-style="Author Note"}

# Abstract

Downlink link adaptation selects a modulation and coding scheme (MCS) in every transmission time interval from channel-quality reports that are delayed and noisy. The deployed solution, outer-loop link adaptation (OLLA), corrects these reports with a scalar integrator driven to a fixed block-error-rate (BLER) target [1], [2]. Reinforcement learning (RL) has been proposed to replace or extend this loop [3]–[7], but reported gains are seldom tested against converged or tuned non-adaptive rules. We evaluate a shared multi-user advantage actor-critic (A2C) agent that adds a residual MCS offset to OLLA in a 3GPP-parameterized macrocell with Chase-combining HARQ, Jakes fading, heterogeneous feedback delays and Markov interference bursts. Trained from scratch on observable state, it is compared with cold-start and steady-state OLLA, constant-offset rules and an offline per-class oracle over 100 held-out traces and 10 seeds, using Holm-corrected Wilcoxon and ±2% equivalence tests. The agent is equivalent to the oracle (−0.3%, 90% CI [−1.5, +0.8]%) and beats cold-start OLLA by 2.9%, but trails the best global offset by 2.4% and, after a 1000-TTI warm-up, converged OLLA by 2.9%. Its actions settle on the oracle’s offset (mean −2.26 vs −2.23 CQI steps), and richer state does not help: RL acts as a calibrator, not a channel tracker. We document nine pitfalls that distorted such comparisons in our own pipeline. Two of them alone cost 3.7% and 9–18% throughput: error penalties in the reward, and scheduler gaming, where the agent’s MCS set its proportional-fair priority.

**Index Terms**—Adaptive modulation and coding, LTE, link adaptation, outer-loop link adaptation (OLLA), deep reinforcement learning, advantage actor-critic, HARQ, equivalence testing, 5G NR.

# 1. Introduction

## 1.1 Context and Motivation

In LTE and 5G NR downlinks, the base station chooses an MCS for each scheduled user in every transmission time interval (TTI). A higher MCS carries more bits per resource block but needs a higher signal-to-interference-plus-noise ratio (SINR) to decode; a lower MCS is robust but wastes spectrum. Per-MCS BLER curves are steep "waterfalls," so a one-level error in either direction costs either a failed transport block or unused spectral efficiency.

The scheduler never sees the true SINR at decision time. It sees a channel quality indicator (CQI): a 15-level quantized report that the user measured several TTIs earlier [1]. Two errors compound. Feedback delay makes the report stale whenever the channel decorrelates faster than the report arrives, which happens at vehicular speeds once the delay exceeds the coherence time. Measurement noise blurs the report even when the channel is static. Interference that switches with neighbouring-cell load adds abrupt, non-stationary shifts on top of fast fading.

Link adaptation must therefore track a moving, partially observed channel well enough to stay near the rate–reliability optimum. HARQ moves that optimum. With Chase combining, a failed first transmission is usually recovered on the next attempt [8], so the goodput-optimal first-transmission BLER can sit well above the conventional 10% target. Running at a higher BLER has costs that goodput does not capture: added latency, HARQ buffer occupancy and control-channel load. Whether a learned controller exploits this trade-off, or merely relocates the operating point that a tuned rule could also reach, is the question this paper studies.

## 1.2 Limitations of Standard OLLA

OLLA is the deployed answer to biased and stale CQI [2]. It keeps a per-user offset $o_i$ (in dB) that is added to the reported SINR before the CQI-to-MCS mapping. After each first transmission, $o_i$ rises by $\Delta_{\mathrm{up}}$ on an ACK and falls by $\Delta_{\mathrm{down}}$ on a NACK. Setting the expected drift to zero fixes the long-run first-transmission BLER at the target $P_{\mathrm{tgt}}$:

$$(1-P_{\mathrm{tgt}})\,\Delta_{\mathrm{up}}=P_{\mathrm{tgt}}\,\Delta_{\mathrm{down}}\ \ \Rightarrow\ \ \Delta_{\mathrm{up}}=\Delta_{\mathrm{down}}\,\frac{P_{\mathrm{tgt}}}{1-P_{\mathrm{tgt}}}\qquad (1)$$

This integral controller needs no calibration and is mean-reverting, which explains its adoption. Converged and well configured, it is a strong baseline: after a 1000-TTI warm-up, OLLA ends within 0.1% of the best constant offset and ahead of the learned agent (steady-state run, Section 5.5). This converged loop should not be confused with the Warm-OLLA comparator of the 200-TTI comparison (Section 5.2), which the agent beats. It nevertheless has three structural limits.

- **Integrator lag.** OLLA reacts only to ACK/NACK events that have already happened. With $\Delta_{\mathrm{down}}=0.5$ dB and $P_{\mathrm{tgt}}=0.1$, $\Delta_{\mathrm{up}}\approx0.056$ dB, so recovering from a 9 dB downward correction after an interference burst takes on the order of 160 successful transmissions. During burst onsets, speed changes and after cell entry, the loop lags.

- **A target that the loop does not reach.** $P_{\mathrm{tgt}}=10\%$ is a convention from systems without soft combining, and in a coverage-limited cell the loop cannot hold it. Sweeping the target from 10% to 50% moved the achieved first-transmission BLER only within 0.52–0.57 for cold-start OLLA and 0.38–0.47 after a 1000-TTI warm-up. Users below the lowest MCS’s decodability stay pinned at that MCS whatever the offset, which the code audit estimates at about 38% of user-TTIs.

- **A single scalar state.** The loop cannot use mobility, HARQ state, feedback delay or burst indicators, so a 3 m/s user with a 2-TTI delay and a 30 m/s user with an 8-TTI delay are treated identically. Multi-offset OLLA [9] and self-adaptive SINR tracking from ACK/NACK history [7] address parts of this limit without learning a policy.

## 1.3 Related Work and the Residual RL Formulation

Formulating outer-loop link adaptation as an RL problem is not new, and prior work falls into four groups that bear directly on our findings.

*Classical and self-adaptive outer loops.* OLLA with a fixed BLER target is the deployed reference [2]. Multi-offset OLLA keeps several integrators and blends them according to the channel regime [9], and SALAD tracks the SINR from ACK/NACK history with a self-adapting step [7]. These methods attack integrator lag and cold-start transients without learning a policy. Because our main result is that the learner's gain over OLLA is a start-up effect that disappears once OLLA converges (Section 5.5), they are the natural non-learning alternatives.

*RL that selects the MCS directly.* Tabular and deep RL have been used to choose the MCS from CQI and ACK/NACK feedback [3], [4]. Such agents must first learn, through exploration, the zero-order CQI tracking that OLLA already provides.

*Learned offsets and tuning-free operation.* Pulliyakode and Kalyani cast OLLA offset selection as RL with ACK/NACK feedback, including bandit formulations over offsets [6], and Saxena et al. target tuning-free link adaptation with learned, Bayesian decision rules [5]. Stateless or contextual bandits learn a static or class-conditional offset with very few parameters; if the task reduces to choosing an operating point, as we find here, they are the lighter alternative to a full-MDP deep policy (Section 6.3).

*HARQ and the BLER target.* With Chase combining the goodput-optimal first-transmission BLER lies well above 10% [8], while latency, HARQ occupancy and control overhead argue for a lower one; constrained MDP formulations make this trade-off explicit [10].

Reported gains over OLLA in this literature are typically 10–20%. Most of these studies compare against OLLA at its default target, in simulators without HARQ cost, user heterogeneity or within-trace non-stationarity, and few test whether a constant offset would achieve the same gain. This motivates both our residual formulation and the comparator ladder of Section 3.


The limitations of OLLA (integrator lag, a fixed 10% BLER target and the absence of instantaneous channel-state awareness) motivate the use of learning-based methods for link adaptation. Reinforcement learning (RL) is particularly suitable because MCS selection at each TTI is a sequential decision problem. A decision made at the current TTI can influence subsequent channel-quality feedback, HARQ retransmission load and cumulative throughput.

Existing studies have considered RL-based link adaptation by allowing the agent to select the MCS directly [3], [4]. However, such a formulation requires the agent to learn, through exploration, the basic zero-order feedback tracking already achieved by OLLA before it can learn any improvement over OLLA. This creates an unnecessary learning burden: the agent must first relearn what OLLA already does.

In this work, we therefore retain classical OLLA as a fixed, always-active inner control loop and formulate the RL agent as a residual correction layer on top of it, in the spirit of RL-based outer-loop offset selection [6]. At each TTI, the agent observes the delayed and noisy CQI report together with the OLLA state and selects a bounded discrete offset to modify OLLA's CQI/MCS decision. The zero-offset action leaves the OLLA decision unchanged and therefore exactly reproduces conventional OLLA behavior.

This design allows the RL agent to focus on learning the additional correction required under different channel conditions, rather than relearning the entire link-adaptation process. Consequently, this approach evaluates whether a state-conditional RL policy can improve on a cold-started OLLA controller and approach an offline-calibrated operating point, while retaining OLLA as a reliable baseline and fallback mechanism.

[AUTHOR NOTE: 1.3 now serves as the Related Work section requested in both review rounds, absorbing the literature paragraph formerly at the start of 1.4. Candidate additions, to be verified before citing: target-BLER optimization for link adaptation (Park et al., 2015), self-optimizing OLLA in LTE (Durán et al., 2015), low-overhead DRL link adaptation (Pang et al., 2024) and LOLLA (arXiv:2606.23110, 2026).]{custom-style="Author Note"}

## 1.4 Key Contributions and Novelty

Our earlier campaigns showed how easily such gains appear and disappear. This paper makes four contributions.

- **A fully specified evaluation environment.** A 3GPP-parameterized macrocell (2 GHz, 20 MHz, 100 RBs, 43 dBm, −92 dBm noise floor) with Type-I HARQ and Chase combining modelled as a +2.5 dB SINR gain per retransmission (up to 3), speed-dependent Jakes AR(1) fading [11], per-user CQI delay (2–8 TTIs) and noise, two-state Markov interference bursts, and steep per-MCS BLER waterfalls. Propagation follows 3GPP TR 38.901 [12], while CQI reporting and transport-block sizes use the LTE TS 36.213 abstraction [1] with logistic link curves; no NR TS 38.214 MCS tables or TDL/CDL link-level channels are modelled. All parameters, equations and code are released.

- **A comparator ladder and a pre-registered protocol.** The learner is compared with open-loop CQI mapping, cold-start and steady-state OLLA, a multi-loop OLLA, a global constant offset, an online per-class rule and an offline per-class oracle. The primary test is pre-registered for proportional-fair scheduling. We report paired Wilcoxon tests [13] with Holm correction [14], two one-sided equivalence tests (TOST) at ±2% [15], 90% confidence intervals and both transient and steady-state horizons, over 100 held-out traces and 10 training seeds.

- **A characterization of what the learner achieves.** Trained from random initialization on observable state with a goodput reward, the agent reaches 3.97 Mbps. It is statistically equivalent to the per-class oracle (−0.3%, 90% CI [−1.5, +0.8]%, TOST p = 0.008) and beats cold-start OLLA by 2.9% (Holm p = 0.045). It trails the best global constant offset by 2.4% (Holm p = 0.045) and, in a 1000-TTI steady-state run, trails converged OLLA by 2.9% (Holm $p=1.6\times10^{-10}$; there the learner and the offset tables were still tuned on cold-start episodes). On the 200-TTI horizon it beats both cold-start OLLA and the 10%-target Warm-OLLA (+5.3%). Its actions settle on the oracle’s operating point (mean offset −2.26 vs −2.23), richer state does not help, and fine-tuning a clone of the oracle finds nothing better. In this environment class RL works as an online calibrator of the operating point, not as a channel tracker.

- **A catalogue of evaluation pitfalls.** We document nine defects found in our own pipeline, with the size of the distortion each caused: circular behaviour cloning on the oracle; an entropy schedule that erased a warm start; transient-only scoring of OLLA; zero-padded metric aggregation, which halved baseline burst, edge and fairness metrics; an off-by-one CQI table (≈75% BLER at the nominal operating point); unbounded OLLA windup; simulator-only state features (true speed, delay and burst state), which did not help; scheduler gaming, in which the agent’s own MCS choice set its proportional-fair priority and its throughput fell by 8.6–17.6%, falling further with more training; and error penalties in the reward, which made the agent run more conservatively than the throughput metric rewards and cost 3.7%. We give a checklist for testing "RL beats OLLA" claims before publication.

We do not claim that RL cannot track the channel. We claim that, in this environment class and against these comparators, a carefully trained deep A2C agent learns the right operating point without calibration data, matching a per-class oracle but not a converged or globally tuned rule, and that the protocol above is needed to see this. Lightweight online calibrators such as bandits over offsets [6] or SALAD [7] are not benchmarked here; Section 6.3 argues that they are the bar a deep policy must clear.

## 1.5 Paper Organization

Section 2 presents the system model: deployment, large- and small-scale propagation, non-stationary burst and mobility dynamics, CQI feedback, the BLER link abstraction and HARQ. Section 3 defines the comparators (OLLA variants, constant-offset rules, the per-class oracle and the schedulers) and casts link adaptation as a Markov decision process with three state tiers. Section 4 describes the shared deep A2C agent, its training objective and exploration schedule, and the behaviour-cloning diagnostic; Appendix A summarizes the tabular baselines of earlier versions. Section 5 reports the pre-registered comparison at both horizons, the state ablation, the OLLA target sweep, the constant-offset landscape and statistical diagnostics. Section 6 interprets the results as operating-point selection, discusses the cost of a high first-transmission BLER and gives evaluation and deployment guidelines. Section 7 concludes and outlines directions where state-conditional adaptation may pay off.

# 2. System Model

This section specifies the simulated downlink. All parameters are collected in Table I; they follow 3GPP macrocell assumptions [12] where a standard value exists.

## 2.1 Network Topology and Deployment

A single macro base station (BS) at the centre of a $1000\times1000$ m area serves $N=10$ user equipments (UEs). The BS transmits with 43 dBm over a 20 MHz carrier at $f_c=2$ GHz, divided into 100 resource blocks (RBs), with an antenna height of 25 m and an antenna gain of 8 dBi. UEs are at 1.5 m height and are located indoors. Time advances in transmission time intervals (TTIs) of $T_{\mathrm{tti}}=1$ ms; each simulated trace (episode) lasts $T=200$ TTIs.

UEs move according to a random-waypoint model. UE $i$ starts at a uniformly drawn position $\mathbf{p}_i(0)$ in the area and walks toward a uniformly drawn destination $\mathbf{q}_i$:

$$\mathbf{p}_i(t+1)=\mathbf{p}_i(t)+\Delta d_i(t)\,\frac{\mathbf{q}_i-\mathbf{p}_i(t)}{\lVert\mathbf{q}_i-\mathbf{p}_i(t)\rVert},\qquad \Delta d_i(t)=\kappa\,v_i(t)\,T_{\mathrm{tti}},\qquad (2)$$

If the remaining distance is shorter than $\Delta d_i(t)$, the UE is placed at $\mathbf{q}_i$ and draws a new destination. The 10 m lower bound applies to the 2-D distance used in the path loss, not to the trajectory.

*Time scale of large-scale mobility.* In the simulator the displacement per TTI is $v_i(t)$ metres, i.e. $\kappa=1000$: large-scale mobility (path loss and shadowing) runs 1000 times faster than the TTI clock, whereas the Doppler of the small-scale fading (Section 2.3) uses the physical speed. A user at 3–30 m/s therefore moves 3–30 m per TTI, and the per-TTI shadowing correlation of (4) is $e^{-v_i/50}\in[0.55,0.94]$, so shadowing decorrelates within roughly 2–20 TTIs, the same scale as the 2–8 TTI feedback delay. All results in this paper use $\kappa=1000$; this makes large-scale fading a major source of CQI staleness, and it should be kept in mind when reading the results as statements about physical speeds.

[AUTHOR NOTE: The factor $\kappa=1000$ was found during the internal review of the v8 draft (`generateChannel_v7.m` adds `v` metres per TTI). Decide whether to (a) keep it and present it as a deliberate time compression, as written here, or (b) set $\kappa=1$ and re-run the campaign, which would make path loss and shadowing almost static within a 200-TTI trace.]{custom-style="Author Note"}

## 2.2 Large-Scale Path Loss and Shadowing

Path loss follows the 3GPP urban-macro non-line-of-sight model [12],

$$\mathrm{PL}_i(t)=13.54+39.08\log_{10}d^{3\mathrm{D}}_i(t)+20\log_{10}f_c^{[\mathrm{GHz}]}-0.6\,(h_{\mathrm{UE}}-1.5)\ \ \text{dB},\qquad (3)$$

with $d^{3\mathrm{D}}_i$ in metres. Log-normal shadowing with standard deviation $\sigma_{\mathrm{SF}}=6$ dB is spatially correlated along each UE's path following Gudmundson's model [16]:

$$\mathrm{SF}_i(t)=r_i(t)\,\mathrm{SF}_i(t-1)+\sigma_{\mathrm{SF}}\sqrt{1-r_i(t)^2}\;w_i(t),\qquad r_i(t)=e^{-\Delta d_i(t)/d_{\mathrm{corr}}},\qquad (4)$$

where $\Delta d_i(t)$ is the distance moved in the last TTI, $d_{\mathrm{corr}}=50$ m, $w_i(t)\sim\mathcal{N}(0,1)$ and $\mathrm{SF}_i(1)\sim\mathcal{N}(0,\sigma_{\mathrm{SF}}^2)$. An outdoor-to-indoor penetration loss of 20 dB and an implementation margin of 6 dB are applied. The thermal noise floor over 20 MHz with a 9 dB UE noise figure is $-174+10\log_{10}(20\cdot10^6)+9\approx-92$ dBm. The resulting SINR of UE $i$ is

$$\gamma_i(t)=P_{\mathrm{tx}}+G-\mathrm{PL}_i(t)-\mathrm{SF}_i(t)+10\log_{10}|h_i(t)|^2-L_{\mathrm{O2I}}-P_N-M_{\mathrm{impl}}-I_{\mathrm{b}}(t)\ \ \text{dB},\qquad (5)$$

where $h_i(t)$ is the small-scale fading coefficient (Section 2.3) and $I_{\mathrm{b}}(t)$ is the additional interference during bursts (Section 2.4). The link budget is coverage-limited: users at the cell edge or in deep shadowing frequently fall below the decoding threshold of the lowest MCS, which our code audit estimates for about 38% of user-TTIs.

## 2.3 Small-Scale Fading and Doppler Dynamics

Small-scale fading is a per-user first-order autoregressive Rayleigh process whose correlation follows the Jakes spectrum [11]:

$$h_i(t)=\rho_i(t)\,h_i(t-1)+\sqrt{1-\rho_i(t)^2}\;u_i(t),\qquad \rho_i(t)=J_0\!\left(2\pi\,\frac{v_i(t)f_c}{c}\,T_{\mathrm{tti}}\right),\qquad (6)$$

with $u_i(t)\sim\mathcal{CN}(0,1)$, $J_0$ the zeroth-order Bessel function and $\rho_i(t)$ clipped to $[0,0.9999]$ and $h_i(1)\sim\mathcal{CN}(0,1)$. At 2 GHz, a pedestrian at 3 m/s has $\rho\approx0.996$ per TTI, whereas a vehicle at 30 m/s has $\rho\approx0.65$, so the channel seen by a 2–8 TTI old CQI report is nearly fresh for slow users and largely decorrelated for fast ones.

## 2.4 Non-Stationary Dynamics

Two mechanisms make each trace non-stationary.

*Interference bursts.* A cell-wide two-state Markov chain switches between a calm and a burst state. In each TTI the chain enters a burst with probability $p_{\mathrm{in}}=1/250$ and leaves it with probability $p_{\mathrm{out}}=1/120$, so mean dwell times are 250 and 120 TTIs and, in steady state, the cell is in a burst about $p_{\mathrm{in}}/(p_{\mathrm{in}}+p_{\mathrm{out}})\approx32\%$ of the time. Every trace starts in the calm state, so the expected burst share of the scored TTIs is 24.6% in a 200-TTI trace and 31% in a 1000-TTI trace. During a burst all users suffer an extra interference of $I_{\mathrm{b}}=9$ dB. Other burst intensities were studied only with the pre-audit code and are not reported (Section 5.3).

*User heterogeneity and speed switches.* A heterogeneity level $h\in[0,1]$ controls the spread of user conditions. For $h>0$, each user's CQI feedback delay $d_i$ is drawn uniformly from the integers $\{\mathrm{round}(4-2h),\dots,\mathrm{round}(4+4h)\}$ (2–8 TTIs at $h=1$) and its initial speed uniformly from $[3,\,3+27h]$ m/s. The homogeneous setting $h=0$ is a separate case rather than the limit of these formulas: all users then have a delay of 4 TTIs and a speed of 5 m/s. With probability 0.5, a user changes speed once, at a uniformly drawn time between 30% and 70% of the trace, to a new speed drawn from the same distribution. All reported runs use $h=1$.

## 2.5 Uplink Feedback and Delay Modeling

Each user reports its SINR with its own delay $d_i$ and Gaussian measurement noise:

$$\tilde{\gamma}_i(t)=\gamma_i\big(\max(t-d_i,1)\big)+\epsilon_i(t),\qquad \epsilon_i(t)\sim\mathcal{N}(0,\sigma_{\mathrm{meas}}^2),\quad \sigma_{\mathrm{meas}}=1\ \text{dB},\qquad (7)$$

so for the first $d_i$ TTIs of a trace the report refers to the first TTI.

The reported SINR, shifted by the OLLA offset, is quantized to one of 15 CQI levels [1],

$$f_{\mathrm{CQI}}(x)=\max\{q\in\{1,\dots,15\}:\ x\ge\theta_q\},\qquad \theta_1=-\infty,\quad \theta_q=\vartheta_{q-1}\ (q=2,\dots,15),\qquad (8)$$

and CQI $q$ is transmitted with MCS $q-1$. Here $\vartheta_m$ is the 10%-BLER point of MCS $m$ (Section 2.6), so a report of CQI $q$ guarantees, for an accurate and fresh SINR, a first-transmission BLER of at most 10% at MCS $q-1$; CQI 1 is the MCS-0 fallback used whenever the SINR is below $\vartheta_1$. Earlier versions of our simulator shifted this table by one level, which put the nominal operating point at about 75% BLER; we return to this in Section 6.4.

## 2.6 Physical Link Abstraction and BLER

The probability that a first transmission with MCS $m$ fails at SINR $\gamma$ follows a logistic waterfall [2],

$$\mathrm{BLER}_m(\gamma)=\frac{1}{1+\exp\!\big(k_m(\gamma-c_m)\big)},\qquad c_m=\vartheta_m-\frac{\ln 9}{k_m},\qquad (9)$$

so that $\mathrm{BLER}_m(\vartheta_m)=0.1$ at the MCS's threshold $\vartheta_m$. The thresholds are $\vartheta_{0},\dots,\vartheta_{14}=-6.7,\,-5.0,\,-3.2,\,-1.5,\,0.8,\,2.0,\,4.5,\,6.8,\,9.2,\,11.5,\,14.0,\,16.3,\,18.7,\,20.5,\,21.8$ dB and the slopes $k_m=3.0+0.2m$ per dB, so higher MCSs have steeper waterfalls. Only $\vartheta_1,\dots,\vartheta_{14}$ enter the quantizer (8); $\vartheta_0$ fixes the BLER curve of MCS 0, which is used whenever the SINR is below $\vartheta_1$. A transmission outcome is drawn from (9) at the true SINR of the TTI in which it is sent. Fig. 1 shows the resulting curves. A successful transmission delivers a transport block whose size $\mathrm{TBS}(m,n_{\mathrm{RB}})$ is taken from the LTE transport-block-size table [1], using row $I_{\mathrm{TBS}}=m$ for MCS $m$ (so "MCS" indexes the TBS rows rather than the 29-entry LTE MCS table); with all 100 RBs allocated, $\mathrm{TBS}(m,100)=2792,\,3624,\,4584,\,5736,\,7224,\,8760,\,10296,\,12216,\,14112,\,15840,\,17568,\,19848,\,22920,\,25456,\,28336$ bits for $m=0,\dots,14$. The delivered throughput in that TTI is $\mathrm{TBS}/T_{\mathrm{tti}}$.

![Per-MCS first-transmission BLER waterfalls of (9): 15 MCSs from MCS 0 (left) to MCS 14 (right), each crossing 10% BLER at its threshold.](v8_waterfalls.png){width=6in}

## 2.7 HARQ with Chase Combining

Failed transport blocks are retransmitted with Type-I HARQ and Chase combining [8]. A retransmission reuses the MCS and transport block of the original transmission and benefits from soft combining, modelled as an SINR gain of 2.5 dB per previous attempt:

$$\gamma^{\mathrm{eff}}_i(t)=\gamma_i(t)+2.5\,n^{\mathrm{retx}}_i\ \ \text{dB},\qquad n^{\mathrm{retx}}_i\in\{1,2,3\}.\qquad (10)$$

A transport block that still fails after three retransmissions is dropped. A pending retransmission occupies the user's next scheduled transmission opportunity, during which the link-adaptation decision for a new transport block is not used, and it is credited to throughput only when the block is finally delivered. How retransmission outcomes update the OLLA offset is specified in Section 3.1. Because the BLER curves are steep, the combining gain makes a retransmission very likely to succeed when the channel has not changed much: for a first transmission sent exactly at its 50% point, (9) gives a retransmission failure probability of $1/(1+e^{2.5k_m})<6\times10^{-4}$ for every MCS. Section 6.2 discusses what this implies for the optimal first-transmission BLER.

Table I. Simulation parameters (headline configuration).

|Parameter|Value|
|:----------|:-----------------------|
| Carrier frequency, bandwidth, RBs | 2 GHz, 20 MHz, 100 RBs |
| TTI, trace length, burn-in | 1 ms, 200 TTIs, first 50 TTIs excluded from metrics |
| BS power, antenna gain, height | 43 dBm, 8 dBi, 25 m |
| Cell area, users | 1000 × 1000 m, BS at centre, $N=10$ |
| UE height, mobility | 1.5 m indoor, random waypoint, $v_i$ metres per TTI ($\kappa=1000$) |
| Path loss | 3GPP UMa NLOS [12] |
| Shadowing | 6 dB, correlation distance 50 m |
| O2I loss, implementation margin | 20 dB, 6 dB |
| Noise figure, noise floor | 9 dB, −92 dBm |
| Small-scale fading | Rayleigh, Jakes AR(1) per TTI |
| Interference bursts | +9 dB; mean dwell 250 TTIs calm, 120 TTIs burst; traces start calm |
| Heterogeneity $h$ | 1 |
| User speed | uniform on [3, 30] m/s; one switch with probability 0.5 |
| CQI delay, measurement noise | uniform on {2,…,8} TTIs, 1 dB |
| CQI/MCS levels | 15 CQI, 15 MCS (MCS = CQI − 1) |
| BLER model | logistic, 10% point at $\vartheta_m\in[-6.7,21.8]$ dB, slope 3.0–5.8 /dB |
| HARQ | Chase combining, +2.5 dB per retransmission, up to 3 retransmissions |
| OLLA | $P_{\mathrm{tgt}}=0.1$, $\Delta_{\mathrm{down}}=0.5$ dB, $\Delta_{\mathrm{up}}\approx0.056$ dB, offset bounded to ±10 dB |
| Multi-OLLA | fast/slow loops with $\Delta_{\mathrm{down}}=0.8$ / 0.2 dB |
| Residual action set | $\{-6,\dots,+4\}$ CQI steps (11 actions) |


# 3. Problem Formulation and Benchmarks

This section defines the comparison suite and the learning problem. All schemes select, for every user in every TTI, the CQI (and hence MCS) used for a new transport block; they differ only in how this choice is made. *Baseline* maps the reported SINR directly through (8) without any correction. *OLLA* adds the integrator offset of Section 3.1, started from zero at the beginning of each trace; *Warm-OLLA* is the same loop after a 1000-TTI warm-up, and *Multi-OLLA* blends a fast and a slow loop. *Fixed*, *Fixed-Online* and *FixedPU* add constant offsets on top of OLLA, calibrated offline (Section 3.3). The proposed Deep A2C controller also acts on top of OLLA, by selecting a residual offset in CQI steps (Section 3.4). Under this residual design every scheme except Baseline keeps an active OLLA loop, and the zero action of the learner reproduces OLLA exactly. Section 3.2 describes the schedulers that decide which user is served.

## 3.1 Classical Benchmark: OLLA

Outer-loop link adaptation (OLLA) is used as a classical benchmark for dynamically adjusting the link-adaptation operating point toward a desired target block error rate (BLER) [2]. Unlike the proposed RL-based controller, OLLA uses a scalar offset that is updated directly from the success or failure of each transmission. Let $o_t$ denote the OLLA offset at transmission instant $t$. For an acknowledged (ACK) transmission, the offset is increased by $\Delta_{\mathrm{up}}$, whereas a negatively acknowledged (NACK) transmission decreases the offset by $\Delta_{\mathrm{down}}$:

$$o_{t+1}=\begin{cases} o_t+\Delta_{\mathrm{up}}, & \text{if ACK},\\ o_t-\Delta_{\mathrm{down}}, & \text{if NACK}.\end{cases}\qquad (11)$$

In our implementation, the downward step is fixed at $\Delta_{\mathrm{down}}=0.5$ dB, while the upward step is selected according to the target BLER $P_{\mathrm{tgt}}$ as

$$\Delta_{\mathrm{up}}=\Delta_{\mathrm{down}}\,\frac{P_{\mathrm{tgt}}}{1-P_{\mathrm{tgt}}}.\qquad (12)$$

This is the zero-drift condition (1) of Section 1.2: if $P$ is the long-run NACK probability, the expected offset change $(1-P)\Delta_{\mathrm{up}}-P\Delta_{\mathrm{down}}$ vanishes exactly at $P=P_{\mathrm{tgt}}$. For the default configuration used in our experiments, $P_{\mathrm{tgt}}=0.1$ and $\Delta_{\mathrm{down}}=0.5$ dB, resulting in

$$\Delta_{\mathrm{up}}=0.5\cdot\frac{0.1}{0.9}\approx 0.0556\ \text{dB}.\qquad (13)$$

Thus, an ACK produces a relatively small upward correction, while a NACK produces a larger downward correction. This compensates for the fact that NACKs are expected to occur only approximately 10% of the time at the desired operating point.

In each transmission time interval (TTI), OLLA is applied to the transmissions selected by the scheduler. The implementation estimates the instantaneous BLER from the selected MCS and channel state and samples the transmission outcome accordingly. New transmissions update the offset as in (11). When HARQ is enabled, retransmissions use chase combining and update the offset with half steps: $+\Delta_{\mathrm{up}}/2$ when a retransmission is acknowledged and $-\Delta_{\mathrm{down}}/2$ when it fails, except that the failure of the third and last retransmission, which drops the block, costs $-\Delta_{\mathrm{down}}$ instead of $-\Delta_{\mathrm{down}}/2$ (a block that fails all four attempts therefore lowers the offset by $3\Delta_{\mathrm{down}}$ in total). Updates take effect at the next TTI; the ACK/NACK itself is not delayed.

The retransmission updates shift the equilibrium of (1). If the first retransmission almost always succeeds (Section 2.7), a failed first transmission is followed by an ACK worth $+\Delta_{\mathrm{up}}/2$, so the net drift per failed block is $-\Delta_{\mathrm{down}}+\Delta_{\mathrm{up}}/2$ and the zero-drift first-transmission BLER becomes $P^*\approx P_{\mathrm{tgt}}/(1-P_{\mathrm{tgt}}/2)\approx0.105$ for $P_{\mathrm{tgt}}=0.1$, a small upward shift. Finally, the offset is bounded,

$$o_t\leftarrow\min\big(\max(o_t,-o_{\max}),\,o_{\max}\big),\qquad o_{\max}=10\ \text{dB}.\qquad (14)$$

Without this bound, users whose SINR lies below the lowest MCS threshold keep receiving NACKs at CQI 1, so their offset winds down without limit and needs tens of ACKs to recover once the channel improves. Practical OLLA implementations bound the offset for the same reason.

*Warm-OLLA and Multi-OLLA.* Two further classical comparators use the same update. *Warm-OLLA* runs the loop for 1000 TTIs on an independent channel segment before the scored trace begins, so that it starts from a converged offset. The segment keeps each user's delay and speed profile but draws new positions, shadowing, fading and burst history. *Multi-OLLA*, inspired by multi-offset OLLA [9], maintains a fast loop ($\Delta_{\mathrm{down}}=0.8$ dB) and a slow loop ($\Delta_{\mathrm{down}}=0.2$ dB) per user, each with $\Delta_{\mathrm{up}}$ from (12), and applies the blend $o=\alpha_{\mathrm{M}} o^{\mathrm{fast}}+(1-\alpha_{\mathrm{M}})o^{\mathrm{slow}}$ with
$\alpha_{\mathrm{M}}=0.5+0.3\cdot\mathbb{1}\{|\beta^{(4)}_{i,t}|>1\ \text{dB/TTI}\}+0.2\cdot\mathbb{1}\{n_{i,t}>0.4\}$,
where $\beta^{(4)}_{i,t}$ is the four-TTI slope of the reported SINR and $n_{i,t}$ the smoothed NACK indicator, both defined in Section 3.5. Both loops are updated in parallel from the outcome of the transmission sent with the blended offset, with full steps for first transmissions and retransmissions alike, and both are bounded by (14).

The default benchmark uses a target BLER of 0.1, while the robustness of the classical controller is evaluated by sweeping the target BLER over $P_{\mathrm{tgt}}\in\{0.1,0.2,0.3,0.4,0.5\}$, both from a cold start and after the 1000-TTI warm-up.

![Cell throughput (left) and achieved first-transmission BLER (right) of the classical OLLA controller re-tuned across target-BLER operating points, from a cold start and after a 1000-TTI warm-up (PF, 100 held-out traces). Horizontal lines show the Deep A2C controller and the best global constant offset. The dashed diagonal marks achieved BLER equal to the target.](v8_olla_sweep.png){width=6.3in}

Figure 2 shows the resulting cell throughput together with the achieved BLER. The cold-started OLLA operating point remains relatively stable over the target-BLER sweep, with mean throughput values of approximately 3.84, 3.77, 3.85, 3.81 and 3.76 Mbps for target BLERs of 0.1, 0.2, 0.3, 0.4 and 0.5, respectively. Importantly, increasing the target BLER does not produce a monotonic throughput improvement. After warm-up the loop does respond to its target, rising from 3.79 Mbps at 0.1 to a best of 3.91 Mbps at 0.4. Even the best re-tuned OLLA remains below the Deep A2C controller (by 1.6%, not significant, $p=0.074$) and below the best global constant offset (4.07 Mbps).

The achieved BLER explains this. A cold-started loop does not reach any of its targets: its first-transmission BLER stays between 0.52 and 0.57 as the target moves from 0.1 to 0.5, because over a 200-TTI trace each user receives too few ACK/NACK updates for the integrator to settle, and users below the lowest MCS threshold stay at high BLER whatever their offset. After warm-up the achieved BLER ranges from 0.38 to 0.47, closer to but still well above the lower targets. The sweep therefore measures the sensitivity of OLLA to its target under the convergence conditions of each horizon, and Section 5.5 compares all schemes at steady state.

A fundamental limitation of this benchmark is that its adaptation mechanism is governed by a single scalar offset and a manually specified target BLER. Consequently, the controller does not explicitly account for the broader system state, such as heterogeneous user conditions, temporal channel dynamics, scheduler behavior or interactions between users. The target BLER is also fixed during operation, meaning that the controller cannot learn to select different operating points according to the instantaneous system condition. These limitations make OLLA an appropriate classical reference: it provides a simple and widely interpretable link-adaptation mechanism while leaving room for a controller that selects its operating point from a richer state. Whether such a controller improves on OLLA through dynamic, state-dependent decisions or through a better static operating point is examined in Sections 5 and 6.1.

## 3.2 Multi-User Scheduling Framework

Because the simulated cell serves $N$ users simultaneously, a scheduling policy is required to decide, at each transmission time interval (TTI), which user is granted the available resource blocks (RBs). Unlike the link-adaptation controllers evaluated in this study, the scheduler does not modify the MCS or power offset directly; rather, it determines whose channel state and OLLA/RL-adjusted operating point are acted upon in a given TTI. Three scheduling regimes are implemented: Proportional Fair (PF), Round Robin (RR) and Equal Share (EQ).

Here $t$ represents the current TTI index, $N$ the number of active users, $\overline{R}_i(t)$ the exponentially averaged historical throughput of user $i$, and $r_i(t)$ the instantaneous achievable rate ("potential rate") of user $i$ under its current channel state. The PF scheduler selects the served user $i^*(t)$ according to

$$i^*(t)=\arg\max_i\ \frac{r_i(t)}{\max\!\big(\overline{R}_i(t),\,r_{\mathrm{floor}}\big)},\qquad (15)$$

where $r_{\mathrm{floor}}=0.1$ is a small floor value that prevents the ratio from becoming numerically unstable when a user's historical average rate approaches zero. All available RBs are then allocated to the selected user for that TTI. This ratio-based rule is the discrete, greedy implementation of the proportional fairness criterion of Kelly et al. [17], who show that allocations of this type converge to one that is both efficient and fair in the sense that, asymptotically, no reallocation can produce a net positive sum of proportional changes in user rates.

*Which rate the scheduler sees.* In the primary set-up, $r_i(t)$ is the transport-block rate of the OLLA reference CQI of user $i$, i.e. of the MCS that OLLA alone would choose, or of the stored MCS when a HARQ retransmission is pending. It is deliberately not the rate of the MCS finally chosen by the link-adaptation controller. When the controller's own choice enters (15), a learner can raise its users' scheduling priority by inflating the MCS, and with a per-user reward it is paid for doing so. We observed exactly this in an earlier configuration of our pipeline: with the scheduler ranking users on the agent's chosen MCS, the trained agent's throughput was 8.6% (Tier-O state) to 17.6% (Tier-A state) lower than with ranking on the OLLA reference rate, the Tier-B agent was only 5.6% better than random actions, and five times more training lowered Tier-O throughput further, to 2.88 Mbps. Ranking on the reference rate keeps scheduling and link adaptation separate.

The historical rate $\overline{R}_i(t)$ is updated once per TTI using an exponential moving average with smoothing factor $\alpha_{\mathrm{PF}}=0.05$:

$$\overline{R}_i(t+1)=(1-\alpha_{\mathrm{PF}})\,\overline{R}_i(t)+\alpha_{\mathrm{PF}}\,x_i(t),\qquad (16)$$

where $x_i(t)$ is the rate actually delivered to user $i$ at TTI $t$ (zero if user $i$ was not scheduled). This gives the PF metric an effective memory horizon of approximately $1/\alpha_{\mathrm{PF}}\approx 20$ TTIs, so that a user's priority reflects recent throughput history rather than instantaneous fluctuations alone.

The two baseline regimes omit channel awareness entirely. Round Robin serves users in a fixed cyclic order,

$$i^*(t)=\big[(t-1)\bmod N\big]+1,\qquad (17)$$

granting every user an equal number of scheduling opportunities over time regardless of channel quality. Equal Share instead splits the total RB budget evenly across all $N$ users at every TTI,

$$\mathrm{RB}_i=\left\lfloor \mathrm{RB}_{\mathrm{total}}/N\right\rfloor,\quad i=1,\dots,N,\qquad (18)$$

with any remaining $\mathrm{RB}_{\mathrm{total}}-N\lfloor \mathrm{RB}_{\mathrm{total}}/N\rfloor$ resource blocks distributed one at a time to the first users in index order so that the full RB budget is always allocated. RR therefore enforces fairness in scheduling opportunities over time, while EQ enforces fairness in resource share within each TTI; neither exploits the multiuser diversity available from independently fluctuating user channels, which is the mechanism PF is designed to capture.

Because the scheduler regime changes the statistics of which channel states are seen by the link-adaptation controller, its identity is made observable to the learning agent rather than left implicit. At each TTI, the active mode is mapped to an integer code and a corresponding one-hot vector over the set of scheduler regimes, which the deep agent appends to its state input. This design choice allows a single policy to specialize its behavior per scheduling regime instead of being forced to average across PF, RR and EQ, which was found in earlier iterations of the framework to degrade PF-specific performance. When several regimes are enabled for training, the scheduler regime for each episode is drawn from a categorical distribution over the candidate schedulers using inverse-CDF sampling, with regime weights normalized to sum to one and falling back to a uniform distribution if unspecified.

The pre-registered comparison of this paper trains and evaluates under PF only (Section 4.5). RR and EQ are retained in the framework and in the state encoding but are not part of the reported campaign. In every reported run the scheduler context is therefore the constant vector $\mathbf{c}_t=[1,0,0]^{T}$; it is kept as an input only for compatibility with the multi-scheduler code.

[AUTHOR NOTE: The v7 writeup of this section reported RR and EQ results (Fig. 10 of v7). Those runs used the pre-audit code and are not repeated for v8. Either re-run RR/EQ evaluation on the v8 primary set-up or keep this section PF-only as written.]{custom-style="Author Note"}

## 3.3 Offline-Calibrated Oracle Benchmark: FixedPU Formulation

To establish a strong non-adaptive reference for the proposed learning-based controller, we construct FixedPU, an offline-calibrated, per-user-class fixed-offset benchmark. Unlike OLLA, which continuously updates its offset from ACK/NACK feedback, FixedPU performs no online adaptation of its class offset during evaluation. Instead, the offset is optimized offline on held-out calibration traces and subsequently fixed according to the long-term delay and mobility characteristics of each user. Like all residual schemes, FixedPU keeps the OLLA loop of Section 3.1 active and applies its offset $o$ in integer CQI steps to the OLLA reference, i.e. through (27) with $a_{i,t}=o$; the same holds for Fixed and Fixed-Online. It therefore represents an oracle-like operating point within the considered class partition and finite offset search space.

Users are partitioned into a $2\times3$ grid according to feedback delay and mean mobility. Let $d_i$ and $\overline{v}_i$ denote the feedback delay and the mean speed of user $i$ over the whole trace, respectively. Because $\overline{v}_i$ averages over the entire trace, the class anticipates any later speed switch; this non-causal knowledge is part of what makes FixedPU an oracle. The delay class is defined as

$$c_d(i)=\begin{cases}1, & d_i\le 4,\\ 2, & d_i\ge 5,\end{cases}\qquad (19)$$

while the mobility class is

$$c_v(i)=\begin{cases}1, & \overline{v}_i<10\ \text{m/s},\\ 2, & 10\le\overline{v}_i\le 20\ \text{m/s},\\ 3, & \overline{v}_i>20\ \text{m/s}.\end{cases}\qquad (20)$$

This produces six user classes that jointly capture two important sources of link-adaptation uncertainty: feedback staleness and user mobility.

For each class, FixedPU searches the candidate offset set

$$\mathcal{O}=\{-5,-4,\dots,2,3\}.\qquad (21)$$

This nine-point grid is narrower than the learner's eleven actions $\{-6,\dots,+4\}$ ((26)). The difference does not bind: every calibrated optimum ($-2$ and $-4$ here, $0$ to $-4$ at steady state) lies strictly inside the grid, and the learner uses its two extra actions in well under 1% of decisions.

The calibration procedure uses $N_{\mathrm{cal}}=20$ independently generated traces, each with a simulation duration of 200 TTIs (1000 TTIs for the steady-state run of Section 5.5) and a cold-started OLLA loop, and these traces are explicitly separated from the subsequent evaluation traces. Proportional-fair (PF) scheduling is used during calibration. After discarding the configured burn-in interval, the mean throughput obtained by every user is accumulated according to its delay–mobility class for each candidate offset.

More formally, if $\mathcal{U}_{d,v}$ denotes the set of calibration observations belonging to class $(d,v)$, the class-specific oracle offset can be expressed as

$$o^*_{d,v}=\arg\max_{o\in\mathcal{O}}\ \frac{1}{|\mathcal{U}_{d,v}|}\sum_{u\in\mathcal{U}_{d,v}}\overline{T}_u(o),\qquad (22)$$

where $\overline{T}_u(o)$ denotes the post-burn-in mean throughput of user $u$ under fixed offset $o$. The resulting six optimized offsets form the lookup table

$$\mathbf{O}^*=\begin{bmatrix}o^*_{1,1}&o^*_{1,2}&o^*_{1,3}\\ o^*_{2,1}&o^*_{2,2}&o^*_{2,3}\end{bmatrix}.\qquad (23)$$

During evaluation, each user is assigned the pre-calibrated offset corresponding to its class, and this offset remains fixed rather than being adjusted according to instantaneous ACK/NACK outcomes or short-term channel evolution. A global fixed-offset comparator (Fixed) is also obtained by maximizing aggregate calibration throughput over the same candidate set,

$$o^*_{\mathrm{G}}=\arg\max_{o\in\mathcal{O}}\ \sum_u \overline{T}_u(o).\qquad (24)$$

If a class contains no calibration users, its entry in $\mathbf{O}^*$ falls back to $o^*_{\mathrm{G}}$. In the primary configuration the calibration selects $o^*_{\mathrm{G}}=-2$ and $\mathbf{O}^*=[-2,\,-2,\,-2;\;-4,\,-2,\,-2]$: every class uses $-2$ except slow users with long feedback delay, which use $-4$. Both optima lie inside the grid.

*Fixed-Online.* FixedPU assigns classes from each user's true delay and true mean speed over the whole trace. Fixed-Online applies the same calibrated table but assigns the class online, from the user's feedback delay and its mean speed over the last 20 TTIs. It tests how much of FixedPU's advantage depends on knowing the class in advance. Because the speed estimate uses simulator speeds rather than a Doppler estimate, it is still optimistic.

The distinction between FixedPU and the online controllers is important. FixedPU benefits from offline access to held-out calibration traces and class-specific exhaustive search, allowing it to select the throughput-maximizing static operating point within the predefined offset grid before evaluation. However, it cannot react online to instantaneous fading, interference bursts, ACK/NACK history or other short-term state changes. Thus, FixedPU should be interpreted as a strong non-adaptive oracle benchmark within the specified class structure and search space, rather than as an unconstrained theoretical capacity bound. It is not an upper bound on static policies either: the single global offset (Fixed) achieves 4.07 Mbps against 3.99 Mbps for FixedPU in the primary configuration, most likely because six separate offsets estimated from the same calibration data are noisier than one.

The comparison with FixedPU therefore serves a stricter purpose than comparison with a conventional online baseline such as OLLA. Rather than asking only whether the RL controller improves upon a predetermined link-adaptation rule, FixedPU tests whether online state-dependent decision making can match or exceed an offline class-wise tuned static operating point. Cases in which A2C approaches FixedPU indicate that the learned controller can recover performance close to an offline-tuned reference without requiring class-wise grid-search calibration at deployment, whereas deviations expose the remaining robustness and generalization gap. Section 5 reports this comparison across state tiers, rewards and scheduler inputs (Fig. 6, Table III, Table V and, in Section 6.1, Table VIII) and at steady state (Table IV, Section 5.5).

## 3.4 MDP Formulation for RL-AMC

The adaptive modulation and coding problem is formulated as a Markov decision process (MDP) $\mathcal{M}=(\mathcal{S},\mathcal{A},P,R,\gamma)$ [18], where the agent observes the current link and system state, selects a residual CQI adjustment, and receives a reward determined by the resulting delivered throughput. Rather than predicting an MCS directly, the RL controller operates residually around the conventional CQI-based link-adaptation reference. This retains the structure of the existing link-adaptation mechanism while allowing the learned policy to correct its operating point according to the observed system state.

At TTI $t$, the conventional link-adaptation reference for user $i$ is obtained from the delayed CQI/SINR observation and the current OLLA offset,

$$q^{\mathrm{ref}}_{i,t}=f_{\mathrm{CQI}}\big(\tilde{\gamma}_{i,t}+o_{i,t}\big),\qquad (25)$$

where $\tilde{\gamma}_{i,t}$ denotes the available (delayed and noisy) channel observation, $o_{i,t}$ is the OLLA offset, and $f_{\mathrm{CQI}}(\cdot)$ denotes the SINR-to-CQI mapping (8). The RL agent does not replace this reference mapping. Instead, it selects a discrete residual action

$$a_{i,t}\in\mathcal{A}=\{-6,-5,\dots,3,4\},\qquad (26)$$

expressed in CQI steps relative to $q^{\mathrm{ref}}_{i,t}$. The transmitted CQI is consequently

$$q^{\mathrm{tx}}_{i,t}=\mathrm{clip}\big(q^{\mathrm{ref}}_{i,t}+a_{i,t},\,q_{\min},\,q_{\max}\big),\qquad (27)$$

with $q_{\min}=1$ and $q_{\max}=15$. Hence, negative actions produce a more conservative MCS selection, $a_{i,t}=0$ recovers the underlying OLLA operating point, and positive actions select a more aggressive operating point. Clipping guarantees that the resulting CQI remains within the supported MCS range. The eleven actions span the calibrated optimum ($-2$, and $-4$ for one class) with margin on both sides.

The state $s_{i,t}\in\mathcal{S}$ is constructed from information available to the controller at decision time. In the primary (Tier-O) configuration, the state includes the current reference CQI, its temporal change, the observed SINR and its short-term temporal evolution, the current OLLA offset, a four-step SINR slope, recent NACK behavior, HARQ status, the user's normalized PF average rate and the scheduler context, stacked over the last three TTIs (Section 3.5). The scheduler identity is represented through a one-hot context vector. This state construction allows the policy to condition its residual MCS adjustment on substantially richer information than the scalar ACK/NACK-driven OLLA update.

The environment transition,

$$s_{t+1}\sim P(\cdot\mid s_t,a_t),\qquad (28)$$

is induced by the underlying channel evolution, delayed CQI feedback, mobility and interference processes, HARQ state, scheduler decisions and transmission outcomes. After the users select their actions, the scheduler allocates the available resource blocks and the corresponding transmissions are evaluated using the instantaneous physical-layer state. Successful transmissions contribute their delivered transport-block sizes to the cell throughput, while failed transmissions may enter the HARQ retransmission process.

The reward is defined from delivered goodput and is assigned per scheduled user. If $T_{i,t}$ denotes the throughput delivered to user $i$ at TTI $t$ (in Mbps), the reward for user $i$'s decision is

$$r_{i,t}=\frac{T_{i,t}}{C_R}-\lambda_{\mathrm{drop}}\,\mathbb{1}^{\mathrm{drop}}_{i,t}-\lambda_{\mathrm{retx}}\,\mathbb{1}^{\mathrm{NACK}}_{i,t},\qquad (29)$$

where $C_R=30$ is a numerical reward-scaling factor. In the primary configuration $\lambda_{\mathrm{drop}}=\lambda_{\mathrm{retx}}=0$, so the reward is pure goodput and matches the metric on which the agent is scored; a "reliability variant" with $\lambda_{\mathrm{retx}}=0.05$ per NACK and $\lambda_{\mathrm{drop}}=0.5$ per dropped block is reported in Sections 4.3 and 6.1. Only users that are scheduled in a TTI produce a training transition, because the action of an unscheduled user does not affect any transmission; each user's decisions therefore form their own sequence over the TTIs in which that user is served. Importantly, unsuccessful new transmissions contribute no immediate delivered throughput, while successful HARQ deliveries contribute when the transport block is ultimately delivered.

The objective of the policy $\pi_\theta(a\mid s)$ is therefore to maximize the expected discounted return

$$J(\theta)=\mathbb{E}_{\pi_\theta}\!\left[\sum_{k=0}^{\infty}\gamma^{k}\,r_{i,t_k}\right],\qquad \gamma=0.95,\qquad (30)$$

where $t_0<t_1<\dots$ are the TTIs in which user $i$ is scheduled, so that the discount applies per scheduled decision. (The discount factor $\gamma$ carries no user or time index, which distinguishes it from the SINR $\gamma_i(t)$ of Section 2.) This balances immediate goodput against the effect of current link-adaptation decisions on subsequent transmissions and system states. The policy is learned using a shared Advantage Actor-Critic (A2C) architecture [19] (Section 4).

![Distribution of residual CQI actions chosen by the trained Deep A2C policy (Tier-O, 10 seeds, 30 held-out traces) and the offline FixedPU class targets for the same users. Actions are relative to the OLLA reference; 0 reproduces OLLA and negative actions are more conservative.](v8_actions.png){width=6in}

Figure 3 provides an empirical view of the resulting policy. The learned A2C controller is concentrated on conservative residual actions: $-3$ (27.8% of decisions), $-2$ (26.7%), $-1$ (19.9%) and $-4$ (13.3%), with 9.0% at the OLLA action 0 and almost none above it. Its mean offset of $-2.26$ coincides with the mean of the offline FixedPU class targets ($-2.23$), and 70.7% of its decisions lie within one step of the target of the user's class. The agent was trained from random initialization and never saw these targets. The policy is not constant: within each user the modal action covers 73% of decisions, and the remainder spreads over neighbouring offsets. Thus, the learned controller converges toward the same conservative operating region as the offline-tuned benchmark, with a spread around it whose cost Section 6.1 quantifies.

## 3.5 State Space Formulation: Three Information Tiers

To investigate whether additional physical and protocol-level information improves RL-based link adaptation, we formulate three nested state representations: Tier-A, an information-equal state containing only the core observations available to the conventional adaptation process; Tier-O, the primary state, which adds observable temporal, HARQ and scheduling information; and Tier-B, which further adds simulator-only quantities [4]. This tiered formulation enables a controlled ablation of state richness while retaining the same action space, reward formulation and A2C architecture.

For user $i$ at TTI $t$, the Tier-A features are

$$s^{A}_{i,t}=\left[\frac{q^{\mathrm{ref}}_{i,t}}{15},\ \frac{\Delta q^{\mathrm{ref}}_{i,t}}{5},\ \frac{\tilde{\gamma}_{i,t}}{30},\ \frac{\Delta\tilde{\gamma}_{i,t}}{5},\ \frac{o_{i,t}}{5},\ \mathbf{c}_t\right]^{T},\qquad (31)$$

where $q^{\mathrm{ref}}_{i,t}$ is the reference CQI, $\Delta q^{\mathrm{ref}}_{i,t}=\mathrm{clip}(q^{\mathrm{ref}}_{i,t}-q^{\mathrm{ref}}_{i,t-1},-6,6)$ is its one-step change, $\tilde{\gamma}_{i,t}$ is the observed SINR, $\Delta\tilde{\gamma}_{i,t}=\tilde{\gamma}_{i,t}-\tilde{\gamma}_{i,t-1}$ (unclipped) and $o_{i,t}$ is the current OLLA offset. All differences are taken over consecutive TTIs, not over scheduled TTIs, and all features are computed for every user in every TTI. The vector $\mathbf{c}_t$ is a three-dimensional one-hot representation of the active scheduler (PF, RR or EQ). Tier-A therefore contains five link-level features and three scheduler-context variables, eight in total.

Tier-O extends this with five features that a base station observes:

$$s^{O}_{i,t}=\left[(s^{A}_{i,t})^{T},\ \frac{\beta^{(4)}_{i,t}}{5},\ n_{i,t},\ h^{\mathrm{pend}}_{i,t},\ \frac{h^{\mathrm{retx}}_{i,t}}{3},\ \frac{\overline{R}_i(t)}{\max_j\overline{R}_j(t)}\right]^{T},\qquad (32)$$

where $\beta^{(4)}_{i,t}=(\tilde{\gamma}_{i,t}-\tilde{\gamma}_{i,t-4})/4$ is the four-TTI finite-difference slope of the reported SINR (over fewer TTIs at the start of a trace), $n_{i,t}$ is an exponentially smoothed NACK indicator with $n_{i,0}=0$, updated as $n_{i,t+1}=0.7\,n_{i,t}+0.3\,\mathbb{1}^{\mathrm{NACK}}_{i,t}$ when user $i$ is scheduled (first transmissions and retransmissions) and $n_{i,t+1}=0.95\,n_{i,t}$ otherwise, $h^{\mathrm{pend}}_{i,t}$ indicates whether a HARQ retransmission is pending, $h^{\mathrm{retx}}_{i,t}$ denotes the current retransmission count and the last term is the user's PF average rate relative to the best user. Tier-O has 13 features.

Tier-B adds three simulator quantities: the user's true speed $v_{i,t}/30$, the true interference-burst state delayed by the user's feedback delay, and the true feedback delay $d_i/8$, for 16 features. A base station would not observe these directly. In all tiers the network input stacks the features of the last three TTIs (consecutive TTIs, zero-padded at the start of a trace), giving 24, 39 and 48 inputs respectively.

The tiers serve distinct experimental purposes. Tier-A restricts the agent to a compact representation derived primarily from link-adaptation observations and recent channel evolution, thereby providing an information-controlled RL benchmark. Tier-O adds information that could, in principle, help distinguish situations that produce similar instantaneous CQI observations but have different temporal or protocol contexts: the SINR slope provides information about channel directionality and the HARQ variables describe retransmission state. Tier-B tests whether privileged information about mobility and the interference regime would help further.

Feature scaling is applied before the state is passed to the neural networks. CQI, CQI variation, observed SINR, SINR variation, OLLA offset, SINR slope, retransmission count, speed and delay are normalized by fixed constants corresponding to their operational ranges, whereas the NACK statistic, HARQ-pending indicator, relative PF rate, burst indicator and one-hot scheduler context are already represented on bounded scales. The actor and critic architectures are otherwise unchanged between the tiers; only the input dimensionality changes. Consequently, the comparison isolates the effect of the additional state information rather than changing the learning algorithm itself.

![State-information ablation: Deep A2C margin relative to FixedPU with 90% confidence intervals for Tier-A, Tier-O and Tier-B (goodput reward, PF, 100 traces × 10 seeds). The shaded band is the ±2% equivalence margin.](v8_tiers.png){width=4.2in}

The state-information ablation in Fig. 4 shows that this additional information does not translate into improved throughput. Relative to the class-conditioned FixedPU benchmark, Tier-A achieves an A2C margin of −0.9% (90% CI −2.0% to +0.2%), Tier-O −0.3% (−1.5% to +0.8%) and Tier-B −2.0% (−3.1% to −0.8%). Tier-A and Tier-O are both equivalent to FixedPU within ±2% (TOST $p=0.046$ and $p=0.008$), whereas Tier-B is significantly below it (Holm $p=0.015$). Thus the observable Tier-O features provide no measurable gain over Tier-A, and the privileged Tier-B features, if anything, hurt.

The ablation therefore suggests that, under the evaluated environment and training procedure, increasing state dimensionality alone is insufficient to improve the learned operating point. The compact Tier-A representation already contains much of the information required to recover the strong static operating region identified by FixedPU, while exposing mobility, burst state and true delay does not yield additional throughput. This observation motivates treating state design as an empirical question rather than assuming that a more detailed physical representation necessarily produces a better RL policy.


# 4. Deep RL Framework and Optimization

The deep controller is a single actor-critic network pair shared by all users (Section 4.1), trained from random initialization with synchronous advantage actor-critic updates (Section 4.2). Section 4.3 describes a separate behavior-cloning diagnostic that asks whether RL can improve on an oracle-initialized policy, and Section 4.4 the exploration schedules that such warm starts require. Section 4.5 gives the training configuration. Tabular baselines from earlier versions are summarized in Appendix A.

## 4.1 Shared Multi-Task A2C Architecture

To accommodate the continuous state representation and enable learning across heterogeneous users, we employ a shared-parameter Advantage Actor-Critic (A2C) architecture [19]. Rather than maintaining a separate policy for each user, all $N$ users share a common actor and critic. At each TTI, the state vectors of all users are processed as a batch, while the actor produces an individual action distribution for each user. Consequently, experience collected from different users contributes to the optimization of the same network parameters. This parameter-sharing formulation avoids a linear increase in model size with the number of users and allows the learned policy to exploit experience across different channel, mobility and feedback-delay conditions.

Let $s_{i,t}\in\mathbb{R}^{d_s}$ denote the stacked state of user $i$ at TTI $t$, where $d_s=24$, 39 and 48 for Tier-A, Tier-O and Tier-B (three frames of 8, 13 and 16 features; Section 3.5). The states of all users are arranged into the input batch

$$\mathbf{S}_t=\big[s_{1,t},\,s_{2,t},\,\dots,\,s_{N,t}\big]\in\mathbb{R}^{d_s\times N}.\qquad (33)$$

The actor and critic are implemented as separate multilayer perceptrons (MLPs) with the same hidden-layer structure. In our implementation, each network contains two fully connected hidden layers with 128 and 96 neurons, each followed by a ReLU activation. Thus, their mappings can be represented as

$$\mathbf{h}^{(1)}_{i,t}=\mathrm{ReLU}\big(\mathbf{W}^{(1)}s_{i,t}+\mathbf{b}^{(1)}\big),\qquad (34)$$

$$\mathbf{h}^{(2)}_{i,t}=\mathrm{ReLU}\big(\mathbf{W}^{(2)}\mathbf{h}^{(1)}_{i,t}+\mathbf{b}^{(2)}\big).\qquad (35)$$

Although the actor and critic use the same architectural form, they do not share weights with each other; each maintains its own learnable parameters and optimizer state. The symbols in (34)–(35) therefore stand for two separate parameter sets, $(\mathbf{W}^{(1)},\mathbf{b}^{(1)},\mathbf{W}^{(2)},\mathbf{b}^{(2)})\subset\theta$ for the actor and a second set $\subset\phi$ for the critic, and $\mathbf{h}^{(2)}_{i,t}$ in (36) and (39) denotes the second hidden layer of the respective network. The term shared therefore refers to parameter sharing across users, rather than weight sharing between the actor and critic.

The actor output layer contains $|\mathcal{A}|=11$ neurons, one for each allowable CQI-offset action, and produces the raw logits

$$\mathbf{z}_{i,t}=\mathbf{W}^{(A)}\mathbf{h}^{(2)}_{i,t}+\mathbf{b}^{(A)}.\qquad (36)$$

These logits parameterize the stochastic policy

$$\pi_\theta(a\mid s_{i,t})=\frac{\exp(z_{i,t,a})}{\sum_{a'\in\mathcal{A}}\exp(z_{i,t,a'})}.\qquad (37)$$

No explicit softmax layer is included in the actor network. Instead, raw logits are retained and the corresponding probabilities and log-probabilities are calculated using numerically stable softmax/log-softmax operations during action selection and optimization. Retaining raw logits avoids numerical precision problems for highly peaked policies.

During training, an action is sampled independently for each user from its predicted categorical distribution,

$$a_{i,t}\sim\pi_\theta(\cdot\mid s_{i,t}),\qquad (38)$$

while evaluation uses the most probable action. The selected action is interpreted as an offset from the reference CQI rather than as an absolute MCS/CQI decision, and the transmitted CQI follows (27). This relative-action formulation preserves the reference link-adaptation decision as the zero-offset action while allowing the learned policy to select more conservative or aggressive transmission settings.

In parallel, the critic maps the same user state to a single scalar value

$$V_\phi(s_{i,t})=\mathbf{W}^{(V)}\mathbf{h}^{(2)}_{i,t}+b^{(V)},\qquad (39)$$

which estimates the expected discounted return from that state and is subsequently used to construct the advantage signal for actor optimization. Thus, for a batch of $N$ users, the actor produces an $|\mathcal{A}|\times N$ matrix of policy logits, whereas the critic produces $N$ state-value estimates.

The framework combines per-user decision making with shared parameters. Each user receives an individual state, selects its own CQI-offset action and is credited with its own delivered goodput (29), so that an action is judged by the transmission it actually affected. The PF ranking uses the OLLA reference rate (Section 3.2), so a user cannot raise its own scheduling priority through its action.

The combination of shared parameters and per-user credit produces a lightweight multi-user learning structure: the number of actor and critic networks remains fixed as $N$ increases, while each user's trajectory contributes training samples to the same networks. Moreover, scheduler identity is included in the state representation, which would allow the same policy to condition its decisions on the active PF, RR or EQ regime; in the reported PF-only campaign this input is constant (Section 3.2).

## 4.2 A2C Training Objectives

The shared actor and critic are optimized using a synchronous advantage actor-critic (A2C) procedure [19]. Rather than updating the networks after every individual transition, the implementation accumulates the transitions of scheduled users in a buffer and performs one update of the shared actor and critic when the buffer holds $B_{\max}=2\,n_{\mathrm{step}}N=200$ transitions ($n_{\mathrm{step}}=10$, $N=10$) or the episode ends. Here $n_{\mathrm{step}}$ only sizes the buffer; returns are not truncated at $n_{\mathrm{step}}$ steps. Because all users are advanced through the same environment timeline, their experiences are jointly incorporated into each gradient update. Under PF, one user is served per TTI, so a 200-TTI episode yields 200 transitions and one update at the end of the episode, and a 1000-TTI episode of the steady-state run yields five.

For each user, the return is computed recursively backwards through that user's own sequence of scheduled decisions. If $\tau$ and $\tau'$ are consecutive TTIs in which user $i$ is scheduled,

$$R_{i,\tau}=r_{i,\tau}+\gamma\,R_{i,\tau'},\qquad (40)$$

and the last transition of each user in the buffer bootstraps from the critic's value of the state observed after it:

$$R_{i,\tau_{\mathrm{last}}}=r_{i,\tau_{\mathrm{last}}}+\gamma\,V_\phi\big(s_{i,\tau_{\mathrm{last}}+1}\big),\qquad (41)$$

where $\gamma=0.95$. Thus each user's return is associated with its own sequence of states and its own bootstrap value, and the discount applies per scheduled decision. The return of a transition is therefore a variable-horizon return over all of that user's later decisions in the buffer (about 20 per user and episode under PF), bootstrapped once; $R_k$ below denotes this return for the $k$-th transition of the batch.

An important detail is that the end of a simulation episode is treated as an artificial time limit rather than a true terminal state. Consequently, the return is bootstrapped from the critic even for the final update, using the state after the last TTI with the updated OLLA, HARQ and rate variables, instead of forcing the terminal value to zero. This avoids systematically underestimating returns for states occurring near the episode boundary. The post-episode state reuses the last CQI report, so $\Delta\tilde{\gamma}_{i,t}$ and $\beta^{(4)}_{i,t}$ keep their final values, while $q^{\mathrm{ref}}_{i,t}$, $\Delta q^{\mathrm{ref}}_{i,t}$, the OLLA offset, the NACK indicator, the HARQ state and the PF rate are recomputed from the updated variables and pushed onto the frame stack.

On TTIs in which a user transmits a HARQ retransmission, the retransmission reuses the stored MCS and the sampled action has no effect. Such transitions remain in the return chain and the critic target, but they are masked out of the policy-gradient term, so the actor is not credited or blamed for actions that did nothing.

The critic estimates the expected return from each state. For a batch containing $B$ transitions, the corresponding advantage estimate is

$$A_k=R_k-V_\phi(s_k).\qquad (42)$$

The critic is optimized by minimizing the mean-squared advantage,

$$\mathcal{L}_V(\phi)=\frac{1}{B}\sum_{k=1}^{B}\Big[R_k-V_\phi(s_k)\Big]^2.\qquad (43)$$

Thus, the critic learns to approximate the bootstrapped return rather than the immediate reward alone.

Before updating the actor, the advantages are standardized across the batch. Specifically,

$$\tilde{A}_k=\frac{A_k-\mu_A}{\sigma_A},\qquad \sigma_A>10^{-6},\qquad (44)$$

where $\mu_A$ and $\sigma_A$ denote the batch mean and standard deviation. For a near-zero standard deviation, only mean centering is applied. The standardized advantage is also detached from the computational graph before being supplied to the actor objective. Consequently, actor gradients do not propagate through the critic when optimizing the policy. Advantage standardization and this stop-gradient operation are important stabilization mechanisms.

For the actor, raw network logits are converted to log-probabilities through the numerically stable log-softmax operation

$$\log\pi_\theta(a\mid s)=z_a-\Big[z_{\max}+\log\sum_{a'}\exp\big(z_{a'}-z_{\max}\big)\Big].\qquad (45)$$

The actor objective combines the advantage-weighted policy-gradient term over non-retransmission transitions $\mathcal{K}$ with an entropy bonus,

$$\mathcal{L}_\pi(\theta)=-\frac{1}{|\mathcal{K}|}\sum_{k\in\mathcal{K}}\log\pi_\theta(a_k\mid s_k)\,\tilde{A}_k-\beta\,\frac{1}{B}\sum_{k=1}^{B}H\big(\pi_\theta(\cdot\mid s_k)\big),\qquad (46)$$

where

$$H(\pi)=-\sum_{a\in\mathcal{A}}\pi(a\mid s)\log\pi(a\mid s).\qquad (47)$$

The entropy term discourages premature collapse to a nearly deterministic action and maintains exploration during policy learning. Unlike the policy-gradient term, it is averaged over all $B$ transitions, including retransmission states where the action has no effect. For training from random initialization, the entropy coefficient is linearly annealed over the episodes (not the updates) from $\beta_0=0.08$ to $\beta_{\mathrm{end}}=0.005$, as in (50). The main trainer never uses behavior cloning; warm starts appear only in the diagnostic of Section 4.3, whose schedule is discussed in Section 4.4.

![Training of the primary Deep A2C configuration (Tier-O, goodput reward, 10 seeds). Left: training cell throughput per episode (10-episode moving average of the seed mean, with the 10–90% band across seeds); the dashed line is FixedPU's evaluation throughput. Right: mean entropy of the sampling policy over all users (scheduled or not) and all TTIs of the episode, with the uniform maximum ln 11 for reference.](v8_learning.png){width=6.3in}

Figure 5 shows the training behaviour. Training throughput rises from 3.60 Mbps over the first 25 episodes to 3.89 Mbps over the last 25, while the policy entropy falls slowly from close to the uniform maximum of $\ln 11\approx2.40$ nats to 2.17 nats. Because this average includes every user in every TTI, also the many states in which a user is not scheduled and its action is never used, it overstates the spread of the decisions that are actually executed. The policy nevertheless remains broad at the end of training, and evaluation acts greedily on it. The spread across seeds is large in every episode because each episode draws a new channel realization.

The optimizer settings are given in Section 4.5. Together, bootstrapped per-user returns, advantage standardization, entropy regularization, detached actor advantages and gradient clipping form the principal optimization mechanisms used to stabilize the shared A2C learner.

## 4.3 Behaviour-Cloning Diagnostic: Can RL Improve on an Oracle-Initialized Policy?

Every learner reported in Section 5 starts from random weights and never sees a calibrated offset. This subsection describes a separate diagnostic that asks a narrower question: if the agent starts exactly at the oracle’s policy, does RL fine-tuning find anything better? A positive answer would reveal state-conditional structure that a per-class constant cannot represent. A null answer bounds what any learner can add, independently of how well it optimizes from scratch.

**Why a diagnostic is needed.** A from-scratch learner can miss the optimum for reasons unrelated to the environment: with 11 residual actions, a near-uniform initial policy spends early TTIs far from the optimum, the goodput reward is sparse and noisy, and the critic is poorly fitted while the actor explores. After 300 episodes our policy entropy is still 2.17 nats of a possible ln 11 ≈ 2.40. Starting from the oracle removes this shortfall by construction, so fine-tuning isolates the question of state-conditional value.

**Teacher and targets.** The teacher is the per-class oracle FixedPU (Section 3.3). Each user is assigned to one of 2 × 3 classes by its CQI feedback delay and mean speed, and its target action is the element of the action set closest to that class’s calibrated offset. During cloning the agent acts with the teacher’s action, so the rollouts follow the oracle’s state distribution. Class labels use simulator ground truth; this is acceptable for a diagnostic of the ceiling, and it is one more reason the cloned run cannot support a calibration-free claim.

**Losses.** For a batch of $B$ scheduled transitions with states $s_b$, of which the first transmissions form the subset $\mathcal{K}$ with teacher actions $a^*_b$, the actor minimizes a cross-entropy loss over $\mathcal{K}$ with a small entropy bonus over all $B$, and the critic fits the per-user returns $G_b$ of the cloned rollout [20]:

$$\mathcal{L}_{\mathrm{actor}}=-\frac{1}{|\mathcal{K}|}\sum_{b\in\mathcal{K}}\log\pi_\theta(a^*_b\mid s_b)-\beta_{\mathrm{BC}}\,\frac{1}{B}\sum_b H\big(\pi_\theta(\cdot\mid s_b)\big)\qquad (48)$$

$$\mathcal{L}_{\mathrm{critic}}=\frac{1}{B}\sum_b\big(G_b-V_\phi(s_b)\big)^2\qquad (49)$$

with $\beta_{\mathrm{BC}}=0.03$. Here $G_b$ is the same per-user, critic-bootstrapped return as $R_k$ in (40)–(41), computed over all scheduled transitions including retransmissions, so delayed HARQ deliveries stay in the target. Cloning uses the Adam settings of Section 4.5, and the optimizer state carries over into fine-tuning. Fitting the critic during cloning means that fine-tuning starts with advantages computed from a value function matched to the clone, rather than from a random critic. Cloning runs for 150 episodes and is followed by 300 episodes of A2C with the warm-start schedule of Section 4.4. Clone and fine-tuned policy share the same seed, so they are identical up to the end of cloning.

**Result.** The clone reaches 4.05 Mbps against the oracle’s 3.99 Mbps (+1.5%, $p=0.045$), with first-transmission BLER 0.393 versus 0.385. One possible reason, not tested here, is that the clone does not observe the class labels and gives the dominant offset −2 to some users of the −4 class, which the landscape of Section 6.1 favours. Under the goodput reward, fine-tuning changed throughput by −0.34% ($p=0.036$; per seed −1.7%, +0.0%, −0.1%, +0.1%, +0.0%). All p-values here are Wilcoxon tests paired over the 100 held-out traces, on the 5-seed average per trace; the mean change is driven by one seed, and four of the five changed by at most 0.1%. The policy stayed trainable throughout, with entropy 0.59–0.65 nats at the end of cloning and 0.51–0.93 nats after fine-tuning. Fine-tuning therefore moved the policy but found no better operating point.

This is the evidence that matters for state-conditional value. Given every opportunity to improve on the oracle (a matched critic, a trainable policy, observable HARQ and NACK history and a full fine-tuning budget), the learner found nothing to add. Together with the state ablation (Section 6.1), it supports the conclusion that the attainable gain in this environment is an operating-point gain.

**The same diagnostic exposes the reward.** Repeated with the penalised reward ($\lambda_{\mathrm{retx}}=0.05$ per NACK, $\lambda_{\mathrm{drop}}=0.5$ per dropped packet), fine-tuning moved the clone away from the oracle: throughput fell by 3.0% ($p=2.2\times10^{-5}$; every seed between −2.5% and −3.5%), and first-transmission BLER fell from 0.393 to 0.289. A learner that leaves the throughput optimum when started on it is optimizing something else. This is how we found the reward pitfall described in Section 6.4.

## 4.4 Exploration Schedules after Warm Starts

Warm-starting an actor-critic interacts badly with an entropy schedule designed for cold starts. Our campaigns hit this from both sides.

**Too much exploration erases the warm start.** Our first cloning run in v7 lost to the oracle by 5.0% (p = 0.017), more than the cold-start run. Entropy fell to H ≈ 0 during cloning and climbed back to H ≈ 1.9 nats within about 100 fine-tuning episodes; with 7 actions the uniform maximum is ln 7 ≈ 1.95, so fine-tuning had pushed the policy almost back to random. The cause was an entropy bonus annealed linearly from 0.05 to 0.001 and indexed only by the RL episode count, so fine-tuning began at the strongest exploration pressure exactly when the policy was already at the oracle [19].

We fixed this with a soft clone ($\beta_{\mathrm{BC}}=0.03$ during cloning) and a fine-tuning anneal that starts at 0.01 after cloning instead of the cold-start value:

$$\beta(e)=\beta_0+(\beta_{\mathrm{end}}-\beta_0)\,\frac{e-1}{E-1},\qquad \beta_0=0.01\ \text{after cloning}\ \ (0.08\ \text{at cold start}),\qquad \beta_{\mathrm{end}}=0.005,\qquad (50)$$

where $e$ is the RL episode index and $E$ the number of RL episodes.

**Too little exploration freezes it.** The soft clone is not a guarantee. In an earlier run with the original scheduler, where the oracle’s class table was a single offset, the same $\beta_{\mathrm{BC}}=0.03$ ended at 0.022–0.064 nats, and 300 fine-tuning episodes left every greedy decision unchanged. A one-hot cross-entropy target drives the logits apart regardless of a small entropy bonus, and once the softmax saturates the policy gradient vanishes. In the corrected runs the clone stayed at 0.59–0.65 nats and remained trainable.

The lesson applies to any actor-critic initialized from demonstrations, a pretrained model or a previous deployment. The exploration schedule must depend on how confident the initial policy is, not only on the episode index, and that confidence should be bounded directly, for example by label smoothing, a logit temperature or a KL penalty towards the clone during fine-tuning. Otherwise fine-tuning either erases the initialization or cannot move it, and both failures look like statements about RL. Check the clone’s entropy before interpreting any fine-tuning result. For from-scratch training in the main campaign the entropy weight anneals linearly from 0.08 to 0.005 over 300 episodes.

## 4.5 Scheduler Configuration and Training Optimization

The proposed deep A2C framework adopts Proportional Fair (PF) scheduling during training, with the scheduler selection weights configured as $\mathbf{w}_{\mathrm{train}}=[1,0,0]$, corresponding to PF, Round Robin (RR) and Equal Share (EQ), respectively. Training and evaluation therefore use the same scheduler, which is also the scheduler on which FixedPU is calibrated, so that neither side of the pre-registered comparison is tuned for conditions the other does not face. The active scheduler is represented through one-hot encoding and incorporated into the state representation.

The actor and critic networks are independently optimized using the Adam optimizer [21], with learning rates of $5\times10^{-4}$ and $10^{-3}$, respectively. To improve training stability and prevent excessively large parameter updates, global gradient-norm clipping is applied separately to both networks, with a maximum norm of 5.0. For a gradient vector $\mathbf{g}$, the clipped gradient is expressed as

$$\tilde{\mathbf{g}}=\mathbf{g}\,\min\!\left(1,\ \frac{5.0}{\lVert\mathbf{g}\rVert_2}\right).\qquad (51)$$

The training procedure employs a discount factor of $\gamma=0.95$ per scheduled decision, with separate learning rates to accommodate the distinct optimization objectives of policy improvement and value estimation.

The computational budget for the main experiments comprises 300 reinforcement-learning episodes per seed, with 200 transmission time intervals (TTIs) per episode and ten independent random seeds. For a 10-user cell under PF, this corresponds to about one actor and critic update per episode, or roughly 300 updates per seed, each on about 200 scheduled transitions. Each trained policy is subsequently evaluated on 100 held-out channel traces, shared by all schemes. The steady-state run uses five seeds of 150 episodes of 1000 TTIs each, with OLLA cold-started in every training episode (no warm-up during training), about 750 updates per seed, and the entropy schedule indexed by episode (Section 5.5). Together, the fixed training configuration, gradient stabilization techniques and paired evaluation provide a consistent framework for assessing the learning stability, robustness and deployment viability of the proposed RL-based adaptive modulation and coding approach.


# 5. Performance Evaluation

The evaluation is organized around one pre-registered question: under proportional-fair scheduling, does the learned controller match or exceed the offline-calibrated per-class oracle FixedPU? Section 5.1 describes the protocol and runs, Section 5.2 the primary comparison, Section 5.3 behaviour during interference bursts, Section 5.4 the state, reward and scheduler ablations, Section 5.5 sensitivity to OLLA's tuning and convergence, and Section 5.6 the statistical procedure and diagnostics.

## 5.1 Simulation Setup and Parameters

The environment parameters are those of Table I. Every run trains the learner with independent seeds and evaluates the frozen policies on the same 100 held-out traces. Each trace fixes the user drop, delays, speeds, channel and burst realizations, and every scheme is evaluated on exactly the same traces, so all comparisons are paired. Calibration traces for Fixed, Fixed-Online and FixedPU are generated from a separate seed range and never overlap with evaluation traces. The deep agent acts greedily (most probable action) during evaluation.

For each scheme, trace $j$ and (for the learner) seed, metrics are computed over the scored TTIs $\mathcal{T}_j$ that follow a burn-in of 50 TTIs (150 TTIs in a 200-TTI trace). With $x_i(t)$ the throughput delivered to user $i$ in TTI $t$ (zero when it is not served or its block fails),

$$\bar{x}_{i,j}=\frac{1}{|\mathcal{T}_j|}\sum_{t\in\mathcal{T}_j}x_i(t),\qquad \mathrm{Tp}_j=\sum_{i=1}^{N}\bar{x}_{i,j},\qquad \mathrm{Tp}^{\mathrm{burst}}_j=\sum_{i=1}^{N}\frac{1}{|\mathcal{T}^{\mathrm{b}}_j|}\sum_{t\in\mathcal{T}^{\mathrm{b}}_j}x_i(t),\qquad (52)$$

where $\mathcal{T}^{\mathrm{b}}_j\subseteq\mathcal{T}_j$ are the scored TTIs inside a burst; calm throughput is defined in the same way over the remaining TTIs. Cell throughput is therefore total delivered bits per unit time. A trace without scored burst TTIs has no burst value and is left out of the burst average, and likewise for calm: in P1, 48 of the 100 traces contain no scored burst TTI and 3 contain no calm TTI. The burst and calm columns are therefore means over different subsets of traces and do not combine into the cell-throughput column with a common weight. First-transmission BLER is the mean model BLER (9) of all first transmissions; edge throughput is the 5th percentile of $\{\bar{x}_{i,j}\}_i$; fairness is Jain's index (Section 5.6). Edge throughput and Jain's index are computed per seed and trace and then averaged; for the statistical tests, the learner's cell throughput is averaged over seeds per trace.

Transmission outcomes are Bernoulli draws from (9). Each combination of trace, scheme and seed uses its own random-number stream, so the traces are common to all schemes but the outcome draws are not. Two identical controllers evaluated under different labels or in different scripts therefore differ slightly. Cold-start OLLA scores 3.86 Mbps in Table III, while the same controller scores 3.84 Mbps as the target-0.1 point of Fig. 2 and as offset 0 of Table VII; offset −2 scores 4.07 Mbps as Fixed and 4.08 Mbps in Table VII; and in Table IV, OLLA and Fixed with offset 0 are the same controller (3.54 Mbps both). Differences of about 0.02 Mbps (0.5%) between such entries are the Monte-Carlo resolution of the comparison, not effects.

Table II lists the runs. The primary configuration P1 uses the observable Tier-O state, the goodput reward and PF ranking on the OLLA reference rate. The other runs change one factor at a time.

Table II. Runs of the corrected campaign (MATLAB R2023a, 3–4 October 2026). All use $h=1$, +9 dB bursts, PF scheduling for training and evaluation, 100 held-out traces and the calibrated table $[-2,\,-2,\,-2;\;-4,\,-2,\,-2]$ unless noted.

|Run|Purpose|State|Reward|PF ranks users on|Seeds × episodes|Scored horizon|
|:---|:--------|:--|:----|:-----|:-----|:-----|
| P1 | Primary configuration | Tier-O | goodput | OLLA reference rate | 10 × 300 | 200 TTIs, cold start |
| P2, P3 | State ablation | Tier-A, Tier-B | goodput | OLLA reference rate | 10 × 300 | 200 TTIs, cold start |
| P4 | Steady state | Tier-O | goodput | OLLA reference rate | 5 × 150 (1000-TTI cold-start episodes) | 950 TTIs after 1000-TTI warm-up and 50-TTI burn-in |
| V1–V3 | Reliability variant | Tier-O, -A, -B | penalised, (29) | OLLA reference rate | 10 × 300 | 200 TTIs, cold start |
| G1–G3 | Original scheduler input | Tier-O, -A, -B | penalised | agent's chosen MCS | 10 × 300 | 200 TTIs, cold start |
| G4 | Longer training | Tier-O | penalised | agent's chosen MCS | 3 × 1500 | 200 TTIs, cold start |
| D1, D2 | Behavior-cloning diagnostic (Section 4.3) | Tier-O | goodput, penalised | OLLA reference rate | 5 × (150 cloning + 300 RL) | 200 TTIs, cold start |

## 5.2 Primary Throughput Comparison

Table III reports all schemes in the primary configuration, and Fig. 6 the paired margins of Deep A2C against each comparator.

Table III. Primary configuration P1 under PF (100 held-out traces; Deep A2C averaged over 10 seeds). Throughput is given with its 95% confidence half-width over traces; edge throughput is the 5th percentile of per-user throughput.

|Scheme|Cell throughput (Mbps)|vs OLLA|First-tx BLER|Edge (Mbps)|Jain|Burst / calm (Mbps)|
|:------|------:|----:|----:|----:|----:|------:|
| Baseline (no OLLA) | 3.52 ± 0.16 | −8.9% | 0.611 | 0.138 | 0.859 | 2.23 / 4.00 |
| OLLA (cold start) | 3.86 ± 0.19 | — | 0.520 | 0.169 | 0.860 | 2.47 / 4.42 |
| Warm-OLLA | 3.77 ± 0.20 | −2.3% | 0.380 | 0.170 | 0.861 | 2.04 / 4.24 |
| Multi-OLLA | 3.92 ± 0.19 | +1.6% | 0.477 | 0.177 | 0.858 | 2.47 / 4.46 |
| Fixed (global, −2) | 4.07 ± 0.19 | +5.4% | 0.392 | 0.184 | 0.869 | 2.42 / 4.68 |
| Fixed-Online | 4.02 ± 0.19 | +4.2% | 0.377 | 0.173 | 0.865 | 2.43 / 4.64 |
| FixedPU (per class) | 3.99 ± 0.19 | +3.2% | 0.385 | 0.179 | 0.864 | 2.42 / 4.52 |
| Deep A2C (Tier-O) | 3.97 ± 0.17 | +2.9% | 0.372 | 0.174 | 0.865 | 2.49 / 4.51 |

![Paired margin of Deep A2C (P1) against each comparator with 90% confidence intervals and Holm-adjusted Wilcoxon p-values. The shaded band is the ±2% equivalence margin of the pre-registered test.](v8_forest.png){width=6.3in}

Across the ten training seeds, the learner's mean throughput ranges from 3.90 to 4.05 Mbps (−2.2% to +1.7% of FixedPU); the confidence half-widths in Table III describe variation across traces of the seed-averaged policy, not variation across seeds.

The pre-registered comparison has a clear answer. Deep A2C reaches 3.97 Mbps against 3.99 Mbps for FixedPU, a margin of −0.3% whose 90% confidence interval (−1.5% to +0.8%) lies inside the ±2% equivalence band (TOST $p=0.008$). The learner therefore matches the per-class oracle but does not exceed it. It improves significantly on cold-started OLLA (+2.9%, Holm $p=0.045$) and on Warm-OLLA at its 10% target (+5.3%), and it is statistically indistinguishable from Multi-OLLA (+1.3%) and Fixed-Online (−1.2%). The single best global offset is 2.4% better (Holm $p=0.045$).

All offset-based schemes and the learner operate at a first-transmission BLER between 0.37 and 0.39, against 0.52 for cold-started OLLA and 0.61 for Baseline.

Warm-OLLA needs a comment, because it runs at almost the same cell-average BLER (0.380) as the best constant but scores 3.77 Mbps, below cold-start OLLA, with the lowest burst throughput of all schemes (2.04 Mbps). Its warm-up runs on an independent channel segment (Section 3.1), so each user enters the scored trace with an offset converged under different conditions, and where that offset is too low it recovers at only $\Delta_{\mathrm{up}}\approx0.056$ dB per ACK. This is a plausible cause, but we have not isolated it with a separate run. The cell-average BLER also mixes users pinned at MCS 0 with adaptable users (Section 6.2), so equal averages do not imply equal operating points for the users that matter. Warm-OLLA in this 200-TTI comparison is distinct from the converged OLLA of the steady-state run (Section 5.5), in which every scheme is warmed up on its own trace. Fairness and edge throughput follow throughput: Deep A2C's Jain index (0.865) lies between those of FixedPU and Fixed, and its edge throughput (0.174 Mbps) is slightly below theirs and above OLLA's.

## 5.3 Behaviour during Interference Bursts

The last column of Table III splits throughput into burst and calm periods; the burst values average over the 52 traces that contain scored burst TTIs (Section 5.1). All schemes lose between 44% and 52% of their throughput during bursts. Deep A2C has the highest burst-period throughput of all schemes (2.49 Mbps, 2.8% above Fixed and 2.7% above FixedPU), but in calm periods it is 3.6% below Fixed and level with FixedPU (4.51 vs 4.52 Mbps). Its whole gap to the best constant therefore comes from calm periods, where a fixed offset is near-optimal by construction, while during bursts it does slightly better than the constants. These splits are descriptive: they were not part of the pre-registered tests and carry no correction for multiple comparisons.

[AUTHOR NOTE: The v7 writeup of this section swept user heterogeneity (h = 0, 0.5, 1) and burst intensity (+6, +9, +12 dB). Those sweeps were not repeated after the code audit, and the forward references to them in Section 2.4 and Table I have been removed; the v8 files `results_v8_calm` and `results_v8_burst12dB` predate it and must not be used. Either re-run the regime sweep on the primary set-up or keep this section to the burst/calm split.]{custom-style="Author Note"}

## 5.4 State, Reward and Scheduler Ablations

Fig. 4 (Section 3.5) and Table VIII (Section 6.1) vary one factor at a time. The state matters least: Tier-A, Tier-O and Tier-B lie within 1.7% of one another under the goodput reward, and the privileged Tier-B is the worst. The reward matters more: with the penalised reward (V1) the Tier-O agent runs at a first-transmission BLER of 0.265 instead of 0.372 and loses 3.7% of the goodput agent's throughput (3.83 vs 3.97 Mbps), falling 4.0% below FixedPU. The scheduler input matters most: when PF ranks users on the agent's own chosen MCS (G1–G3), throughput drops by a further 8.6% (Tier-O) to 17.6% (Tier-A) relative to the same penalised agent with reference-rate ranking, and training five times longer (G4) lowers Tier-O throughput further, to 2.88 Mbps. The ablations show that the learner's result depends much more on how the problem is posed than on what the agent observes.

## 5.5 Sensitivity to OLLA Tuning and Convergence

A frequent objection to learned link adaptation is that its gain reflects a poorly tuned or unconverged baseline. We test this in two ways.

*Re-tuning OLLA's target.* Fig. 2 (Section 3.1) re-evaluates OLLA with targets from 0.1 to 0.5, from a cold start and after a 1000-TTI warm-up. The best re-tuned OLLA is the warmed-up loop at a 40% target (3.91 Mbps); Deep A2C is 1.6% above it, which is not significant ($p=0.074$). Re-tuning OLLA's target therefore closes most, but not all, of its gap to the learner over the 200-TTI horizon.

*Letting everything converge.* In P4 every OLLA loop is warmed up for 1000 TTIs and all schemes are scored over the following 950 TTIs (a 1000-TTI trace after its 50-TTI burn-in). OLLA and Warm-OLLA are therefore the same controller in P4: both are warmed up on the same 1000-TTI segment and differ only in their outcome draws (Section 5.1). The learner is trained for 150 episodes of 1000 TTIs, but with OLLA cold-started in every training episode, and the offset comparators are calibrated on cold-start traces of the same length, which selects a global offset of 0 and the class table $[-4,\,0,\,0;\;-1,\,0,\,0]$. Both the learner and the offset tables are thus tuned on cold-start dynamics and deployed on a converged loop. We did not run the matched control in which the learner is trained, and FixedPU calibrated, after the warm-up. P4 therefore shows how cold-start-tuned offsets behave on a converged loop. It does not establish what a learner trained on a converged loop would reach. Table IV shows the outcome.

Table IV. Steady-state evaluation P4 (1000-TTI warm-up, 950 scored TTIs, 100 traces; Deep A2C averaged over 5 seeds). OLLA and Warm-OLLA, and OLLA and Fixed (offset 0), are identical controllers whose entries differ only through outcome draws. Baseline has no OLLA and is not warmed up; it is lower than in Table III because a longer trace spends more time in bursts (Section 2.4).

|Scheme|Cell throughput (Mbps)|First-tx BLER|Deep A2C margin|
|:-----|------:|------:|------:|
| Baseline | 3.42 | 0.612 | +0.6% |
| OLLA | 3.54 | 0.390 | −2.9% (Holm $p=1.6\times10^{-10}$) |
| Warm-OLLA | 3.52 | 0.391 | −2.5% |
| Multi-OLLA | 3.56 | 0.389 | −3.4% |
| Fixed (global, 0) | 3.54 | 0.389 | −2.8% |
| Fixed-Online | 3.43 | 0.370 | +0.3% |
| FixedPU | 3.43 | 0.375 | +0.2% (TOST $p=7.9\times10^{-6}$) |
| Deep A2C (Tier-O) | 3.44 | 0.353 | — |

At steady state the converged loops (OLLA, Warm-OLLA, Multi-OLLA) and the global constant, which here is 0, all end within 3.52–3.56 Mbps at a first-transmission BLER of about 0.39. Deep A2C remains equivalent to FixedPU (+0.2%) but is 2.9% below OLLA. Once the loop has converged, the cold-start-tuned offsets, learned or calibrated, add error rather than remove it: FixedPU's table moves slow users away from an already converged loop and drops to 3.43 Mbps, while the global calibration, which happened to select 0, matches OLLA. The learner's advantage over OLLA in the primary configuration is therefore an advantage over OLLA's start-up transient.

## 5.6 Statistical Validation and Diagnostics

The throughput comparisons rest on a significance test designed to determine whether observed differences between Deep A2C and each comparator are distinguishable from noise, rather than on raw mean differences alone. This section describes that testing procedure as implemented in the comparison harness, together with two complementary diagnostics (trace-level win/loss analysis and action-distribution analysis) that examine the same underlying comparison from different angles. Unless stated otherwise, results refer to the primary configuration P1.

For each pair of schemes, let $d_j=\mathrm{Tp}_{\mathrm{A2C}}(j)-\mathrm{Tp}_{\mathrm{comp}}(j)$ denote the per-trace difference in cell throughput between Deep A2C and a given comparator on held-out trace $j$, for $j=1,\dots,n_{\mathrm{eval}}$, where $n_{\mathrm{eval}}=100$. Because the same 100 channel traces are evaluated under every scheme, the comparison is paired: each trace contributes one matched difference rather than two independent samples. The Wilcoxon signed-rank test [13] is used in place of a paired t-test because it does not assume the differences $d_j$ are normally distributed, only that their distribution is symmetric about the true median difference, a weaker and more defensible assumption given the bounded, non-Gaussian nature of per-trace throughput.

The comparison harness applies this test seven times, comparing Deep A2C against Baseline, OLLA, Warm-OLLA, Multi-OLLA, Fixed, Fixed-Online and FixedPU in turn,

$$p_k=\mathrm{signrank}\big(\mathrm{Tp}_{\mathrm{A2C}},\,\mathrm{Tp}_k\big),\qquad (53)$$

with the margin reported alongside each test as

$$\mathrm{margin}_k=100\times\frac{\overline{\mathrm{Tp}}_{\mathrm{A2C}}-\overline{\mathrm{Tp}}_k}{\overline{\mathrm{Tp}}_k}.\qquad (54)$$

Because seven comparisons are drawn from the same Deep A2C sample, the family-wise error rate is controlled with the Holm–Bonferroni procedure [14]. A non-significant Wilcoxon test does not by itself show that two schemes perform equally; it may only reflect limited data. The harness therefore also reports a 90% confidence interval and the two one-sided tests (TOST) procedure [15] with an equivalence margin of ±2%, which is the pre-registered criterion for parity. Both are parametric and computed on the absolute differences $d_j$. The interval is the paired $t$-interval $\bar{d}\pm t_{0.95,99}\,s_d/\sqrt{100}$, divided by $\overline{\mathrm{Tp}}_k$ to express it in percent, so it is centred on (54) and ignores the sampling variance of the denominator. TOST consists of two one-sided paired $t$-tests of $\bar{d}$ against $\pm0.02\,\overline{\mathrm{Tp}}_k$. All margins in this paper follow (54), computed from unrounded means and normalized by the comparator's own mean; the "vs OLLA" column of Table III normalizes by OLLA instead. Recomputing margins from the two-decimal means in the tables can therefore differ by up to 0.2 percentage points (e.g. 3.9748 vs 3.9880 Mbps gives −0.33%, while 3.97 vs 3.99 gives −0.50%). Table V summarizes the seven comparisons.

Table V. Deep A2C against each comparator (P1, PF, 100 held-out traces, 10 seeds). TOST tests equivalence within ±2% and is shown where parity is in question.

| Comparator | Margin | 90% CI of margin | Wilcoxon p | Holm-adjusted p | TOST p (±2%) |
|:------|-----:|----------:|-------:|-------:|------:|
| Baseline | +13.0% | +10.8% to +15.1% | $3.2\times10^{-13}$ | $2.2\times10^{-12}$ | — |
| OLLA | +2.9% | +1.2% to +4.6% | 0.009 | 0.045 | 0.81 |
| Warm-OLLA | +5.3% | +3.8% to +6.8% | $1.1\times10^{-7}$ | $6.4\times10^{-7}$ | — |
| Multi-OLLA | +1.3% | −0.4% to +3.0% | 0.13 | 0.26 | 0.24 |
| Fixed | −2.4% | −3.8% to −1.0% | 0.009 | 0.045 | 0.67 |
| Fixed-Online | −1.2% | −2.6% to +0.1% | 0.077 | 0.23 | 0.18 |
| FixedPU | −0.3% | −1.5% to +0.8% | 0.68 | 0.68 | 0.008 |

Only the comparison with FixedPU establishes equivalence. The improvements over Baseline, OLLA and Warm-OLLA and the shortfall against Fixed remain significant after Holm correction; the differences from Multi-OLLA and Fixed-Online are neither significant nor shown to be negligible.

![Trace-by-trace comparison of Deep A2C (P1, averaged over 10 seeds) and FixedPU cell throughput on the 100 held-out traces. Points above the dashed diagonal are traces where A2C exceeds FixedPU.](v8_scatter.png){width=4.2in}

Figure 7 visualizes the paired comparison underlying the Wilcoxon test directly, plotting Deep A2C's cell throughput against FixedPU's cell throughput for each of the 100 held-out traces, with a diagonal dashed line marking equality. Points above the line indicate traces where A2C exceeded FixedPU; points below indicate the reverse. The trace-level tally is 48 wins and 52 losses for Deep A2C against FixedPU (sign test $p=0.76$). The points track closely along the diagonal across the full observed throughput range (approximately 2 to 6 Mbps per trace), with no systematic divergence at either the low- or high-throughput end, indicating that A2C's parity with FixedPU holds consistently across easy and difficult channel conditions rather than being an artifact of aggregate averaging over a few outlier traces. Across training seeds the margin to FixedPU ranges from −2.2% to +1.7%, so a single seed is not a reliable estimate of the learner's performance.

Jain's fairness index for a set of per-user throughputs $\{x_1,\dots,x_N\}$ is defined as

$$J=\frac{\left(\sum_i x_i\right)^2}{N\sum_i x_i^2},\qquad (55)$$

which equals 1 when all users receive identical throughput and approaches $1/N$ as allocation becomes maximally unequal. Computed per trace and seed and then averaged (Section 5.1), Deep A2C achieves a Jain's index of 0.865, closely matching FixedPU (0.864) and Fixed (0.869), and exceeding OLLA (0.860) and Baseline (0.859). Edge throughput (the 5th percentile of per-user throughput) shows Deep A2C at 0.174 Mbps, slightly below Multi-OLLA (0.177), FixedPU (0.179) and Fixed (0.184), and above OLLA (0.169) and Baseline (0.138). These results indicate that Deep A2C's parity with the oracle benchmark is not achieved by sacrificing fairness or by neglecting the weakest users.

Fig. 3 (Section 3.4) addresses a different diagnostic question: whether the Deep A2C policy is genuinely conditioning its action on the observed state, or has instead converged to selecting a single fixed action almost irrespective of state. The trained policies are re-evaluated on 30 held-out traces, and the action-selection frequency is compared against the distribution of per-user-class target offsets used by FixedPU, obtained by mapping each user's delay and speed class directly through the fixed-class lookup table. Deep A2C's mean offset ($-2.26$) matches the FixedPU mean ($-2.23$), 70.7% of its decisions lie within one step of the class target, and its modal action covers 73% of each user's decisions. The learned policy is therefore close to a class-conditional constant with a moderate spread around it, rather than a highly state-reactive controller, and it reached this operating point without ever seeing the oracle's targets.

Across the three diagnostics (paired significance testing, trace-level win/loss distribution and action-selection analysis), the evidence converges on a single, internally consistent picture: Deep A2C is statistically equivalent to the oracle FixedPU benchmark, does so without compromising fairness or edge-user performance, and arrives at this parity by learning a policy that is behaviorally close to a constant class-conditional offset.


# 6. Discussion and Practical Implications

Section 5 compared a from-scratch deep A2C agent with a ladder of classical rules. This section explains what the agent learned, what a high first-transmission BLER costs, when RL is worth deploying as a calibrator, and how such claims should be evaluated. The common thread is that this environment rewards choosing the right operating point far more than tracking the channel quickly, and that a correctly specified learner finds that operating point on its own.

## 6.1 Setpoint Control: Operating-Point Choice, Not Fast Adaptivity

The agent behaves like the per-class oracle: a nearly constant offset per user, at the oracle’s level. Table VI places every scheme on the rate–reliability trade-off at the headline point.

Table VI. Operating points at the headline configuration (+9 dB bursts, heterogeneous users, PF scheduler ranking users on the OLLA reference rate, goodput reward), 100 held-out traces; A2C averaged over 10 seeds. Calibrated class table: [−2, −2, −2; −4, −2, −2].

| Scheme (PF, headline point) | Offset over OLLA reference | First-tx BLER | Cell throughput (Mbps) | vs oracle |
|:--|:--|:--|:--|:--|
| Open-loop CQI mapping | none (no OLLA) | 0.611 | 3.52 | −11.8% |
| OLLA, cold start | 0 | 0.520 | 3.86 | −3.1% |
| OLLA, 1000-TTI warm-up | 0 | 0.380 | 3.77 | −5.4% |
| Multi-OLLA | 0 (fast/slow blend) | 0.477 | 3.92 | −1.6% |
| Fixed (global constant) | −2 | 0.392 | 4.07 | +2.1% |
| Fixed-Online (estimated class) | per class | 0.377 | 4.02 | +0.9% |
| FixedPU (per-class oracle) | −2 (−4 for one class) | 0.385 | 3.99 | — |
| Deep A2C, Tier-O, from scratch | learned (mean −2.26) | 0.372 | 3.97 | −0.3% |

Five observations explain the table.

- **A smooth landscape with one optimum.** Throughput as a function of a single constant offset is unimodal (Table VII, Fig. 8), peaking at −2 with 4.08 Mbps and BLER 0.388; one level either side costs 1.4% and 2.3%. The offline calibration found the same offset. Nothing in the landscape requires state-conditional control to reach the optimum.

- **The agent finds the oracle’s operating point.** Its mean offset is −2.26 against −2.23 for the oracle, 71% of its decisions lie within one level of the oracle’s per-class action, and its first-transmission BLER is 0.372 against 0.385. For each user the modal action covers 73% of decisions. Throughput is equivalent to the oracle (−0.3%, 90% CI [−1.5, +0.8]%, TOST p = 0.008).

- **Spread around the optimum is what it costs.** The agent trails the single best constant by 2.4% (Holm p = 0.045). Only 26.7% of its decisions use the best offset itself; 47.7% are one level away and 25.7% two or more, where Table VII shows losses of 1.4%–2.3% and more. The spread, not the centre, explains the gap.

- **Learning is genuine.** Training throughput rises from 3.60 to 3.89 Mbps between the first and last 25 episodes, the trained agent beats a uniform-random action policy by +10.8% (p = $4.3\times10^{-13}$), and the ten seeds lie between −2.2% and +1.7% of the oracle.

- **No gain from more state or from fine-tuning.** Table VIII compares three state tiers. Adding true speed, true delay and the ground-truth burst flag (Tier-B), or removing HARQ and NACK history (Tier-A), does not improve on Tier-O, and starting from a clone of the oracle, fine-tuning found nothing better (Section 4.3). A caveat: our policy is a feedforward network with a three-frame stack, not a recurrent model or a channel predictor, so these results show that the features do not help this learner, not that no learner could use them.

Table VII. Constant-offset landscape on the same 100 held-out traces (global constant applied on top of OLLA).

| Constant offset | Cell throughput (Mbps) | First-tx BLER | vs best constant |
|:--|:--|:--|:--|
| −6 | 3.65 | 0.210 | −10.7% |
| −5 | 3.79 | 0.242 | −7.3% |
| −4 | 3.93 | 0.290 | −3.8% |
| −3 | 4.03 | 0.327 | −1.4% |
| −2 | 4.08 | 0.388 | — |
| −1 | 3.99 | 0.457 | −2.3% |
| +0 | 3.84 | 0.520 | −6.1% |
| +1 | 3.53 | 0.612 | −13.6% |
| +2 | 3.38 | 0.673 | −17.3% |
| +3 | 3.18 | 0.739 | −22.2% |
| +4 | 2.86 | 0.791 | −29.9% |

![Constant-offset landscape on the 100 held-out traces: cell throughput (left) and first-transmission BLER (right) of a single global offset applied on top of OLLA. The diamond marks the Deep A2C controller at its mean offset.](v8_landscape.png){width=6.3in}

Table VIII. A2C throughput by state tier, reward and scheduler input; 10 seeds, 100 held-out traces. The oracle is the same in the first two columns (FixedPU, 3.99 Mbps); in the third it is FixedPU evaluated with the original scheduler input (3.93 Mbps). The reward and the scheduler input change the result far more than the state does.

| State tier | Goodput reward (primary): throughput, vs oracle | Penalised reward: throughput, vs oracle | Original scheduler, penalised reward: throughput, vs oracle |
|:--|:--|:--|:--|
| Tier-A (CQI, OLLA offset, trends) | 3.95 Mbps, −0.9% | 3.74 Mbps, −6.2% | 3.08 Mbps, −21.6% |
| Tier-O (+ HARQ state, NACK history, SINR slope, PF rate) | 3.97 Mbps, −0.3% | 3.83 Mbps, −4.0% | 3.50 Mbps, −11.1% |
| Tier-B (+ true speed, delay, burst flag) | 3.91 Mbps, −2.0% | 3.77 Mbps, −5.4% | 3.13 Mbps, −20.5% |

**At steady state, converged OLLA is the operating point.** After a 1000-TTI warm-up and 950 TTIs of scoring, OLLA, warm OLLA, Multi-OLLA and the global constant all end within 3.52–3.56 Mbps. The agent reaches 3.44 Mbps, equivalent to the per-class oracle (+0.2%, TOST p = $7.9\times10^{-6}$) but 2.9% below OLLA (Holm p = $1.6\times10^{-10}$). The oracle’s class table was calibrated, and the agent trained, on cold-start traces, and once the loop has converged any extra offset, learned or calibrated, adds error rather than removing it. The agent’s advantage over OLLA at 200 TTIs is therefore a transient effect.

**HARQ and the cost of a high BLER.** With Chase combining, a failed first transmission is cheap to recover [8], so goodput keeps rising as the first-transmission operating point moves well above 10%; the best constant runs at 0.388. Goodput does not count what that operating point costs: added HARQ delay, occupied HARQ processes and extra control-channel load. The reward can price these in. With the v8 penalties (0.05 per NACK, 0.5 per dropped packet) the agent ran at BLER 0.265 instead of 0.372 and lost 3.7% throughput. That is a legitimate design choice, but it must be made explicitly and evaluated against the same objective, for example as a BLER constraint [10]. It must not be left implicit in a reward that is then scored on throughput.

## 6.2 HARQ Chase-Combining Error Subsidization

The constant-offset landscape (Table VII, Fig. 8) shows where goodput peaks: at an offset of −2, with a first-transmission BLER of 0.388, about four times the conventional 10% target. Offsets that push the BLER down to 0.290 (−4) or 0.210 (−6) cost 3.8% and 10.7% of throughput; offsets that push it up to 0.520 (0, i.e. cold-started OLLA) or 0.612 (+1) cost 6.1% and 13.6%. Converged OLLA settles at almost the same point (0.390, Table IV). This is established HARQ behaviour rather than a finding of this paper [8]: with Chase combining, a failed first transmission is usually recovered at the next attempt, so it costs a transmission opportunity rather than the transport block.

Our link model makes the mechanism explicit. Because the BLER curves are steep, the 2.5 dB combining gain makes a retransmission very likely to succeed when the channel has not changed much (Section 2.7). If $p_m$ is the first-transmission BLER of MCS $m$ and retransmissions almost always succeed, the expected number of transmission opportunities per delivered block is approximately $1+p_m$, and the goodput per opportunity is approximately

$$G(m)\approx\frac{\mathrm{TBS}(m)}{T_{\mathrm{tti}}\,(1+p_m)}.\qquad (56)$$

Raising the MCS by one level increases $\mathrm{TBS}(m)$ substantially at every level, while the denominator can at most double. The goodput-optimal operating point therefore lies where the marginal gain in transport-block size balances the growth of $1+p_m$, which in our simulator is near a first-transmission BLER of 0.4. Cold-started OLLA (0.52) is above this optimum, which is why a conservative offset helps it, and converged OLLA already sits near it, which is why the same offset then hurts (Section 5.5).

Two qualifications apply. First, (56) is a quasi-static approximation for users above the MCS-0 floor. A retransmission occupies the user's next scheduled opportunity, not the next TTI, and for fast users or at a burst onset the channel can change in between. Second, the reported BLER is a cell average over all first transmissions. It mixes adaptable users with users pinned at MCS 0 (about 38% of user-TTIs, Section 2.2), whose BLER stays high whatever the offset, so at the best constant the BLER of adaptable users is lower than the reported 0.39. Converged OLLA does not optimize (56): it drives adaptable users toward about 0.105 (Section 3.1), and its cell average of 0.39 is lifted by the pinned users. That this average lands near the goodput optimum of the constant-offset landscape is therefore partly a property of this link budget rather than of OLLA.

Approximation (56) captures only goodput. Each retransmission adds a HARQ round-trip of latency, occupies a HARQ process and adds control signalling, none of which the primary reward or metrics penalize, and the combining model is favourable: the gain is a fixed 2.5 dB per attempt applied at the true SINR of the retransmission TTI. The reliability variant of Section 6.1 shows the price of pricing these costs in: it runs at a BLER of 0.265 and gives up 3.7% throughput. The operating points reported here should therefore be read as goodput-optimal for this model, not as recommended targets; a deployment that cares about latency should impose the BLER level as an explicit constraint [10].


## 6.3 When Is RL Worth Using as an Online Calibrator?

If the optimal policy is a constant, RL can still be useful when the constant is expensive to find. Our oracle needed a grid search over 9 offsets for each of 6 user classes, on 20 dedicated calibration traces, for one scheduler, one HARQ configuration and one burst regime. In a network this grid multiplies across cells, schedulers, traffic mixes and software releases.

The from-scratch agent removes that cost: it reaches the oracle’s operating point and throughput (−0.3%, equivalent at ±2%) from its own reward, with no calibration traces and no class labels. That is the supported claim. Three results bound it.

- **A cheaper calibration does better.** The single best global offset, found by a 9-point search, beats the agent by 2.4%. Fixed-Online, which estimates each user’s class online with no learning, is 1.2% ahead (Holm p = 0.23, not significant).

- **The advantage over OLLA is transient.** The agent beats cold-start OLLA by 2.9% over 200 TTIs and the best OLLA target from a 10–50% sweep by 1.6% (p = 0.074, not significant), but trails converged OLLA by 2.9% at steady state.

- **Training is not free.** Ten seeds of 300 episodes each still spread from −2.2% to +1.7% around the oracle, so a deployment needs several seeds, validation and a fallback.

Deep RL is therefore worth considering where calibration data are unavailable and users are short-lived enough that OLLA rarely converges, for example cells dominated by short sessions. Elsewhere a calibrated constant on top of OLLA, or a converged OLLA alone, is simpler and at least as good. The quantity to be learned is a small table of offsets. A bandit over offsets [6], an outer loop that adapts its own target or a self-adaptive SINR tracker [7] learns it with far fewer parameters, and these lighter calibrators, which this study did not benchmark, are the bar a deep policy must clear.

## 6.4 Evaluation and Deployment Guidelines

Each guideline below traces to a defect or result in our own campaigns. The first group concerns how to evaluate an RL link-adaptation claim; the second concerns deployment in a gNodeB.

### Evaluating a claim

- **Score OLLA at steady state as well as from cold start.** Short traces from a zero offset flatter any learner. Our agent beats OLLA by 2.9% over 200 cold-start TTIs and trails it by 2.9% at steady state; in v7 the sign flipped the same way.

- **Compare with a tuned constant, not only with OLLA.** The best global constant beats our agent by 2.4%. Without it, an untuned baseline makes an operating-point shift look like learning.

- **Never clone the comparator you report against.** Parity reached by cloning the oracle is circular. Report the from-scratch learner as the result and treat cloning as a diagnostic, with the clone’s confidence checked (Section 4.4).

- **Test equivalence explicitly.** A non-significant difference is not parity. Use TOST with a pre-declared margin [15], at least 100 paired traces, several training seeds, common traces across schemes (ideally also common random numbers for the outcome draws, which our harness lacked; Section 5.1) and Holm correction across comparators [14].

- **Sanity-check the simulator’s operating point.** With perfect CSI and action 0, first-transmission BLER should not exceed the target. Our CQI table failed this check (≈75% BLER) in three successive versions. Check the time scale of every mobility process as well: our large-scale mobility advanced by $v_i$ metres per TTI, 1000 times faster than the TTI clock (Section 2.1).

- **Bound every integrator.** Unbounded OLLA offsets wound down indefinitely for users below MCS-0, making warm OLLA look worst: in an audit check on six traces, Warm-OLLA rose from 2.36 to 3.43 Mbps once its offset was bounded to ±10 dB.

- **Aggregate with missing values, not zeros.** Zero-padded result arrays halved every deterministic baseline’s burst, edge and fairness metrics and produced spurious +218% to +250% "RL advantages."

- **Give the agent only observable state and disclose its structure.** Our Tier-B state used true speed, true delay and the ground-truth burst flag. These features did not help (Table VIII), and they make the comparison unfair to classical rules. State that the agent is residual to an active OLLA loop, and ablate that loop.

- **Do not let the agent’s action set its scheduling priority.** In the original code the proportional-fair metric used the agent’s chosen MCS as the user’s potential rate, and a per-user reward then paid the agent to inflate its MCS and win the slot. Throughput was 8.6% (Tier-O) to 17.6% (Tier-A) lower than with ranking on the OLLA reference rate. The Tier-B agent was only 5.6% better than random actions, and five times more training lowered Tier-O throughput further, to 2.88 Mbps.

- **Train on the objective you report.** Penalties for NACKs and dropped packets made the agent run at a lower BLER than throughput favours and cost 3.7% throughput. Started on the oracle, the penalised learner walked away from it (−3.0%). If reliability matters, make it an explicit constraint and report it.

- **Run sanity controls.** Report a random-action policy, the constant-offset landscape and the learning curve next to the headline number. A learning curve that falls with more training, and a learner that walks away from the optimum when started on it, were the symptoms that exposed the last two defects.

### Deploying in a gNodeB

- **Keep the agent residual to OLLA.** Action 0 is then the deployed baseline, which bounds worst-case behaviour and gives a fallback.

- **Size the action set to the calibrated optimum, with margin, and give baselines the same reach.** An optimum on the edge of the search grid signals that the true optimum lies outside it. If the agent can jump 6 levels in one step, compare it with a rule that can too.

- **Keep scheduling and link adaptation separate, and train on the deployed scheduler.** Rank users on a rate estimate that the agent cannot manipulate.

- **Set the reliability trade-off explicitly.** Use a BLER or latency constraint matched to the bearer’s delay budget, and monitor first-transmission BLER and the action histogram in operation.

- **Plan for variance and convergence.** Train several seeds, select on held-out validation, and hand over to OLLA once the loop has converged, or fall back to it whenever the learned policy underperforms.

# 7. Conclusion and Future Directions

## 7.1 Summary of Contributions

We asked what a deep RL link-adaptation agent achieves once the simulator includes HARQ cost, user heterogeneity, non-stationary interference and steep BLER curves, and once the agent is compared with converged and tuned classical rules rather than with a cold-start OLLA alone.

Trained from random initialization on observable state with a goodput reward, a shared multi-user A2C agent acting as a residual offset over OLLA reaches 3.97 Mbps under proportional-fair scheduling. It is statistically equivalent to the offline per-class oracle (−0.3%, 90% CI [−1.5, +0.8]%) and beats cold-start OLLA by 2.9%. It trails the best global constant offset by 2.4% and, at steady state, converged OLLA by 2.9%, over 100 held-out traces and 10 seeds. Its actions settle on the oracle’s operating point (mean offset −2.26 vs −2.23). Richer state does not help, and fine-tuning a clone of the oracle finds nothing better. In this environment class, RL earns its keep as an online calibrator that finds the operating point without calibration data, not as a channel tracker, and a tuned constant or a converged loop still does slightly better.

The second contribution is methodological. Nine defects in our own pipeline each created or hid a multi-percent difference between RL and its baselines: circular behaviour cloning, an entropy schedule that erased a warm start, transient-only scoring, zero-padded aggregation, an off-by-one CQI table, unbounded integrator windup, simulator-only state features, scheduler gaming (9–18% throughput) and error penalties in the reward (3.7%). The checklist in Section 6.4 and the released code are intended to make future "RL beats OLLA" claims easier to test.

## 7.2 Future Research Directions

Two questions remain open: how to close the remaining gap to the best tuned rule, and whether any learner can add state-conditional value on top of the right operating point.

- **Tighten the learned operating point.** The agent’s gap to the best constant comes from the spread of its actions around the optimum. Test lower final entropy, proximal or KL-regularized updates, and a cooperative cell-level reward.

- **Benchmark lighter calibrators.** Compare deep RL with bandits over offsets [6], self-adaptive SINR tracking [7] and target-adaptive OLLA, which learn the same small offset table with far fewer parameters.

- **Study short-dwell non-stationarity.** In our simulator interference bursts last 120–250 TTIs while CQI feedback arrives within 2–8 TTIs, so the reactive loop always sees a burst long before it ends. Sweep burst dwell down to and below the feedback delay, where a predictive policy could act before CQI reflects the change.

- **Use policies with memory.** Replace the frame-stacked MLP with recurrent or attention-based policies, or pair the agent with an explicit channel predictor, and repeat the state ablation.

- **Constrain reliability.** Train under an explicit first-transmission BLER or latency constraint [10] and report throughput at a fixed reliability level.

- **Test autonomy and realism.** Disable the background OLLA integrator to test the agent as a full replacement, validate on 3GPP TR 38.901 link-level channels [12] and measured traces, and extend to multi-cell settings where neighbouring controllers interact.

# Appendix A. Tabular RL Baselines of Earlier Versions

To assess the benefits of deep function approximation over conventional reinforcement learning, two tabular baselines were implemented in earlier versions of the framework: Q-Learning (QL) and Tabular Actor-Critic (TabAC). Both methods employ shared parameter tables across all users and operate within the same wireless environment as the deep A2C framework, including identical CQI-offset actions, rewards and scheduling mechanisms. Unlike deep A2C, which processes continuous-valued state features through neural networks, the tabular methods require explicit state discretization.

Both tabular algorithms use a six-dimensional discrete state representation,

$$s^{\mathrm{tab}}_{i,t}=\big(c_{i,t},\ \Delta c_{i,t},\ b^{\mathrm{SINR}}_{i,t},\ b^{\mathrm{trend}}_{i,t},\ b^{\mathrm{offset}}_{i,t},\ b^{\mathrm{sched}}_{t}\big),\qquad (57)$$

where $c_{i,t}$ is the reference CQI, $\Delta c_{i,t}$ denotes its temporal variation, and the remaining components represent the observed SINR, SINR trend, OLLA offset and scheduler identity. The observed SINR is mapped to the nearest of 20 predefined grid points, while the SINR trend is classified into falling, approximately stable and rising categories using thresholds of −1 and 1 dB. The OLLA offset is discretized into five categories, and the scheduler is represented by three possible indices. With 15 CQI levels, 11 CQI-difference levels and $|\mathcal{A}|$ offset actions, the resulting Q-table contains

$$|\mathcal{S}||\mathcal{A}|=15\times11\times20\times3\times5\times3\times|\mathcal{A}|\qquad (58)$$

state-action entries, 1,633,500 with the eleven actions used here. Although this representation provides explicit state-action values, its size illustrates the dimensionality bottleneck associated with tabular learning, particularly when many states are infrequently visited. Incorporating additional channel, mobility or HARQ features would further increase the table size multiplicatively.

The Q-Learning baseline follows the conventional off-policy temporal-difference update [22]:

$$Q(s_t,a_t)\leftarrow Q(s_t,a_t)+\alpha\Big[r_t+\gamma\max_{a'}Q(s_{t+1},a')-Q(s_t,a_t)\Big],\qquad (59)$$

where the learning rate is $\alpha=0.1$ and the discount factor is $\gamma=0.95$. Actions are selected using an $\epsilon$-greedy strategy, with $\epsilon$ decaying geometrically from an initial value of 0.30 toward 0.05 over training. To avoid systematically favoring negative CQI offsets in previously unvisited states, ties between maximum Q-values are resolved in favor of the zero-offset action. This preserves the baseline CQI recommendation when the available Q-values do not distinguish between actions.

The Tabular Actor-Critic baseline maintains separate tables for action preferences $\theta(s,a)$ and state-value estimates $V(s)$. Its policy is obtained through a softmax transformation,

$$\pi_\theta(a\mid s)=\frac{\exp\big(\theta(s,a)\big)}{\sum_{a'}\exp\big(\theta(s,a')\big)}.\qquad (60)$$

Following each transition, the temporal-difference error is computed as

$$\delta_t=r_t+\gamma V(s_{t+1})-V(s_t),\qquad (61)$$

and the critic and actor parameters are updated according to

$$V(s_t)\leftarrow V(s_t)+\alpha_v\,\delta_t,\qquad (62)$$

$$\theta(s_t,\cdot)\leftarrow\theta(s_t,\cdot)+\alpha_\theta\,\delta_t\big[\mathbf{e}_{a_t}-\pi_\theta(\cdot\mid s_t)\big],\qquad (63)$$

where $\alpha_v=0.10$, $\alpha_\theta=0.05$, and $\mathbf{e}_{a_t}$ denotes the one-hot vector corresponding to the selected action. Both tabular methods update their shared tables using transitions from all users, allowing accumulated experience to contribute to a common decision policy.

In the earlier (pre-audit) campaign both tabular learners stayed close to OLLA's throughput and well below the deep learner, consistent with the dimensionality argument above: discretization reduces the resolution of channel-state information, while the large state-action space limits the frequency with which individual entries can be updated. 

These learners were not ported to the corrected v8 code and are not part of any result in this paper. Their bin edges and exploration schedule are those of the earlier code release. They are kept here as background for the dimensionality argument: with eleven actions the table has 1,633,500 entries, against about 60,000 scheduled transitions per training seed. A stateless or class-conditioned bandit over the eleven offsets (11 or 66 entries) would be the more direct non-deep comparator (Section 6.3).


# References

[1] 3GPP, "Evolved Universal Terrestrial Radio Access (E-UTRA); Physical layer procedures," TS 36.213, V14.2.0 (Release 14), 2017.

[2] K. I. Pedersen et al., "Frequency domain scheduling for OFDMA with limited and noisy channel feedback," in *Proc. IEEE VTC 2007-Fall*, 2007, doi: 10.1109/VETECF.2007.380.

[3] R. Bruno, A. Masaracchia, and A. Passarella, "Robust adaptive modulation and coding (AMC) selection in LTE systems using reinforcement learning," in *Proc. IEEE 80th Veh. Technol. Conf. (VTC2014-Fall)*, Vancouver, Canada, 2014, doi: 10.1109/VTCFall.2014.6966162.

[4] M. P. Mota, D. C. Araujo, F. H. Costa Neto, A. L. F. de Almeida, and F. R. P. Cavalcanti, "Adaptive modulation and coding based on reinforcement learning for 5G networks," in *Proc. IEEE Globecom Workshops*, 2019, arXiv:1912.04030.

[5] V. Saxena, H. Tullberg, and J. Jaldén, "Reinforcement learning for efficient and tuning-free link adaptation," *IEEE Trans. Wireless Commun.*, 2022, arXiv:2010.08651.

[6] S. K. Pulliyakode and S. Kalyani, "Reinforcement learning techniques for outer loop link adaptation in 4G/5G systems," arXiv:1708.00994, 2017.

[7] R. Wiesmayr, L. Maggi, S. Cammerer, J. Hoydis, F. Aït Aoudia, and A. Keller, "SALAD: Self-adaptive link adaptation," arXiv:2510.05784, 2025.

[8] E. Dahlman, S. Parkvall, and J. Sköld, *5G NR: The Next Generation Wireless Access Technology*. London, U.K.: Academic Press, 2018, doi: 10.1016/C2016-0-04354-9.

[9] M. Ahsen, B. Yanakiev, C. Rosa, and R. Adeogun, "Rank-aware link adaptation for XR tethering groups with realistic tethering link: A multi-offset OLLA framework," arXiv:2604.20459, 2026.

[10] E. Altman, *Constrained Markov Decision Processes*. Boca Raton, FL, USA: Chapman & Hall/CRC, 1999.

[11] W. C. Jakes, *Microwave Mobile Communications*. New York, NY, USA: Wiley, 1974.

[12] 3GPP, "Study on channel model for frequencies from 0.5 to 100 GHz," TR 38.901, V17.0.0 (Release 17), 2022.

[13] F. Wilcoxon, "Individual comparisons by ranking methods," *Biometrics Bulletin*, vol. 1, no. 6, pp. 80–83, 1945, doi: 10.2307/3001968.

[14] S. Holm, "A simple sequentially rejective multiple test procedure," *Scand. J. Statist.*, vol. 6, no. 2, pp. 65–70, 1979.

[15] D. J. Schuirmann, "A comparison of the two one-sided tests procedure and the power approach for assessing the equivalence of average bioavailability," *J. Pharmacokinet. Biopharm.*, vol. 15, no. 6, pp. 657–680, 1987, doi: 10.1007/BF01068419.

[16] M. Gudmundson, "Correlation model for shadow fading in mobile radio systems," *Electron. Lett.*, vol. 27, no. 23, pp. 2145–2146, 1991.

[17] F. P. Kelly, A. K. Maulloo, and D. K. H. Tan, "Rate control for communication networks: Shadow prices, proportional fairness and stability," *J. Oper. Res. Soc.*, vol. 49, no. 3, pp. 237–252, 1998.

[18] R. S. Sutton and A. G. Barto, *Reinforcement Learning: An Introduction*, 2nd ed. Cambridge, MA, USA: MIT Press, 2018.

[19] V. Mnih et al., "Asynchronous methods for deep reinforcement learning," in *Proc. ICML*, 2016, arXiv:1602.01783.

[20] D. A. Pomerleau, "ALVINN: An autonomous land vehicle in a neural network," in *Advances in Neural Information Processing Systems 1*, 1989, pp. 305–313.

[21] D. P. Kingma and J. Ba, "Adam: A method for stochastic optimization," presented at the Int. Conf. Learn. Represent. (ICLR), 2015, arXiv:1412.6980.

[22] C. J. C. H. Watkins and P. Dayan, "Q-learning," *Machine Learning*, vol. 8, no. 3–4, pp. 279–292, 1992, doi: 10.1007/BF00992698.