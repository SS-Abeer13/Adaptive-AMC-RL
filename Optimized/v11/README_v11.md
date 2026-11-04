# v11 — target-BLER action space (P1)

**Approved and run 21 Oct 2026** (pre-registration below was written and approved
before any v11 experiment result was produced). Per `IMPLEMENTATION_PLAN_v11.md`.

## Result (21 Oct 2026, 16:32, 87 min campaign)
**No win on any of the 3 pre-registered cases** (`WIN|...|=0` for all three;
multiplicity count for v11: 3 cases tested, 0 wins). Full numbers in
`Dataset/fill_summary_v11_P1.txt`.

| Tag | Primary | A2C | Best comparator | A2C vs best | Verdict |
|---|---|---|---|---|---|
| `T1_gp` | goodput | 2.904 Mbps | Baseline 2.988 | −2.8%, Holm 7.5e-16 | loses (also loses to Per-class tuned target, −1.1%, Holm 4.2e-5) |
| `T2_stale` | goodput | 2.707 Mbps | Baseline 2.858 | −5.3%, Holm 3.9e-26 | loses (also loses to OLLA tuned −3.5%, Per-class tuned −3.2%) |
| `T4_deadline` | on-time | 0.8298 | Fixed 0.8484 | −2.2%, Holm 6.8e-17 | loses (also loses to OLLA, OLLA tuned, Multi-OLLA, Context table, Per-class tuned, Bandit-over-targets) |

A2C beats the weaker comparators it was designed to beat (OLLA at the untuned
10% target, Fixed, Context table, the global offset bandit) in every case,
but loses to **Baseline** (T1/T2) and to the **tuned-target OLLA / per-class
tuned target** (all three) — the two comparators specifically added for this
phase to make sure A2C isn't just getting credit for a mis-tuned reference.
This confirms the plan's lesson 1 (`IMPLEMENTATION_PLAN_v11.md` §0): giving
the agent the *same lever* the tuned baselines already use removes the
structural gap, but a learned per-user, per-epoch policy over that lever
still doesn't beat a well-calibrated static or per-class choice in these
three environments, at 800 episodes / 5 seeds. `Deep A2C v11 (best-on-val)`
is identical to `Deep A2C v11` in all three cases (`env.a2c.val_every` was
left at its default 0 for this run).

Per the plan's stop rule (§4): P1 alone doesn't trigger it (that's after
steps 2–4: P1/P2/P4). Candidate next steps: P2 (PPO + GAE + cell-level
critic, which targets the same failure modes from a different angle) or
P4 (GRU + richer history) directly; or treat this as a second confirmed
negative result (alongside v10's E1–E3) and start writing up the deadline
win plus the negative/methodological findings.

## P2 — PPO + GAE (pre-registration, 21 Oct 2026)
`DeepPPO_Shared_v11.m` implements the plan's P2 (clipped surrogate,
GAE(lambda)=0.95, 4 epochs x minibatch 256 per rollout, running mean/std
normalisation of observations and rewards, clipped value loss, an
entropy-coefficient floor). It reuses the exact same environment
interaction as `DeepA2C_Shared_v11` (state features, the P1 target-mode
semi-MDP epoch, scheduling, physics), so a trained PPO actor is a drop-in
policy for `evalPolicy_v11`'s `'a2c_v11'` ptype. `env.reward_kind = 'cell'`
is implemented (cell goodput minus the OLLA reference expectation, credited
to the scheduled user) but **not used below** -- simplification: the
critic stays decentralised (same state as the actor) rather than the
centralised cell-summary critic the plan describes; this is a scope cut
for this round, not a verified-equivalent substitute.

**Acceptance diagnostic** (E1 environment, offset mode, 3 seeds x 150
episodes -- reduced from a full run to bound runtime; "diagnostic, not a
result" per the plan):

| Check | Target | Result |
|---|---|---|
| Training curve non-decreasing, last 50% | all seeds | 2/3 seeds (1 seed's 2nd-half mean fell) |
| Greedy action histogram non-degenerate | max action < 95% | 0.694 / **0.963** / 0.631 (1 seed over target) |
| Seed SD of final throughput | < 0.5% | **11.7%** |

The implementation runs correctly end-to-end (training, checkpointing,
evaluation via the shared `a2c_v11` ptype, reporting in `runComparison_v11`
and `fill_stats_v11`) and the agent visibly learns (cell throughput moves
off its initial value), but seed-to-seed variance at this reduced scale is
far above the plan's 0.5% target and one seed's action histogram is close
to degenerate. This is a 3-seed/150-episode diagnostic, not the full
800-episode/5-seed scale the criteria likely assume, so it is suggestive
rather than conclusive -- logged here for the record either way.

Per-episode cost at this scale: ~0.55-0.85 s/episode (3 seeds, 150 episodes
each, 80-125 s/seed) -- comparable to `DeepA2C_Shared_v11`, not the ~9x
overhead an earlier full-width smoke test suggested. A full `T1_gp_ppo` /
`T2_stale_ppo` / `T4_deadline_ppo` campaign at the P1 scale (5 seeds, 800
episodes, 300 evaluation traces, training **both** A2C and PPO per the
plan's "keep A2C for comparison") is estimated at roughly 2-4 hours total,
pending confirmation at full scale.

**Experiments.** Same cases, environments, comparator set and win criterion
as the three P1 cases above, with PPO trained alongside A2C under new tags
`T1_gp_ppo`, `T2_stale_ppo`, `T4_deadline_ppo`. Multiplicity for v11: 6
cases now tested in total (3 P1 + 3 P2), 0 wins.

## P2 result (21 Oct 2026, 20:36, 174 min campaign)
**No win for A2C or PPO on any of the 3 cases.** PPO's seed-to-seed
variance at full scale (800 episodes) was far better than the reduced-scale
diagnostic suggested -- `T2_stale_ppo` (0.13%) and `T4_deadline_ppo`
(0.42%) both meet the plan's <0.5% target; `T1_gp_ppo` is close (1.38%).
That said, `T4_deadline_ppo`'s greedy action histogram has max action
fraction 0.960 -- just over the plan's 95% degeneracy threshold (PPO
collapsed onto the most conservative target, 0.5, on the deadline case).

| Tag | Primary | A2C | PPO | Best comparator | Verdict |
|---|---|---|---|---|---|
| `T1_gp_ppo` | goodput | 2.904 | 2.919 | Baseline 2.988 | both lose (A2C −2.8%, PPO −2.3%) |
| `T2_stale_ppo` | goodput | 2.707 | 2.684 | Baseline 2.858 | both lose (A2C −5.3%, PPO −6.1%) |
| `T4_deadline_ppo` | on-time | 0.8298 | 0.8005 | Fixed 0.8484 | both lose (A2C −2.2%, PPO −5.6%) |

PPO is not meaningfully better than A2C here: essentially tied on `T1_gp`,
and clearly worse than A2C on `T2_stale` and especially `T4_deadline`
(where its policy nearly collapsed to a single conservative target). GAE +
the clipped objective did not fix the underlying issue P1 already showed:
giving the agent the tuned baselines' own lever (the target BLER) still
doesn't produce a policy that beats a well-calibrated static or per-class
choice, in any of these three environments, A2C or PPO, offset or target
action space. This is the plan's second algorithm family (after A2C) to
fail to win on the goodput/on-time cases, now across 6 total cases (0
wins). Per the plan's stop rule (§4), this is the point to seriously weigh
writing up the deadline win (v10 E4c, the only positive result so far)
plus the negative/methodological findings, rather than continuing to P4
(GRU + richer history) on the same reward/environment structure.

## Status of the v11 codebase at this pre-registration
- P0 (infrastructure) is done: `Optimized/v11/` is a straight copy of v10 with
  `_v10` → `_v11` renamed throughout. With the defaults, v11 reproduces v10
  bit-for-bit — checked by `test_equivalence_v11.m`
  (`matlab -batch "run('test_equivalence_v11.m')"`), which passed on
  `baseline` / `olla` / `fixed` / `multi_olla` / `ctxtab` (3 traces) and on a
  5-episode Deep A2C training run, all bit-exact against v10.
- P0.2 vectorised the per-user hot loops (`evalPolicy_v11`, `txStep_v11`,
  `DeepA2C_Shared_v11`) — ~4–7.5x faster training, same equivalence test.
- P0.3 added optional parallel rollouts (`env.a2c.n_envs`, default 1 =
  unchanged) and P0.4 added validation-based model selection
  (`env.a2c.val_every`/`n_val`, default 0 = disabled; reported as scheme 8b
  "Deep A2C v11 (best-on-val)" once enabled). Both default off and bit-exact
  against v10 when off.
- P0.5 added `ACT|` (greedy-policy action histogram) and `LCURVE|` (train /
  validation deciles) lines to `fill_stats_v11`.
- **Nothing below this point has been run.** This file pre-registers P1
  (target-BLER action space, §2 of the implementation plan) before any of it
  is executed, per the experiment protocol in §3 of that plan.

## Why P1 (from the v9/v10/v10b/v10e results)
The v10 goodput cases (E1–E3) gave no win: a per-CQI-offset action fights the
OLLA integrator, and the tuned-target OLLA alone already beats the 10%-target
default by 2–5%. Acting directly on the OLLA target BLER — per user, per
decision epoch — is a strict superset of what tuned-target OLLA can do, and
it does not require unlearning the integrator's dynamics first.

## P1 change under test
- `env.action_mode = 'target'` (new; `'offset'` keeps the v9/v10 behaviour
  used above for the equivalence test). The action selects a target BLER for
  that user from `env.target_set = [0.01 0.03 0.10 0.20 0.30 0.50]`; OLLA's
  down-step uses the user's own target: `du_i = dd * t_i / (1 - t_i)`.
- Semi-MDP decision epoch: the action (and the chosen target) is held for
  `env.target_epoch = 10` TTIs per user; reward is accumulated over the
  epoch, not per TTI.
- Everything else (physics, HARQ, scheduler, state tiers, reward kinds) is
  unchanged from v10/v11-P0.

## Cases (fixed before any v11-P1 result was seen)
| Tag | Environment | Primary metric | Extra A2C cue | Notes |
|---|---|---|---|---|
| `T1_gp` | v10 E1 (headline, physical mobility) | goodput (Mbps) | none | control case: does the target action alone help with no extra cue |
| `T2_stale` | v10 E2 (60–120 km/h, periodic/stale CQI) | goodput (Mbps) | report age, report deviation (unchanged from v10) | target action + the v10 cue together |
| `T4_deadline` | v10 E4 (10-TTI deadline traffic) | on-time delivery ratio | deadline slack (unchanged from v10) | target action on the deadline track |

No `_nofeat` ablations are planned for P1 itself (the action-space change is
the thing under test, not a cue); `T2_stale`/`T4_deadline` reuse the v10 cue
unmodified to isolate the effect of the action space from the effect of the
cue, which v10 already measured separately.

## Comparators (every case; calibrated on calibration traces, disjoint from evaluation traces)
Baseline, OLLA (10% target), **OLLA (tuned target, grid `env.olla_targets`)**,
Multi-OLLA, Fixed, FixedPU (per-class oracle), Context table (OLLA + per-cue-bin
offset), **Per-class tuned target** (one calibrated target per delay-class ×
speed-class bin — same information as FixedPU, new for P1), **Contextual
bandit over targets** (delay class, new for P1; replaces the offset-armed
bandit in the target-action cases), UCB bandit (global, offset-armed, kept
for continuity with v10). Common random numbers; Tier O; scheduler PF.

The headline A2C (`Deep A2C v11`) is reported strictly autonomously
(`bc_warm_eps = 0`), per the v9/v10 fairness note. `Deep A2C v11
(best-on-val)` (P0.4) is also reported for every case, with its own
`env.a2c.val_every`/`n_val` recorded in the `V11ENV|` log line.

## Seeds, traces, splits
- 5 seeds (escalate to 10 if seed SD on the primary metric exceeds 1%).
- 300 evaluation traces per case (seeds 9000+).
- Calibration traces 60000+ (fixed-offset / context-table / tuned-target
  grids), validation traces 80000+ (P0.4, only if `val_every > 0` is set for
  a given run), evaluation traces 9000+ — all disjoint.
- Common random numbers throughout (outcome draws shared across schemes on a
  trace).

## Pre-registered win criterion (unchanged from v10)
A2C wins a case iff, on the primary metric, it beats **every** comparator
with Holm-adjusted Wilcoxon p < 0.05 **and** a 90% CI lower bound > 0
(`WIN|...|=1`). Every case is reported whatever the outcome; no case is
dropped or re-tuned after its result is seen.

## Multiplicity
This is the first round of v11 cases. `T1_gp`, `T2_stale`, `T4_deadline`
count as **3 cases** for multiplicity; any later v11 case (P1 ablations, P2
PPO re-runs of the same tags, etc.) adds to this count, reported together
per the plan's §3.4.

## Before launching
1. `test_equivalence_v11.m` must pass (done — see Status above).
2. `fill_v11_preflight.m`: a 2-episode preflight of every case in this file,
   run and checked before the real campaign.
3. This file approved (tags, comparators, metric, win criterion) — **pending**.

## P4 — recurrent memory (pre-registration, 21 Oct 2026)
P1/P2 both gave no win, so per the plan's own ordering P4 is next.
**Scope cut agreed with the user before implementation** (P1's target
action and P2's PPO both assume per-TTI / per-scheduled-transition sample
independence that a recurrent policy's sequential 16-step truncated-BPTT
chunks break; combining all three correctly is substantially more
engineering for a combination P1+P2 already suggest won't help beyond the
recurrence itself):
- **Action space**: offset (P1's target-BLER action, not used).
- **Update rule**: A2C-style single-pass return per 16-TTI chunk (not
  P2's PPO -- P2 already showed PPO isn't better than A2C here).
- **Architecture**: `DeepGRU_Shared_v11.m`, GRU(64) replacing the L_seq=3
  frame-stacking memory, hidden state carried per user across the whole
  episode during rollout (hand-coded GRU step from the network's own
  extracted weights, verified against `dlnetwork`'s own `forward()` --
  a per-TTI `dlarray` forward was ~30ms/call, far too slow at this scale).
  Training replays each 16-TTI chunk through the real network via
  `dlfeval` from that chunk's own (detached) initial hidden state --
  standard truncated BPTT.
- **New features** (`featExtra_v11`, all gNB-side): `ack8` (EMA proxy for
  the fraction of ACKs over the last ~8 scheduled attempts -- a summary
  scalar, not 8 separate lagged bits), `tsince` (TTIs since last
  scheduled), `offtrend` (OLLA offset minus its own slow EMA). HARQ round
  and CQI age were already state inputs pre-P4.
- **Comparators**: unchanged, **not** given the three new cues (the
  plan's "give the context table the same cue" is satisfiable for one new
  1-D cue via the existing `cueVal_v11`/`cueBin_v11` machinery, but R2/R3
  keep their original E2/E3 cue (`dev`/`cellnack`) for continuity with
  v10, so this is a known fairness gap, not a fix: a GRU win must be read
  as "recurrence + 3 extra cues" vs. the original comparator set, not an
  apples-to-apples recurrence-only test).

**Experiments.** Re-test v10's E2 (`R2_stale`) and E3 (`R3_cellcue`)
environments with GRU trained alongside A2C. Multiplicity for v11: 8
cases once run (6 above + these 2).

**Acceptance diagnostic** (E2 environment, 3 seeds x 150 episodes):

| Check | Target | Result |
|---|---|---|
| Training curve non-decreasing, last 50% | all seeds | 3/3 pass |
| Greedy action histogram non-degenerate | max action < 95% | 0.56 / 0.63 / 0.73 -- all comfortably under |
| Seed SD of final throughput | < 0.5% | 14.1% |

Same pattern as P2's diagnostic: clean pass on the two structural checks,
seed SD far over target at this reduced scale. P2's own full-scale run
later showed this was a scale artifact (11.7% at 150 episodes -> 0.1-1.4%
at 800), so the full campaign is launched on that same read, not because
the 0.5% bar was met here.

## P4 result (21 Oct 2026, 23:52, 137 min campaign)
**No win for A2C or GRU**, but a clearly different story from P1/P2.

| Case | A2C | GRU | Baseline | GRU vs. weaker comparators |
|---|---|---|---|---|
| `R2_stale` | 1.487 (-48.0% vs Baseline) | 2.724 (-4.7%) | 2.858 | beats OLLA/Fixed/FixedPU/Context table/both bandits by 1.1-1.9%, Holm < 0.05 |
| `R3_cellcue` | 1.492 (-49.0%) | 2.755 (-5.8%) | 2.925 | statistically tied with the same five (p = 0.29, not significant) |

A2C's collapse here (-48/-49%) is **not a P4 regression** -- it reproduces
v10's own original E2_stale A2C result almost exactly (-43.1% in
`Dataset/results_v10_E2_stale.txt`, offset action + the default `goodput`
reward, the "v10 reward defect" the implementation plan's own lessons
describe; `v10b`'s fix was to switch to `oppcost`, which the P1/P2 cases
sidestepped by using the target-BLER action instead, not by changing the
reward). Both action histograms show the same bang-bang pattern between
the action range's two endpoints (A2C: 57-61% / 27-41% split between the
extremes; GRU similar but less extreme), consistent with that known
credit-assignment issue, not a new recurrence-specific failure mode.

**What's actually interesting**: GRU, trained under the *same* defective
reward, is dramatically more stable than A2C (-4.7/-5.8% vs -48/-49%) and
clears every comparator except Baseline and OLLA-tuned -- on `R3_cellcue`
it's statistically indistinguishable from OLLA, Fixed, FixedPU, the
context table and both bandits. Recurrent memory alone did not fix the
underlying reward-credit problem enough to win, but it visibly buffered
against it in a way the 3-frame MLP could not. A cleaner test would retry
with `reward_kind = 'oppcost'` (v10b's fix) under the same GRU
architecture -- not run here, flagged as the natural next diagnostic
rather than assumed.

Multiplicity for v11: **8 cases tested, 0 wins** (3 P1 + 3 P2 + 2 P4).

## P4b — oppcost follow-up (requested 22 Oct 2026)
Requested test: re-run `R2_stale`/`R3_cellcue` with `reward_kind = 'oppcost'`
(v10b's fix for the defect that collapsed offset-mode A2C above) to see
whether proper credit assignment + GRU recurrence together close the
remaining ~4-6% gap to Baseline.

**Bug found and fixed before trusting the first run**: `DeepGRU_Shared_v11`
parsed `env.reward_kind` but never branched on it -- its reward computation
was hardcoded to the plain goodput formula. The first `R3_cellcue_opp` run
produced a GRU result bit-identical (to 4 decimals, same action histogram)
to the earlier plain-`goodput` `R3_cellcue` run, which is what exposed it;
A2C's result in that same run *had* changed, confirming the bug was
GRU-specific. Fixed (added the same `oppcost` branch
`DeepA2C_Shared_v11`/`DeepPPO_Shared_v11` already had), verified the fix
makes GRU training actually diverge by reward kind, discarded the invalid
partial run, and retrained both cases from scratch. (Two native heap
corruption crashes, `0xc0000374`, hit during the retrain -- the same known
MATLAB instability noted in the implementation plan -- the `.bat`
auto-restart recovered both times.)

**Corrected result: `oppcost` fixes A2C, does not help GRU.**

| Case | A2C (oppcost) | GRU (oppcost) | A2C (goodput, for reference) | GRU (goodput, for reference) | Baseline |
|---|---|---|---|---|---|
| `R2_stale` | 2.660 (-6.9%) | 2.510 (**-12.2%**) | 1.487 (-48.0%) | 2.724 (-4.7%) | 2.858 |
| `R3_cellcue` | 2.781 (-4.9%) | 2.744 (-6.2%) | 1.492 (-49.0%) | 2.755 (-5.8%) | 2.925 |

`oppcost` does exactly what v10b said it would for A2C: both collapses are
gone, and on `R3_cellcue` A2C is now statistically **tied** with OLLA,
Fixed, FixedPU, the context table and both bandits (diff = +0.01%, p =
0.19) -- it only loses to Baseline and tuned-target OLLA. That is the
closest any v11 scheme has come to a win on a goodput case.

GRU under the same corrected reward is **worse than A2C**, not better, in
both cases -- the reverse of what the (buggy) P4 run suggested. Recurrence
did not close the gap once credit assignment was fixed; if anything it
underperformed the simpler feedforward policy here. Still no win for
either scheme. Multiplicity for v11: **10 cases tested, 0 wins** (8 above
+ these 2; `R2_stale_opp`/`R3_cellcue_opp` are new tags, not re-runs of
`R2_stale`/`R3_cellcue`).

## Run (once approved)
`run_v11_headless.bat` (preflight, then campaign). Progress:
`Dataset/fill_summary_v11.txt` (`CONFIG` / `ACT` / `LCURVE` / `CMP` / `WIN`
lines per tag), full log `logs/fill_v11.log`. Resumable: rerun the `.bat` and
finished points (existing `ckpt/<tag>_seed<n>.mat`) are skipped.
