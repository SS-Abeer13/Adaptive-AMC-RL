# RL-AMC v17 — Release Package

This package reproduces the v17 core benchmark for the RL-AMC paper: a frozen, single-version campaign evaluating Deep A2C link adaptation under transmission-time Proportional Fair scheduling (`env.pf_avg = 'scheduled'`), end-of-trace feedback drain (`env.drain = true`), and packet-capped goodput accounting (`env.useful_bits = true`).

`README_v17.md` and `PLAN_v17.md` in this package are the governing pre-registration, verification, and results documents.

## Requirements

- **MATLAB R2023a** (developed and tested on R2023a; Windows 64-bit).
- **Deep Learning Toolbox** — required (`dlnetwork`, `dlfeval`, `adamupdate` for training and inference in `DeepA2C_Shared_v17.m`).
- **Statistics and Machine Learning Toolbox** — required (`signrank` for Wilcoxon signed-rank test, `tinv` for confidence intervals, `prctile` for 5th-percentile cell-edge throughput).
- **Parallel Computing Toolbox** — recommended for multi-seed parallel training across local CPU workers (`n_workers = 2` recommended to keep RAM within 4 GB).
- No 5G, LTE, or Communications Toolbox functions are required.

## Package Structure

```
release/
  README_release.md        -- this file
  PLAN_v17.md              -- governing plan and pre-registered hypotheses
  README_v17.md            -- pre-registration (S1-5) and full campaign results (S6)
  case_registry.csv        -- project-wide registry (90 rows) tracking multiplicity and validity
  code/                    -- self-contained MATLAB source scripts and runner batch files
  dataset/
    fill_summary_v17.txt   -- master execution log with per-scheme CONFIG/PRIM/SCHEME/CMP/WIN lines
    results_v17_<tag>.txt  -- per-case detailed human-readable summary files
  paper/
    table_core.csv         -- 72 comparative evaluations (margins, CIs, Wilcoxon/Holm p-values, Jain, Edge5)
    table_harq_ablation.csv-- margin swings between RTT 8 and RTT 0 across all comparative rules
    table_training_length.csv-- 800-episode vs 3,000-episode sample-efficiency analysis
    headroom.csv           -- genie and hindsight reference bounds on evaluation traces
    figures/               -- publication bar charts, margin vs RTT curves, and action histograms (PNG & PDF)
```

## Reproducing the Results

All commands can be executed from within `code/` headless via `matlab -batch`:

1. **Run Full Campaign:**
   ```bash
   run_v17_headless.bat
   ```
   Or inside MATLAB:
   ```matlab
   fill_v17_campaign
   ```
2. **Generate Publication Tables:**
   ```matlab
   build_v17_tables
   ```
3. **Generate Publication Figures:**
   ```matlab
   generate_v17_figures
   ```
4. **Run Headroom Bounds:**
   ```matlab
   headroom_v17
   ```
5. **Run Verification Test Suite:**
   - `test_equivalence_v17` (bit-level reproduction of v16 under defaults)
   - `test_pf_update_v17` (unit test of scheduled PF EMA rate averaging)
   - `test_engine_consistency_v17` (0.000% gap between legacy RTT 0 and new RTT 1 engines)
   - `test_fairness_sanity_v17` (symmetry between RTT 8 and RTT 0 under scheduled PF)
   - `test_parfor_seeds` (bit-identical training between serial and parallel workers)
