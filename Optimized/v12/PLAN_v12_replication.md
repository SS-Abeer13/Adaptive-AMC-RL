# v12 replication — implementation plan for Claude Code

Written 22 Oct 2026. Goal: test, once and on data never used before, whether the v10 deadline
result (A2C beats every comparator on on-time delivery) replicates. The pre-registration is
`README_v12.md` in this folder; read it first. **Do not change its sections 1–5.**

Files already in `Optimized/v12/` (written for you; adapt only if an interface differs, and
say so in README_v12 §7):

| File | Purpose |
|---|---|
| `README_v12.md` | pre-registration (draft, needs user approval) |
| `v12_setup.m` | paths, `base` (identical to v11), cases `C.R1_pf` and `C.R2_edf` |
| `schedule_users_v12.m` | v5 allocator plus `'edf'` |
| `test_edf_v12.m` | unit test for the EDF allocator |
| `analyze_v12_replication.m` | pre-registered decision rules → `REPLCMP` / `REPLSEED` / `REPL` lines |
| `fill_v12_campaign.m`, `fill_v12_preflight.m` | campaign and 2-episode preflight |
| `run_v12_headless.bat`, `run_v12_resume.m`, `run_v12_preflight.bat` | headless launchers (auto-restart) |

---

## Tasks

### T1 — Create the v12 core from v11 (do not overwrite the files above)
Copy these v11 files into `Optimized/v12/`, renaming `_v11` → `_v12` in file names **and**
contents, and `A2C v11` / `PPO v11` / `GRU v11` → `… v12`:

`Bandit, baseCQI, calibrateCtx, calibrateFixedClass, calibrateTargetClass, cqiAge,
cqiFeedback, ctxBin, cueBin, cueVal, DeepA2C_Shared, DeepGRU_Shared, DeepPPO_Shared,
defaultEnv, estimateBLER, evalPolicy, featExtra, fill_stats, generateChannel, harqInit,
holmAdjust, metricMean, MultiOLLA, nCtxBins, nExtra, runComparison, slackOf, stateFeat,
tbsFromMCSandRB, trafficInit, trafficPost, trafficPre, txStep, userClass, userDeadline,
userMetric, test_equivalence`

Do **not** copy v11's `fill_*`, `run_*`, `v11_setup`, `v11b_check` or `README_v11`.
Make sure `results_v12_<tag>.mat` is written by `runComparison_v12` (check its save line).

### T2 — `crn_seed_base` option
- In `runComparison_v12`, replace `rng(50000 + j); traces(j).U = rand(...)` with
  `rng(crnBase + j)`, where `crnBase = g('crn_seed_base', 50000)`. The default keeps v11 behaviour.
- Record `crn_seed_base`, `trace_seed_base` and `base_seed` in the `V12ENV|` / `CONFIG|`
  line of `fill_stats_v12`. The replication must be checkable from the log alone.

### T3 — EDF scheduler plumbing
- Replace every `schedule_users_v5(...)` call in `evalPolicy_v12`, `DeepA2C_Shared_v12` and
  `Bandit_v12` with:
  ```matlab
  dlv = inf(1, N); dlv(Q.has) = Q.dl(Q.has);
  rb = schedule_users_v12(<mode>, t, N, R_emas, pot, env.total_RB, dlv);
  ```
  Use the same variable that holds the traffic state in each file. For full-buffer traffic,
  `Q.dl` is irrelevant and EDF falls back to PF.
- `R2_edf` sets `sched_list` and `train_schedulers` to include `'edf'`, with
  `train_sched_weights = [0 0 0 1]`. Check that:
  - `sampleSched_v5` can return `'edf'` with these fields. If it reads a different field, adapt
    `v12_setup` and note it.
  - `schedContext_v5` builds a 4-wide one-hot. The state dimension then grows by 1 for R2_edf
    only; R1_pf keeps the 3-scheduler list.
  - The calibration functions use `env.calib_sched` (= `eval_schedulers{1}` = `'edf'` for R2_edf).
- `DeepPPO_Shared_v12` and `DeepGRU_Shared_v12` are not used in v12. Leave them unchanged,
  but make sure they still run with defaults (the equivalence test).

### T4 — `fill_stats_v12(matFile, tag, fid, si)`
Add an optional 4th argument `si` (scheduler index, default 1): `M = r.metrics(si)`, and add
`sched=<name>` to the `CONFIG` / `V12ENV` line. Nothing else changes.

### T5 — Tests (all must pass before T6)
1. `test_equivalence_v12.m`: with defaults, v12 is bit-exact with **v11** on the same cases
   as the v11 test (baseline / olla / fixed / multi_olla / ctxtab on 3 traces, plus a
   5-episode A2C training run).
2. `test_edf_v12.m` → `logs/test_edf_v12.log` shows `TEST_EDF_OK`.
3. **Recipe check.** Run `runComparison_v12` with v11's `C.E4_deadline` options and
   `n_eval = 20`, `n_seeds = 1`, `ep_deep = 20`. It must reproduce the corresponding v11 run
   with the same options bit for bit. (Run it on v11 too; the default `crn_seed_base`, PF and
   no EDF.)
4. `run_v12_preflight.bat` → `logs/fill_v12_preflight.txt` shows `PREFLIGHT_R1_pf_OK` and
   `PREFLIGHT_R2_edf_OK`, and the `REPL|` lines parse.

Log each result under README_v12 §7 under "Pre-run checks".

### T6 — Stop and ask for approval
Show the user:
- the README_v12 sections 1–5, unchanged;
- the test results;
- the estimated run time.

Launch `run_v12_headless.bat` only after the user explicitly approves.

### T7 — After the run
- Append to README_v12 §7:
  - the `REPL` lines for both tags, with the `REPLCMP` and `REPLSEED` lines;
  - which row of the §4 table applies;
  - the restart count (`logs/restarts_v12.txt`) and any deviation.
- Do not re-run, retune or re-tag anything after seeing results. Any further experiment needs
  a new pre-registration section and a new tag.

---

## Expected run time
The v11 timing is about 260 s per seed (A2C plus 2 bandits, 800 episodes).
- **R1_pf:** about 45 min of training (10 seeds) and about 35–45 min of evaluation (500 traces).
- **R2_edf:** about 25 min training and about 25 min evaluation.
- **Total:** about 2.5 h. The PC must stay awake; the launcher restarts after native MATLAB
  crashes, and finished seeds are reloaded from `Dataset/ckpt/`.

## Prompt to give Claude Code
> Read `Optimized/v12/PLAN_v12_replication.md` and `Optimized/v12/README_v12.md`. Do tasks
> T1–T5 exactly as written, without changing README_v12 sections 1–5 or the provided v12 scripts
> unless an interface requires it (record any such change in README_v12 §7). Run all tests
> headless with `matlab -batch`. Then stop at T6 and show me the results before launching anything.
