# v17x runner: headless batch for the Checkpoint-5 stages

Runs, in the approved order (Checkpoint 5b), **G1 → W1 → NR1 → G6a → (report point) → G6b → G6c → G10 → A1 → A3 → A6** with automatic restart, per-stage and per-unit checkpoints, a heartbeat log, the 20-trace preflight with the 1.5× pause rule, 2 parfor workers, and an **error marker instead of a "finished" line** whenever anything fails.

The scientific content of every stage is **frozen** in `paper/proposals/` (`common_rules.md`, `G6_…`, `W1_…`, `NR1_…`, `G10_…`, `A6_…`, `checkpoint5_list.md`, `AMENDMENTS.md`). Freeze commits and file hashes: `paper/STATUS.md`, `paper/proposals/FREEZE.sha256`. This folder contains only the orchestration.

## What was tested and what was not
- **Tested (4 Nov 2026, GNU Octave 8, in the cloud container):** the orchestration logic of `run_v17x_all.m`, `v17x_unit.m`, `v17x_hb.m`, `v17x_status.m`, driven by a bash loop that copies the batch file's restart rules. Self-tests 1–3 pass: restart after a crash with completed stages and units skipped; two failures → `HALTED.marker`, `ERROR_<stage>.txt` and no "FINISHED" anywhere; a measured rate above 1.5× the basis → pause (exit 3), and continuation after `APPROVE_<stage>.txt`.
- **Not tested:** `run_v17x_all.bat` itself (no Windows here), MATLAB-only features (`parpool`, `getReport`, `-batch` exit codes), and `stage_g1.m` / `stage_g1_preflight.m` (they parse, but need MATLAB and the v17 results). **Run the self-test on your PC first (step 0 below).**
- **Not implemented yet:** stages `w1, nr1, g6a, g6b, g6c, g10, a1, a3, a6` are stubs that halt with "not implemented". Claude Code implements them from the frozen specs (master prompt below).

## Files
| File | Role |
|---|---|
| `run_v17x_all.bat` | Restart loop (CRLF). Exit 0 finished · 2 halted · 3 paused · 4 gave up · 5 unexpected |
| `run_v17x_all.m` | Orchestrator: preflight, pause rule, error handling, markers, status |
| `v17x_cfg.m` | Configuration from environment variables |
| `v17x_hb.m`, `v17x_unit.m`, `v17x_status.m`, `v17x_reset.m` | Heartbeat; atomic per-unit checkpoint; `STATUS.txt`; clear an error state |
| `stage_g1.m`, `stage_g1_preflight.m` | G1 (wraps `Optimized/v17/g1/g1_recut_v17.m`; done only if EQUIV = 1 and REPRO = 0 for both cases) |
| `stage_<id>.m`, `stage_<id>_preflight.m` | One pair per stage (stubs for all except G1) |
| `stage_st_*.m` | Self-test stages |

## Environment variables (set before the batch, or edit the defaults in the .bat)
`MATLAB_EXE` · `STAGES` (comma list, default all) · `N_WORKERS` (default **2**) · `G6B_PROFILE` (`full`, decided; `lite` is defined but not used) · `G10_CELLS` (default `G2_hi_d10,G3_lo_d18`; the other two corners are future work and are dropped if requested) · `V17X_SELFTEST` (1, 2, 3) · `V17X_SMOKE` (1 = tiny sizes, separate `Dataset_smoke`).

## Files written (in `Dataset\`)
| File | Meaning |
|---|---|
| `STATUS.txt` | One line per stage: done / pending / ERROR / PAUSED; first line `FINISHED` only if every requested stage is done |
| `stage_<id>.done` | Stage completed (timestamp, elapsed) |
| `ckpt\<stage>\<unit>.mat` | Completed unit (atomic write); reused after a restart |
| `PREFLIGHT_<id>.txt` | Measured seconds per unit, basis, ratio, projected hours |
| `REPORT_<id>.txt` | Descriptive report written after a stage (R9); the pipeline does not wait for it and it cannot change any pre-registered choice |
| `PAUSED_<id>.txt` | Pause rule triggered: read it; create `APPROVE_<id>.txt` to continue |
| `ERROR_<id>.txt`, `attempts_<id>.txt` | Error text; attempt count (the stage is retried once) |
| `HALTED.marker` | A stage failed twice or is not implemented. The batch exits 2 and does not restart |
| `FINISHED_ALL.marker` | Written only when every requested stage is done and no error marker exists |
| `..\logs\heartbeat_v17x.txt` | One line per unit event and at most every 30 s from the loops |
| `..\logs\restarts_v17x.txt`, `matlab_batch_N.log` | Launch log; raw MATLAB output |

**After fixing a halted stage:** `matlab -batch "v17x_reset('w1')"` (removes the error state, keeps checkpoints and done markers), then rerun the batch.

## Stage interface (what Claude Code implements)
```matlab
function pf = stage_<id>_preflight(ctx)
% Measure on 20 traces (or 20 episodes). Return
%   struct('unit','eval'|'episode', 'sec_per_unit', measured, 'n_units_total', N, 'note', 'text')
function stage_<id>_report(ctx)     % OPTIONAL (R9): write Dataset/REPORT_<id>.txt, descriptive only
function stage_<id>(ctx)
% Do all work through ctx.unit(name, @() ...) so every unit is checkpointed.
% Call ctx.hb('...') between chunks (client only, never inside parfor).
% Throw an error on any failed check. No return value.
```
`ctx` fields: `stage, root, v17, outdir, ckptdir, logdir, n_workers (2), smoke, g6b_profile, g10_cells, hb, hbf, unit`. Unit names: letters, digits, `_`, `-`. Chunk long loops (≤ 25 traces or one sweep per unit) so a restart loses at most minutes. Under `ctx.smoke`, use tiny sizes (2 traces, 2 seeds, 2 episodes).

## Per-stage checklist (from the frozen specs)
| Stage | Spec | Units (checkpoint) | Must-pass gates (error if violated) |
|---|---|---|---|
| `w1` | W1 §§2–3, §6 | `comparators_det`, `bandit_seed_K`, `a2c_seed_K`, `ens`, `repro20`, `secondary_recal` | warm-up off reproduces stored M1 on 20 traces bit-exactly |
| `g6a` | G6 §2.2, §2.5 | `sep_grid_chunkK`, `fixedpu_joint_sweepS`, `ctx_exh_chunkK`, `olla_set_K`; writes `composite_table.csv`; **`stage_g6a_report`** | disjoint seeds asserted; exhaustive counts (9 / 343 / 30); report holds calibration-set information only |
| `g6b` | G6 §2.3, §2.4 | `start_k_sweep_s` | sanity check (objective ≥ every coarser table); SHA-256 logged before any evaluation |
| `g6c` | G6 §3–4 | `eval`, `repro`, `analysis` | refuses to run if the hash or sanity check failed; REPRO max diff = 0 |
| `nr1` | NR1 §3–4 | `calib`, `train_seed_K`, `eval` | calibrated tables equal M1's; selector bit-identical when the flag is unset |
| `g10` | G10 §2–5, §7 | per cell (G2, G3): `feas`, `calib_single_*`, `calib_comb_start_k_sweep_s`, `train_seed_K`, `bandit_*`, `eval` | disjoint seeds incl. G6 and A6 ranges |
| `a1` | `checkpoint5_list.md` prompt A1 | `peruser` | REPRO of stored `cell_tp` |
| `a3` | `checkpoint5_list.md` prompt A3 | `timing` | none |
| `a6` | `A6_pf_timing_prereg.md` §2, §6 | `equiv_test`, six `cell_*` units | `test_equivalence_v17.m` passes; disjoint seeds |

---

## MASTER PROMPT FOR CLAUDE CODE (paste on the author's PC)

> You are working in the repo `Adaptive-AMC-RL` on the author's Windows PC (MATLAB R2023a). Create and use a new branch `v17x`; never commit to `main`. Commit with the repository's configured author identity; **do not add `Co-Authored-By`, `Claude-Session` or any other AI attribution to commit messages**.
>
> **Rules (non-negotiable).**
> 1. The scientific design is frozen in `paper/proposals/common_rules.md`, `G6_calibration_budget_prereg.md`, `W1_warmup_prereg.md`, `NR1_nonoracle_residual_prereg.md`, `G10_operating_grid_prereg.md`, and `checkpoint5_list.md` (prompts A1, A3). Do **not** edit these files or any existing file under `Optimized/v17/`. Add new files only (copies with a suffix, or files in `Optimized/v17x/`). If a spec seems wrong or impossible, **or if implementing a stage would require changing anything in a frozen spec, stop and report: the change comes back to the cloud session first** (amendments are only allowed before the run that uses them starts, and are recorded in `AMENDMENTS.md`).
> 2. Every evaluator copy must pass a bit-identity test against the frozen `evalPolicy_v17.m` before use (`common_rules.md` R4). Every REPRO check must give a maximum difference of exactly 0, or the stage errors.
> 3. Use `ctx.unit` for every unit of work, call `ctx.hb` between chunks, never call it inside `parfor`, use 2 workers, and set `rng(seed,'twister')` inside every worker as the v17 code does.
> 4. Do not write a "finished" or "done" message anywhere unless the check that proves it passed.
>
> **Step 0: test the runner.** From `Optimized\v17x`: run `set V17X_SELFTEST=1 && run_v17x_all.bat` (expect exit code 0 and `FINISHED` in `Dataset_selftest\STATUS.txt`, with the crash-once stage restarted and its first unit skipped; see `logs_selftest\heartbeat_v17x.txt`). Then `V17X_SELFTEST=2` (expect exit code 2, `HALTED.marker`, no `FINISHED` anywhere), then `V17X_SELFTEST=3` (expect exit code 3 and `PAUSED_st_slow.txt`; create `APPROVE_st_slow.txt`, rerun, expect exit 0). Delete the `*_selftest` folders. Report any deviation and stop.
>
> **Step 1: G1.** If `Optimized\v17\paper\g1\g1_summary.txt` exists, show me its `EQUIV` and `REPRO` lines. The stage `g1` is skipped automatically when both cases are clean.
>
> **Step 2: implement the stages, one at a time, in the run order `w1`, `nr1`, `g6a`, `g6b`, `g6c`, `g10`, `a1`, `a3`, `a6`.** For each: write `stage_<id>.m` and `stage_<id>_preflight.m` following the interface above and the per-stage checklist; write any helper functions in `Optimized\v17x\<id>\`; run it with `set V17X_SMOKE=1 && set STAGES=<id> && run_v17x_all.bat` and show me the smoke output and the unit list; commit. Do not start a real run until I say so.
>
> **Step 3: launch.** When I confirm, run `run_v17x_all.bat` (G6 runs the `full` profile; G10 runs the two pre-registered cells; do not offer the other two). Do not change `N_WORKERS`. If the batch exits with code 3, show me `PAUSED_*.txt` and `PREFLIGHT_*.txt` and wait. If it exits with code 2, show me `HALTED.marker` and `ERROR_*.txt` and wait.
>
> **Step 4: report.** After each stage finishes (and when `REPORT_<id>.txt` appears, e.g. after `g6a`), list its output files, quote its verdict row (from the pre-registration wording table, quoting numbers without reinterpreting the rule), and commit the result files on `v17x`. Send me: `fill_summary_v17w.txt`, `table_warmup.csv`, `REPORT_*.txt`, `composite_table.csv`, `cal500_tables.txt`, `ctxj_cells.csv`, `table_cal500.csv`, `fill_summary_v17b_cal.txt`, `fill_summary_v17n.txt`, `table_nr1.csv`, `fill_summary_v17c.txt`, `base_rule_by_cell.csv`, `table_cells.csv`, `fill_summary_v17pf.txt`, `a6_pf_timing.csv`, `paper\g1\*`, `a1_peruser.mat`, the A3 timing, and `Dataset\STATUS.txt`.
