# v17 — correction round: PF averaging fix, engine-gap check, realistic-HARQ re-run (plan for Claude Code)

Written 3 Nov 2026 after the v16 review (`claude/amc_v16_results_review_2026-11-03.md`).
Work in `D:\Adaptive AMC A2C+QL\Optimized`. Stages A → E, with **two stop points**: after Stage A
(diagnosis) and before the campaign (Stage D).

---

## 0. Why v17

The v16 review measured Baseline and OLLA on K3-like traces (6 traces, full buffer, PF):

| HARQ | Baseline Mbps | Jain | 5th-pct user |
|---|---|---|---|
| rtt 0, 1 proc (legacy `txStep` engine) | 3.152 | 0.503 | 0.0122 |
| rtt 1, 1 proc (new process engine) | 3.458 | 0.484 | 0.0184 |
| rtt 8, 1 proc | 3.466 | 0.478 | 0.0350 |
| rtt 8, 8 proc | **4.837** | **0.420** | **0.0040** |

Two defects follow from this:
1. **PF averaging artefact.**
   - **Cause:** the new engine updates `R_emas` with *ACKed* throughput at feedback time,
     8 TTIs after transmission. With 8 processes, the strongest user stays eligible and its
     average does not rise, so PF degenerates into bursty max-rate scheduling (+40–50 %
     goodput, Jain 0.50 → 0.42, edge users starved).
   - **The fix:** real PF schedulers update the average at scheduling time with the assigned
     rate.
   - **Scope:** this affects every RTT > 0 result in v15 (Z1–Z3) and v16 (K1, K3, L1, L3).
2. **Engine discontinuity.** The legacy engine at rtt 0 and the new engine at rtt 1 / 1 process
   should behave almost identically. They differ by about +10 % in Baseline goodput, and the
   reason is unexplained.

What still stands:
- the RTT-0 cases computed with the legacy engine (v16 K2, K4; v12–v14);
- every conclusion that does not depend on RTT > 0.

v17 fixes both defects and re-runs the realistic-HARQ benchmark. The v16 results it relies on:
- K1, deadline at RTT 8: offset A2C at 800 episodes won all 9, while residual A2C at 800
  episodes lost;
- L1: residual A2C at 3000 episodes won all 9, which is the training-limited verdict.

v17 tests both again, under a correct scheduler.

---

## Stage A — Diagnosis and housekeeping (no campaign). **STOP after A and report.**

### A1. Engine-gap diagnosis
Copy v16 → v17 (core files, `_v16` → `_v17`). Write `diag_engine_gap_v17.m`.
- **Setup:** the K3 environment, Baseline policy, 3 traces, CRN draws. Run
  (a) the legacy engine at `rtt 0`, `nproc 1`, and (b) the new engine at `rtt 1`, `nproc 1`.
- **Per-TTI logging for both:** scheduled user, MCS, TBS, new tx / retx, the outcome draw used,
  bits credited (and at which TTI), and `R_emas` for all users.
- **Report the first TTI where the scheduled user or the credited bits differ,** then classify
  the cause. Possible causes, to be checked rather than assumed:
  - the 1-TTI `R_emas` delay;
  - different eligibility (single process busy for 1 TTI);
  - retx priority or retx potential;
  - CRN draw alignment (which uniform a retransmission uses);
  - the drop or `nret` semantics;
  - the burn-in window shift (credit at t+1).
- **Write the result to README_v17 §2.** Then:
  - (i) if it is a **bug**, fix it;
  - (ii) if it is a **legitimate semantic difference** (e.g. one TTI of feedback delay), keep it
    and quantify how much of the 10 % it explains;
  - (iii) if it is unresolved, **stop and report**.

### A2. Housekeeping
1. **README_v16:**
   - rewrite §6.5 (HARQ ablation), which contradicts itself;
   - update §6.8 (the release folder *was* produced);
   - state the PPO fallback (offset mode, untuned) wherever PPO numbers appear;
   - add a "Superseded" note: the RTT > 0 cases (K1, K3, L1, L3) were run under the PF averaging
     artefact and are replaced by v17.
2. **README_v15 §6:** add the same superseded note for Z1–Z3.
3. **`case_registry.csv`:** add a `status` column (`valid` / `superseded: PF averaging artefact
   (v17)`) and set it for every v15 RTT > 0 row and the v16 K1, K3, L1, L3 rows. Do not delete
   rows.

---

## Stage B — Code fixes and tests

### B1. PF averaging option (`env.pf_avg`)
- **`'acked'`** is the default and reproduces v16 bit for bit:
  - legacy engine: `R_emas` is updated with the delivered rate in the same TTI;
  - new engine: `R_emas` is updated with ACKed bits at feedback time.
- **`'scheduled'`** (the v17 setting):
  - at TTI t, for each scheduled user, `R_emas ← (1−α)·R_emas + α·r_i(t)`, where `r_i(t)` is the
    rate of the block **transmitted** at t (TBS·1e-3, new tx or retx);
  - unscheduled users decay with `r = 0`;
  - this applies in both engines, and in **all** loops: `evalPolicy`, `DeepA2C_Shared` (main loop
    and `rollout_episode`), `Bandit`, `calibrate*`, `selectBaseRule`, `headroom` and
    `feasibility`.
- Goodput and on-time accounting do **not** change; only the scheduler's average does.

### B2. Tests (all must pass; log them in README_v17 §5)
1. **Equivalence:** with defaults (`pf_avg = 'acked'`), v17 is bit-exact with v16. Use the usual
   scope, plus one RTT-8 deadline evaluation and one RTT-8 full-buffer evaluation.
2. **PF update unit test:** on a 3-user toy trace, `R_emas` changes at the transmission TTI,
   never at the feedback TTI, and by the transmitted TBS whatever the outcome.
3. **Engine consistency** (after A1 and B1): with `pf_avg = 'scheduled'`, on 20 traces in both
   the K3 and K1 environments (Baseline, OLLA, Fixed), compare the legacy engine at rtt 0 with
   the new engine at rtt 1 / 1 proc:
   - goodput and on-time must agree within ±1 %;
   - Jain must agree within ±0.01.
   - If they don't, stop and report.
4. **Fairness sanity** (expectation, recorded before the result is seen): with
   `pf_avg = 'scheduled'`, on 20 K3-environment traces, Baseline goodput at
   rtt 8 / 8 proc ÷ rtt 0 must lie in [0.85, 1.10], and Jain must be within ±0.03 of rtt 0.
   - If not, **stop and report**: some other HARQ-engine effect is distorting the scheduler.
5. **Fairness reporting:** `fill_stats_v17` and the analyser add `jain` and `edge5` (the
   5th-percentile user metric) for every scheme in every case. They are already computed in
   `runComparison` (`M.jain`, `M.edge_tp`); expose them in `REPLCMP` and in `table_core`.
6. **Preflight:** 2 episodes, 2 seeds, 6 traces for every case in C2. Time it and extrapolate.

---

## Stage C — Pre-registration (README_v17 §1–5; fixed after approval)

### C1. Frozen configuration
- **The v16 C1 configuration,** plus `pf_avg = 'scheduled'` everywhere, including at RTT 0.
  All v17 cells share one PF definition.
- **HARQ:**
  - RTT8 = `rtt 8`, `nproc 8`, new engine;
  - RTT0 = `rtt 0`, `nproc 1`, legacy engine. Its consistency with the new engine is verified
    by B2.3.
- **Comparators:** the 9 as before, all calibrated within each case under the same scheduler.
- **PPO is dropped** in v17. The v16 PPO ran offset-only and untuned; it is reported as
  exploratory.

### C2. Cases (fresh seeds and traces, disjoint from v9–v16)

| Tag | Traffic | HARQ | RL schemes (episodes, seeds) | Eval traces | CRN | base_seed |
|---|---|---|---|---|---|---|
| `M1_dl_rtt8` | deadline | RTT8 | **A2C-resid (3000, 10) = primary**; A2C-offset (800, 10); A2C-resid (800, 10) | 500: 500001–500500 | 510001+ | 20042 |
| `M2_dl_rtt0` | deadline | RTT0 | **A2C-resid (3000, 10) = primary**; A2C-resid (800, 10) | 500: 520001–520500 | 530001+ | 21042 |
| `M3_gp_rtt8` | goodput | RTT8 | **A2C-resid (800, 10) = primary**; A2C-offset (800, 5) | 500: 540001–540500 | 550001+ | 22042 |
| `M4_gp_rtt0` | goodput | RTT0 | **A2C-resid (800, 10) = primary** | 500: 560001–560500 | 570001+ | 23042 |

- **Primary scheme choice.**
  - For deadline traffic, the primary scheme is residual A2C at 3000 episodes, because v16 found
    the deadline case training-limited.
  - For goodput traffic, it is residual A2C at 800 episodes, because v16 found goodput not
    training-limited.
  - The other schemes are secondary and get no extra claims.
- **Seed blocks.** Each scheme uses its own block within `base_seed`:
  - A2C-resid-3000: +200…;
  - A2C-resid-800: +300…;
  - A2C-offset: +500…;
  - bandits: +400 / +600.

  Check that no block overlaps another across cases.
- **Checkpoints.** The 3000-episode runs checkpoint **every 250 episodes**, as well as per seed,
  because v16 lost wall time to external interruptions.

### C3. Decision rules (unchanged)
"Beats X" means Holm over the 9 comparators gives p < 0.05 **and** the 90 % CI lower bound > 0.
- **Claim A:** beats OLLA, tuned OLLA and Multi-OLLA.
- **Claim B:** beats Fixed, FixedPU and the Context table.
- **WIN:** beats all 9.

Claims are decided for the **primary scheme** of each case.

**Fairness guard** (reported, and it qualifies any WIN): if the primary scheme's Jain is lower
than the best calibrated rule's Jain by more than 0.02, or its `edge5` is more than 10 % lower,
the paper must state the WIN together with that fairness cost.

### C4. Predictions (from v16, stated now)

| Case | Prediction | Source |
|---|---|---|
| M1 | primary WIN; offset-800 WIN; resid-800 Claim B fail | v16 L1, K1 |
| M2 | primary WIN | v16 K2, v14 Y0, v13 X2 |
| M3, M4 | no Claim B; A2C ≈ base rule | v16 K3, K4 and earlier |
| all | with `pf_avg = 'scheduled'`, the RTT-8 absolute levels fall back near RTT-0 levels (B2.4) | v17 B2.4 |

### C5. Wording (fixed now)

| Outcome | Paper may say |
|---|---|
| M1 primary WIN, fairness guard clear | "Under realistic HARQ timing (RTT 8, 8 processes) and a correctly averaged PF scheduler, residual A2C trained for 3000 episodes beat every comparator, including calibrated fixed-offset rules (+x %), without a fairness penalty." |
| M1 primary WIN, fairness guard triggered | the same, plus "… at a fairness cost (Jain −x, edge users −y %)". |
| M1 primary Claim B fails | "Under realistic HARQ timing, learned link adaptation did not outperform calibrated fixed backoffs on deadline traffic; the earlier RTT-8 wins (v16) did not survive correction of the PF scheduler." |
| M2 WIN | "Without HARQ delay, the gain over all comparators replicated for the fourth time (+x %)." |
| M3 / M4 no win | "On full-buffer goodput, no RL design outperformed calibrated rules." |
| Training length | One sentence: 3000 vs 800 episodes in M1 and M2, as a descriptive margin difference. |

### C6. Multiplicity
v17 adds 4 cases, for a project total of 39 (superseded cases are still counted). The registry
records them.

---

## Stage D — Run (**STOP for approval before launch**)
- `run_v17_headless.bat`, with auto-restart, per-seed checkpoints and the 250-episode
  checkpoints for the 3000-episode runs.
- **Order:** M3 → M4 → M2 → M1. The short cases run first, so most results exist early, and the
  longest case runs last.
- **Estimated time** (from the v16 rates: about 40 min per 3000-episode seed under RTT 8,
  about 7 min per 800-episode seed, about 1 h evaluation per 500-trace case with several
  schemes):
  - M1 ≈ 9–10 h;
  - M2 ≈ 7–8 h;
  - M3 ≈ 2.5 h;
  - M4 ≈ 2 h;
  - **total ≈ 21–23 h.**

  The B2.6 preflight timing replaces this estimate.
- **Keep the PC awake, and check the status at least twice a day.** v16 lost 3 days to an
  unnoticed stop. The launcher writes `logs/heartbeat_v17.txt` every 10 minutes (timestamp,
  case, seed, episode), so a stall is visible.

---

## Stage E — After the run
1. **README_v17 §6:**
   - `REPL` / `REPLCMP` (with Jain and edge5), the C4 prediction check, the fairness guard, the
     C5 row, restarts and deviations;
   - the engine-gap diagnosis outcome (§2), repeated in summary.
2. **Paper outputs** in `Optimized/v17/paper/`:
   - `table_core.csv` with fairness columns;
   - `table_harq_ablation.csv` (M1 vs M2, M3 vs M4, under one PF definition);
   - `table_training_length.csv` (M1, M2);
   - `headroom.csv`;
   - figures: bars per case, RL margin vs RTT (RTT 0 and 8 from v17; RTT 4 only if re-run, so
     drop the v15 Z2 point), and action histograms.
3. **`case_registry.csv`:** add the v17 rows, with status `valid`.
4. **`release/`:** refresh it with the v17 code, data summaries, every README and the registry.
   The user decides about publishing.
5. **No re-runs, re-tags or re-tuning.** Then the paper rebuild starts. It cites v17 for all
   RTT-8 results, v16 K2/K4 and v14 for the history, and the registry for multiplicity.

---

## Prompt to give Claude Code
> Read `Optimized/v17/PLAN_v17.md`. Do Stage A: create `Optimized/v17` from v16 (core files
> only, `_v16` → `_v17`), run `diag_engine_gap_v17.m` headless with `matlab -batch`, classify
> the engine-gap cause, and do the A2 housekeeping (README_v16 and README_v15 superseded notes,
> registry status column). Then **stop and show me the diagnosis** before Stage B.
