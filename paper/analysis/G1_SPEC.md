# G1 re-cut: which decisions does the residual policy actually change?

**Status:** script ready, to be run on the author's PC. Results are not yet available. No claim depends on them yet.

## 1. Can the existing logs answer G1?

**No.** The v17 result files (`Optimized/v17/Dataset/results_v17_*.mat`, HDF5, read here with h5py) store only **per-trace aggregates** per scheme and seed: `primary`, `cell_tp`, `ontime`, `jain`, `edge_tp`, `bler`, `cqie`, `tp_burst`, `tp_calm`. They also store `act_hist`, which is summed over **all users and TTIs**.

No per-decision record (user, time, state, action) is stored. `fill_summary_v17.txt` holds only summaries. The existing `table_action_by_state.csv` came from a *re-evaluation* (`diag_action_by_state_v17.m`). Its log has only 5 columns, with no time index, CQI delay, interference state or base-rule CQI.

## 2. Smallest instrumented re-evaluation (no training)

- **What:** greedy re-evaluation of the **stored** policies `results.policies.A2C` (10 seeds) and of FixedPU, on the **original** 500 evaluation traces. The traces are regenerated with the same seeds (`trace_seed_base + j`, `crn_seed_base + j`), exactly as `runComparison_v17.m` L183–191 does.
- **Instrumented evaluator:** `Optimized/v17/g1/evalPolicy_v17_g1.m`, a mechanical copy of `evalPolicy_v17.m`. The **only** change is that `info.sch_log` is widened from 5 to 13 columns: `[user, act_idx, slack, is_retx, busy_procs, t, cqi_delay, mean_speed, burst_state, ref_cqi, base_offset_b_i, sent_cqi, remaining_bits]`. `diff evalPolicy_v17.m g1/evalPolicy_v17_g1.m` shows exactly 6 changed sites.
- **Built-in guards** (the script stops or reports if any fails):
  1. `EQUIV`: `[tp, bler, cqi_err, act]` from the copy and from the frozen evaluator are `isequal` on 5 traces.
  2. `REPRO`: re-evaluated cell goodput equals the stored `metrics.cell_tp` for every seed × trace. The maximum absolute difference must be 0. This proves the traces and policies are the ones in the paper.
- **Cases:** M1_dl_rtt8 and M3_gp_rtt8 by default. Optional: M2, M4.
- **Estimated cost:** 5,000 A2C evaluations + 500 FixedPU evaluations per case, about 10–30 min per case with no parallel pool. No GPU is needed.

## 3. Filter and definitions (fixed before running)

- **Kept:** scheduled users, after the 50-TTI burn-in, on a **new transmission** (`is_retx == 0`). Retransmissions are dropped, because the stored MCS is reused and δ has no effect (`harqTransmit_v17.m` L27–31).
- δ ∈ {−1, 0, +1} from `act_idx` ∈ {1, 2, 3}.
- **Effective δ:** `sent_cqi − clip(ref_cqi + b_i, 1, 15)`. It differs from δ only when CQI clipping cancels the action. Clipped cases are counted (`n_clipped`).
- **State bins** (edges fixed now):

| Condition | Bins |
|---|---|
| CQI delay class (same split as FixedPU, `userClass_v17`) | ≤ 4 TTI, ≥ 5 TTI. Also each delay 2…8 |
| Remaining-deadline fraction = slack / 10 TTI (deadline cases) | ≤ 0.3, 0.3–0.6, > 0.6 |
| Remaining-bits fraction (deadline cases) | ≤ 0.5, > 0.5 |
| Interference state (cell-wide Markov burst) | calm, burst |
| Speed class (same split as FixedPU) | < 10, 10–20, > 20 m/s |
| Busy HARQ processes (RTT 8 only) | 0, 1–2, ≥ 3 |

## 4. Outputs (`Optimized/v17/paper/g1/`)

- `g1_action_by_state.csv`: per bin: `n_decisions`, % δ = −1 / 0 / +1, % effective δ ≠ 0, `n_clipped`.
- `g1_summary.txt`: EQUIV, REPRO, counts (logged / retx dropped / kept), and **PUMATCH**. PUMATCH is the share of new-transmission decisions at the same (trace, TTI, user) where A2C sent the same CQI as FixedPU. Expected ≈ 1.0 for M3, given the metric identity below.
- `g1_log_<tag>.mat`: the raw decision log, kept for G2 (on-time attribution by state).

## 5. What the paper may say before and after

- **Before G1:** no action-share or mechanism statement. Allowed: *"In M3 the residual policy is metrically identical to its base rule FixedPU: goodput, Jain index and 5th-percentile user throughput are bit-identical on all 500 traces for all 10 seeds"* (ledger R19a). For M4 the policy is **not** identical: 2,985 of 5,000 seed × trace cells match.
- **After G1:** shares are reported only with the denominator "scheduled new transmissions" and the counts. A mechanism sentence needs a bin with ≥ 5 % of decisions and a share pattern consistent across seeds. G2 attribution is a separate step.
