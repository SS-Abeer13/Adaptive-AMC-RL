# RL-AMC — v11 implementation plan (performance boost)

Written 21 Oct 2026 from the v9 / v10 / v10b / v10e results. Intended to be picked up in
**Claude Code** working in `D:\Adaptive AMC A2C+QL\Optimized`. Read §0 first.

---

## 0. Context for Claude Code (read before changing anything)

**Where things are**
- `Optimized/v10/` — current code. v10 = v9 plus switches; with defaults it reproduces v9
  bit for bit. Entry points:
  - `runComparison_v10(opts)` — calibrate → train A2C and bandits → evaluate on held-out traces.
  - `fill_stats_v10` — writes the PRIM / CMP / WIN lines.
  - `v10_setup.m` — the `base` options and the case structs `C.*`.
  - Campaign scripts: `fill_v10*_campaign.m`; launchers: `run_v10*_headless.bat`.
- `Optimized/v9/` — the physical-mobility baseline campaign (frozen; do not edit).
- Results go in `Optimized/v10/Dataset/fill_summary_v10.txt` (all runs, append-only) and in
  `results_v10_<tag>.mat`. Trained seeds are checkpointed in `Dataset/ckpt/`.
- The pre-registration log is `Optimized/v10/README_v10.md`. Every new experiment gets a
  section there **before** it is run.

**Running MATLAB**
- MATLAB R2023a, with the Deep Learning, Statistics, Parallel, 5G, LTE and RL toolboxes.
- Run headless: `matlab -batch "cd('<v10>'); <script>" -logfile <log>`.
- Launchers loop and restart after a crash. Native heap-corruption crashes (c0000374) happened
  5 times on 20–21 Oct, so keep the checkpoint and restart pattern for every long run.
- A standard point (5 seeds × 800 episodes, 100 traces) takes about 15–25 min; with 300 traces,
  about 25–35 min.

**What the numbers say so far** (primary metric; full detail in the project notes)

| Case | A2C | Best simple method | Verdict |
|---|---|---|---|
| Goodput, v9 headline (κ = 1) | 2.80 Mbps | Baseline 3.06 / tuned OLLA 2.98 | loses about 4–8 % |
| Goodput E1–E3, v10b (opp-cost reward) | ≈ OLLA (policy collapses to action 0) | Baseline, ~5 % higher | loses about 4–6 % |
| Deadline E4c (300 traces) | 0.8514 on time | Fixed 0.8484 | **wins all**: +0.35 %, Holm 0.005 |
| Mixed deadlines E5 | 0.8013 | Context table 0.8035 | tie |

**Lessons that constrain the design**
1. **The reference is weak.** OLLA at a 10 % target is about 5 % below the open-loop mapping on
   goodput, and the tuned target is 0.3–0.5. A residual on top of a mis-tuned OLLA starts at a
   disadvantage, and OLLA's integrator works against the residual.
2. **Reward credit.** A per-user goodput reward lets the shared agent take slots (v10). The
   opp-cost fix (v10b) removes that, but leaves too little advantage signal, so the policy
   collapses to "do nothing".
3. **Optimisation is noisy.** E5 seed means range from 0.794 to 0.816. Entropy either stays
   near uniform (v9) or collapses (v10). The cues helped in no case.
4. **Fair comparators decide the verdict.** Keep tuned-target OLLA, the context table, FixedPU
   and the bandits in every run, and add new ones whenever A2C gets a new capability (§3).

---

## 1. Performance levers, ranked by expected gain ÷ cost

| # | Lever | Why it should help (from our data) | Expected effect | Cost |
|---|---|---|---|---|
| L1 | **Act on the OLLA target BLER, not on a CQI offset** (per user, per decision epoch) | The tuned global target already beats OLLA by 2–5 %. A per-user, per-context target is a strict superset, and it changes slowly, so it is learnable. It also stops the agent fighting the integrator. | goodput +2–5 % vs OLLA; matches or beats tuned OLLA | M |
| L2 | **PPO + GAE(λ) with reward and value normalisation, cell-level critic** | Fixes both failure modes: the slot-stealing reward (v10) and the vanishing advantage (v10b). | stable training, lower seed variance | M |
| L3 | **Behaviour-cloning warm start from the best simple rule, then KL-regularised RL fine-tuning** | The BC diagnostic reached the oracle (2.871 vs 2.888). Starting there and improving conservatively means A2C is never worse than the reference. | ≥ best simple; small gain on top | S |
| L4 | **Validation-based model selection** (choose the checkpoint or seed on calibration traces) | Seed spread (about ±1.5 %) is as large as the effects we test. Selecting on validation traces, never on evaluation traces, is legitimate. | removes bad seeds; +0.5–1 % | S |
| L5 | **Recurrent policy (GRU) + ACK/NACK history + time since last scheduled** | Three stacked frames cannot represent bursts, CQI aging or scheduling gaps. This is why the E2/E3 cues did nothing. | enables E2/E3-type gains | M |
| L6 | **Finer actions: 0.5 dB SINR offset, or the NR MCS table (28 levels)** | Fifteen CQI levels with 1-step offsets are coarse. The fixed table already captures most of what 1-step moves can give. | +0.5–1.5 % | S–M |
| L7 | **Deadline track: tighter budgets (URLLC), HARQ-round–aware MCS, plus an EDF scheduler comparator** | The only win so far is deadline traffic; the effect should grow when retransmission planning matters. | larger on-time gain | M |
| L8 | **Throughput engineering: vectorise the per-user loops; parallel episode rollouts (`parfor`)** | Training budget is capped by run time (about 0.2 s per episode). 4–8× more episodes makes L2/L5 feasible. | enabler | M |

Do **not** do any of the following:
- Weaken or drop comparators.
- Tune A2C on the evaluation traces.
- Promote an ablation that happened to win into the headline.
- Re-run a finished case under the same name after seeing its result. Use a new tag and a new
  README section.

---

## 2. Phased implementation plan

Each phase creates `Optimized/v11/` files: copy v10, rename `_v10` → `_v11`, and keep the
defaults reproducing v10. The equivalence test in P0.1 must pass before any experiment.

### P0 — Infrastructure (do first; about half a day)
- **P0.1 Copy v10 → v11 and add an equivalence test.**
  - Add `test_equivalence_v11.m`: with the defaults, v11 must give the same `evalPolicy`
    output as v10 for baseline, olla, fixed, multi_olla and ctxtab on 3 traces.
  - Fails → stop.
- **P0.2 Vectorise the hot paths (L8).**
  - Remove the per-user `for i = 1:N` loops in `evalPolicy`, `DeepA2C_Shared`, `txStep`
    (`estimateBLER` and `tbsFromMCSandRB` via lookup tables) and `baseCQI` (use `discretize`).
  - Acceptance: identical outputs (the P0.1 test) and ≥ 3× faster per episode.
- **P0.3 Parallel rollouts.**
  - In `DeepA2C_Shared_v11`, collect K episodes in `parfor` using the current weights, then do
    one update over the merged buffer.
  - Option `env.a2c.n_envs` (default 1 = current behaviour).
  - This also isolates crashes in workers.
- **P0.4 Validation-based model selection (L4).**
  - Every M episodes, evaluate the greedy policy on `n_val = 10` validation traces (seeds
    disjoint from both calibration (60000+) and evaluation (9000+); use 80000+). Keep the best
    checkpoint.
  - Report both the "last" and the "best-on-validation" policy (as scheme 8 and scheme 8b).
- **P0.5 Logging.**
  - Add `ACT|tag|...` (the action histogram of the greedy policy on the evaluation traces) and
    `LCURVE|tag|...` (deciles of training and validation) to `fill_stats_v11`, so a collapse is
    visible without opening the .mat files.

### P1 — Target-BLER action space (L1) — highest priority
- **Change.**
  - New `env.action_mode = 'offset' | 'target'`.
  - In `'target'` mode the action picks an OLLA target BLER from
    `env.target_set = [0.01 0.03 0.1 0.2 0.3 0.5]` for that user. OLLA steps use the user's
    target: `du_i = dd · t_i / (1 − t_i)`. Pass a per-user target vector into `txStep_v11`.
  - Decision epoch: every `env.target_epoch = 10` TTIs per user (semi-MDP). Hold the action in
    between, and accumulate the reward over the epoch.
- **Files.** `defaultEnv_v11`, `txStep_v11` (vector target), `evalPolicy_v11` (new `a2c`
  branch), `DeepA2C_Shared_v11` (epoch logic), `Bandit_v11` (arms = targets, for fairness).
- **New fair comparators.**
  - **Tuned-target OLLA** (exists).
  - **Per-class tuned target**: calibrate one target per (delay class × speed class), the same
    information as FixedPU.
  - **Contextual bandit over targets**: delay class.
- **Experiments.**
  - `T1_gp`: goodput, v10 E1 environment.
  - `T2_stale`: E2 environment.
  - `T4_deadline`: E4 environment, on-time objective.
  - 5 seeds, 300 traces. Pre-register the cases in README §v11 first.
- **Win criterion.** Unchanged (all comparators, Holm < 0.05, 90 % CI lower bound > 0).

### P2 — PPO + GAE + cell-level critic (L2)
- **Change.** `DeepPPO_Shared_v11.m` (new file; keep A2C for comparison).
  - Clipped objective (ε = 0.2), GAE λ = 0.95, 4 epochs × minibatch 256 per rollout.
  - Running mean and std normalisation of rewards and observations.
  - Value clipping and an entropy schedule with a floor (no collapse below 0.5 nats).
- **Reward.**
  - `env.reward_kind = 'cell'`: each TTI's reward is the **cell** goodput (sum over users)
    minus the reference expectation.
  - It is credited to the scheduled user's transition, with a centralised critic input: the
    user's own state plus cell summary features (mean CQI, cell NACK EMA, number of users with
    pending HARQ).
  - Keep `'oppcost'` and `'ontime'` as options.
- **Acceptance (diagnostic, not a result).**
  - On the E1 environment, the training curve is non-decreasing over the last 50 %.
  - The greedy-policy action histogram is not degenerate (no single action above 95 %).
  - Seed SD below 0.5 %.
- **Experiments.** Repeat the P1 cases with PPO (`*_ppo`).

### P3 — BC warm start + KL-regularised fine-tuning (L3)
- **Change.**
  - `env.a2c.bc_source = 'fixed' | 'ctxtab' | 'olla_tuned'`.
  - Pre-train the actor by cross-entropy on that rule's actions (target mode: its target) for
    `bc_eps` episodes.
  - Then RL with the loss term `+ β · KL(π ‖ π_BC)`, with β annealed from 1 to 0.1.
- **Reuse.** `DeepA2C_BC_v9.m` already contains the BC machinery; port it.
- **Fairness note.** The headline A2C must be **autonomous** (no BC). The BC variant is
  reported as a separate scheme, "A2C (BC + RL)". This mirrors the v8 decision
  (`bc_warm_eps = 0`) and keeps the comparison clean.

### P4 — Recurrent policy and richer history (L5)
- **Change.** `env.a2c.arch = 'mlp' | 'gru'`. GRU (64 units) over the per-user sequence; keep
  the hidden state per user across TTIs in both evaluation and training (truncated BPTT, 16 steps).
- **New features** (all gNB-side; add to `featExtra_v11`):
  - the last 8 ACK/NACK outcomes;
  - TTIs since the user was last scheduled;
  - the HARQ round;
  - CQI age (exists);
  - the OLLA offset trend.
- **Comparators.** Unchanged. If a new cue is added, give the context table the same cue
  (one-dimensional bins).
- **Experiments.** Re-test E2/E3 (`R2_stale`, `R3_cellcue`) with GRU + PPO + the target action.

### P5 — Finer actions (L6)
- `env.action_mode = 'sinr_offset'`: the action is an SINR offset in 0.5 dB steps (−4…+2 dB),
  applied before CQI quantisation.
- Optional: the NR 28-level MCS table and the BLER curves (`estimateBLER_v11` needs a new
  table; source the curves from 38.214 / the 5G Toolbox `nrDLSCHInfo` and document it).
- Comparators must use the same resolution: re-calibrate the fixed and context-table grids in
  0.5 dB steps.

### P6 — Deadline / URLLC track (L7)
- Tighter budgets (D = 2, 3, 4 TTI) and a target-reliability metric: the fraction of users
  whose on-time ratio is at least 0.99.
- Make HARQ planning matter: allow the action to choose the retransmission MCS (currently
  always the stored MCS).
- **Add the EDF (earliest-deadline-first) scheduler** as a comparator scheduler, and evaluate
  every scheme under PF and EDF. Otherwise a reviewer will say the gain is a scheduling effect.
- Experiments: `U1_D4`, `U1_D2`, `U2_mixed_EDF`.

---

## 3. Experiment protocol (unchanged from v10, required for every phase)

1. **Pre-register** in `README_v11.md`:
   - tag, environment, A2C variant;
   - the full comparator list, with any new same-information comparator;
   - primary metric, and the win criterion (all comparators, Holm < 0.05, 90 % CI lower bound > 0);
   - the number of cases tested so far (for multiplicity).
2. **Seeds, traces and splits.**
   - 5 seeds (10 if the seed SD exceeds 1 %), 300 evaluation traces.
   - Calibration traces 60000+, validation 80000+, evaluation 9000+.
   - Common random numbers.
3. **Tags.**
   - Never reuse a tag.
   - A finished case is only re-run as a new tag with a "declared deviation" note (as v10b).
4. **Reporting.**
   - Every case is reported.
   - Ablations stay ablations.
   - Report the total case count with any win (Bonferroni across cases as a sensitivity check).
5. **Before launching a campaign**, run a 2-episode preflight of every case
   (`fill_v11_preflight.m`) and the P0.1 equivalence test.

---

## 4. Suggested order and time budget

| Step | Work | Wall-clock run |
|---|---|---|
| 1 | P0.1–P0.5 infrastructure and tests | — (about 3–4 h of coding) |
| 2 | P1 target action + comparators; preflight; campaign `T1/T2/T4` | about 2 h |
| 3 | P2 PPO; diagnostic acceptance on E1; campaign `*_ppo` | about 3 h |
| 4 | P4 GRU + history on E2/E3 (only if P1/P2 still show no goodput win) | about 3 h |
| 5 | P6 URLLC / EDF track (extends the existing deadline win) | about 2 h |
| 6 | P3 BC + RL variant, as a secondary scheme | about 1 h |
| 7 | P5 finer actions | optional |

Stop rule: if after steps 2–4 the goodput cases still give no win, write the paper around the
deadline result plus the negative and methodological findings (1000× bug, slot-stealing reward,
strength of calibrated baselines). That paper is honest and publishable.

---

## 5. Prompt to start Claude Code with

> Read `Optimized/v10/IMPLEMENTATION_PLAN_v11.md` and `Optimized/v10/README_v10.md`. Create
> `Optimized/v11` as a copy of v10 with `_v10` renamed to `_v11`. Implement phase P0 (P0.1–P0.5)
> and run `test_equivalence_v11.m` headless with `matlab -batch`. Do not start any experiment
> campaign until the equivalence test passes and I approve the README_v11 pre-registration.
