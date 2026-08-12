# v7 Technical Process Report: Design, Execution, Diagnosis, and Resolution

**Scope:** Every decision made in the v7 campaign, with the reasoning behind it — not just what was done, but why it was done that way, what alternatives were rejected, and what evidence triggered each pivot.

---

## Part 1: Why v7 Exists

### 1.1 The Problem v6 Left Unsolved

v6 demonstrated that Deep A2C, using OLLA-relative action encoding, beat the classical OLLA outer loop by statistically significant margins at several CQI feedback delays (e.g. +6.7% at delay 6, p<0.001). On its face this looked like a clean win for learned link adaptation.

The audit control that broke this conclusion was **A3**: a fixed-offset baseline. The reasoning behind adding A3 was simple — if RL's gain over OLLA is really about *learning a policy*, then a policy that cannot learn (a constant number) should lose badly. A3 was calibrated (grid-searched on separate traces) and then evaluated identically to every other scheme. It matched Deep A2C's throughput.

**Why this mattered:** it meant the entire measured RL advantage was explainable as *where the operating point sits*, not *what decision rule got you there*. A constant can't condition on state by construction — so if a constant achieves the same throughput as a neural policy with access to the full observation history, the neural policy's extra machinery isn't contributing anything measurable.

### 1.2 Diagnosing *Why* v6 Allowed This

This required asking: what features of the v6 environment make a constant offset sufficient? Four were identified, each removed independently in v7:

1. **No cost for being wrong.** v6 scored transmissions as `(1-BLER) × TBS` — expected goodput, not a Bernoulli outcome. There was no retransmission channel. An aggressive MCS that fails 40% of the time is charged only a 40% throughput discount, never a wasted slot. This makes "always run as hot as possible, average out the losses" close to optimal by construction — there is no scenario where restraint pays off, because failure has no operational cost beyond its direct probability.
2. **No heterogeneity.** Every user had the same CQI delay and the same speed distribution. A single number, once tuned, fits everyone equally, by definition — there is no user for whom the constant is wrong.
3. **Quasi-stationarity.** The channel process had no regime changes within a trace — no interference bursts, no speed transitions. An integrator (OLLA) and a static number both converge to the same steady state when the environment doesn't move.
4. **Strict informational equality.** The RL state vector was designed to carry exactly the same information as the OLLA loop (by design, to make the OLLA-relative comparison "fair"). This closed off the one channel through which RL could plausibly outperform a scalar rule: seeing something the scalar rule structurally cannot.

**The logic that produced v7:** if all four of these conditions are simultaneously responsible for making a constant sufficient, then v7 should remove all four at once and re-test. A weaker design (removing only one or two) would leave open the objection "maybe the remaining simplification is still doing the work." Removing all four and *still* finding a constant sufficient would be a much stronger, more defensible negative result. This is why v7 is not an incremental patch but a five-lever redesign.

---

## Part 2: The Five Design Levers (D1–D5)

Each lever below is presented with the problem it targets, the specific mechanism chosen, and — critically — the reasoning for why that specific mechanism rather than an easier alternative.

### D1: HARQ with Chase Combining

**Problem targeted:** failure has no cost in v6.

**Mechanism:** a failed first transmission is not simply "lost throughput" — it triggers a retransmission of the *same* transport block at the *same* MCS, on the user's next scheduled slot, with a chase-combining SINR gain of +2.5 dB per prior attempt (up to 3 retries before the block is dropped). OLLA still updates only on first-transmission ACK/NACK, matching real 3GPP outer-loop behavior.

**Why chase combining specifically, and not just "retransmission with no gain"?** Because a retransmission scheme with zero combining gain would make aggressive MCS selection strictly worse (every failure costs a full extra slot with no compensating benefit), which risks *overcorrecting* the environment into a regime where conservative constants trivially dominate — the same failure mode as v6, just inverted. Chase combining is the real mechanism used in deployed HARQ systems, and it's what makes an aggressive first-transmission MCS choice a genuine trade-off rather than a strictly dominated or strictly dominant strategy: you gain throughput if it succeeds, you pay a real slot cost if it fails, but a failure isn't fatal because the *next* attempt is easier. This is precisely the kind of trade-off a state-conditional policy should, in principle, be able to exploit — knowing when the channel is stable enough that gambling on a high MCS is safe.

### D2: Per-User Heterogeneity

**Problem targeted:** one constant fits everyone in v6.

**Mechanism:** each user draws an independent CQI feedback delay (uniform 2–8 TTIs) and mobility speed (uniform 3–30 m/s) at trace generation time. These are collapsed into a 2×3 grid (2 delay classes × 3 speed classes) for the purposes of the FixedPU comparator.

**Why a 2×3 grid rather than continuous per-user calibration?** Continuous per-user calibration would require calibration data for every possible (delay, speed) combination — effectively giving the oracle comparator infinite resolution, which would make it un-losable by construction and defeat the purpose of the comparison. A coarse discrete grid is the realistic version of what an operator could actually deploy (you calibrate for a handful of user segments, not per-individual), and it deliberately leaves room for a state-conditional policy to outperform it *if* within-class variation matters. If RL beats a 6-bucket comparator, that's a real finding; if it can't even do that, finer-grained oracle tuning would only make the case against RL stronger, so the coarse grid is the fairer test in RL's favor.

### D3: Non-Stationarity (Interference Bursts + Speed Switches)

**Problem targeted:** quasi-stationarity in v6.

**Mechanism:** a cell-wide two-state Markov chain toggles an interference burst (+6/+9/+12 dB extra interference), with mean dwell times of ~250 TTIs calm and ~120 TTIs during a burst. Each user additionally undergoes one mid-trace speed change.

**Why a Markov chain rather than periodic or scripted bursts?** A Markov process makes burst onset and duration genuinely unpredictable from the policy's perspective except through its own observations — a scripted, periodic burst schedule could in principle be memorized or exploited via the episode/TTI index rather than via the channel state, which would produce a spurious appearance of "adaptivity" that isn't really state-conditional. Markov burst dynamics force any advantage to come from actually reading the channel.

**Why these specific dwell times (250 calm / 120 burst)?** This was chosen to be within the trace length (simTime = 200 TTIs) such that bursts are a meaningful fraction of each trace but traces aren't burst-saturated. In retrospect (see Part 5, root cause 1), this dwell/delay relationship turned out to be a weak point — the CQI feedback delay (2–8 TTIs) is much shorter than the burst dwell time (120–250 TTIs), meaning bursts are *visible* to the feedback loop well within their duration, which limits how much a purely predictive (rather than reactive) advantage RL could extract. This is flagged explicitly as a v8 design consideration.

### D4: Honest Physics (Steep BLER Waterfalls + Jakes Fading)

**Problem targeted:** v6's gentle BLER curves made MCS overshoot cheap regardless of HARQ.

**Mechanism:** per-MCS BLER-vs-SINR curves were steepened (waterfall slope parameter k ∈ [3.0, 5.8], vs. v6's [1.2, 2.7]), and fading was generated per-user via a Jakes-calibrated AR(1) process where the innovation coefficient is derived directly from the user's *instantaneous* speed:

```
ρᵢ(t) = J₀(2π · vᵢ(t)·fc/c · T_tti)
```

**Why derive ρ from speed rather than using a single fixed fading coefficient?** A fixed ρ (as in earlier versions) makes fading statistically identical for a stationary user and a 30 m/s user, which is physically wrong and — more importantly for this experiment — removes exactly the signal (channel coherence time shrinking with speed) that a state-conditional policy would need to observe and act on. Speed-derived Jakes fading ties the fading process to something the environment can, in principle, expose to the agent (via the speed feature in Tier-B state), making it a fair test of whether that information is exploitable.

### D5: Two-Tier State (Information Ablation)

**Problem targeted:** the strict informational equality that closed off any information-based RL advantage in v6.

**Mechanism:** Tier-A is the exact v6 state (reference CQI, ΔCQI, observed SINR, SINR trend, OLLA offset, scheduler one-hot) — no more information than OLLA's own scalar loop. Tier-B adds five features no scalar loop can represent: HARQ pending/retransmission count, a NACK-burst exponential moving average, a 4-TTI SINR slope, the user's instantaneous speed, and a feedback-delayed observed-burst indicator.

**Why keep both tiers rather than just using Tier-B everywhere?** Because the *comparison between* Tier-A and Tier-B is itself the experiment that tests whether richer information matters. If v7 had shipped with only Tier-B, a null result would be ambiguous — is RL failing because state-conditional adaptivity has no value here, or because Tier-B still doesn't carry the *right* information? Running both tiers at the same operating point converts this from a philosophical question into a testable ablation (Section 6 of the evaluation report; the answer, executed, was: no significant difference — see Part 4).

---

## Part 3: Why This Specific Comparator Suite and Pre-Registration

### 3.1 Why Oracle-Tuned Constants Are the Correct Comparator

The most common objection to "RL beats OLLA" claims in the literature is that OLLA is a weak, zero-knowledge baseline — it never sees calibration data and only reacts. If RL is given access to representative training traces (which it is — every learner trains on freshly generated traces from the same distribution as evaluation), the fair comparison isn't against a baseline that had zero access to that distribution; it's against the *best possible non-adaptive policy given the same distributional access*. That is exactly what Fixed and FixedPU are: they consume calibration traces (a separate seed range, never the evaluation traces) to find the best constant, then are evaluated cold with zero further adaptation. If RL can't beat a policy with the same data access and *no* representational capacity for state-conditioning, that's a much stronger statement about RL's marginal value than "RL beats a policy nobody credits with having seen any data."

### 3.2 Why FixedPU (Per-Class), Not Just Fixed (Global)

A global constant is a weak comparator precisely because D2 (heterogeneity) guarantees no single number is optimal for every user. If RL only had to beat the global constant, a win would be trivially explainable as "RL learned to be different for different users" — which a *lookup table keyed on user class* could also do, without any state-conditioning at all. FixedPU closes this loophole: it already captures per-user heterogeneity through calibration, so any remaining RL advantage over FixedPU must come from something FixedPU cannot represent — either within-user state-conditioning or exploiting non-stationarity (D3) faster than a static number can.

### 3.3 Why the Pre-Registered Win Condition Is A2C vs. FixedPU on PF, Specifically

- **PF (proportional-fair), not RR or EQ:** PF is the deployed industry-standard scheduler; a result that only holds under RR or EQ would be of limited practical relevance. Both RR and EQ are still evaluated and reported as secondary evidence, but the primary hypothesis is scoped to the scheduler that matters operationally.
- **Paired Wilcoxon, not a t-test:** cell throughput distributions across traces are not guaranteed to be normal (they're bounded, skewed by burst/calm mixture), and the comparison is naturally *paired* — every scheme sees the identical 30 held-out traces. A paired non-parametric test is the correct tool for paired, possibly non-normal data; using a t-test would risk both a false-precision problem (assuming normality that may not hold) and would waste the pairing structure that reduces variance.
- **p < 0.05 threshold, one pre-declared condition:** pre-registering a single win condition, before running the campaign, is what prevents the analysis from drifting into "we'll declare victory on whichever scheduler/metric happens to look best after the fact." This is why the report treats "0/9" as a real, reportable finding rather than reframing the question until something passes.

---

## Part 4: The Campaign, Point by Point — Why Each Experiment Was Chosen

The 9-point pre-registered sweep was not arbitrary; each point tests a specific hypothesis about *where* adaptivity value should appear if it exists at all.

1. **`phase0_calm`** (hetero=0, no bursts): the credibility anchor. If RL doesn't match OLLA even in the *easiest possible* v7 configuration (closest to v6's conditions, but still with HARQ), something is broken in the implementation, not the hypothesis. This point exists to catch implementation bugs before spending compute on harder points.
2. **`hetero050`, `hetero100`:** isolates D2 in isolation (bursts off). If heterogeneity alone is enough to give RL an edge over a global/per-class constant, that would show up here without the confound of non-stationarity.
3. **`burst06dB`, `burst09dB`, `burst12dB`:** isolates D3 by sweeping burst intensity. The hypothesis under test: as bursts become more disruptive, a reactive-only rule (OLLA, or a static constant) should degrade faster than a policy that can detect burst onset and correct proactively. Three intensities were run (not just one) so the result wouldn't hinge on a single arbitrarily chosen burst strength — if RL wins at 6 dB but not 9 or 12 dB (or vice versa), that's informative about *where* the effect is concentrated; a single point can't distinguish a real but narrow effect from noise.
4. **`headline_tierA`:** the D5 ablation, run at the burst09dB operating point (the point selected as "headline" because it combines all four levers at a moderate, plausible burst intensity). Directly tests whether Tier-B's extra features matter.
5. **`headline_warm1000`:** OLLA is deliberately given 1000 TTIs of warm-up before scoring begins, letting its offset converge to steady state before the comparison starts. This is a *defense* of OLLA — it tests whether RL's advantage (if any) is really about correcting OLLA's cold-start transient, which would evaporate once OLLA is allowed to converge. This point is designed to be adversarial to the RL hypothesis, on purpose: a result that survives this stacked deck is more credible than one that doesn't.
6. **`headline_fresh`:** an independent replication of the headline point with a completely different base seed and trace seed range. This exists because a single training run's result could be a seed-specific artifact rather than a repeatable phenomenon — running the *identical* configuration again under fresh randomness is the only way to distinguish a real effect from noise in the training process itself.

**Reasoning for running all nine before drawing conclusions, rather than stopping at the first result:** any individual point could show a spurious win or loss due to sampling variance. The 9-point design lets the *pattern across points* — not any single number — drive the conclusion. When all nine independently returned the same verdict (comparator parity or loss, never a significant win), that consistency is what made the "0/9" finding trustworthy rather than an artifact of one unlucky configuration.

---

## Part 5: Diagnosing the 0/9 Result — The Investigative Process

A 0/9 result has two possible explanations that look identical from the outside: (a) there is genuinely no exploitable adaptivity value in this environment class, or (b) something in the experimental pipeline is preventing RL from reaching its actual ceiling. These require different responses — (a) is a publishable negative result as-is; (b) means the negative result is contaminated by a bug and cannot be trusted until fixed. The only way to distinguish them is to audit the actual code and logs, not to re-run the same pipeline hoping for a different answer.

### 5.1 Root Cause 1: Calibration/Training Distribution Asymmetry

**How it was found:** direct inspection of `calibrateFixedClass_v7.m` line 23 shows `envE.scheduler = 'pf'` hard-coded — FixedPU is calibrated exclusively against the PF scheduler. Cross-referencing against `defaultEnv_v7.m`, Deep A2C's training loop samples schedulers via `train_sched_weights = [0.50, 0.25, 0.25]` — a 50/25/25 mix across PF/RR/EQ. **The reasoning:** the pre-registered test scores A2C on PF only, but A2C spent half its training budget on schedulers the test doesn't measure. This isn't a subtle statistical effect — it's a straightforward apples-to-oranges comparison: the comparator was optimized for exactly the condition being tested; the learner was not. This alone would depress A2C's PF-specific performance without saying anything about whether state-conditioning has value.

### 5.2 Root Cause 2: Action-Set / Calibration-Grid Clipping

**How it was found:** the calibration grid `fixed_cands = -2:1` was inspected against its own selected optimum. The selected global offset was `-2` — the *edge* of the search grid. An optimum sitting at the boundary of a search range is a classic sign that the true optimum lies outside the tested range. Widening the class-level breakdown confirmed one user class's true optimum was `-4`, entirely outside Deep A2C's action set of `±3`. **The reasoning:** if the comparator's true optimal action isn't even *representable* by the learner's action space, no amount of training can let the learner match it — this is a specification bug, not evidence about learning capability, and needed to be fixed before the comparison could be considered meaningful.

### 5.3 Root Cause 3: Undertraining on Cold Start

**How it was found:** by comparing vanilla A2C's converged throughput (from the `phase0_calm` learning curve) against a policy it can trivially represent (the constant), and observing A2C settled roughly 5% *below* that constant's throughput despite the network architecture being expressive enough to represent a constant exactly. **The reasoning:** a network that cannot even reproduce a policy within its own representational capacity is underfit — either exploring too much, or not converging within the 500-episode budget. This motivated introducing a warm-start mechanism (behavior cloning) explicitly designed to guarantee the learner starts from at least the achievable floor, so that any subsequent fine-tuning gain (or lack thereof) is unambiguous.

### 5.4 Root Cause 4: Entropy Restart After Behavior Cloning (the `tier1` bug)

This was the most subtle bug and required reading raw training logs, not just aggregate results.

**The fix attempt that exposed it:** `tier1` introduced 150 episodes of behavior cloning — training the actor via cross-entropy against FixedPU's per-class target actions — intended to solve Root Cause 3 by starting RL fine-tuning from a policy that already matches the oracle, so any *further* gain would be attributable to genuine learning rather than lucky convergence.

**What the log showed:** during the BC phase, the printed policy entropy dropped to `H=0.000` — the clone had fully saturated (a deterministic, oracle-matching policy). But once RL fine-tuning began, the *first* fine-tuning episodes showed entropy climbing back to `H≈1.9` (near-uniform over 7 actions) within roughly 100 episodes.

**The reasoning that identified the cause:** the entropy bonus coefficient schedule was written as a *continuous anneal from `ent_start=0.05` to `ent_end=0.001`*, indexed by fine-tuning episode number — with no awareness that a prior BC phase had already produced a low-entropy, informative policy. The RL phase started this schedule at its *maximum* value (0.05), which is a strong pressure toward entropy maximization — precisely counteracting the deterministic clone it had just been given. In effect, the code was un-teaching the useful thing it had just taught.

**Why this counts as a bug rather than "RL exploring, as designed":** exploration entropy bonuses exist to prevent premature convergence to a bad local policy — they are not supposed to actively destroy a policy that is already at (or above) the achievable floor. The purpose of BC warm-starting was defeated by a schedule that didn't know BC had happened.

**The fix, and the reasoning behind each part of it:**
- BC-phase entropy coefficient lowered from an implicit maximum to `0.03` — kept deliberately non-zero (not `0.0`) so the clone remains *soft* rather than fully saturated logits; a fully saturated clone produces near-zero gradients during subsequent fine-tuning (vanishing-gradient risk), so a small amount of softness was preserved on purpose to keep the network trainable.
- Post-BC fine-tuning anneal changed to start at `0.01` (not `0.05`) — low enough that fine-tuning doesn't re-randomize the clone, but nonzero so genuine exploration around the clone is still possible if a better policy exists nearby.
- Action set widened to `-5:3` — directly addressing Root Cause 2 (the true class optimum of `-4` is now representable).

### 5.5 Root Cause 5 (Ruled Out, Not Found): Missing State Information

The Tier-A vs. Tier-B ablation was run specifically to check whether the residual gap might be explained by Root Causes 1–4 *plus* a genuine information deficit. **The reasoning for treating this as a distinct, testable hypothesis rather than assuming it away:** even after fixing 1–4, it remained possible that Tier-B's extra features (HARQ state, NACK history, slope, speed, burst indicator) simply aren't sufficient — that some *other* piece of information, not yet implemented, is what's missing. The ablation's result (no significant difference between Tier-A and Tier-B) doesn't prove no information could help; it proves that the five specific features hypothesized to help, don't. This is reported as a bounded, honest claim rather than an overclaim.

---

## Part 6: The Fix Iterations — Reasoning at Each Step

### 6.1 `tier1`: First Attempt

**Changes:** PF-only training weights (fixes Root Cause 1), 150-episode BC warm start (targets Root Cause 3), calibration grid widened to `-4:2` (partially addresses Root Cause 2).

**Result:** still a loss (-5.0%, p=0.017) — *worse* on the point estimate than the unfixed vanilla run (-0.7%).

**Why this counted as informative rather than just "the fix didn't work":** a worse result after applying fixes is itself a diagnostic signal — it meant a *new* problem had been introduced, not that the underlying hypothesis was wrong. This is what motivated reading the raw training log rather than accepting the headline number, which is how Root Cause 4 (the entropy-restart bug) was found.

### 6.2 `tier1b`: The Corrected Attempt

**Changes on top of `tier1`:** action set widened further to `-5:3` (fully resolves Root Cause 2), BC entropy softened to 0.03, post-BC fine-tuning anneal starts at 0.01 (resolves Root Cause 4).

**Result:** statistical parity with FixedPU (-0.4%, p=0.813), first-transmission BLER matching almost exactly (0.439 vs 0.443 — direct physical confirmation the policy converged to the *same operating point*, not just the same aggregate throughput by coincidence), and a robust win over OLLA (+12.8%, p=0.0003).

**The critical secondary finding, and why it matters more than the headline number:** the 500 episodes of RL fine-tuning applied on top of the BC clone produced *zero* additional throughput over the clone itself. This is a stronger statement than "RL matched the oracle" — it says that *given every opportunity to improve on the oracle* (full training budget, richer state, real gradient-based optimization), the learner found nothing to add. That is direct evidence for the "no exploitable state-conditional structure beyond the setpoint" conclusion, independent of the campaign-wide comparator asymmetry issues.

### 6.3 `tier1-nobc`: Closing the Circularity Objection

**Why this run was necessary, and why it wasn't run first:** `tier1b`'s headline number, while methodologically the "fixed" result, has an inherent limitation as evidence for any claim of the form "RL doesn't need calibration data" — it was *initialized* by imitating the calibrated FixedPU comparator. A skeptical reader would correctly object: of course it matches FixedPU, it was shown FixedPU's answers directly. This objection is airtight and needed to be pre-empted, not argued around.

**The design of the control:** identical to `tier1b` (PF-only training, widened action set) but with `bc_warm_eps=0` — no behavior cloning at all. This isolates exactly one variable: does the *from-scratch* learner, with the calibration-asymmetry and action-clipping bugs fixed but with zero access to the oracle's answers, still reach comparable performance?

**Result:** -5.1% vs. FixedPU (p=0.060, not significant), +7.5% vs. OLLA (p=0.005, significant). **Why this is the methodologically load-bearing result for any "no per-deployment tuning" claim:** it demonstrates near-parity was reached without the learner ever seeing the oracle's calibrated answers — only from interacting with the environment and its own reward signal. `tier1b` demonstrates the achievable *ceiling* (with a clean initialization, confirming no further gain exists to be found); `tier1-nobc` demonstrates that the ceiling is *approximately reachable without the crutch*.

### 6.4 Final Performance Summary — All Schemes, Final (`tier1b`) Model

The table below is the single reference point for "what does the final, fully-fixed model actually do," pulling every metric the harness collects (not just cell throughput) for all seven schemes at the headline point, PF scheduler, under the `tier1b` configuration:

| Scheme | Cell Tp (Mbps) | Δ vs. Baseline | Edge Tp | BLER₁ | Jain | vs. Deep A2C (Wilcoxon) |
|---|---|---|---|---|---|---|
| Baseline (no OLLA) | 3.10 ± 0.25 | (ref) | 0.09 | 0.692 | 0.825 | +19.9%, p=1.1e-4 *** |
| OLLA (reactive) | 3.29 ± 0.27 | +6.3% | 0.13 | 0.640 | 0.845 | +12.8%, p=2.8e-4 *** |
| Fixed (best global constant) | 3.77 ± 0.35 | +21.8% | 0.17 | 0.444 | 0.884 | −1.6%, p=0.262 (n.s.) |
| **FixedPU** (oracle, per-class — pre-registered comparator) | 3.73 ± 0.34 | +20.4% | 0.17 | 0.443 | 0.881 | **−0.4%, p=0.813 (n.s.)** |
| QL v7 (tabular) | 3.12 ± 0.25 | +0.9% | 0.10 | 0.690 | 0.833 | +19.4%, p=2.9e-6 *** |
| Tab AC v7 (tabular) | 3.11 ± 0.21 | +0.4% | 0.10 | 0.677 | 0.826 | +19.4%, p=2.9e-6 *** |
| **Deep A2C v7 (`tier1b`, final)** | **3.71 ± 0.32** | **+19.9%** | **0.17** | **0.439** | **0.879** | — |

**Reading this table as the project's bottom line:** the final model is statistically indistinguishable from the oracle-calibrated, per-user-class comparator ($p=0.813$) — the pre-registered win is not achieved, but neither is a loss — while it beats every reactive or tabular scheme by a wide, highly significant margin, and its edge-user throughput, first-transmission BLER, and Jain fairness index all closely track FixedPU's. This is the constant-policy / setpoint-effect finding restated as a single operational table: the learned policy lands on essentially the same point of the throughput/reliability trade-off curve as the best possible fixed rule.

The same final model, evaluated in the OLLA target-BLER sweep (Part 7 below, no retraining involved), beats the best-retuned OLLA across every tested target ($+12.9\%$ against OLLA's own best achievable operating point, $p=6.6\times10^{-4}$) and a uniform-random action control ($+24.1\%$, $p=2.4\times10^{-6}$) — ruling out both "OLLA was simply mis-tuned" and "the policy is indistinguishable from noise" as explanations for its margin over OLLA.

---

## Part 7: The External Review and the OLLA Target-BLER Sweep

### 7.1 Why an Adversarial Review Was Sought

By the time `tier1b` and `tier1-nobc` were complete, three internally-generated explanations (comparator parity, zero-gain-from-fine-tuning, information ablation) all pointed the same direction. The risk at this stage is confirmation bias — having built the diagnostic story, it becomes easy to stop looking for alternative explanations of the *same* data. An external, structured adversarial review (five independent reasoning perspectives, cross-reviewed against each other) was run specifically to surface objections that hadn't been considered internally, rather than to validate what had already been concluded.

### 7.2 The Objection That Survived Review

Multiple independent reviewers converged on the same concern: Deep A2C's converged first-transmission BLER sits near 44%, while OLLA is *by design* pinned to a 10% target BLER (`env.olla_target = 0.1`, hard-coded). The reasoning: comparing a policy operating at 44% BLER against a policy locked to 10% BLER isn't necessarily comparing algorithms — it may be comparing *operating points*, one of which (OLLA's) was never re-tuned for this environment's HARQ chase-combining physics. The 10% target predates HARQ and was calibrated for a world where retransmission gain didn't exist; under chase combining, a much higher first-transmission error rate can be throughput-optimal because failures are cheap to recover from. If simply re-tuning OLLA's target BLER closes most of the A2C-vs-OLLA gap, then that gap isn't measuring anything about learning at all.

### 7.3 Why This Objection Could Be Tested Cheaply

Unlike every other experiment in this campaign, this test requires **no retraining**. `OLLA` is a comparator, not a learner — its behavior is entirely determined by the `olla_target` parameter, and it can be re-evaluated on the exact same 30 held-out traces already used throughout the campaign in minutes. This made it the highest-value, lowest-cost experiment available: capable of overturning the entire OLLA-related conclusion, at a fraction of the cost of any training run.

### 7.4 Design of the Sweep and Its Controls

`sweep_olla_target_v7.m` re-evaluates OLLA at five target BLER values (10%, 20%, 30%, 40%, 50%) on the identical held-out traces, alongside two additional controls:

- **A uniform-random-action policy**, to test a separate objection raised in the same review: given the near-uniform entropy observed during much of A2C's training (Part 5.4), is it possible the "learned" policy is statistically indistinguishable from random action selection? If so, the entire result would be an artifact of *where the action set happens to be centered*, not of any learned behavior.
- **A constant-offset-(-1) policy**, to directly test whether A2C's throughput is explainable purely by the *mean* of its action distribution rather than any state-conditional structure — since the widened action set `-5:3` has a mean of -1, this tests whether A2C is simply "running one step hotter, always" rather than doing anything more sophisticated.

### 7.5 Results and Their Interpretation

| Comparison | Margin | p-value | Conclusion |
|---|---|---|---|
| A2C vs. best OLLA (any target, 10–50%) | +12.9% | 0.0007 | The gain does **not** close — best OLLA (still at its default 10% target) remains 12.9% below A2C |
| A2C vs. random action | +24.1% | 2.4×10⁻⁶ | A2C is clearly **not** a coin flip |
| A2C vs. constant −1 | +3.7% | 0.136 (n.s.) | A2C is statistically indistinguishable from a single well-chosen constant |

**The reasoning for why these three results together are conclusive, not contradictory:** the OLLA-target result rules out "mis-tuned baseline" as an explanation for the RL-vs-OLLA gain — that gain is real and survives an adversarial re-tuning attempt. The random-action result rules out "the policy learned nothing at all." The constant-(-1) result is *consistent with, not contradictory to*, the report's central finding: it says A2C's value over OLLA is well-approximated by a single constant, which is exactly the "setpoint effect, not state-conditional adaptivity" conclusion already reached through the comparator-parity and zero-fine-tuning-gain evidence. Three independent methods (throughput/BLER matching, ablation, and this external-validation sweep) converge on the same answer, which is why the conclusion is reported with confidence rather than as a single unreplicated finding.

---

## Part 8: The Diagnostic Figures — Reasoning for Each

Beyond the primary campaign results, several additional analyses were run specifically to convert *inferred* conclusions into *directly observable* evidence:

- **Trace-level win/loss scatter:** the aggregate margin (a single averaged number) can't reveal whether A2C wins consistently on a subset of "hard" traces and loses elsewhere, versus losing uniformly. Plotting every trace individually against the y=x diagonal makes this visible at a glance — and the result (wins and losses scattered symmetrically, no clustering) rules out the possibility that RL has a real advantage confined to some unmodeled trace subpopulation.
- **Scheduler sensitivity (PF/RR/EQ):** since the pre-registered test is PF-only, and Root Cause 1 established that PF-only training was itself a fix, it became necessary to show *why* RR and EQ look different — not to hide the EQ loss, but to correctly attribute it (neither FixedPU nor A2C was tuned for EQ, so a loss there says nothing about the PF conclusion).
- **Action-distribution histogram:** every other piece of evidence for "the policy is a constant" is *indirect* — inferred from throughput and BLER numbers being similar. This experiment tests the claim *directly*: does the network's chosen action, decision-by-decision, actually concentrate near a fixed point, or does it look state-dependent and merely average out to a similar number? This required a new evaluation pass because per-decision actions weren't stored in the original campaign `.mat` files — only aggregated statistics were. The reasoning for building this despite the extra engineering cost: indirect evidence (matching aggregate statistics) is always open to the objection "maybe it's a coincidence of averaging"; direct evidence (the actual distribution of chosen actions) closes that gap.
- **Tabular vs. deep training curves:** included to make the learner-capacity hierarchy (QL ≈ Tab AC << Deep A2C ≈ FixedPU) visually traceable to the training process itself, rather than asserted only from final-epoch numbers — showing that the tabular methods plateau early and stay plateaued, consistent with the discretization/underfitting explanation in Part 5.3's logic extended to the tabular case (a 35,000-entry table with ~1,500 total training samples across 5 seeds cannot be expected to converge).

---

## Part 9: Synthesis — What the Full Chain of Reasoning Establishes

Putting every step together, the case for the final conclusion rests on convergent evidence from methodologically independent angles, which is deliberately how it was built:

1. **Nine independently-run campaign points**, spanning calm/heterogeneous/bursty conditions at three burst intensities, an information ablation, an OLLA-favorable defense, and a seed replication — all returning the same verdict (no significant win over FixedPU).
2. **Root-cause code audit**, not speculation, identifying four concrete, fixable issues (calibration asymmetry, action clipping, undertraining, entropy-restart bug) — each verified by direct inspection of source code and training logs, not inferred from aggregate statistics alone.
3. **A corrected run (`tier1b`) reaching statistical parity**, with physical confirmation via matching BLER operating points, and a zero-gain-from-fine-tuning result that is stronger evidence than parity alone.
4. **A from-scratch control (`tier1-nobc`)** closing the specific circularity objection that the parity result depended on seeing the oracle's answers.
5. **An externally-sourced adversarial review** that surfaced an objection not considered internally, and a cheap, decisive experiment (the OLLA target-BLER sweep) that resolved it — with the answer *not* supporting the "mis-tuned baseline" alternative explanation, strengthening rather than weakening the OLLA-related finding.
6. **Direct behavioral evidence** (the action-distribution histogram) converting an inference about aggregate statistics into an observation about the actual decision-making process.

**Why this matters methodologically, independent of the specific throughput numbers:** the process itself — pre-registration, root-cause diagnosis via code/log inspection rather than re-running and hoping, adversarial external review, and direct behavioral verification rather than resting on aggregate statistics — is a template for how "RL beats baseline X" claims in wireless research should be interrogated before publication. Each step exists because the previous step's result was, on its own, insufficient to rule out a specific plausible alternative explanation.

---

## Part 10: Honest Limitations and What Remains Open

- The burst dwell time (120–250 TTIs) is long relative to CQI feedback delay (2–8 TTIs), meaning bursts are visible to the reactive OLLA loop well within their duration — this may understate any advantage a *predictive* policy could have in a regime where bursts are shorter than the feedback delay. This is explicitly flagged as a v8 design direction, not glossed over.
- The Tier-A/Tier-B ablation rules out the five specific additional features tested; it does not prove no other feature could help.
- `tier1-nobc`'s near-parity result is not statistically significant in either direction (p=0.06) — it is consistent with both "true parity" and "a small residual gap," and should be reported with that honest uncertainty rather than as a clean win.
- All findings are specific to this simulator's parameterization (chase-combining gain, BLER waterfall steepness, burst intensity range); generalizing to other HARQ configurations or channel models would require re-running the equivalent campaign, not assuming the conclusion transfers.

---

## Part 11: Legacy Modules Reused in the v7 Pipeline

v7 is not a ground-up rewrite. Every file with a `_v7` suffix is new or substantially rewritten for this campaign, but the pipeline deliberately imports a set of unversioned or `_v5`-suffixed helper functions from `../v5` and `../case2_3` rather than reimplementing them. This was a conscious engineering decision, not an oversight, and the reasoning matters for reproducibility: it defines exactly which parts of the pipeline are new (and therefore need auditing for v7-specific bugs) and which parts are inherited, already-audited components that carried their correctness forward from earlier versions.

Every `run_v7_point.m` invocation begins with:
```matlab
addpath(fullfile(here, '..', 'v5'));
addpath(fullfile(here, '..', 'case2_3'));
```
making these legacy functions available to every v7 script without duplicating their code.

### 11.1 `sampleSched_v5.m` — Training Scheduler Sampler

**What it does:** draws which scheduler (`pf`, `rr`, or `eq`) a training episode uses, weighted by `env.train_sched_weights`.

**Why reused rather than rewritten:** the logic — weighted categorical sampling with a uniform fallback when weights are missing or mismatched — has no v7-specific content. It's a generic sampling utility. Rewriting it under a `_v7` name would have added a second copy of logic that is already correct and already exercised by v5's own campaign, with no functional difference. **This is also the exact function whose weight vector became Root Cause 1** (Part 5.1) — the bug was not in `sampleSched_v5` itself (it correctly samples according to whatever weights it's given), but in the *caller* supplying it the wrong distribution (`[0.5, 0.25, 0.25]` instead of `[1, 0, 0]`) relative to what the comparator was calibrated against. This distinction matters: the legacy module was not the source of the bug, but understanding what it does was necessary to locate where the actual bug lived.

### 11.2 `schedContext_v5.m` — Scheduler One-Hot Context

**What it does:** converts the active scheduler string into a one-hot context vector, appended to every user's state vector (`nSched` extra state dimensions, present in both Tier-A and Tier-B).

**Why reused:** this feature exists so a single shared network can condition its policy on which scheduler is currently active, letting one Deep A2C model generalize across PF/RR/EQ rather than requiring three separately trained networks. The one-hot encoding logic itself is scheduler-agnostic infrastructure carried over unchanged from v5, where it was originally introduced and validated.

### 11.3 `schedule_users_v5.m` — RB Allocation

**What it does:** given a scheduler mode, the current TTI, per-user EMA-tracked rates (`R_emas`), and each user's requested "potential" throughput (`pot`), allocates resource blocks (`rb`) among users for that TTI — implementing the actual PF/RR/EQ scheduling rule.

**Why reused:** this is the scheduler itself — the mechanism that decides *who transmits*, as opposed to *what MCS they use* (which is what v7's RL agents control). Since the v7 project's entire contribution is about link adaptation (MCS selection), not scheduling, there was no reason to touch this function; keeping it identical to v5 also guarantees that any throughput differences observed between v6/v7 configurations are attributable to the link-adaptation layer, not to a silently different scheduling implementation. This is an important methodological control: changing the scheduler code between versions would have confounded every throughput comparison in this entire report series.

### 11.4 `baseCQI_v5.m` — SINR-to-Reference-CQI Mapping

**What it does:** maps an observed (noisy, delayed) SINR value to a reference CQI index via `env.CQI_thresholds`, used as the OLLA-corrected reference that every scheme's action offset is applied on top of.

**Why reused:** this is a pure, stateless lookup function — the CQI-threshold table itself was updated for v7's steeper BLER curves (`defaultEnv_v7.m`'s `CQI_thresholds`), but the *mapping logic* (find the highest threshold not exceeded by the SINR) required no change. Reusing the function while updating only its input parameters is the correct way to propagate a physics change (D4) without risking a transcription bug in reimplementing already-correct lookup logic.

### 11.5 `trendBin_v5.m` and `argmaxNoOp_v5.m` — Tabular-Learner Utilities

**What they do:** `trendBin_v5` discretizes a continuous SINR-trend value into one of `env.n_trend` bins for the tabular (QL, Tab AC) state representation; `argmaxNoOp_v5` breaks ties in a tabular policy's action-value lookup, with an explicit bias toward the no-op (OLLA-equivalent) action rather than an arbitrary index.

**Why reused, and why the tie-break logic matters historically:** `argmaxNoOp_v5` exists because of a bug discovered in v1 (documented in the v6 methodology report) — MATLAB's default `max` function's tie-breaking returned the *first* matching index, which biased early tabular policies toward the minimum action index rather than the intended no-op action, causing collapsed throughput. `argmaxNoOp_v5` is the audited fix for that specific defect. Reusing it in v7 (rather than reimplementing tie-breaking from scratch) is a direct guard against reintroducing a bug that was already found and fixed once.

### 11.6 `tbsFromMCSandRB` (in `case2_3`) — Transport Block Size Table

**What it does:** given an MCS index and a resource-block count, returns the transport block size (TBS) in bits — the standard 3GPP-style TBS lookup table used to convert an MCS/RB decision into an actual bit-rate for throughput scoring.

**Why reused from `case2_3` rather than v5 or a new v7 table:** the TBS table is a fixed physical-layer constant (it encodes standardized MCS-to-bitrate mappings), independent of any RL-AMC design decision made across v1–v7. It was implemented once, in the earliest applicable case study, and has been imported unchanged ever since. Reimplementing a standards-table lookup from scratch for each version would only introduce risk (a transcription error) with no corresponding benefit, since the table's correctness is orthogonal to every algorithmic change made in later versions.

### 11.7 Why This Matters for the Report's Credibility

Two consequences follow from this dependency structure:

1. **Bug locality.** Every root cause identified in Part 5 was found in `_v7`-suffixed files (`defaultEnv_v7.m`, `calibrateFixedClass_v7.m`, `DeepA2C_Shared_v7.m`) or in the *parameters passed into* legacy functions — never inside the legacy functions' own logic. This is expected: the legacy modules implement scheduling and lookup mechanics that are shared, stable infrastructure, while the v7-specific files implement the actual experimental design (HARQ, heterogeneity, bursts, state tiers, comparator calibration) where new bugs would be expected to originate.
2. **Comparability.** Because the scheduler (`schedule_users_v5`), the CQI mapping mechanism (`baseCQI_v5`), and the TBS table (`tbsFromMCSandRB`) are byte-for-byte identical to what v5 and v6 used, any throughput difference observed between v6 and v7 configurations can be attributed to the deliberate v7 design changes (D1–D5) and not to an incidental implementation drift in shared infrastructure — which is a necessary condition for the "v7 removes v6's simplifications" narrative in Part 1 to be a valid comparison at all.

---

**Document scope note:** this report explains reasoning and process. For the formal results tables, statistical detail, and figures, see `DATA_STATUS_REPORT_v7.md` and `v7_comprehensive_evaluation_report.pdf` in `docs/`.
