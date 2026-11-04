# v13 — RL policy improvements: implementation plan for Claude Code

Written 23 Oct 2026, after the v12 replication. Work in `D:\Adaptive AMC A2C+QL\Optimized`.
Read §0 first. This plan has a **gate**: Stage 1 is built only if Stage 0 shows enough headroom.

---

## 0. Context (what v12 established, and why these changes)

On deadline traffic, these are the v12 results (fresh seeds and traces, pre-registered):

| | A2C on-time | vs OLLA family | vs best calibrated rule |
|---|---|---|---|
| R1_pf (10 seeds, 500 traces) | 0.8421 | +0.9–1.0 % (pass) | Fixed (−1): **−0.47 %** (loss); FixedPU −0.34 % (loss) |
| R2_edf (5 seeds, 300 traces) | 0.8717 | +1.7–1.8 % (pass) | Fixed (−2): +0.28 %; FixedPU +0.09 % (tie) |

Observations the changes are built on:
1. **The best simple policies are static conservative offsets.** When A2C works, it lands near one
   (EDF: 74 % of decisions at −2, the calibrated offset). Its only possible gain is the state
   dependence around that offset.
2. **Seed failures dominate the margin.** R1 seed 2 reached 0.805 while the others reached
   0.832–0.854. Without seed 2, A2C equals Fixed (0.8462 vs 0.8461).
3. **The on-time reward is sparse** (±1 per packet), so credit for individual MCS choices is
   noisy.
4. **The scheduler is a bigger lever than MCS.** PF → EDF raised every scheme by about 3 points;
   RL's MCS choice adds about 1 point over OLLA.
5. **Counting:** about 17 cases have been tested, and every new case is added to the count. Keep
   this round small (3 cases) and pre-registered.

Code base: `Optimized/v12/` (bit-exact with v11 by default, plus EDF and `crn_seed_base`).
v13 is copied from v12 in the same way v12 was copied from v11.

---

## Stage 0 — Headroom check (gate; no RL training)

**Question.** How much on-time delivery is available above the calibrated fixed rule at all?
If the answer is "very little", no policy change can give a meaningful headline. Stop and write
the paper.

### S0.1 New reference policies in `evalPolicy_v13`
- **`'genie_cqi'` (perfect-CSI bound).** Each TTI, user i gets the largest CQI q such that
  `estimateBLER_v13(SINR_true(t,i), q-1) <= env.genie_bler`. There is no OLLA (the offset is
  unused), and HARQ is unchanged.
  - `env.genie_bler` is calibrated on the calibration traces (60000+) over the grid
    `[0.001 0.01 0.03 0.1 0.2]` by the primary metric (the same machinery as the tuned OLLA
    target: add it to `calibrateCtx_v13` or a new `calibrateGenie_v13`).
  - This bounds what *any* link-adaptation policy could reach with perfect, instantaneous CSI.
    No realisable policy, RL included, has this information.
- **`'fixed_hindsight'` (adaptivity bound with realistic information).** For each evaluation
  trace, evaluate Fixed with every offset in `-4:2` (common random numbers) and keep the best
  offset **for that trace** in hindsight.
  - This bounds the benefit of adapting a single offset per trace, using the same delayed CQI
    every scheme gets.
  - Implement it as an analysis step that calls `evalPolicy_v13('fixed', ...)` with
    `env.fixed_offset = o` for each o. It is not a new ptype.

### S0.2 Script `headroom_v13.m`
- Use the v12 `R1_pf` and `R2_edf` environments and **their evaluation traces**: rebuild them
  from `trace_seed_base` and `crn_seed_base` exactly as `runComparison_v12` does.
- Re-calibrate Fixed and FixedPU as v12 did. They must reproduce v12's Fixed values: R1 0.8461,
  R2 0.8693. If they don't, stop.
- Compute and write to `Dataset/headroom_v13.txt`, per environment:
  `HEAD|<env>|fixed=..|fixedpu=..|hindsight=..|genie=..|genie_bler=..|a2c_v12=..`
- The `a2c_v12` value is taken from `results_v12_<tag>.mat` (no re-run).
- Run time: about 15–30 min (500 + 300 traces × (7 offsets + genie + 2 rules)).

### S0.3 Gate (thresholds fixed now; they are relative to the calibrated Fixed rule)

An environment **has headroom** if both of these hold, as relative differences
(`100·(x − Fixed)/Fixed`):
- genie − Fixed ≥ +2 %;
- hindsight − Fixed ≥ +0.5 %.

| Condition | Decision |
|---|---|
| Neither R1 nor R2 has headroom | **STOP.** Record it in README_v13 and write the paper. Headroom statement: "even per-trace hindsight adaptation gains < x %; perfect CSI gains < y %". |
| At least one has headroom | Build Stage 1. |

Report the numbers to the user and **wait for approval** before Stage 1, whatever the outcome.

---

## Stage 1 — Residual-on-calibrated-rule A2C + seed ensemble (pre-registered, 3 cases)

All changes are additive switches in the v13 code; the defaults reproduce v12 bit for bit.

### S1.1 Residual action mode (`env.action_mode = 'resid'`)
- **Base rule.** `b_i` is the calibrated offset of the better of {Fixed, FixedPU}. Choose it by
  score **on the calibration traces** (never on evaluation traces) and record the choice in
  `V13ENV|`.
- **Action.** `delta in env.resid_actions = [-1 0 1]`; sent CQI = `clip(ref_i + b_i + delta)`.
- **Deviation cost.** Reward term `- env.resid_pen * abs(delta)` on every decision, with
  `resid_pen = 0.02` (2 % of the on-time bonus).
- **Initialisation.** Set the actor's last-layer bias so that P(delta = 0) ≈ 0.9 at
  initialisation (logit bias +3 on the zero action). The agent starts at the base rule and only
  moves when it learns to.
- **Files.** `defaultEnv_v13`, `evalPolicy_v13` (the `a2c` branch adds `b_i + delta`),
  `DeepA2C_Shared_v13` (action decode, reward term, bias init), `runComparison_v13` (pick the
  base rule after calibration and pass it in `env`).
- The `Bandit_v13` arms stay the full offset set (unchanged comparators).

### S1.2 Seed ensemble (new scheme "Deep A2C v13 (ensemble)")
- **Policy.** Greedy action = `argmax` of the **mean softmax** over the K trained seeds' actors.
  This is one deterministic policy, evaluated once per trace.
- **Implementation.** New ptype `'a2c_ens'` in `evalPolicy_v13`. It takes a cell array of
  actors, runs each forward pass and averages the probabilities.
- **Keep the per-seed scheme** (mean over seeds, as before) for comparison.

### S1.3 Optional shaped on-time reward (`env.reward_kind = 'ontime_shaped'`)
- Potential-based shaping (Ng et al. 1999), which leaves the optimal policy unchanged:
  `F = gamma * Phi(s') - Phi(s)`, `Phi(s) = -env.shape_c * rem_frac_i`, with `shape_c = 0.5`.
  Add it to each scheduled transition's reward, on top of `ontime`.
- It is used **only** in case `X2_pf_shaped` below.

### S1.4 Validation selection
Turn on the existing P0.4 machinery with `a2c.val_every = 50`, `n_val = 10`, validation traces
80000+. Report it as a secondary scheme (best-on-val). The ensemble uses the **last** checkpoint
of each seed. That choice is fixed now, so we cannot pick between "last" and "best" after
seeing results.

### S1.5 Cases (all fresh seeds and traces, disjoint from v10–v12)

| Tag | Role | Scheduler | Policy | Reward | Seeds (base_seed) | Eval traces | CRN |
|---|---|---|---|---|---|---|---|
| `X1_pf` | **primary** | PF | resid + ensemble | ontime | 10 (3042) | 500: 40001–40500 | 41001+ |
| `X1_edf` | secondary | EDF (all phases) | resid + ensemble | ontime | 10 (4042) | 500: 42001–42500 | 43001+ |
| `X2_pf_shaped` | secondary | PF | resid + ensemble | ontime_shaped | 10 (5042) | 500: 44001–44500 | 45001+ |

- **Environment.** v12 `E4` exactly: the deadline settings, PF/EDF settings as in R1/R2,
  800 episodes, `base.a2c` hyper-parameters.
- **Primary scheme.** "Deep A2C v13 (ensemble)" in `X1_pf`.
- **Comparators.** The v12 set: Baseline, OLLA, OLLA tuned, Multi-OLLA, Fixed, FixedPU,
  Context table, Bandit global, Bandit delay. Also report the base rule itself: it is Fixed or
  FixedPU, already in the set.
- **Decision rules.** Same as v12 (`analyze_v13_replication.m` = the v12 analyser with the
  scheme name changed): Claim A (OLLA family), Claim B (Fixed, FixedPU, Context table), WIN
  (all 9). Holm over 9, plus the 90 % CI lower bound > 0.
- **Wording table (fixed now):**

| X1_pf outcome | Paper may say |
|---|---|
| Claim B passes | "Learning a residual on the calibrated rule, with a seed ensemble, beats every comparator, including calibrated fixed-offset rules (+x %), in a pre-registered test on fresh data." Report it together with the v12 failure and the total case count. |
| Claim B fails | "Residual learning and ensembling did not produce a gain over calibrated rules; the gain over the OLLA family is (still / no longer) present." |

### S1.6 Tests (all must pass before launch)
1. `test_equivalence_v13.m`: bit-exact with v12 with defaults (baseline / olla / fixed /
   multi_olla / ctxtab, plus a 5-episode A2C run).
2. **Residual sanity check.** `resid_pen` is large (e.g. 10), the initial bias is set and the
   run is 20 episodes. The greedy policy must pick delta = 0 in ≥ 99 % of decisions and match
   the base rule's on-time score on 20 traces within 0.1 %.
3. **Ensemble sanity check.** An ensemble of K copies of the same actor must equal that actor's
   evaluation bit for bit.
4. **Shaping sanity check.** With `shape_c = 0`, `ontime_shaped` must be bit-exact with
   `ontime`.
5. **Preflight** (2 episodes, 2 seeds, 6 traces) of all three cases. `REPL|` lines must parse.

### S1.7 Run
- Launcher `run_v13_headless.bat`, with the same auto-restart and checkpoint pattern as v12.
- Estimated run time: about 90 min per case, so about 4.5 h in total.
- Stop for user approval of README_v13 §1–5 before launching.

---

## Stage 2 — Joint scheduling + link adaptation (design only; separate study)

Only if the user asks for it after Stage 1. It needs its own plan and pre-registration.
- **Idea.** The agent also chooses *which* user is scheduled each TTI, or ranks users, not only
  the MCS. Observation 4 says the scheduler lever is about 3× larger.
- **Required comparators** (otherwise the result is not credible):
  - EDF + calibrated Fixed;
  - PF + calibrated Fixed;
  - a max-weight / deadline-aware heuristic (e.g. a slack-weighted PF metric) with a calibrated
    weight.
- **Design issues to solve first:**
  - a centralised action space (N users × offsets) or a factorised policy;
  - credit assignment across users, which is cell-level by nature;
  - training cost.
- Expect about 1–2 days of implementation.

---

## Housekeeping (any time)
- README_v13 is pre-registration first (§1–5), then results (§6), as in v12.
- Multiplicity: Stage 0 adds no cases (reference policies only); Stage 1 adds 3 (total about
  20). Report it.
- Never re-run, re-tag or re-tune a finished case.

---

## Prompt to give Claude Code
> Read `Optimized/v13/PLAN_v13.md`. Create `Optimized/v13` from `Optimized/v12` (core files
> only, `_v12` → `_v13`, as v12 was created from v11). Implement **Stage 0 only** (S0.1–S0.2).
> Check that the re-calibrated Fixed values reproduce v12 (0.8461 PF, 0.8693 EDF), run
> `headroom_v13.m` headless with `matlab -batch`, write `Dataset/headroom_v13.txt`, apply the
> S0.3 gate, and stop to show me the numbers and the gate decision. Do not start Stage 1
> without my approval.
