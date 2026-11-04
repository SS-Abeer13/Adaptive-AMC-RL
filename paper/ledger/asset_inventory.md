# Asset inventory (paper-ready tables and figures)

Status key: ✅ usable as is · 🔧 usable after restyle or re-cut · ⛔ do not use.

MATLAB is **not** available in this cloud container, and the `.mat` result files hold MATLAB `dlnetwork` objects. Figures or tables that need policy re-evaluation must therefore be regenerated on the author's PC. Figures built only from the CSVs and text summaries can be redrawn here in Python/matplotlib (`paper/figures_src/`, Phase 7).

## 1. Tables

| Asset | Content | Source script | Data file | Status |
|---|---|---|---|---|
| `Optimized/v17/paper/table_core.csv` | 72 rows: (case × RL scheme × comparator) margin %, 90 % CI, Wilcoxon p, Holm p, beats flag, Jain and edge5 for both arms | `Optimized/v17/build_v17_tables.m` | `Optimized/v17/Dataset/fill_summary_v17.txt` (REPLCMP lines) | ✅ (cross-checked against REPLCMP for M1/M2 primary rows) |
| `Optimized/v17/paper/table_harq_ablation.csv` | RTT 8 vs RTT 0 margins per comparator (M1/M2, M3/M4) | `build_v17_tables.m` | `table_core.csv` | ✅ |
| `Optimized/v17/paper/table_training_length.csv` | 800 vs 3000 episodes, margin vs Fixed with CIs (M1, M2) | `build_v17_tables.m` | `table_core.csv` | ✅. Note: 800 and 3000 ep use different seed blocks (+301.. vs +201..), so this is not a paired seed comparison |
| `Optimized/v17/paper/headroom.csv` | Fixed / genie / hindsight per case, 500 traces | `Optimized/v17/headroom_v17.m` | eval traces regenerated from seeds | ✅ |
| `Optimized/v17/paper/table_action_by_state.csv` | Action share by slack, tx type, busy processes (M1, M2), scheduled users only | `Optimized/v17/diag_action_by_state_v17.m` | `results_v17_M{1,2}*.mat` + `evalPolicy_v17` `sch_log` | 🔧 Re-cut needed: slack/busy bins include retransmissions, where δ is a no-op (gaps G1) |
| `Optimized/case_registry.csv` | 108 rows, 67 cases, role, verdict, status | `Optimized/build_case_registry.m` | per-version summaries | ✅ (supplementary table) |
| README_v17 §6.2 per-case tables | Full scheme lists incl. best-on-val, 95 % CI | hand-assembled | `fill_summary_v17.txt` PRIM lines | 🔧 Rebuild from PRIM lines by script (numbers spot-checked, they match) |
| `Optimized/v14/README_v14.md` §7.4 grid table | 2×2 load/deadline | `fill_summary_v14.txt` | — | 🔧 Pre-v17 PF; use as historical robustness only |
| `Optimized/v13/Dataset/headroom_v13.txt` | v13 genie/hindsight gate | `headroom_v13.m` | — | ✅ historical |

## 2. Figures

| Asset | Message | Source script | Data | Status |
|---|---|---|---|---|
| `v17/paper/figures/bars_M{1..4}_*.pdf/png` | Primary metric for every scheme, 95 % CI | `generate_v17_figures.m` (fig set 1) | `results_v17_*.mat` | 🔧 Restyle (column width, grayscale, consistent order). Can be redrawn from PRIM lines in Python, with no MATLAB needed |
| `v17/paper/figures/margin_vs_rtt.pdf/png` | "RL margin vs HARQ RTT" | `generate_v17_figures.m` L67–70 | **Hard-coded numbers** `m_dl = [0.28, -0.21, -1.94]`, `m_gp = [-0.26, -0.01]` | ⛔ **Do not use.** The values are superseded v16 K1/K3/K4 and v15 Z2 results (PF artefact), and two points are mislabelled "v17". Replace with a figure from `table_harq_ablation.csv` (RTT 0 vs 8, v17 only) |
| `v17/paper/figures/acthist_M{1..4}_*.pdf/png` | Greedy action histogram | `generate_v17_figures.m` (fig set 3) | `M.act_hist`: **all N users per TTI**, scheduled or not | ⛔ as captioned ("fraction of decisions"). Rebuild on scheduled new transmissions only (gaps G1) |
| `Docs/figures/v5..v8`, `papers/v8_draft/v8_figures/*` | v8 results | — | — | ⛔ withdrawn results. Use at most a schematic of the system model, if one exists |
| *(missing)* learning curves at 3000 ep | Training dynamics, seed spread | — | `LCURVE` lines in `fill_summary_v17.txt` (8 lines) + `results_v17_*.mat` | 🔧 To build. Check whether LCURVE lines hold the full curve; otherwise the author's PC is needed |
| *(missing)* seed-level dot plot | 9/10 seeds above best rule | — | `REPLSEED` lines | 🔧 Can be built here from text |
| *(missing)* on-time vs goodput Pareto | No throughput cost of the deadline gain | — | PRIM lines (ontime and goodput fields) | 🔧 Can be built here from text |
| *(missing)* campaign timeline / registry overview | Self-correction history | — | `history_table.csv`, registry | 🔧 Can be built here |
| *(missing)* system-model block diagram | OLLA reference → base rule → residual δ → MCS; HARQ processes; PF | — | — | 🔧 Draw (TikZ) |

## 3. Regeneration commands (author's PC, MATLAB R2023a)

```matlab
cd 'D:\Adaptive AMC A2C+QL\Optimized\v17'
build_v17_tables            % table_core / harq_ablation / training_length
headroom_v17                % headroom.csv
diag_action_by_state_v17    % table_action_by_state.csv (re-cut version to be specified, gaps G1)
generate_v17_figures        % bars_*, acthist_*, margin_vs_rtt (fix L67-70 first)
```

## 4. Data available here without MATLAB

`fill_summary_v17.txt` holds these line types: PRIM (52), SCHEME (52), CMP (108), REPLCMP (72), REPL (16), REPLSEED (8), ACT (16), LCURVE (8), WIN (12), SEEDS (4), TRAIN (4), LATECREDIT (4), CALIB/BASE_RULE (4 each). Every headline number in the ledger comes from these lines.
