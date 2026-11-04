# RL-AMC v16 — Release Package

This package reproduces the v16 core benchmark for the RL-AMC paper: a frozen, single-version
re-run of the goodput/deadline × RTT0/RTT8 × 800/3000-episode grid described in `README_v16.md`.
`README_v16.md` and `PLAN_v16.md` in this package are the pre-registration and results documents
(read those first — this file only covers how to reproduce them).

## Requirements

- **MATLAB R2023a** (the version this code was developed and run on; not tested on other
  releases).
- **Deep Learning Toolbox** — required. `DeepA2C_Shared_v16.m`, `DeepGRU_Shared_v16.m`,
  `DeepPPO_Shared_v16.m` and `evalPolicy_v16.m` use `dlnetwork`, `dlarray`, `dlfeval`,
  `adamupdate` and (GRU scheme only) `gruLayer`.
- **Statistics and Machine Learning Toolbox** — required. `signrank` (Wilcoxon), `tinv` (CI),
  `prctile` (5th-percentile cell-edge throughput) are used in `runComparison_v16.m`,
  `analyze_v16_replication.m`, `fill_stats_v16.m`, `Bandit_v16.m`, `generateChannel_v16.m`,
  `shaping_pair_v16.m`.
- **Parallel Computing Toolbox** — optional. `DeepA2C_Shared_v16.m` uses `parfor` for the
  multi-environment rollout path (`env.a2c.n_envs > 1`, not used by any of the C2 cases in this
  release — all run with the default single-environment path); without the toolbox, `parfor`
  degrades to a plain `for` loop and the code still runs, just serially.
- No 5G, LTE or Communications Toolbox functions are used anywhere in this code (checked by
  grepping for `nr*`/`lte*`/`comm.*` call patterns across every file in `code/`).

## What's in this package

```
release/
  README_release.md       -- this file
  PLAN_v16.md              -- the governing plan (Stages A-E)
  README_v16.md            -- pre-registration (S1-5) and results (S6)
  case_registry.csv        -- every case across v10-v16 (78 rows); v16's 20 rows are tagged
                              version=v16
  code/                    -- every .m/.bat file needed to reproduce the campaign (see below)
  dataset/
    fill_summary_v16.txt   -- the full campaign log: CONFIG/CALIB/PRIM/SCHEME/SEEDS/TRAIN/
                              LATECREDIT/ACT/CMP/WIN/REPLCMP/REPLSEED/REPL lines for every
                              case and scheme
    results_v16_<case>.txt -- the per-case human-readable report (one per C2 case)
  paper/
    table_core.csv            -- every (case, scheme, comparator) margin/CI/p-value/Holm/beats
    table_harq_ablation.csv   -- K1-vs-K2 and K3-vs-K4 (RTT8 minus RTT0) margin swings
    table_training_length.csv -- K1-vs-L1 and K3-vs-L3 (800ep vs 3000ep), with the C5 verdict
    headroom.csv               -- genie/hindsight reference bounds per case, on the evaluation
                                  traces
    figures/                   -- bars_<case>.png/.pdf, margin_vs_rtt.png/.pdf,
                                  acthist_<case>.png/.pdf
```

`code/` is self-contained for every file this release actually needs: it includes the three v5
scheduler helpers (`sampleSched_v5.m`, `schedContext_v5.m`, `schedule_users_v5.m`) that
`DeepA2C_Shared_v16.m`/`DeepGRU_Shared_v16.m`/`DeepPPO_Shared_v16.m`/`evalPolicy_v16.m`/
`schedule_users_v16.m`/`Bandit_v16.m` call directly (confirmed by grep — nothing else from `v5`,
`v7` or `case2_3` is actually invoked, even though `runComparison_v16.m` and several test files
`addpath` those three sibling folders defensively; that `addpath` is a no-op here). **One
exception**: `test_equivalence_v16.m` checks v16 against v15 bit-for-bit and needs the full
`Optimized/v15` directory from the original repository, not included in this release (it is a
cross-version regression test, not part of reproducing v16's own results).

## Reproducing the tables and figures

All from inside `code/`, headless (`matlab -batch "run('<script>')"`), or interactively:

1. **Run a case**: `v16_setup` (sets up paths and the base/`C` structs for all 6 cases), then
   `o = base; ov = C.K1_dl_rtt8; fn = fieldnames(ov); for k=1:numel(fn), o.(fn{k})=ov.(fn{k}); end;
   o.save_tag = 'K1_dl_rtt8'; runComparison_v16(o);` — or just run `fill_v16_campaign` to run all
   6 cases in the pre-registered order (K1→K3→K2→K4→L1→L3), writing
   `Dataset/results_v16_<tag>.mat`/`.txt` and appending to `Dataset/fill_summary_v16.txt`. This
   is resumable: it skips any case already marked `STEP|<tag>|done` in the summary file, and
   reloads per-seed checkpoints from `Dataset/ckpt/` (this release ships the logs, not the
   checkpoints or the `.mat` results, which are large and regenerate deterministically from the
   seeds below).
2. **table_core / table_harq_ablation / table_training_length**: run `build_v16_tables` (parses
   `Dataset/fill_summary_v16.txt`'s `REPLCMP`/`REPL` lines — no re-simulation).
3. **headroom.csv**: run `headroom_v16` (re-evaluates Fixed/genie/hindsight on each case's own
   evaluation traces — this does re-run simulation, ~2-4 minutes per case).
4. **Figures**: run `generate_v16_figures` (loads the `.mat` result files from step 1, so step 1
   must have produced them first).
5. **Full B3 test suite** (equivalence, timing, conservation, process-limit, delayed-credit,
   residual-goodput sanity): each `test_*_v16.m` file runs standalone.

Running the full campaign takes on the order of **1-2 days of wall time** on the reference
machine (see `README_v16.md` S5.6 for the preflight-based estimate, ~71h as a conservative upper
bound, and S6.1 for what the actual run took in practice, including why it ran far longer in wall
time than in real compute due to unrelated environment interruptions).

## Seed ranges (C2, `README_v16.md` S4)

All seed and trace ranges are fresh and disjoint from v9-v15 and from each other.

| Case | `base_seed` | `trace_seed_base` | `crn_seed_base` | A2C-resid training seeds | A2C-offset/PPO training seeds | Eval traces |
|---|---|---|---|---|---|---|
| K1_dl_rtt8 | 14042 | 400000 | 410000 | `base_seed+200+[1..10]` | `base_seed+300/1000+[1..5]` | 400001-400500 |
| K2_dl_rtt0 | 15042 | 420000 | 430000 | `base_seed+200+[1..10]` | `base_seed+300/1000+[1..5]` | 420001-420500 |
| K3_gp_rtt8 | 16042 | 440000 | 450000 | `base_seed+200+[1..10]` | `base_seed+300/1000+[1..5]` | 440001-440500 |
| K4_gp_rtt0 | 17042 | 460000 | 470000 | `base_seed+200+[1..10]` | `base_seed+300/1000+[1..5]` | 460001-460500 |
| L1_dl_rtt8_long | 18042 | 480000 | 485000 | `base_seed+200+[1..5]` | — (A2C-resid only) | 480001-480300 |
| L3_gp_rtt8_long | 19042 | 490000 | 495000 | `base_seed+200+[1..5]` | — (A2C-resid only) | 490001-490300 |

Bandit comparators use `base_seed+400+[1..n_seeds]` (global) and `base_seed+600+[1..n_seeds]`
(delay-class) in every case. Evaluation-phase RNG draws are seeded per `(trace, scheme, seed)` as
`77000 + 100*trace + 10*scheme_index + seed` inside `runComparison_v16.m` — deterministic given
the scheme ordering printed at the top of each case's run.

## Known deviations from the C1-C2 pre-registration (see `README_v16.md` S3 for full detail)

- **PPO runs in offset-action mode**, not resid, in every case (`DeepPPO_Shared_v15` had no resid
  support; porting it was judged out of scope — see S3.1). PPO's RTT/HARQ physics *were* ported,
  so its RTT8 results are still physically correct.
- **A2C-offset and PPO train at the same seed count as A2C-resid's cap but are pre-registered at
  a smaller count (5 vs 10)** — this release's `v16_setup.m` sets `n_seeds_ppo` /
  `n_seeds_a2c_offset` to 5, matching C2 exactly (an earlier draft of this campaign ran all three
  at 10 seeds; that deviation was corrected before the results in this package were produced —
  see `README_v16.md` S3.3).

## Portability note

Several scripts (`v16_setup.m`, `run_v16_resume.m`, `headroom_v16.m`, `build_v16_tables.m`,
`generate_v16_figures.m`, every `test_*_v16.m`) hardcode the absolute path
`D:\Adaptive AMC A2C+QL` as `root`. This matches every prior version in this project (v9-v15) and
was not changed for this release. To run this package from a different location, edit that one
`root = '...'` line in each script you intend to run.

## License

See `LICENSE` in this directory (placeholder — the project maintainer has not yet chosen a
license; do not treat this code as licensed for reuse until that file is filled in).

## Publishing

This release package is prepared for the project maintainer's own use in assembling the paper. No
part of it has been published (e.g. to GitHub or Zenodo) by this process — that decision, and the
DOI/hosting arrangement if any, is the maintainer's to make per `PLAN_v16.md` Stage E.
