# RL-AMC v17 — Zenodo Release Package Guide

This package accompanies the publication on Deep Reinforcement Learning for Adaptive Modulation and Coding (RL-AMC) under realistic channel dynamics, Proportional Fair (PF) scheduling, and multi-process HARQ delay.

This guide provides instructions to inspect the package, understand the seed conventions, review pre-registration hashes, and reproduce each paper table strictly from stored results.

---

## 1. What's Included

```
release/
  README_release.md        -- this document
  LICENSE                  -- MIT license for open-source code and benchmark data
  PLAN_v17.md              -- governing campaign protocol and pre-registered hypotheses
  README_v17.md            -- pre-registration specification and full campaign results
  case_registry.csv        -- project-wide registry (108 rows, 67 cases, with correction column)
  reproduce_tables.py      -- standalone script strictly reproducing all 6 paper tables
  MANIFEST.sha256          -- SHA-256 checksums of every file in the release archive
  code/                    -- self-contained MATLAB source code and batch runner scripts
  dataset/                 -- master logs, human-readable summary files, and evaluation data
  paper/                   -- core CSV tables, ablation analyses, and publication figures
```

The accompanying Zenodo archive (`release_v1.zip`) additionally bundles:
- Full evaluation run `.mat` files:
  * `results_v17_M1_dl_rtt8.mat`, `results_v17_M2_dl_rtt0.mat`
  * `results_v17_M3_gp_rtt8.mat`, `results_v17_M4_gp_rtt0.mat`
- Confirmatory checkpoints and evaluation traces:
  * `ckpt/g6c/eval.mat` (G6c 500-trace rule recalibration)
  * `ckpt/nr2/eval.mat` and `ckpt/nr2/train_seed_*.mat` (NR2 confirmatory replication)
  * `ckpt/nr_g10/eval_*.mat` and `ckpt/nr_g10/train_seed_*.mat` (NR-G10 operating grid)
  * `ckpt/w1/comparators_det.mat`, `ckpt/w1/bandit_seed_*.mat`, `ckpt/w1/a2c_seed_*.mat` (W1 warm-up)
- Full instrumented headroom evaluation logs (`Dataset/hr/full/hr_log_*.mat`)
- Exported ONNX actors (`actor_m1.onnx`, `actor_nr2.onnx`)

---

## 2. Requirements & Environment

### MATLAB Requirements
- **MATLAB R2023a** (tested on Windows 64-bit and Linux x86_64).
- **Deep Learning Toolbox** — required for actor-critic training and inference (`dlnetwork`, `dlfeval`, `adamupdate`).
- **Statistics and Machine Learning Toolbox** — required for statistical testing (`signrank`, `tinv`, `prctile`).
- **Parallel Computing Toolbox** — recommended for multi-worker parallel seed training (`parfor`).
- *Note:* No 5G, LTE, or Communications Toolboxes are required.

### Python Environment
A standard Python 3.11+ environment with common scientific libraries:
```bash
pip install numpy scipy h5py scikit-learn torch sionna pytest onnxruntime
```

Two pure-Python sub-packages are included in the repository:
1. `bench/calla_stats/`: Pure-Python statistics package implementing paired margins, exact tie-adjusted Wilcoxon signed-rank tests matching MATLAB `signrank`, Holm multiplicity adjustment, and hierarchical seed×trace bootstrap. Zero MATLAB dependencies.
2. `sionna_env/`: Gymnasium single-cell 3GPP environment for multi-user AMC link adaptation with multi-process HARQ.

---

## 3. Seed Conventions

All pseudo-random number generator (RNG) seeds are strictly pre-registered and deterministic:
- **Evaluation Channel Traces:**
  * M1 / deadline traces: `rng(500000 + j)`, Common Random Numbers (CRN): `rng(510000 + j)` for $j = 1 \dots 500$.
  * M3 / full-buffer traces: `rng(540000 + j)`, CRN: `rng(550000 + j)` for $j = 1 \dots 500$.
  * Verified by reading from `results_v17_<case>.mat`.
- **Learned Policy Multi-Seed Training:**
  * 10 independent training seeds: $s = 1 \dots 10$.
  * Action decision draws: `rng(77000 + 100*j + 10*k + s)` with $k = 8$.
- **Statistical Bootstrap Seeds:**
  * Hierarchical seed×trace bootstrap: `20261104` ($B = 20,000$).
  * Seed-mean bootstrap: `20261105` ($B = 20,000$).
  * Headroom cross-validation & bootstrap: `20261111` ($B = 20,000$).

---

## 4. Reproducing Paper Tables

### All Tables (Single Master Command)
To rebuild and strictly verify all 6 tables against committed copies within pre-registered statistical tolerances:
```bash
python release/reproduce_tables.py
```
*(Executes in ~5 seconds; exits with code 0 on 100% pass, non-zero on any difference).*

### Table-by-Table Reproduction Commands

1. **Table 1 (`table_core.csv` — M1, M2, M3, M4 core comparisons; 72 rows):**
   ```bash
   python -m pytest bench/calla_stats/tests/test_reproduce_g3.py
   ```
2. **Table 2 (`table_cal500.csv` — G6c 500-trace rule recalibration):**
   ```bash
   python -m pytest bench/calla_stats/tests/test_reproduce_cal500.py
   ```
3. **Table 3 (`table_nr2.csv` — NR2 confirmatory replication of non-oracle residual A2C):**
   ```bash
   python -m pytest bench/calla_stats/tests/test_reproduce_nr2.py
   ```
4. **Table 4 (`REPORT_nr_g10.txt` — NR-G10 18-row operating grid table):**
   ```bash
   python -m pytest bench/calla_stats/tests/test_reproduce_nr_g10.py
   ```
5. **Table 5 (`table_warmup.csv` — W1 OLLA warm-up effect):**
   ```bash
   python -m pytest bench/calla_stats/tests/test_reproduce_warmup.py
   ```
6. **Table 6 (`hr_predictions.csv` — HR1 learnable myopic headroom predictions P1–P4):**
   ```bash
   python release/reproduce_tables.py
   ```
   *To re-fit GBT estimators from scratch on raw decision logs (~2–4 hours):*
   ```bash
   python paper/analysis/hr_stats.py
   ```

---

## 5. Frozen Pre-Registrations and Cryptographic Hashes

Before any evaluation run or statistical analysis, the protocol was committed and cryptographically locked. Verification command:
```bash
cd paper/proposals && sha256sum -c FREEZE.sha256
```

### Registered Hashes (`FREEZE.sha256`, Freeze v8)

| SHA-256 Checksum | File | Description |
|:---|:---|:---|
| `c629332df0eb98086d201a61505758716bfde5dbfc3dd33175d1d24bad5b8bbd` | `G6_calibration_budget_prereg.md` | Recalibration budget protocol |
| `3a69b7d023c601f8c221ca03b4ec60b67d2953c2855c23878683ddf8330f1b5d` | `W1_warmup_prereg.md` | OLLA warm-up protocol |
| `ed4e5e38faadf9ee7ecff10fa0c65367413aaa91526efec9c720d780716f0258` | `NR1_nonoracle_residual_prereg.md` | Non-oracle residual A2C protocol |
| `ceecd80b8224a21d1665b45136413ad02871d4ae5cc7f356a6af671a9419131e` | `G10_operating_grid_prereg.md` | Operating grid protocol |
| `35ffa58f563c5e184b5429acafcdbbcb4fa92f78d1ee4970c2609af4dca1a8d8` | `A6_pf_timing_prereg.md` | PF timing audit protocol |
| `f8382b866c5b51131d4185f4fe2920efabe46b6f7ed81963ec5759472fed664f` | `common_rules.md` | Common decision rules |
| `9debb4c685cf84a2af6afd787a6c84b3f95f061ccf8f0e58b80321b3b002909c` | `checkpoint5_list.md` | Pre-registered checkpoints |
| `d72e7a0f64506fe278ed319bc0bbe74d564de0cf1a27c3543311acd226fade0a` | `compute_basis.md` | Computational resource basis |
| `1210d5b17aeae883796ad369f17e7ef1ffeed404d7c317c23d7b4d97612c3e0c` | `NR2_confirmatory_prereg.md` | Confirmatory replication protocol |
| `c73b4157438f3f91397c6ba32159b494dd9e57dade0917052bca3f112656f71f` | `../analysis/nr2_stats.py` | Analysis script for NR2 |
| `bb37226469be55b434fb58600e9fce629bf6ef0d379186512116fe2e99222e08` | `NR_G10_operating_grid_prereg.md` | NR-G10 grid protocol |
| `c0c23c2735b737a9dc2e6d07959ae901e47e216a22be92382a1d69ab5a00f30b` | `AMENDMENTS.md` | Pre-registered amendments log |
| `ba7978b105408813f3f4dfb92d73f93757c64e43c30a5a40925ea018ee26eed9` | `HR1_headroom_prereg.md` | Learnable headroom protocol |
| `83f53ca0d67ec5267936e0f8fbc86b9be1c54a43eb08eb6a7dfec96847ad212b` | `../analysis/hr_stats.py` | Analysis script for HR1 |
