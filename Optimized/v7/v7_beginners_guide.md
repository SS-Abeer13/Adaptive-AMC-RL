# A Beginner's Guide to RL-Based Link Adaptation: The Full Story, Built From First Principles

**Who this is for:** someone comfortable with theory in general — optimization, control, probability, maybe some machine learning — but with no assumed background in cellular networks or wireless communications specifically. Every domain-specific concept is built up before it's used. Nothing is assumed except mathematical maturity.

**What this covers:** the entire research program, from "what problem are we even solving" through six major redesigns (v1 through v6) and the final, most rigorous version (v7), ending with why the final answer turned out to be a carefully-earned null result — and why that is still a real scientific contribution.

---

## Roadmap

1. **The physical problem** — what a cellular downlink is, and why choosing how to transmit is genuinely hard.
2. **The classical solution** — OLLA, explained as a control loop.
3. **Why reinforcement learning enters the picture at all** — built from the decision-process formalism up.
4. **The long road to a trustworthy pipeline (v1–v5)** — four rounds of debugging, each triggered by a specific numeric red flag.
5. **The uncomfortable lesson from v6** — why a "does RL actually work" claim can be an illusion, and how that illusion was caught.
6. **The redesigned experiment (v7)** — five specific changes, each closing one loophole from v6.
7. **How the experiment was made rigorous** — pre-registration and hypothesis testing, explained from scratch.
8. **What happened when it ran** — the headline result.
9. **The detective work** — diagnosing *why* the result came out the way it did.
10. **Fixing it, one iteration at a time.**
11. **An adversarial sanity check, and the final decisive experiment.**
12. **The big picture: what this all actually means.**
13. **A glossary**, for reference while reading.

---

## Part 1: The Physical Problem

### 1.1 What a Cellular Downlink Actually Is

A cellular base station (a cell tower) serves many users at once. Each user carries a phone; the base station has a fixed amount of radio spectrum (frequency bandwidth) it can use to send data. The **downlink** is specifically the direction from base station to user — the base station is transmitting, the user's phone is receiving.

Time is sliced into small chunks called **Transmission Time Intervals (TTIs)** — in this project, 1 millisecond each. In every TTI, the base station decides: which users get to transmit data this instant, and at what rate?

### 1.2 Modulation and Coding: Trading Rate for Reliability

Here is the central engineering tension. To send data over a radio channel, the base station encodes bits into a radio waveform using a combination of **modulation** (how many bits are packed into each transmitted symbol) and **coding** (how much redundancy is added to protect against errors). Together these choices are called the **Modulation and Coding Scheme (MCS)**.

A higher MCS packs more bits per symbol and less redundancy — it's faster, but any given amount of noise or interference is more likely to corrupt it beyond recovery. A lower MCS is slower but far more robust to noise. This is a direct analogue of the classic information-theoretic trade-off: for any fixed channel quality (measured, roughly, as the ratio of received signal power to noise-plus-interference power, or **SINR** — Signal-to-Interference-plus-Noise Ratio), there is a maximum rate at which you can transmit with an arbitrarily small error probability (this is the intuition behind the **Shannon capacity** of a channel). Real systems don't operate at the theoretical Shannon limit, but the same shape of trade-off holds: pick too aggressive an MCS for the SINR you actually have, and your error rate spikes; pick too conservative an MCS, and you're leaving throughput on the table.

The quantity that captures "how often does a chosen MCS actually fail on this channel" is the **Block Error Rate (BLER)**: the probability that a transmitted block of bits, at a given MCS and a given SINR, is received with uncorrectable errors. BLER is a steeply increasing function of MCS (holding SINR fixed) — go up one MCS level and the error probability can jump sharply, because you've eaten into your noise margin. This SINR-vs-BLER relationship, for each MCS, is sometimes called a **waterfall curve**, because plotted on the right axes it looks like a steep drop from "always fails" to "never fails" over a narrow SINR range.

**The core decision, restated:** at every TTI, for every user, choose the MCS that maximizes expected useful throughput, given the channel conditions right now.

### 1.3 Why You Can't Just Always Use the Highest MCS

If SINR were perfectly known and constant, this would be a solved, static problem: look up the best MCS for that SINR, done. The reason this remains a genuinely hard *control* problem, not a lookup-table problem, is that **the base station does not know the true, instantaneous SINR when it makes the decision.**

### 1.4 Channel Quality Indicator (CQI) and Feedback

The user's phone measures the channel and reports back a summary — the **Channel Quality Indicator (CQI)**, essentially a quantized estimate of SINR. This report has to travel back to the base station, get processed, and only then does the base station choose an MCS for the *next* opportunity to transmit to that user. This introduces two problems that compound:

- **Feedback delay.** The CQI report the base station uses at time $t$ was actually measured at some earlier time $t - d$, where $d$ is a delay of a few milliseconds (a few TTIs). If the channel has changed in the meantime, the base station is acting on stale information.
- **Measurement noise.** The CQI report itself is a noisy estimate, not the true SINR.

### 1.5 The Core Difficulty

Put together: the base station must choose an MCS *now*, but only has a noisy, delayed estimate of a channel that may have moved since that estimate was taken. If the user is standing still and the channel is stable, a delay of a few milliseconds barely matters. If the user is in a moving vehicle, the channel can change substantially within that delay window — a phenomenon governed by **Doppler spread** (how fast the channel decorrelates, related to the user's speed and the carrier frequency) and captured by the channel's **coherence time** (the time window over which the channel can be treated as roughly constant). When the feedback delay exceeds the coherence time, the CQI report is essentially useless for predicting the current channel — you're being told what the weather was five minutes ago and asked to dress for right now.

This is the fundamental problem that **link adaptation** exists to solve: choosing an MCS, every TTI, per user, under delayed and noisy channel information, to maximize throughput while keeping errors under control.

---

## Part 2: The Classical Solution — OLLA as a Control Loop

### 2.1 A Thermostat Analogy

If you've studied control theory, this next part will feel immediately familiar. The industry-standard solution to link adaptation is called **Outer Loop Link Adaptation (OLLA)**, and it is, structurally, nothing more exotic than a thermostat.

A thermostat doesn't try to perfectly model the thermal dynamics of a room. It just does something simple and robust: if the room is too cold, turn the heat up a bit; if too hot, turn it down a bit; repeat. Over time, it settles near the target temperature, correcting for whatever it doesn't explicitly model (drafts, sunlight, an open window) purely through this feedback loop.

OLLA does exactly this, but for MCS selection. It maintains a running numerical **offset** $\Delta_{\text{OLLA}}$, added to the reported CQI before mapping it to an MCS:

$$\text{effective SINR}_t = \text{reported SINR}_t + \Delta_{\text{OLLA}}$$

### 2.2 The Update Rule

After each transmission, the receiver reports back success (ACK, acknowledgment) or failure (NACK, negative acknowledgment) for that specific transmission — this is fast, local feedback, distinct from the slower CQI reporting loop. OLLA reacts to it immediately:

$$
\Delta_{\text{OLLA}} \leftarrow
\begin{cases}
\Delta_{\text{OLLA}} + \delta_{\text{up}} & \text{if ACK (success): nudge up, be a bit more aggressive next time} \\
\Delta_{\text{OLLA}} - \delta_{\text{down}} & \text{if NACK (failure): back off, be more conservative}
\end{cases}
$$

If you pick the step sizes $\delta_{\text{up}}$ and $\delta_{\text{down}}$ correctly, this simple up/down rule provably converges, in steady state, to a target error rate $P_{\text{target}}$ (classically 10%). The balance condition is:

$$(1-P_{\text{target}}) \cdot \delta_{\text{up}} = P_{\text{target}} \cdot \delta_{\text{down}}$$

Intuitively: successes are common (say, 90% of the time at the target error rate) so each one should nudge the offset up by only a little; failures are rare (10% of the time) so each one should push the offset down by a proportionally larger amount, to balance out over many transmissions.

### 2.3 What OLLA Can and Cannot Do

This is, in control-theoretic terms, a simple **integral controller**: it accumulates a correction based on the error signal (ACK/NACK) over time. It requires zero calibration — it can be deployed on day one with no knowledge of the specific deployment — and it is provably stable and mean-reverting to its target.

But it has a structural limitation that any control theorist will recognize immediately: it is **purely reactive**. It only ever responds to what has already happened (a past ACK or NACK); it has no model of the channel and no ability to anticipate a change before it happens. If the channel is about to degrade sharply (say, the user is entering a shadowed region), OLLA finds out only after it starts seeing failures — by which point it has already been transmitting too aggressively for a stretch, wasting throughput on failed attempts, before it corrects.

**This is exactly the gap a predictive, state-aware controller could in principle close** — and it is exactly the gap that motivates trying reinforcement learning.

---

## Part 3: Why Reinforcement Learning Enters the Picture

### 3.1 What a Decision Process Is, Built From Scratch

Reinforcement learning (RL) is the branch of machine learning concerned with sequential decision-making: an agent repeatedly observes something about the world, takes an action, receives a numerical reward, and the world evolves — and the agent's goal is to learn, through experience, a rule for choosing actions (a **policy**) that maximizes its long-run accumulated reward.

Formally, this is captured by a **Markov Decision Process (MDP)**: a tuple of (states, actions, transition dynamics, reward function). At each discrete time step, the agent is in some state $s_t$, takes an action $a_t$ according to its policy $\pi$, the environment transitions to a new state $s_{t+1}$ according to some (possibly unknown) dynamics, and the agent receives a reward $r_t$. The agent's objective is to find $\pi$ maximizing expected discounted cumulative reward, $\mathbb{E}\left[\sum_t \gamma^t r_t\right]$, where $\gamma \in [0,1)$ discounts future rewards.

When the agent cannot observe the true state directly — only some partial, noisy signal correlated with it — this generalizes to a **Partially Observable MDP (POMDP)**. This is the correct framing for link adaptation: the agent (the base station's link-adaptation algorithm) never observes the true instantaneous SINR; it only observes a delayed, noisy CQI report.

### 3.2 Mapping Link Adaptation Onto This Formalism

Once you have the POMDP formalism in hand, the mapping is direct:

- **State (observation):** the reported CQI history, the current OLLA offset, and whatever other features the system is given (more on this below).
- **Action:** which MCS to choose for the next transmission.
- **Reward:** the throughput actually delivered — which depends on whether the chosen MCS succeeded or failed, given the *true* (unobserved) channel state.
- **Transition dynamics:** governed by real physics — path loss, fading, mobility, interference — which the agent does not need to know explicitly; it only needs to learn, from experience, what tends to work.

### 3.3 Why This Looks Like a Natural RL Problem

The appeal of framing link adaptation as RL, rather than sticking with OLLA's simple reactive rule, is that a sufficiently expressive policy — in particular, a neural network trained via RL — can in principle learn to condition its decisions on *patterns* in the observed state that a simple scalar integrator cannot represent at all: trends in the SINR history, correlations with user mobility, structure in how interference tends to evolve, and so on. If such patterns exist and are exploitable, RL should be able to find and use them, and should therefore be able to *outperform* a policy (like OLLA) that structurally cannot use them.

This is a genuinely reasonable hypothesis. Whether it's *true*, for this specific problem, under realistic conditions, is exactly the empirical question this whole research program investigates — and, as you'll see, the honest answer turns out to be more subtle than a simple "yes."

### 3.4 A Clever Reframing: OLLA-Relative Action Encoding

Here is a design choice worth pausing on, because it reflects good experimental hygiene. If you naively set up the RL agent to choose an MCS *directly* — an absolute action, independent of what OLLA would have chosen — you run into an unfair comparison: OLLA gets to use fast ACK/NACK feedback (the outer loop described in Part 2), but if the RL agent's state doesn't include that same feedback, it's being asked to compete with one hand tied behind its back. Any observed "RL loses to OLLA" result would then just be measuring an information deficit, not a genuine algorithmic shortcoming.

The fix used throughout this project is called **OLLA-relative action encoding**: every RL policy (and every comparator) carries the *same* OLLA loop internally, computing the same reference offset $\Delta_{\text{OLLA}}$ from the same ACK/NACK feedback. The RL agent's action is not "which MCS to use" directly, but **an additive correction on top of OLLA's own choice**:

$$\text{chosen CQI} = \text{OLLA-corrected reference CQI} + a_t, \qquad a_t \in \{-K, \dots, -1, 0, 1, \dots, K\}$$

Notice that choosing action $a_t = 0$ makes the RL policy behave *identically* to plain OLLA. This has an elegant consequence: it guarantees, by construction, that RL can never do worse than OLLA in principle (it could always just learn to pick 0 every time), and it isolates the experimental question to exactly the thing worth testing — **does the agent learn something worth doing beyond what OLLA already does?** — rather than conflating that question with "does the agent have access to the same basic feedback OLLA has." This is analogous to a common trick in statistics and econometrics: rather than comparing a rich model to a naive one directly, you re-parameterize so the naive model is a special case (here, the zero vector) nested inside the richer one, and test whether the richer model's *additional* parameters earn their keep.

This specific formulation — OLLA-relative encoding — is itself the product of an earlier debugging history, not something arrived at on the first attempt. That history is the subject of the next part, because it establishes the research discipline that carries through everything afterward: a surprising number, good or bad, is a lead to chase down, not a result to report at face value.

---

## Part 4: The Long Road to a Trustworthy Pipeline (v1–v5)

Before any "does RL beat OLLA" question could be asked honestly, the underlying simulation and training pipeline itself had to be built and debugged — and it took four major iterations, each triggered by a specific quantitative red flag, to reach a version worth taking seriously. This history matters for two reasons: it establishes the general research discipline that carries through the rest of this story, and it explains why v6 (not v1) is the actual starting point for the "does adaptivity have value" question addressed in Part 5 onward.

### 4.1 v1: Absolute Per-User Actions, and a Tie-Breaking Bug

The earliest version had agents choose an MCS directly and independently per user — no OLLA-relative encoding yet, no shared learning across users.

**Red flag:** trained tabular RL performed far below even the simplest, naive fixed-mapping baseline — not a modest underperformance, but something closer to a model that had barely trained at all.

**Root cause, found by tracing the actual decision logic:** two compounding issues. First, the software's built-in function for finding the best action from a table of estimated action-values breaks ties by returning the *first* matching index by default. Early in training, before any action has been tried enough to show a real difference, most action-value estimates are still sitting at their identical initial value (typically zero) and are therefore tied — so the "pick the best action" step was silently, systematically biased toward the lowest-indexed action every single time a tie occurred, rather than making an unbiased or randomized choice. This is a classic hidden-bug class in RL implementations: a supposedly neutral utility function turns out to encode a strong, unintended prior. Second, giving each user their own separate action-value table fragmented the learning experience — each user's table only updated from that one user's transitions — so every table converged far slower than pooling experience across users would have allowed.

**Fix:** implemented an explicit, deliberate tie-breaking rule (biased toward the safe, no-op choice rather than an arbitrary index), and shared learning across users where appropriate.

**Lesson:** a bug in a supposedly neutral utility function can dominate an entire experiment's outcome. The corrected tie-breaking function became a standing, reused utility for every later version of this project.

### 4.2 v2–v3: The "No-Op Imitation" Trap

The next iterations tried biasing training toward the do-nothing action, and adding auxiliary shaping rewards to encourage stability.

**Red flag:** the most heavily-biased configurations performed the *worst* of everything tested — worse than doing nothing special at all.

**Root cause:** in an offset-based action space (where action 0 means "make no change to the current estimate"), biasing a policy toward the no-op action doesn't teach it to be cautious — it teaches it to freeze its estimate and stop tracking a channel that is, in reality, continuously changing. A no-op-biased agent stops adapting entirely, which is worse than either full adaptation or even fully random behavior.

**Fix:** removed the no-op bias and the shaping bonuses entirely.

**Lesson:** a bias intended to encode "prefer safe behavior" can instead encode "stop doing your job," if the action that looks safe doesn't actually mean what it appears to mean in context. Shaping rewards need to be checked against what they actually incentivize operationally, not just what they sound like they should encourage.

### 4.3 v4: Rewriting Actions Relative to a Fixed Reference

This version introduced a precursor to the OLLA-relative encoding described in Part 3.4: actions were redefined as offsets from a fixed, static reference mapping, rather than absolute MCS choices made from nothing.

**Outcome:** for the first time, a trained deep-learning policy edged out OLLA on raw throughput.

**Accompanying fixes made at the same time:** the BLER waterfall curves (Part 1.2) were recalibrated to more realistic shapes; feedback delay and measurement noise were introduced into the CQI reporting pipeline (the simulation had, until this point, been unrealistically clean); and several standard deep-RL training-stability techniques were applied — correctly bootstrapping value estimates at the end of a finite episode, and standardizing the "advantage" signal used to compute policy gradients (both well-known fixes for the high variance that plagues actor-critic training).

**Lesson:** relative action encoding (in this baseline-relative form) turned out to be a substantially better-behaved formulation than absolute action selection — a lesson carried forward and later refined into the OLLA-relative form used from v6 onward.

### 4.4 v5: An "Impossible" Result Reveals Two Deeper Bugs

Before trusting v4's promising result, it was re-audited.

**Red flag:** OLLA was measured as beating the naive baseline by over 160% — a number large enough to be physically implausible for a control loop that, by its own design, can only nudge its offset by small increments each step. An implausibly large positive result deserves exactly the same scrutiny as a bad one: it usually means something in the *measurement pipeline*, not the underlying phenomenon, is inflated.

**Root cause 1 — a scheduler information leak:** the resource-scheduling logic (which decides which users get to transmit in a given TTI, based on their recent throughput history — see the Proportional Fair scheduler discussed in Part 7.1) was, by a wiring mistake, given access to the *true, future* outcome of a transmission attempt when deciding whom to schedule, rather than only the information that would genuinely be available at scheduling time. This let the scheduler implicitly favor whichever policy happened to be more aggressive, regardless of whether that aggression was actually a good decision — an information leak from the future into a decision that should only see the past, similar in spirit to lookahead bias in a backtested trading strategy.

**Root cause 2 — a reward "prisoner's dilemma":** rewards were computed per-user rather than pooled at the cell level, which created a perverse incentive: a user (or the policy acting on its behalf) could gain a scheduling advantage by over-reporting its own channel quality, since a more optimistic report made that user look more attractive to schedule — even though it also raised that user's own risk of transmission failure. This is a direct analogue of a multi-agent incentive-misalignment problem: a reward structure that rewards individually-selfish behavior at the expense of the group outcome, even though every agent shares the same underlying network resource.

**Fix:** restricted the scheduler to only see information genuinely available at decision time (the *reported*, not the *true*, channel quality), and switched to a single, pooled, cooperative cell-level reward shared by every user's learning update — removing the incentive to misreport.

**Lesson:** an unrealistically *good* result deserves exactly the same forensic scrutiny as an unrealistically bad one. Scheduler information leakage and misaligned multi-agent incentives are recurring failure modes worth actively checking for in any multi-user RL system, not just this one.

### 4.5 v6: Closing the Information Gap With OLLA-Relative Encoding

With the scheduler and reward bugs from v5 fixed, the honest result was that RL merely *matched* OLLA, no longer beating it.

**Diagnosis:** OLLA has access to fast, per-transmission ACK/NACK feedback (Part 2.2) that, in the v5 setup, was not being exposed to the RL agent's own observed state at all. This is an informational asymmetry, not a genuine capability gap — OLLA wasn't smarter, it just knew something the learner wasn't told.

**Fix:** the OLLA-relative action encoding introduced in Part 3.4 — give every learner (and every comparator built afterward) the same OLLA loop internally, and define the RL action as a correction on top of it, exposing the current OLLA offset itself as part of the observed state.

**Outcome:** this is the version that finally produced a genuinely fair, apples-to-apples comparison — and, as the next part describes, the version whose *apparent* success under this fair comparison turned out to still be incomplete, once one more control was added.

This four-round history — from a tie-breaking bug, through a reward-shaping trap, to two forms of information leakage, before finally reaching a version worth taking seriously — is why v6, not v1, is the appropriate starting point for asking "does this approach actually work." The audit habit built up over these rounds — treat every surprising number, good or bad, as a lead to chase down rather than a result to accept — carries directly into the v6-to-v7 story that follows.

---

## Part 5: The Uncomfortable Lesson From v6

### 5.1 What v6 Found

With the pipeline finally trustworthy (Part 4.5), v6 ran the OLLA-relative RL setup described in Part 3.4 and found that a neural-network policy, trained via an actor-critic RL algorithm, beat plain OLLA by a statistically significant margin — several percent higher throughput, at multiple feedback-delay settings, with the difference confirmed via a formal hypothesis test.

On its face, this is precisely the positive result the hypothesis in Part 3.3 predicted.

### 5.2 The Control That Changed Everything

Good experimental design, though, asks not just "does my sophisticated method beat a naive baseline?" but "does my sophisticated method beat the *best simple thing I can think of*?" This is the machine-learning analogue of testing against a null hypothesis, or of Occam's razor: before crediting a complex model with genuine insight, you must rule out that a much simpler model achieves the same result.

The relevant "simple model" here is a **constant**: instead of a neural network that observes state and outputs a decision, just pick one fixed number — a single, unchanging correction offset — calibrated in advance (on separate data, not the traces used for the final comparison, to keep this fair) and then applied identically, forever, regardless of anything happening in the environment. A constant, by definition, cannot condition on state. It cannot adapt. It cannot predict. It is, in a real sense, the simplest possible policy that isn't literally "do nothing."

When this control was added to v6's evaluation, it matched the neural network's throughput. **A policy that cannot see, think, or adapt performed identically to a policy built specifically to see, think, and adapt.**

### 5.3 Why This Matters So Much

This is not a minor asterisk on the result — it changes what the result *means*. If a constant achieves the same throughput as the neural policy, then whatever the neural policy is "beating OLLA" by is fully explainable as **where you set the operating point** (essentially: run a bit hotter/more aggressively than OLLA's own default equilibrium), not as anything the network *learned to do differently in different situations*. The word for this in the rest of this guide is a **setpoint effect**: the entire measured gain is a single scalar shift, not evidence of state-conditional adaptivity.

This is exactly the kind of finding that, if missed, would lead to an overclaimed publication: "We show RL beats industry-standard OLLA by X%" sounds impressive and *is a true statement*, but it invites a false inference (that the network learned something clever and situational) that a proper control shows is unsupported. Catching this before publication, rather than after, is the entire value of running the constant-offset control in the first place.

The next question this naturally raises is: **why did v6's specific environment make a constant sufficient?** Answering that diagnostically is what led directly to the redesign that became v7.

---

## Part 6: Redesigning the Test — v7's Five Levers

Diagnosing *why* a constant sufficed in v6 required examining exactly what simplifications the v6 simulation environment made, and asking: does each simplification remove a specific *reason* a state-conditional policy might have an advantage? Four such simplifications were identified, and v7 removes all four simultaneously (plus adds an information-theoretic control, for five changes total), for the reasoning given below.

### 6.1 (D1) Errors Cost Nothing → Add HARQ With Retransmission

In v6, a failed transmission was simply scored as a probabilistic discount on throughput — there was no mechanism by which failure actually *cost* anything beyond its direct probability. This creates a degenerate incentive: since failure has no extra penalty, the throughput-maximizing strategy is simply "be as aggressive as possible, and let the average work out," with no situational restraint ever being rewarded.

The fix is to add **Hybrid Automatic Repeat Request (HARQ)**: if a transmission fails, the receiver doesn't just discard it — it keeps the corrupted data and combines it with a retransmission of the *same* block, a process called **chase combining**, which improves the effective SINR of the retry (modeled here as a $+2.5$ dB boost per prior attempt, up to 3 attempts before giving up). Crucially, that retransmission consumes a real time slot that could otherwise have carried new data for someone else. Now, an overly aggressive first attempt has a genuine cost — wasted capacity on retries — creating an actual trade-off between "transmit fast and risk a costly retry" versus "transmit conservatively and use every slot for new data." This is exactly the kind of trade-off a smart, situation-aware policy should, in principle, be able to navigate better than a fixed rule.

### 6.2 (D2) Every User Is Identical → Add Heterogeneity

In v6, every user had the same feedback delay and the same mobility profile. Under that condition, a single calibrated constant is, tautologically, optimal for every user — there's no variation across users for a smarter policy to exploit.

v7 makes each user draw an independent feedback delay (2–8 TTIs) and speed (3–30 m/s). Now a *single* constant cannot be simultaneously optimal for a slow user with fast, accurate feedback and a fast user with slow, stale feedback. This directly opens a channel through which adaptivity — even just "know which user you're talking to and act accordingly" — could pay off.

### 6.3 (D3) Nothing Ever Changes Mid-Trace → Add Non-Stationarity

If the environment's statistics never change within an observed trace, a reactive integrator (OLLA) and a static constant both eventually settle to the same steady-state answer — there's no *transition* for a predictive policy to react to faster than a reactive one.

v7 introduces a randomly-timed, randomly-lasting **interference burst** — modeled as a two-state Markov chain that toggles extra interference on and off — plus a mid-trace change in each user's mobility speed. These are exactly the kind of regime *shifts* where a purely reactive controller is structurally disadvantaged: by the time OLLA "notices" (via a string of failures) that conditions have changed, several TTIs of suboptimal decisions have already occurred. A policy that can detect the onset of a shift from subtler cues, faster than OLLA's integrator reacts, should have room to add value here.

### 6.4 (D4) Physics Was Too Forgiving → Steepen the Error Curves and Add Realistic Fading

v6 used relatively gentle BLER-vs-SINR curves (recall Part 1.2's "waterfall" description) — meaning overshooting the ideal MCS by a bit didn't cost much in error probability. v7 uses much steeper curves, so precision in MCS choice actually matters.

Separately, v6 modeled fading (rapid, random fluctuations in received signal strength due to multipath propagation) with a fixed statistical correlation over time, regardless of how fast the user was moving. This is physically wrong — a fast-moving user's channel genuinely decorrelates faster (short coherence time; recall Part 1.5) — and, more importantly for the experiment, it silently threw away exactly the physical link between "user speed" and "how predictable the channel is" that a speed-aware policy would need in order to exploit that connection. v7 fixes this using the standard **Jakes fading model**, deriving the channel's time-correlation coefficient directly from each user's instantaneous speed via the Doppler relationship:

$$\rho_i(t) = J_0\!\left(2\pi \frac{v_i(t) f_c}{c} T_{\text{tti}}\right)$$

where $J_0$ is the zeroth-order Bessel function of the first kind (this is the standard closed-form result for the autocorrelation of Rayleigh fading under the classical Jakes/Clarke scattering model), $f_c$ is the carrier frequency, $c$ is the speed of light, and $T_{\text{tti}}$ is the TTI duration.

### 6.5 (D5) An Information Control: Two State "Tiers"

The last change is not a physical change to the environment at all, but an experimental control, analogous in spirit to the constant-offset control from Part 5.2 — this time targeting a different possible confound: what if RL's failure (or success) is really about whether it's given the *right information*, rather than about whether adaptivity has value at all?

v7 defines two versions of what the RL agent is allowed to observe:

- **Tier A**: exactly the same information OLLA's own loop has access to (essentially, nothing more than the CQI history and the current offset) — an "information-equal" baseline, ensuring any RL advantage found here cannot be attributed to a state-observation the constant/OLLA comparators simply don't have access to.
- **Tier B**: Tier A, plus five additional features no scalar control loop could represent even in principle — the HARQ retry state, a short-term history of failures, the SINR's recent trend, the user's instantaneous speed, and a (delayed) indicator of whether an interference burst is currently observed.

Running the *same* experiment under both tiers, and comparing the results, is a clean way to isolate the question "does richer information help?" from every other question this guide asks.

---

## Part 7: How the Experiment Was Made Rigorous

Before running the full campaign, the design commits, in writing, to exactly how success will be judged — a practice called **pre-registration**, borrowed from clinical trials and increasingly adopted in computational science specifically to prevent a well-known failure mode: if you're allowed to choose your success criterion *after* seeing the data, you can almost always find *some* metric, subset, or scheduler under which your preferred method looks good, purely by chance (this is closely related to the **multiple comparisons problem** in statistics — the more ways you're allowed to slice the data looking for significance, the more likely you are to find spurious significance somewhere).

### 7.1 The Pre-Registered Win Condition

Stated in advance: **the neural-network RL policy must beat the best-tuned constant offset, calibrated per user class, under the industry-standard scheduling rule (Proportional Fair, a scheduling policy that balances throughput and fairness across users), on a paired statistical test at significance level $p < 0.05$.**

Every design choice in that sentence has a reason:

- **The comparator is the constant, not just OLLA.** As established in Part 5, OLLA alone is too weak a bar — beating it doesn't distinguish "learned something clever" from "found a better setpoint." The constant, calibrated with access to the same kind of representative data the RL agent trains on, is the more demanding, more honest bar.
- **Per user class ("FixedPU"), not a single global constant.** Recall Part 6.2: heterogeneity means a single global constant is provably suboptimal. Comparing against a *per-class* constant (six constants, one for each combination of two delay categories and three speed categories) closes the easy loophole of "RL wins just by learning to treat different users differently" — a lookup table keyed on user identity could do that without any real state-conditioning either.
- **One specific scheduler (PF).** This is the scheduler actually used in deployed networks; a result that only holds under an unrealistic scheduling rule would be of limited relevance. (Other schedulers are still measured and reported, just not used to define the pass/fail criterion.)
- **A paired statistical test at $p<0.05$.** "Paired" means every scheme is evaluated on the *exact same* set of held-out test scenarios (30 independently generated "traces," random user populations and channel realizations, never seen during training or calibration), which removes a lot of noise you'd otherwise have to average away — you're directly comparing scheme A's score to scheme B's score *on the same conditions*, trace by trace, rather than comparing two separately-averaged numbers. The specific test used, the **Wilcoxon signed-rank test**, is a nonparametric alternative to a paired t-test — it doesn't assume the underlying differences are normally distributed, which is the safer assumption here since throughput distributions are bounded and often skewed. A result of $p<0.05$ means: if there were truly no difference between the two schemes, an effect this large (or larger) would show up by chance less than 5% of the time — the conventional (if somewhat arbitrary) threshold for calling a result "statistically significant."

### 7.2 Why Run Nine Separate Experiments, Not Just One

The full campaign runs this comparison at nine different operating points: a calm, homogeneous baseline (to catch basic implementation bugs before trusting harder results); two levels of user heterogeneity in isolation; three levels of interference-burst intensity; the Tier-A information-equal ablation; a version where OLLA is given a long "head start" to reach its steady state before scoring begins (a deliberately unfavorable-to-RL control); and an independent replication of the main result using entirely different random seeds.

The logic for this breadth: any single experiment could show a misleading result purely from sampling variance — an unlucky (or lucky) draw of random channels and training randomness. Running the *same underlying hypothesis* across many different conditions, and looking for a *consistent pattern* across all of them, is far more trustworthy than any single number. If the RL agent were going to find a real advantage anywhere, this design gives it many independent chances to show it.

---

## Part 8: What Happened — the Headline Result

The full nine-point campaign was run, training every method (a plain reactive baseline, OLLA, the global constant, the per-class constant, two tabular RL algorithms, and the deep neural-network RL agent) from scratch multiple times (different random seeds) and evaluating every one of them, cold, on the same held-out test traces.

**Result: zero of nine experiments passed the pre-registered win condition.** The neural network never beat the per-class constant at statistical significance on the primary scheduler; in three of the nine it lost significantly. It did, however, consistently beat plain OLLA — by anywhere from a few percent to over ten percent, often at high statistical significance.

At first glance this looks like the same v6 lesson repeating: the "beats OLLA" claim survives, but the "beats the honest, hard-to-beat comparator" claim does not, even after specifically redesigning the environment to remove the four simplifications hypothesized to be responsible for this pattern in v6.

**But this raised an important methodological fork:** a null result of this kind has (at least) two very different possible explanations, and they call for completely different responses:

- **(a)** There really is no exploitable adaptivity value in this class of problem — the constant genuinely is close to optimal, and the honest scientific conclusion is a well-supported negative result.
- **(b)** Something in the experimental *pipeline itself* — a bug, a mismatch, an unfair comparison buried in the code — is preventing the RL agent from reaching its actual achievable performance, and the null result is an artifact of that flaw rather than a fact about the underlying problem.

These look identical from the outside (both produce "0 out of 9"), but only one of them is a trustworthy scientific finding. The only responsible way to distinguish them is to go looking, systematically, for evidence of (b) — not to simply accept the null and write it up, and not to keep re-running the same flawed pipeline hoping for a different answer.

---

## Part 9: The Detective Work

This section is, in essence, a debugging narrative — but a principled one, where each step is motivated by a specific, falsifiable question rather than random tinkering. It follows the same discipline established across the v1–v5 history in Part 4.

### 9.1 Are the Two Methods Actually Being Compared Fairly?

The very first thing to check in any "method A loses to method B" result is whether A and B were actually given comparable resources and conditions. Inspecting the code that calibrates the per-class constant revealed it was tuned using *only* the primary scheduler (PF) — exactly the condition the pre-registered test measures. Inspecting the RL training code, however, revealed the neural network split its training time across *three* different schedulers (50% on PF, 25% each on two others). **The comparator was specialized for exactly the test condition; the learner was not.** This is not a subtle statistical artifact — it's closer to grading two students on the same exam after only one of them was told which exam it would be.

### 9.2 Can the Learner Even Represent the Comparator's Answer?

The calibration search for the best constant offset was conducted over a limited numerical range. Inspecting the result showed the *chosen* best offset sat right at the *edge* of the range that had been searched — a classic warning sign in any optimization procedure that the true optimum lies outside the range you searched (if you only look between 0 and 10 and the best value you find is 10, the true best is probably above 10). Worse, once the range was properly widened, one user category's true optimal offset fell entirely outside the *action set* the neural network was even allowed to choose from. **The comparator's true best answer was, quite literally, an option the learner was never given.**

### 9.3 Is the Network Simply Undertrained?

Comparing the network's performance after training against a policy it is, by construction, perfectly capable of representing (recall: action $0$ makes it act like OLLA, and it could in principle learn to output any single constant action every time, since that's just a special, simple case of what a neural network can express) — the trained network settled *below* what a constant achieves. A model failing to match a policy well within its own expressive power is a sign of an optimization problem (bad initialization, insufficient training, poor exploration), not evidence about the underlying task's difficulty.

### 9.4 A Subtler Bug, Found Only by Reading Training Logs

An attempted fix for issue 9.3 was to **warm-start** the network: before letting it learn freely via trial and error, first train it to directly imitate the calibrated constant's decisions (a standard machine-learning technique called **behavior cloning** — essentially, supervised learning on "what would the expert do here," used as an initialization before switching to reinforcement learning proper).

This is a reasonable idea, but the *result got worse*, not better. This is itself informative: a fix that makes things worse usually means a new bug was introduced, not that the underlying idea was wrong — so the next step was to read the raw, per-episode training logs, not just the final summary numbers.

The logs revealed the mechanism precisely. **Entropy**, in the RL sense, measures how random/spread-out a policy's action choices are — a policy that always picks the same action deterministically has zero entropy; a policy choosing uniformly at random among all actions has maximum entropy. The behavior-cloning phase successfully drove the policy's entropy down to essentially zero (a confident, deterministic clone of the constant, exactly as intended). But the moment reinforcement-learning fine-tuning began, its entropy *immediately climbed back up toward maximum* over the following episodes.

The cause: RL training typically includes a small bonus reward for maintaining exploratory (higher-entropy) behavior, to prevent the policy from prematurely locking onto a bad decision before it's explored enough — a standard, generally sensible technique. But this exploration bonus had been scheduled to start at its *maximum* strength at the *beginning* of the fine-tuning phase, with no awareness that the policy arriving at that phase was already a carefully-shaped, informative clone rather than a freshly-initialized random network. The fine-tuning process was, in effect, actively *un-teaching* the useful thing the behavior-cloning phase had just taught it.

This is a genuinely subtle failure mode, and the only way to catch it was to look past the aggregate result and inspect the actual training dynamics — a useful general lesson: when a machine learning experiment produces a surprising negative result, the raw learning curves (not just the final score) are often where the real explanation is hiding.

---

## Part 10: Fixing It, One Iteration at a Time

### 10.1 First Attempt: Address the Obvious Issues

The first round of fixes addressed 9.1 (train on the same single scheduler the comparator was calibrated on) and 9.2 (widen both the calibration search range and the network's action set) and 9.3 (add the behavior-cloning warm start). Result: still a loss, and by a *larger* margin than before any fixes were applied — which is precisely the signal, discussed in 9.4, that motivated digging into the raw logs.

### 10.2 Second Attempt: Fix the Entropy Bug

With the entropy-restart mechanism (9.4) identified and specifically corrected — softening the entropy pressure during the cloning phase itself (so the clone stays informative but not perfectly rigid, which also helps gradients flow properly during the subsequent fine-tuning), and having the post-cloning exploration schedule pick up from a low starting value rather than resetting to maximum — the result changed qualitatively: **the network reached statistical parity with the constant.** Not a win, but no longer a loss either — the difference was small and not statistically distinguishable from zero. Physically, the two policies converged to nearly identical operating points (their realized error rates matched to within a fraction of a percent), confirming this wasn't a coincidence of averaging but a genuine convergence to the same solution.

Even more informative than the parity itself: the substantial further training applied *after* the clone was already in place produced **no additional improvement whatsoever.** Given every remaining opportunity — a full training budget, richer state information, real gradient-based learning — the network found nothing to add on top of imitating the constant. This is stronger evidence than the parity number alone: it says the ceiling has genuinely been reached, not just matched by luck.

### 10.3 Closing a Remaining Objection

There is an obvious, legitimate objection to stop here: the network that reached parity was initialized by directly copying the calibrated constant's answers. Of course it matches — it was shown the answer key. This objection has to be taken seriously, because it undermines any claim that reinforcement learning can reach this performance level *without* needing the same calibration data the constant required.

The fix is a clean control: retrain the network with the exact same corrected setup, but *without* the behavior-cloning step at all — purely from scratch, learning only from its own trial-and-error interaction with the environment, never shown the constant's calibrated answer. This version reached near-parity as well (a small, not-statistically-significant gap remained), while still beating OLLA by a solid, significant margin. This is the version that actually supports a claim like "learned adaptation reaches this performance level without needing the oracle's calibration pass" — the version initialized from the clone demonstrates the *achievable ceiling*; this from-scratch version demonstrates that ceiling is *approximately reachable honestly*.

---

## Part 11: An Adversarial Sanity Check, and the Final Decisive Experiment

### 11.1 Why Seek Out Disagreement, Deliberately

By this point in the process, several independently-derived pieces of evidence all pointed the same direction: the constant matches the network, and no matter what refinements are applied, the network never exceeds it. There is a well-known risk at exactly this stage of a research project — **confirmation bias**: once you've built a coherent story that explains your data, it becomes easy to stop looking hard for alternative explanations of that *same* data, because everything you check seems to confirm what you already believe.

The response used here was to deliberately seek out structured, adversarial scrutiny — explicitly tasking a set of independent reviewers with trying to find flaws in the reasoning, rather than asking "does this look right?" This surfaced an objection that had not been considered internally.

### 11.2 The Objection

The RL agent's operating point involves letting the error rate run quite high (roughly 40–45% of first attempts fail, before HARQ retransmission rescues most of them) — a much higher error rate than OLLA's classical target of 10%. The reviewers' concern: is the entire measured advantage over OLLA simply because OLLA's target was never re-tuned for the new physics (specifically, the HARQ retransmission gain added in Part 6.1, which makes tolerating a higher first-attempt error rate cheaper than it used to be)? If you just moved OLLA's own target error rate up to match, would OLLA close the gap on its own, with no learning involved at all?

This is a serious objection: if true, the "RL beats OLLA" finding would really be a "somebody forgot to re-tune the classical baseline for the new HARQ physics" finding — a much less interesting result, and not really about learning at all.

### 11.3 Why This Was Cheap to Test, and What the Test Showed

Crucially, this objection could be tested *without retraining anything*. OLLA's target error rate is just a fixed parameter of the algorithm, not something learned — it can simply be re-run, at several different target values, on the exact same held-out test scenarios already used throughout the campaign, and compared to the (already-trained, unchanged) neural network's fixed operating point. This is a matter of minutes of computation, not hours of retraining, which made it an unusually high-value experiment to run: it could potentially overturn a central finding of the whole project, at almost no cost.

Two further controls were run alongside it, targeting two more possible artifacts: a policy that picks actions completely at random (to rule out "the network learned nothing distinguishable from noise"), and a *different* single constant chosen to match the mean of the network's action range (to test whether the network's advantage is really just "always run one step hotter," rather than anything more sophisticated than that).

**The results:** re-tuning OLLA's target error rate across a wide range did **not** close the gap — the best OLLA could do, across every target tested, remained substantially below the neural network's throughput, at high statistical significance. The random-action control confirmed the network's behavior is clearly not indistinguishable from noise. The single-constant control, interestingly, showed the network's advantage *is* statistically indistinguishable from what a single well-chosen constant achieves.

Put together, these three results are mutually consistent, not contradictory: the network's advantage over OLLA is real and survives an adversarial attempt to explain it away as a mis-tuned baseline — but that advantage is well-explained by a single scalar operating-point shift, exactly the "setpoint effect, not learned situational adaptivity" conclusion this whole investigation has been converging on since Part 5.

---

## Part 12: The Big Picture

### 12.1 What Was Actually Learned, Scientifically

Setting aside every individual number, the shape of the final finding is this: across a redesigned environment specifically engineered to create the *conditions* under which state-conditional adaptivity should matter — costly errors, heterogeneous users, abrupt regime changes, realistic physics, and a fair information comparison — a learned neural-network policy consistently reaches, but does not exceed, the performance of the best possible *unchanging* rule, once that rule is allowed to depend on which broad category of user it's talking to. It does, however, reliably and robustly outperform the classical reactive control algorithm actually deployed in real networks today — and that gain survives every attempt made to explain it away as a measurement artifact.

### 12.2 Why This Is Still a Genuine, Useful Result

It would be easy to read "the fancy method didn't beat the simple baseline" as a failure. It is worth being explicit about why that reading is wrong here.

First, **a rigorously-obtained negative result closes off a specific, previously-open scientific question** — "does state-conditional adaptivity have measurable value in link adaptation under these realistic conditions?" — with real evidence, rather than leaving it as an untested assumption. Given how much of the surrounding literature makes "RL beats OLLA" claims without running the kind of constant-offset control described in Part 5, this result is also a warning: those claims may often be reporting the same setpoint effect found here, under a more impressive-sounding name.

Second, **the process by which this was established is itself a template.** Six major versions of debugging (Part 4) before the pipeline was trustworthy; pre-registering the success criterion before running the experiment (Part 7); diagnosing a surprising result by reading code and logs rather than re-running and hoping (Part 9); running a from-scratch control to close a circularity objection (Part 10.3); deliberately seeking adversarial review rather than stopping at internal agreement (Part 11.1); and finding the cheapest possible experiment that could overturn the conclusion, then actually running it (Part 11.3) — each of these is a defensible, transferable practice for any research claiming a learned method beats a classical one.

Third, there is a genuine positive, practical claim left standing: a learned policy reaches the performance of an oracle-calibrated rule *without needing that oracle's calibration data*, which has real deployment value (no manual tuning pass required per deployment) even though it does not represent a throughput improvement over careful manual tuning.

### 12.3 What Remains Open

A few things this investigation did not settle, and shouldn't be overclaimed as settled: whether a different, more extreme kind of non-stationarity (bursts shorter than the feedback delay, so the reactive loop genuinely cannot keep up) would change the finding; whether some other, untested state feature might carry the missing signal; and whether the near-parity of the from-scratch result (Part 10.3) is truly zero gap or a small one that a larger experiment could resolve with more statistical power. These are the natural next questions, not loose ends to paper over.

---

## Part 13: Glossary

- **BLER (Block Error Rate):** the probability a transmitted block of data is received with uncorrectable errors, for a given MCS and channel quality.
- **CQI (Channel Quality Indicator):** a quantized report, sent by the receiver, summarizing its estimate of channel quality (SINR).
- **Coherence time:** the time window over which a wireless channel can be treated as approximately constant; shrinks as user speed increases (via Doppler spread).
- **HARQ (Hybrid Automatic Repeat Request):** a retransmission protocol where a failed transmission is retried and combined with the original (chase combining) rather than discarded, improving the odds of eventual success.
- **MCS (Modulation and Coding Scheme):** the specific combination of modulation order and code rate chosen for a transmission, trading data rate against robustness to errors.
- **MDP / POMDP (Partially Observable Markov Decision Process):** the formal mathematical model underlying reinforcement learning: states, actions, rewards, and (in the POMDP case) the fact that the true state is not directly observed.
- **OLLA (Outer Loop Link Adaptation):** the classical, industry-standard reactive control algorithm for link adaptation, structurally an integral controller driven by ACK/NACK feedback.
- **Pre-registration:** committing, before an experiment is run, to exactly what will count as success — to prevent post-hoc cherry-picking of favorable metrics or conditions.
- **SINR (Signal-to-Interference-plus-Noise Ratio):** the ratio of received signal power to the combined power of interference and noise; the primary determinant of achievable error-free data rate.
- **Setpoint effect:** a result where an apparent "learned" advantage is actually fully explained by a fixed operating-point shift, rather than by any decision-making that varies with context.
- **TTI (Transmission Time Interval):** the discrete time slice (here, 1 millisecond) in which scheduling and transmission decisions are made.
- **Waterfall curve:** the characteristic steep BLER-vs-SINR curve for a given MCS.
- **Wilcoxon signed-rank test:** a nonparametric statistical hypothesis test for paired data, used here because it does not assume the compared quantities are normally distributed.

---

**This guide is a companion to, not a replacement for, the two technical reports:** `v7_technical_process_report.pdf` (the full reasoning and diagnostic chain, in denser technical form) and `v7_comprehensive_evaluation_report.pdf` (the formal results, statistics, and figures).
