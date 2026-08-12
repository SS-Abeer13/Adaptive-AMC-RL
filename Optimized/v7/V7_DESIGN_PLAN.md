# v7 Design Plan — Making the RL Advantage Prominent (and Honest)

**Date:** 2026-07-21 · **Goal:** an environment where reinforcement learning wins *big* over OLLA and over every fixed rule — because the environment genuinely demands adaptivity, not because the comparison is rigged.

---

## 1. Why v6 capped the RL advantage (the diagnosis)

The v6 data explains exactly why the gap was small, and each cause points to a v7 design lever:

1. **The environment is quasi-stationary.** One speed, one delay, one interference level for all users for the whole trace. The optimal CQI offset is therefore nearly a *constant* — and a constant rule (Fixed −1/−2) matched the AI (A3 result). RL can only show an advantage when the best action *changes* with state.
2. **Errors are free (no HARQ).** A failed transport block costs nothing but its own slot, so the throughput-optimal BLER is absurdly high (~0.45) and flat — any bold scheme wins, smartness not required.
3. **One sigmoid BLER curve for all MCS.** Real per-MCS waterfall curves make the optimal operating point depend on SINR region — a state-dependence v6 never had.
4. **Strict information equality.** v6's design goal was a clean ablation (action 0 ≡ OLLA, same inputs). Scientifically excellent — but it deliberately denies RL the thing RL is actually good at: exploiting rich observable state that a scalar integrator cannot.
5. **The A2C exploited ±3 actions where tabular methods couldn't** (+6.2%, p=0.0019, the one clean mechanism win in v5/v6). Bigger action spaces amplify the deep-RL edge.

## 2. The v7 thesis (one sentence)

*When the radio environment is heterogeneous and non-stationary — as real cells are — a fixed correction cannot fit all users at all times, an integrator adapts too slowly, and a state-conditional learned policy wins decisively.*

Every mechanism below is a documented real-world effect. We are not rigging the game; we are stopping the simulator from hiding the conditions under which adaptivity matters.

## 3. The five design changes (in priority order)

### D1 — HARQ with retransmission cost (review M1)
Chase-combining HARQ, max 3 retransmissions, each costing a slot. Failed TBs now consume real airtime. Effects: throughput-optimal BLER drops to the realistic 10–30% band, kills the "just run hot" degenerate strategy that let fixed offsets win, and adds per-user HARQ state (retx counter, soft-combined SINR gain) that only RL can condition on.

### D2 — Heterogeneous users (per-user speed, delay, interference)
Each user draws its own speed (3–30 m/s → per-user Jakes ρ via the v6 `jakes_rho` machinery), its own CQI delay (2–8), and its own O2I/interference class. One fixed offset now *cannot* be right for everyone: the pedestrian needs ≈0, the vehicle needs −2. OLLA eventually personalizes but only at ~1 update per scheduled slot; RL personalizes instantly from state. **This is the single strongest legitimate gap-creator against the fixed-offset control.**

### D3 — Non-stationary regimes (bursty interference + speed changes)
Markov-switching interference (e.g., a neighboring cell toggling load: +0/+6/+12 dB bursts, dwell ~100–300 TTIs) and mid-trace speed changes (user boards a bus). OLLA's integrator lags every transition by design; a policy reading instantaneous features (SINR trend, NACK burst count) reacts in one TTI. Transient-heavy environments are where integrators bleed. Fixed offsets are always wrong in at least one regime.

### D4 — Realistic per-MCS BLER curves + honest PHY constants
Replace the single sigmoid with per-MCS AWGN waterfall curves (table-driven, standard LTE link-level abstractions; ship the table in-repo). Fix the C6 physics debt at the same time: Jakes ρ **on by default**, 20 MHz / 100 RB consistent, time axis documented. This removes the "0.45-optimal BLER is a model artifact" reviewer attack permanently.

### D5 — Two-tier state design (the honest info-advantage headline)
- **Tier A (info-equal, the fair ablation):** exactly the v6 state. Keeps the beloved action-0 ≡ OLLA property and comparability with v6.
- **Tier B (full-state, the headline):** adds features OLLA *provably cannot use* — HARQ retx state, NACK-burst counter, SINR slope over last k TTIs, per-user speed estimate, interference-regime indicator. Label the comparison honestly: "what state-conditional control buys beyond any scalar outer loop."
- Action space ±3 (the v5/v6 mechanism evidence says deep RL exploits it; tabular can't).

## 4. Comparator suite (carried over — this is what makes it credible)

All v6 controls stay, from day one, so the win is unimpeachable:
cold OLLA · **converged OLLA (warm_ttis=1000)** · **best fixed offset per config (A3 grid)** · per-user best fixed offset (new, stronger control for D2) · adaptive-target OLLA (optional stretch: OLLA that tunes its own BLER target — the strongest classical rival) · QL / Tab-AC / Deep A2C.

**Pre-registered win condition:** Deep A2C (Tier B) beats *converged* OLLA **and** the *per-user best fixed offset* on PF cell throughput at trace-level Wilcoxon p<0.05 with Holm over the primary family, while never significantly losing on BLER or edge throughput. If it can't clear that bar, v7 doesn't ship.

## 5. File repurposing map

| v7 file | From | Change |
|---|---|---|
| `defaultEnv_v7.m` | `defaultEnv_v6.m` | + HARQ params, per-user speed/delay/interference draws, regime-switch params, Jakes-by-default, 20 MHz/100 RB |
| `generateChannel_v7.m` | `generateChannel_v5.m` | per-user ρ (Jakes), Markov interference bursts, mid-trace speed switches; returns regime traces for logging |
| `estimateBLER_v7.m` | `estimateBLER_v5.m` | table lookup per MCS (waterfall curves) + soft-combining gain under HARQ |
| `harq_v7.m` | **new** | small module: retx counter, combining gain, slot accounting |
| `evalPolicy_v7.m` | `evalPolicy_v6.m` | + HARQ loop, per-user delays (vectorized delay indexing), Tier-A/B state switch, keeps `'fixed'`, `'olla'`, adds `'fixed_peruser'` and optional `'olla_adaptive'` ptypes |
| `runComparison_v7.m` | `runComparison_v6.m` | inherits all 2026-07-21 fixes (trace-level CIs, headless-figure skip, header provenance); + comparator suite rows; + regime-conditioned reporting (gap during bursts vs calm) |
| `DeepA2C_Shared_v7.m` | `DeepA2C_Shared_v6.m` | wider input layer (Tier B features), ±3 actions, ep=300 default (heap-safe), CPU-only |
| `QL_Shared_v7.m` / `AC_Shared_v7.m` | v6 | Tier-A state only (tabular can't fit Tier B) — expected to lag, which is itself the capacity result |
| `run_v7_point.m` / `run_v7_remaining.bat` | `run_A2_point.m` / `.bat` | same one-process-per-point, resumable, logging pattern |
| `sweepHetero_v7.m`, `sweepBurst_v7.m` | `sweepDelay_v6.m` | primary families: heterogeneity width and burst intensity replace the delay sweep |
| Unchanged imports | `baseCQI_v5, cqiFeedback_v5, schedule_users_v5, schedContext_v5, trendBin_v5, argmaxNoOp_v5, pfPotential_v5, sampleSched_v5` | via addpath, as v6 does |

## 6. Experiment plan (compute-aware: ~30–80 min/run, heap-safe protocol)

**Phase 0 — Sanity (1 day):** N=10 homogeneous, no bursts, HARQ on. Expect: optimal BLER now 10–30%; converged OLLA ≈ near-optimal; RL ≈ parity. *This run proves the simulator is no longer biased toward running hot — it is the credibility anchor.*
**Phase 1 — Heterogeneity family (the new primary):** sweep user-mix width (all-same → wide mix), 5×30, all comparators. Hypothesis: RL gap grows monotonically with heterogeneity; per-user fixed offset closes part of it, converged OLLA doesn't.
**Phase 2 — Burst family:** sweep interference burst intensity/dwell. Report the gap *during* transients vs calm separately (regime-conditioned metrics — this is where the prominent numbers will live).
**Phase 3 — Ablations:** Tier A vs Tier B (what does extra state buy?), ±2 vs ±3, deep vs tabular. Warm-family defense run. Fresh-seed replication of the headline point (learned the A2 lesson: replicate before writing).

All runs: headless, one MATLAB process per point, ep=300, CPU, resumable — the v6 crash playbook.

## 7. Honesty guards (so reviewers can't repeat the v6 story)

- Phase 0 null result reported prominently ("in calm conditions, classical control is enough — as it should be").
- Every headline table contains the fixed-offset and converged-OLLA rows. No comparator is ever dropped.
- Tier A vs Tier B labeled explicitly; the info-equal ablation is never conflated with the full-state headline.
- Pre-registered primary family + win condition written in this file *before* the first run (this section is that record).
- All v6 disclosure discipline carries over: trace-level CIs, Holm, budget provenance in headers, negative results kept.

## 8. What success looks like

A paper titled roughly *"Where Learning Beats the Loop: Residual RL for Link Adaptation in Heterogeneous, Non-Stationary Cells"* — with a Phase-0 null anchoring credibility, a heterogeneity/burst regime map where the RL gap is large (plausibly +10–25% during transients against even the best classical rule), and the v6 dataset repurposed as the "calm regime" half of the story. v6 wasn't wasted: it's the control condition v7 gets measured against.
