# v12 — independent replication of the deadline result (pre-registration)

**Status: DRAFT, written 22 Oct 2026 before any v12 code was run. It must be approved before the
campaign is launched.** Once approved, nothing in sections 1–5 changes. Results are appended
in section 7.

## 1. What is being replicated
v10 `E4c_deadline` (300 traces) met the v10 win criterion. A re-analysis on 22 Oct
(`claude/amc_v11_status_2026-10-22.md`) showed two weaknesses:

1. 100 of its 300 evaluation traces were the traces of the original E4, which motivated the
   follow-up.
2. On the 200 fresh traces alone, A2C beats the OLLA family (+1.5–1.8 %) but not all
   calibrated rules: vs FixedPU +0.45 % (Holm 0.087), vs the context table +0.62 % (Holm 0.11).

Including v11, about 15 cases have been tested in total and 1 passed. v12 tests the deadline
result once more, on data that has never been used, with the recipe fixed in advance.

## 2. Recipe (identical to E4c; anything not listed is unchanged)
- **Environment:** v10/v11 `E4_deadline`.
  - 10 users, PF; 12 kbit packets every 20 TTI with a 10-TTI budget.
  - Outdoor users (O2I 0 dB); Tier O state plus the `slack` cue.
- **A2C:**
  - offset action (−4…+2) with `reward_kind = 'ontime'`;
  - 800 episodes; hyper-parameters from `base.a2c`;
  - `bc_warm_eps = 0`; validation-based selection **off** (`a2c.val_every = 0`).
  - The reported policy is the last policy of each seed, averaged over seeds per trace.
- **Comparators** (all calibrated on the calibration traces 60000+, which are the same as in v10):
  Baseline, OLLA, OLLA (tuned target), Multi-OLLA, Fixed, FixedPU (Oracle), Context table,
  Bandit (global), Bandit (delay class).
- **Code:** v12 = the v11 core, renamed. With defaults it is bit-exact with v11 (equivalence
  test). Two additions, both inactive for the primary case:
  - `crn_seed_base`, which only changes which outcome draws are used;
  - the `'edf'` scheduler.

## 3. Cases, seeds and decision rules

| Tag | Role | Scheduler | Training seeds | Evaluation traces | CRN draws |
|---|---|---|---|---|---|
| `R1_pf` | **primary** | PF (as E4c) | 10: base_seed 1042 → 1243–1252 (v10: 243–247) | 500: 20001–20500 (v10: 9001–9300) | 30001–30500 (v10: 50001+) |
| `R2_edf` | secondary | EDF for calibration, training and evaluation | 5: base_seed 2042 | 300: 21001–21300 | 31001–31300 |

**The test.** "A2C beats X" means two things hold:
- the Holm-adjusted two-sided Wilcoxon signed-rank p < 0.05, Holm over all 9 non-RL comparators;
- the 90 % CI lower bound of the mean paired per-trace difference is > 0.

**Decision rules for `R1_pf`** (computed by `analyze_v12_replication.m`):
- **Claim A (OLLA family):** A2C beats OLLA, OLLA (tuned target) **and** Multi-OLLA.
- **Claim B (calibrated rules):** A2C beats Fixed, FixedPU (Oracle) **and** the context table.
- **WIN:** A2C beats all 9 (the v10 criterion).

`R2_edf` is reported with the same three rules. It answers the question "does the gain
survive a deadline-aware scheduler?" and does not change the primary verdict.

## 4. What each outcome lets the paper say (fixed now)

| R1_pf outcome | Wording allowed |
|---|---|
| Claim A and B pass | "In an independent pre-registered replication (500 fresh traces, 10 fresh seeds), deadline-aware A2C beat every comparator, including calibrated fixed-offset rules (+x %)." |
| Claim A passes, B fails | "A2C reliably beats OLLA and tuned-target OLLA on on-time delivery (+x %) but only matches calibrated fixed-offset rules; the earlier win over those rules did not replicate." |
| Claim A fails | "The deadline gain did not replicate." The paper becomes a negative and methodological result. |

The R2_edf result is added as one sentence: either the gain also holds under EDF, or it is
specific to PF.

## 5. Power (planning note, not a decision rule)
On the 200 fresh E4c traces the standard error of the A2C − FixedPU difference was about
0.22 %. With 500 traces it is about 0.14 %, so a true +0.45 % effect gives z ≈ 3.2. Holm over
9 comparisons needs roughly z ≥ 2.8 for the smallest p, so the expected power is about 70 % for
Claim B. Ten seeds instead of five also reduce the policy (seed) variance. Claim A (effect
about +1.5–1.8 %, z > 8) is expected to pass. **A failure of Claim B is a plausible and
reportable outcome.**

## 6. Multiplicity
v12 adds 2 cases (1 primary, 1 secondary) to the running count, about 17 in total. The primary
claim is a confirmatory test of one pre-specified hypothesis on new data. It is reported
together with the total count and with the exploratory history (v10 E4 → E4c).

## 7. Results

### Pre-run checks (22 Oct 2026) -- T1-T5 of PLAN_v12_replication.md
- **T1** (core copy): all 36 listed files copied from `Optimized/v11/`, renamed
  `_v11`->`_v12` in filenames and contents, including the `Deep A2C/PPO/GRU v11` ->
  `v12` scheme-name strings. `runComparison_v12` writes `results_v12_<tag>.mat`
  (confirmed in its save line).
- **T2** (`crn_seed_base`): added (`g('crn_seed_base', 50000)`, default unchanged
  from v11's hardcoded `50000`); `base_seed`/`trace_seed_base`/`crn_seed_base` are
  now stored on `env` and logged in both the `CONFIG|` and `V12ENV|` lines.
- **T3** (EDF plumbing): `schedule_users_v5` calls in `evalPolicy_v12.m` (1),
  `DeepA2C_Shared_v12.m` (2: main loop + the `n_envs>1` `rollout_episode_v12`
  path) and `Bandit_v12.m` (1) replaced with `schedule_users_v12(..., dlv)` as
  specified. `sampleSched_v5`/`schedContext_v5` (shared, unedited) are already
  generic over `env.sched_list`/`env.train_schedulers`, so `'edf'` needed no
  `v12_setup` adaptation. `DeepPPO_Shared_v12`/`DeepGRU_Shared_v12` left on the
  plain `schedule_users_v5` path, as instructed (not used by v12's two cases).
- **T4** (`fill_stats_v12` scheduler index): added optional 4th arg `si` (default
  1), `M = r.metrics(si)`, `sched=<name>` added to both `CONFIG|` and `V12ENV|`.
- **T5 tests** (all headless, `matlab -batch`):
  1. `test_equivalence_v12.m` -- **PASS**. The file as copied compared v12
     against **v10** (the literal `v10`->`v11` substring rename left the v10
     reference untouched); fixed to compare against **v11** per the task
     (`logs/test_equivalence_v12.log`): baseline/olla/fixed/multi_olla/ctxtab
     bit-exact on 3 traces, plus a 5-episode A2C training run bit-exact.
  2. `test_edf_v12.m` -- **PASS**, `logs/test_edf_v12.log` shows `TEST_EDF_OK`.
  3. Recipe check -- **PASS**. `runComparison_v11` and `runComparison_v12` run
     on identical options (v11's `E4_deadline`, `n_eval=20`, `n_seeds=1`,
     `ep_deep=20`, default `crn_seed_base`/PF/no EDF): every scheme's
     `cell_tp`/`primary` arrays and the learning curves matched with `max(abs(diff)) = 0`
     for all 11 schemes (temporary check script, not committed).
  4. `run_v12_preflight.bat` -- **PASS**. `logs/fill_v12_preflight.txt` shows
     `PREFLIGHT_R1_pf_OK` and `PREFLIGHT_R2_edf_OK`; `REPLCMP`/`REPLSEED`/`REPL`
     lines parse for both, `R1_pf` under `sched=pf` and `R2_edf` under `sched=edf`
     as expected.

No deviations from the provided files beyond the `test_equivalence_v12.m`
reference fix above (needed to satisfy T5.1's literal requirement).

**Estimated run time** (per `PLAN_v12_replication.md`): about 2.5 h total
(`R1_pf`: ~45 min training + ~35-45 min evaluation at 10 seeds/500 traces;
`R2_edf`: ~25 min + ~25 min at 5 seeds/300 traces). Machine must stay awake;
`run_v12_headless.bat` auto-restarts after a native MATLAB crash and reloads
finished seeds from `Dataset/ckpt/`.

**Approved and run 22 Oct 2026, 124.3 min total.**

### Run outcome

| Tag | n_traces | A2C | Claim A (OLLA family) | Claim B (calibrated rules) | WIN (all 9) |
|---|---|---|---|---|---|
| `R1_pf` (primary) | 500 | 0.8421 | **PASS** | **FAIL** | FAIL |
| `R2_edf` (secondary) | 300 | 0.8717 | **PASS** | FAIL (by one comparator) | FAIL |

**`R1_pf` — REPLCMP** (A2C vs. each comparator; `beats` = Holm p<0.05 and 90% CI lower bound > 0):

| vs. | pct | Holm p | beats |
|---|---|---|---|
| Baseline | +3.31% | 2.3e-40 | 1 |
| OLLA | +0.96% | 3.4e-08 | 1 |
| OLLA (tuned target) | +0.93% | 5.8e-08 | 1 |
| Multi-OLLA | +1.03% | 1.6e-08 | 1 |
| Fixed | **-0.47%** | 2.8e-04 | **0 (A2C loses, significant)** |
| FixedPU (Oracle) | **-0.34%** | 0.0119 | **0 (A2C loses, significant)** |
| Context table | +0.09% | 0.906 | 0 (tie, n.s.) |
| Bandit (global) | +11.90% | 7.1e-81 | 1 |
| Bandit (delay class) | +11.59% | 4.0e-81 | 1 |

Seed consistency: 6/10 seed means exceed the best calibrated rule (Fixed,
0.8461); seed means range 0.8053-0.8541 (`REPLSEED`).

**`R2_edf` — REPLCMP:** same pattern, but **stronger** -- A2C now also beats
Fixed (+0.28%, Holm 1.8e-04) and the context table (+0.48%, Holm 0.032); it
only ties FixedPU (Oracle) (+0.09%, Holm 0.712, not significant). 7 of 9
comparators beaten, vs. 6 of 9 under PF.

### Outcome row (section 4)
**"Claim A passes, B fails"**: *"A2C reliably beats OLLA and tuned-target
OLLA on on-time delivery (+0.9-1.0% under PF, +1.7-1.8% under EDF) but only
matches calibrated fixed-offset rules; the earlier win over those rules did
not replicate."* Under PF, "matches" is generous -- A2C significantly
**loses** to Fixed (-0.47%) and FixedPU (-0.34%), it does not merely tie
them. Under EDF, A2C beats Fixed and the context table and only ties
FixedPU -- the deadline-aware scheduler does not just preserve the gain,
it is the one condition under which Claim B's lone holdout is a tie rather
than a loss.

**R2_edf one-sentence addition (section 4):** the gain is **not** specific
to PF -- the OLLA-family margin replicates under EDF too, and is in fact
larger, with fewer calibrated rules outscoring A2C.

### Restarts and deviations
- `logs/restarts_v12.txt`: 2 entries (1 initial start + 1 restart after a
  native heap-corruption crash, `0xc0000374`, during `R1_pf` -- the same
  known MATLAB instability noted in `IMPLEMENTATION_PLAN_v11.md`; the
  `.bat`'s auto-restart recovered it, no seed was lost).
- No deviation from this document's sections 1-5 or from the provided v12
  files beyond the `test_equivalence_v12.m` reference fix already logged
  above (T5.1).

### Multiplicity
v12 adds its 2 pre-registered cases as planned (section 6): about 17 cases
tested in total across the project, 1 pass before v12 (v10 E4c) plus this
replication's Claim A (not the full WIN criterion). Per the plan's T7
instruction, no further run, re-tag or re-tune follows this result;
anything further needs a new pre-registration.
