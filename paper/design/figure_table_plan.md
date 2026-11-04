# Figure and table plan (Phase 6)

Main text: **8 figures and 5 tables** (F1–F8, T1–T5). Appendix: AT1–AT3. Supplement: registry and per-case tables.
**Build location:** "here" = can be built in the cloud session from files in the repo (Python, `paper/figures_src/`); "PC" = needs MATLAB output the author runs; "TikZ" = drawn in LaTeX.
**Data caveat:** the `.mat` files are MATLAB v7.3 (HDF5) and are readable with `paper/analysis/v17mat.py`. Existing PNG/PDF files under `Optimized/v17/paper/figures/` are **not used** (`margin_vs_rtt` is superseded data; `acthist_*` counts all users per TTI; `bars_*` are restyled from data).

## Style rules (all figures)
- **Vector PDF**, single column 3.5 in (88.9 mm) or double column 7.16 in. Fonts ≥ 7 pt, Times-compatible. No titles inside the figure (captions carry them). Legends present.
- **Grayscale-safe:** every series differs by marker shape and line style as well as colour. A colour-blind-safe palette.
- **One scheme order and one marker per scheme in all figures:** Baseline, OLLA, OLLA (tuned), Multi-OLLA, Fixed, FixedPU (class oracle), Context table, Bandit (global), Bandit (delay class), Residual A2C (primary), Ensemble. In M1 and M2, OLLA = OLLA (tuned) (target 0.10 selected) and the two bandits coincide (P04); plot them once with a combined label ("OLLA / tuned", "Bandit (both)").
- Error bars are defined in every caption (95 % CI of the mean over traces; 90 % CI of the paired % margin; hierarchical bootstrap CIs, B = 20,000).
- Before writing chart code in Phase 7, load the `dataviz` skill. Scripts live in `paper/figures_src/`, one script per figure, run by `make figures`.

## Figures

| ID | § | Type / size | Message | Data (file → field) | Script | Build | Status |
|---|---|---|---|---|---|---|---|
| **F1** | I | Ordered dot plot with 95 % CI, 1 col | Thesis in one picture: the primary scheme clears OLLA by a lot (+11.96 %) and the best calibrated rules by little (+1.58 %). Brackets mark the margins | `fill_summary_v17.txt` `PRIM\|M1_dl_rtt8\|<scheme>` (on-time, ci95); margins from `REPLCMP` (R02–R07) | `f1_thesis.py` (new) | here | ready |
| **F2** | III | Two-panel schematic, 2 col | (a) signal flow: CQI → OLLA reference → base rule + residual δ → MCS → HARQ processes → PF scheduler. (b) PF average updated at scheduling time vs at ACK time on an RTT-8 timeline | none (concept; S05–S07, S13) | `f2_system.tex` (TikZ) | TikZ | Phase 7 |
| **F3** | VI-A | 4-panel forest plot, 2 col | Margin of the primary scheme vs every comparator in M1–M4, with 90 % CI and the Holm-significance mark. M1 positive vs all; M3/M4 negative vs Fixed | `Optimized/v17/paper/table_core.csv` (`scheme = Deep A2C v17`; margin, ci90, holm_p) | `f3_forest.py` (new) | here | ready |
| **F4** | VI-B | Dot plot with CIs, 1 col | Seed-level view for M1: ten per-seed margins vs the Context table (9 above 0), the trace-only 90 % CI and the hierarchical 95 % CI; M2 and resid-800 for contrast | `results_v17_M1/M2_*.mat` `metrics.primary`; `paper/analysis/out/g3_seed_stats.csv` | `f4_seeds.py` (new; reuses `v17mat.py`) | here | ready |
| **F5** | VI-F | 2-panel, 2 col | (a) headroom: Fixed, A2C (primary, ensemble), hindsight, genie for M1–M4; (b) M1 training curves (10 seeds × 3000 episodes) with the 800-vs-3000 margin vs Fixed | (a) `headroom.csv` + `PRIM` lines; (b) `results.learning_curves`, `table_training_length.csv` | `f5_headroom_training.py` (new) | here | ready |
| **F6** | VI-G | Multi-panel, 2 col | Robustness of the M1 comparison: (a) cold vs warm-up margins [W1]; (b) margins vs re-calibrated and combined comparators, with calibration-vs-evaluation values [G6]; (c) non-oracle base [NR1]; (d) the two G10 cells with per-cell base rule and oracle flag [G10] | outputs of W1, G6, NR1, G10 (`fill_summary_v17w/_cal/_n.txt`, `table_cal500.csv`, grid CSV) | `f6_robustness.py` (new) | after PC runs | **pending runs**; default: omitted |
| **F7** | VI-H | Heat map or grouped bars, 1–2 col | Share of δ ∈ {−1, 0, +1} on **scheduled new transmissions** by state bin (CQI delay class, remaining-deadline fraction, interference state, speed class), counts shown; M3 for contrast | `g1_action_by_state.csv`, `a1_peruser.mat` | `f7_behaviour.py` (new) | after PC run | **pending G1/A1**; default: omitted |
| **F8** | VII-C | 2-panel bars, 1 col | PF-average timing: Baseline (and OLLA, Fixed) goodput and Jain for {RTT 0; RTT 8, 1 process; RTT 8, 8 processes} under ACK-time vs scheduling-time averaging, on one trace set | A6 output (`fill_summary_v17pf.txt`); fallback: H17 numbers in T5 | `f8_pf_timing.py` (new) | after A6 | **pending A6** (own frozen text, runs after G10); default: row in T5 |

## Tables

| ID | § | Content | Source | Script | Build | Status |
|---|---|---|---|---|---|---|
| **T1** | II | 8 closest learned-LA papers × {setting, HARQ model, calibrated-rule baseline, information parity}; footer with the 23-paper counts and the abstract-only caveat | `paper/lit/lit_matrix.csv` | `t1_lit.py` → `t1.tex` | here | ready |
| **T2** | V-B | Information table: scheme × {CQI, ACK history, slack, delay class, speed class (oracle), HARQ-process state, calibration data} | `paper/design/information_table.md` (code-verified; S13a) | hand-set in LaTeX, checked by `t2_check.py` against the code lines | here | ready |
| **T3** | III | Simulation parameters (cell, channel, CQI, HARQ, scheduler, traffic, trace length) | `defaultEnv_v17.m`, `v17_setup.m`; ledger S01–S12 | `t3_params.py` from the ledger | here | ready |
| **T4** | VI-A | M1 full comparator table (on-time, margin, 90 % CI, Holm p, Jain, edge5) and M2–M4 summary rows | `table_core.csv` | `t4_results.py` | here | ready; G6/W1 columns **[slots]** |
| **T5** | VII | Pitfalls and superseded results: symptom → diagnosis → fix → effect (ledger numbers) | `paper/ledger/history_table.csv`, ledger H01–H19, R30–R31 | `t5_pitfalls.py` | here | ready; PF row updated by A6 |
| AT1 | App. A | Hyper-parameters and training details | `V13ENV a2c={…}`, `v17_setup.m`, S15–S16 | `at1_hparams.py` | here | ready |
| AT2 | App. B | Full comparator tables M1–M4 and seed-level tables | `table_core.csv`, `g3_seed_stats.csv` | `at2_full.py` | here | ready |
| AT3 | App. C | Calibration outcomes (offsets, class tables, context table) and G6/W1/NR1 details | `CALIB\|…`, `BASE_RULE\|…` lines; G6/W1/NR1 outputs | `at3_calib.py` | here / PC | partly pending |

Supplement S1: `case_registry.csv` (108 rows with `correction`) as CSV and PDF. S2: per-case tables from `fill_summary_v17.txt`.

## Number discipline
- `numbers.tex` is generated from the ledger and the source files by `paper/manuscript/build_numbers.py`. Each macro keeps its ledger ID in a comment. Prose and table numbers use macros only.
- A check script compares every macro value to the raw file it comes from and fails the build on a mismatch (Phase 8 audit).

## New item created by this plan: A6, PF-timing demonstration (no training)
**Why:** F8 and the pitfall claim need one controlled comparison on one trace set. Today the ACK-time numbers come from a 6-trace scan (README_v17 §1) and the scheduling-time numbers from different 20-trace runs, so they cannot share a figure honestly. The v16-versus-v17 re-run is confounded by traces, drain and useful bits (H17a).
**Design (descriptive; makes no claim about RL):** frozen v17 code, `pf_avg ∈ {acked, scheduled}`, `drain = true`, `useful_bits = true` in both arms. HARQ ∈ {RTT 0 / 1 process, RTT 8 / 1 process, RTT 8 / 8 processes}. Schemes Baseline, OLLA and Fixed (offset from M3). 100 K3-like full-buffer traces (seeds 800001–800100, CRN 810001+), same traces in all 18 cells. Report goodput, Jain and edge5 per cell.
**Compute:** 3 schemes × 6 configs × 100 traces = 1,800 evaluations × 0.095 s ≈ **3 min** (+ preflight).
**Class:** nice-to-have, strongly recommended. Pre-registered expectation (not a decision rule): under `acked` the 8-process goodput exceeds the 1-process goodput by a wide margin and Jain falls; under `scheduled` both are within a few percent. If this is not seen, F8 and the pitfall wording are revised.
**Prompt for Claude Code:**
> In `Optimized/v17/`, write `a6/a6_pf_timing.m`. Use `v17_setup.m` K3-like full-buffer settings (case M3's environment but `harq_rtt`/`harq_nproc` per cell). Generate 100 traces (trace seeds 800001–800100, CRN 810001+) as `runComparison_v17.m` L183–191 does. For `pf_avg ∈ {'acked','scheduled'}` × {(0,1),(8,1),(8,8)} evaluate `baseline`, `olla` and `fixed` (offset −1) with the frozen `evalPolicy_v17.m` (`drain = true`, `useful_bits = true` in all cells). Write per-trace goodput, Jain and edge5 and the cell means with 95 % CIs to `Dataset/fill_summary_v17pf.txt` and `paper/a6_pf_timing.csv`. Check first that `acked` + `drain=false` reproduces v16 on 3 traces (the B2.1 test). Branch `v17pf`.

## Placeholders
F6, F7, F8 and every pending number in T4/AT3 use the macros of `paper/manuscript/pending.tex` (outline §4). Figure scripts read the run outputs directly and fail if an item marked `run` has missing files.
