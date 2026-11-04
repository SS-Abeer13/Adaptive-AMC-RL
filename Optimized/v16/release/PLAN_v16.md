# v16 — consolidation: one frozen simulator, one core benchmark (implementation plan for Claude Code)

Written 28 Oct 2026. Purpose: **no new ideas.** Re-establish the paper's main results on a single
frozen code version with realistic HARQ, so that every main table comes from one simulator and
one protocol. Work in `D:\Adaptive AMC A2C+QL\Optimized`. Stages A → E, with an approval stop
before the campaign.

---

## 0. Why v16

The verdict is consistent across 29 cases (v9–v15), but the evidence is spread across seven code
versions:

| Evidence | Version | HARQ model | RL design |
|---|---|---|---|
| Goodput: no RL win (offset / target / PPO / GRU) | v9–v11 | instantaneous, 1 process | offset or target action; goodput or oppcost reward |
| Deadline: win vs OLLA; v12 fail and v13 secondary vs Fixed | v12–v13 | instantaneous | offset → residual |
| Deadline: WIN vs all at the nominal point; operating-point specific | v14 | instantaneous | residual + shaped on-time |
| Deadline: no win vs Fixed under realistic HARQ (−1.35 % at RTT 8) | v15 | **RTT 8 / 4, 8 processes** | residual + shaped on-time |

Open questions a reviewer will raise, all answered by v16:
1. Do the **goodput** negatives still hold under realistic HARQ and the final A2C design
   (residual on the calibrated rule, oppcost reward)?
2. Is the RL deficit under realistic HARQ an artefact of **too little training** (800 episodes)?
3. Do the main numbers reproduce when **all cells run on one version** with fresh data?

v16 = the v15 core (copied as before). With `harq_rtt = 0` and `harq_nproc = 1`, it is
bit-exact with v15.

---

## Stage A — Housekeeping (no new runs, except one small calibration re-check)

1. **README_v15 §6.** Write it from `fill_summary_v15.txt`:
   - the REPL / REPLCMP / REPLSEED lines for all three aggregators, the RTTEFF and LATECREDIT
     lines, the restart (02:57) and the C4 outcome row ("Claim B fails, Claim A passes");
   - the robustness verdict, with all three margins negative: "operating-point specific";
   - **Deviation:** the requested re-run of `feasibility_v15.m` after the Z3 `pkt_period` change
     (25 → 20) was not done before launch.
2. **Post-hoc check for that deviation.** Run `feasibility_v15.m` now for Z3 only, on
   calibration traces, and record the result in README_v15 §6 as **post-hoc**:
   - whether Fixed is inside [0.50, 0.97];
   - whether the substitution rule would have changed anything.
3. **README_v13 corrections.** Check that the corrections listed in PLAN_v14 Stage A are present
   (§1 v12 numbers, the §7.2 wording, the removed "clean sweep" and shaping attribution, the
   aggregator note). Apply any that are missing.
4. **Case registry.** `build_case_registry.m` parses every `fill_summary_v1*.txt` (v10–v15) and
   writes `Optimized/case_registry.csv` with one row per case:
   - `version, tag, role (primary / secondary / robustness / ablation), env summary, rl_scheme,`
   - `primary_metric, rl_value, best_rule, margin_vs_best_rule_pct, claimA, claimB, win,`
   - `holm_vs_best, n_seeds, n_traces`.

   For v9 (no REPL lines), take the CMP / WIN lines. This file feeds the multiplicity table in
   the paper.

---

## Stage B — Code (small) and tests

### B1. Copy v15 → v16
Core files only, renamed `_v15` → `_v16`. Defaults stay v15-identical.

### B2. Check, and fix if needed, the combinations not yet used together

| Combination needed by v16 | Check |
|---|---|
| Full-buffer (goodput) traffic with `harq_rtt > 0` and `nproc = 8` | New data is always available; goodput is credited at ACK time; the OLLA update is delayed. |
| `reward_kind = 'oppcost'` under RTT | The slot opportunity cost is charged at **transmission**; the delivered goodput is credited at **feedback** to `bufR(dec_id)`, through the v15 delayed-credit path. |
| `action_mode = 'resid'` with `primary = 'goodput'` | The base rule (better of Fixed / FixedPU) is selected on calibration traces **by goodput**. |
| PPO with `action_mode = 'resid'` | If `DeepPPO_Shared` does not support resid, implement it the same way as A2C (decode and bias init). If that is not feasible in under about 2 h, use PPO in offset mode and record that. |
| `fill_stats` / analyser with several RL schemes | One `REPL` line per RL scheme (`scheme=<name>`). The Holm family stays the 9 non-RL comparators, applied separately for each RL scheme. |

### B3. Tests (all must pass; log them in README_v16 §5)
1. **Equivalence.** With RTT 0 and 1 process, v16 = v15 bit-exact (same scope as before, plus
   one deadline evaluation).
2. **Full-buffer under RTT.**
   - Timing: the goodput for a block sent at t appears at t + 8.
   - Conservation: Σ credited bits = Σ ACKed useful bits.
   - Process limit holds, with 20 traces.
3. **Oppcost delayed credit.** On a 2-user toy run, each transmission gets exactly one
   opportunity-cost charge at t and one goodput credit at t + RTT, on the same `dec_id`.
   `LATECREDIT` is logged.
4. **Residual goodput sanity.** With `resid_pen = 10` and 20 episodes, the greedy policy uses
   δ = 0 in ≥ 99 % of decisions and matches the base rule's goodput within 0.1 %.
5. **PPO-resid sanity** (if implemented): the same as test 4, for PPO.
6. **Preflight** (2 episodes, 2 seeds, 6 traces) of every case in C2. Time it and extrapolate
   the full campaign duration.

---

## Stage C — Pre-registration of the core benchmark (README_v16 §1–5; fixed after approval)

### C1. Frozen configuration (applies to every case unless the table says otherwise)
- **Environment:** the v9–v15 physical-mobility macro cell (κ = 1), 10 users, PF, Tier O, CRN,
  common calibration traces 60000+, validation traces 80000+.
- **Traffic:**
  - goodput = full buffer, the v10 E1 environment;
  - deadline = 12 kbit packets every 20 TTI, 10-TTI budget, O2I 0 dB (v14 Y0 / v15 Z1).
- **HARQ:**
  - **RTT8** = `harq_rtt 8, harq_nproc 8` (the default for the paper);
  - **RTT0** = `0, 1` (ablation; v14 conditions).
- **RL** (800 episodes, `base.a2c` hyper-parameters, validation selection on, primary
  aggregator = per-seed mean):
  - **A2C-resid** (primary RL scheme): δ ∈ {−1, 0, 1}, `resid_pen 0.02`, bias +3. Reward:
    `oppcost` for goodput, `ontime_shaped` (`shape_c 0.5`) for deadline.
  - **A2C-offset** (legacy design, for continuity): actions −4…+2, same rewards.
  - **PPO-resid** (or PPO-offset if B2 fell back): same rewards.
- **Comparators** (9, all calibrated within each case): Baseline, OLLA, OLLA (tuned target),
  Multi-OLLA, Fixed, FixedPU, Context table, Bandit (global), Bandit (delay class).
- **Reported reference bounds** (descriptive, computed on the evaluation traces after the run):
  genie and per-trace hindsight offset.

### C2. Cases (all seed and trace ranges fresh and disjoint from v9–v15)

| Tag | Traffic | HARQ | RL schemes (seeds) | Eval traces | CRN | base_seed |
|---|---|---|---|---|---|---|
| `K1_dl_rtt8` | deadline | RTT8 | A2C-resid (10), A2C-offset (5), PPO (5) | 500: 400001–400500 | 410001+ | 14042 |
| `K2_dl_rtt0` | deadline | RTT0 | same | 500: 420001–420500 | 430001+ | 15042 |
| `K3_gp_rtt8` | goodput | RTT8 | same | 500: 440001–440500 | 450001+ | 16042 |
| `K4_gp_rtt0` | goodput | RTT0 | same | 500: 460001–460500 | 470001+ | 17042 |
| `L1_dl_rtt8_long` | deadline | RTT8 | A2C-resid, **3000 episodes** (5) | 300: 480001–480300 | 485001+ | 18042 |
| `L3_gp_rtt8_long` | goodput | RTT8 | A2C-resid, **3000 episodes** (5) | 300: 490001–490300 | 495001+ | 19042 |

Each RL scheme in a case uses its own seed block derived from `base_seed` (A2C-resid +200…,
A2C-offset +300…, PPO +700…, bandits +400 / +600 as now). Check that these blocks never overlap
across cases.

### C3. Decision rules (unchanged from v12–v15)
For each RL scheme in each case, "beats X" means Holm over the 9 comparators gives p < 0.05
**and** the 90 % CI lower bound > 0. The claims are:
- **Claim A:** beats OLLA, OLLA (tuned target) and Multi-OLLA.
- **Claim B:** beats Fixed, FixedPU and the Context table.
- **WIN:** beats all 9.

**Primary scheme:** A2C-resid. **Headline cells:** K1 (deadline) and K3 (goodput), both
realistic HARQ.

### C4. Predictions from prior evidence (stated now; the paper reports agreement or disagreement)

| Case | Prediction (source) |
|---|---|
| K1 | Claim A pass; Claim B fail; A2C-resid − Fixed < 0 (v15 Z1: −1.35 %) |
| K2 | WIN, A2C-resid − Fixed ≈ +0.4 % (v14 Y0: +0.44 %) |
| K3 | no Claim B; A2C-resid ≈ the base rule (v10b / v11: RL ≈ OLLA, Baseline strongest) |
| K4 | same as K3 |
| L1 / L3 | 3000 episodes changes A2C-resid − Fixed by < 0.3 pp (training is not the bottleneck) |

### C5. Training-length rule (L1 / L3 vs the A2C-resid row of K1 / K3)
Compare (A2C-resid − Fixed) at 3000 episodes with the same quantity at 800 episodes. The two use
different traces, so compare the margins with their 90 % CIs.
- **"Training-limited"** if the 3000-episode margin's CI lies entirely above the 800-episode
  margin's CI.
- **"Not training-limited"** otherwise.

### C6. Wording (fixed now)

| Outcome | Paper may say |
|---|---|
| K1 Claim B fails | "Under realistic HARQ timing, learned link adaptation does not outperform a calibrated fixed backoff on deadline traffic; its gain over the OLLA family (+x %) is largely attributable to that backoff." |
| K1 WIN | "Under realistic HARQ timing, residual A2C beat every comparator (+x % vs the best calibrated rule)." Report it with the v15 disagreement. |
| K3 / K4 no win | "On full-buffer goodput, no RL design outperformed calibrated rules, with or without HARQ delay." |
| K2 vs K1 | One sentence on how the RL margin depends on HARQ feedback delay (RTT 0 vs 8). |
| L1 / L3 | "Increasing training from 800 to 3000 episodes did / did not change the result." |

### C7. Multiplicity
v16 adds 6 cases (4 core plus 2 training-length; each RL scheme inside a case is reported, not
counted separately), for a project total of 35. The registry from Stage A4 is updated.

---

## Stage D — Run
- `run_v16_headless.bat`, with auto-restart and per-seed checkpoints.
- **Order:** K1 → K3 → K2 → K4 → L1 → L3. The realistic-HARQ headline cells run first.
- **Estimated time** (from the v15 rates, about 125 min per 10-seed RL scheme case with
  evaluation): each core case with 3 RL schemes (10 + 5 + 5 seeds) takes about 4 h, and each
  3000-episode case about 3 h.
  - **Total: about 22 h.** It can run over one long night plus a day.
  - The B3.6 preflight timing replaces this estimate before approval.
- Keep the PC awake. The launcher restarts after a native crash; finished seeds are reloaded.
- **Stop for user approval** of README_v16 §1–5 and the timing before launch.

---

## Stage E — After the run (feeds the paper directly)
1. **README_v16 §6:**
   - REPL lines per scheme and case;
   - the C4 prediction check (agree / disagree per case);
   - the C5 verdict;
   - restarts and deviations.
2. **Paper-ready outputs** in `Optimized/v16/paper/`:
   - `table_core.csv`: per case, per scheme, against the comparators, with margins and Holm p.
   - `table_harq_ablation.csv`: the K1 vs K2 and K3 vs K4 margins.
   - `table_training_length.csv`.
   - `headroom.csv`: genie and hindsight per case.
   - Figures (PNG + PDF), made with the existing figure style:
     - on-time / goodput bars per scheme per case;
     - RL margin vs RTT (RTT 0, 4, 8; use v15 Z2 for RTT 4, labelled "v15");
     - the action histogram of A2C-resid per case.
3. **Update `case_registry.csv`** with the v16 rows.
4. **Release package** `release/`:
   - the v16 core code and `README_release.md` (requirements: MATLAB R2023a plus the toolboxes
     used; how to reproduce each table; all seed ranges);
   - `case_registry.csv`, every pre-registration README and the summary files;
   - a LICENSE placeholder.

   The user decides on publishing (e.g. GitHub + Zenodo DOI).
5. **No re-runs, re-tags or re-tuning** after results. Then hand off to the paper rebuild.

---

## Prompt to give Claude Code
> Read `Optimized/v16/PLAN_v16.md`. Do Stage A (README_v15 §6 including the feasibility
> deviation and the post-hoc Z3 check, the README_v13 correction check, and
> `build_case_registry.m` → `Optimized/case_registry.csv`). Then Stage B: create `Optimized/v16`
> from v15 (core files only, `_v15` → `_v16`), make the B2 checks and fixes, and run all B3
> tests headless with `matlab -batch`, including the timed preflight. Write README_v16 §1–5 from
> Stage C. Stop and show me the test results, the timing estimate, any B2 fallback (e.g. PPO
> mode) and README_v16 §1–5. Do not launch the campaign until I approve.
