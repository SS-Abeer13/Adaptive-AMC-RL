# Pre-registration HR1 (Plan 4, stage `hr1`): learnable myopic headroom over calibrated tables

**STATUS: FROZEN (Amendment 7, 11 Nov 2026, before any instrumented run on evaluation traces)** (`AMENDMENTS.md`). The analysis script `paper/analysis/hr_stats.py` is frozen with this text (`FREEZE.sha256`). Common rules: `common_rules.md` (R3, R4, R6, R8, R9 apply; R1, R2 and R7 do not, see §7). **Class: measurement with pre-registered directional predictions.** Results go in §9; §§1–8 do not change after the freeze.

**Independence.** Written after all main results (M1–M4, W1, G6, NR1, NR2, G10, NR-G10, A1) were known; they motivate the predictions. The instrumented evaluator (`Optimized/v17/headroom/`, commits `fc78cc7`, `5f2659e`) has been run only on 20 **calibration** traces (seeds 60001–60020) for its bit-identity test (`Dataset/hr/hr_equiv.txt`, all `bit_identical=1`). No headroom quantity has been computed on any trace: `hr_stats.py` was developed and tested on synthetic logs only, and the 20-trace calibration logs were not analysed. No evaluation trace has been run through the instrumented evaluator.

## 1. Question
How much can **any** learner that sees the gNB-observable features add, per decision, over the best calibrated table on the same decisions? And does that "learnable headroom" line up with where the learned policy did and did not help: no gain on full-buffer goodput (M3), a robust gain around the non-oracle base (NR2) but not around the oracle base (M1), and a loss for slow users (A1)?

## 2. Data
- **Evaluator:** `Optimized/v17/headroom/evalPolicy_v17_hr.m` via `hr_instrument_v17.m`, bit-identical to the frozen evaluator (R4). One row per scheduled **new** transmission; 65 columns (names in `COLS`): identifiers (1–3), the policy's 19 current-frame observation features `obs_1..obs_19` (4–22), table cell indices `slack_bin, delay_class, speed_class, busy_harq_bin` (23–26), `base_rule_offset` (27), `action_taken` (28), `n_rb, bits_remaining, slack_remaining` (29–31), per candidate offset a ∈ {−4,…,+2}: `mcs` (32–38), `tbs` (39–45), `ubits` (46–52), `psucc` (53–59), and the taken action's `tbs_act, ubits_act, bler1, p_success_actual, sent_cqi, ref_cqi` (60–65). `psucc(a) = 1 − estimateBLER_v17(SINR_true, mcs(a))` for a first transmission (no combining); `ubits(a) = min(tbs(a), bits_remaining)`.
- **Traces (evaluation traces of the main round, unchanged; R4):** M1 `M1_dl_rtt8`: 500 traces, `rng(500000 + j)`, CRN `rng(510000 + j)`, j = 1…500. M3 `M3_gp_rtt8`: 500 traces, `rng(540000 + j)`, CRN `rng(550000 + j)`. These are the stored `env.trace_seed_base` / `env.crn_seed_base` of `Optimized/v17/Dataset/results_v17_<case>.mat`; the stage reads them from there and asserts the values above. No new seeds, traces or training.
- **Runs (scheme whose decisions are logged):** M1: `Fixed`, `Context table`, `Context-joint-500` (the frozen combined table, hash-checked), `M1` (the 10 stored M1 policies, oracle base FixedPU), `NR2` (the 10 stored NR2 policies, non-oracle base Fixed −2). M3: `Fixed`, `Context table`, `Context-joint-500`, `A2C_case` (the stored M3 policies). NR2 does not apply to M3. **Seeds:** for a learned scheme, each of its 10 policies (M1 and M3: `R.policies.A2C{s}` of the results file; NR2: `Dataset/ckpt/nr2/train_seed_s.mat`), s = 1…10, is run on every trace with the decision draws of the M1 evaluation convention, `rng(77000 + 100 j + 10 k + s)` (k = 8 for a learned scheme; for the tables k = 5 Fixed, 7 Context table, 99 combined, s = 1), and all decisions are pooled. The current tool loads seed 1 only (`A2C{1}`, `train_seed_1.mat`); the full mode must loop over s.
- **Output:** `Optimized/v17x/Dataset/hr/full/hr_log_<case>_<scheme>.mat` (`L_all`, `COLS`, `tag`, `sch_saved_name`), separate from the calibration smoke logs in `Dataset/hr/`.

## 3. Definitions (frozen; implemented in `hr_stats.py`)
- **Per-decision value of an action:** q_i(a) = psucc_i(a) · ubits_i(a), the expected useful bits of the first transmission.
- **(a) Clipping:** candidate offsets that map to the **same MCS** in a decision (CQI or MCS clipping) are **one action**. Their q is identical (asserted); a model's prediction for that action is the mean of the predictions of the offsets that share the MCS; ties between distinct actions go to the lower MCS.
- **(b) Action sets:** the **residual-restricted** headroom uses, per decision, the distinct MCS among the offsets {b_i − 1, b_i, b_i + 1}, with b_i = `base_rule_offset` of that decision (clipped to [−4, +2]). The **table** headroom uses all distinct MCS among {−4, …, +2}.
- **(c) Full buffer:** in M3, ubits = tbs (`bits_remaining` is infinite; asserted for every candidate).
- **Tables (partitions of the decisions):** Fixed (one cell); FixedPU (delay class × speed class); Context table (slack bin); Combined table (slack bin × delay class × speed class × busy-HARQ bin). For each table and fold, the cell's action is the argmax of the **cross-fitted** cell mean of q over the other folds (global mean for an empty cell), over the full action set. V_table = mean of q_i at that action.
- **Learner:** for each candidate offset, a gradient-boosted regression m_a(x) of q_i(a) on x = `obs_1..obs_19`, cross-fitted over 5 folds that split by **trace** (fold = trace rank mod 5). Two models, both pre-specified: `gbt_a` (300 iterations, learning rate 0.05, 31 leaves, ≥ 40 samples per leaf) and `gbt_b` (600, 0.03, 63, ≥ 20); no early stopping; random_state 0. V_learn = mean of q_i at argmax_a m̂_a(x_i) over the allowed set. **The estimate is the larger of the two models** (an under-fitted model under-states the headroom).
- **Genie bound:** V_genie = mean_i max_a q_i(a) (uses the true SINR; not achievable from x).
- **Headroom:** H = 100 · (V − V_table) / V_table, in percent of the table's expected useful bits, computed on the decisions of one run. Uncertainty: trace-level bootstrap (resample traces, recompute ratio of sums), B = 20,000, rng 20261111, 95 % percentile interval; the same resampled traces are used within a run.
- **Scope of the quantity.** H is **myopic** (one decision, first transmission) and is in units of expected useful bits, not on-time ratio or goodput. It is a model-based counterfactual through the simulator's own link abstraction. The learner here sees only the current frame (19 features), whereas the deployed policy sees three stacked frames (57), so H is conservative for that policy. The sequential term (effects on later HARQ, queue and scheduler states) is **not** measured here; if pursued, it needs a separate amendment.

## 4. What is computed (all reported, `hr_values.csv`)
For every run and every table: H_genie; H_learn over the full action set and over the residual-restricted set, for both models (the larger marked primary); number of decisions.

## 5. Predictions and decision rules (each reported with its estimate and 95 % interval)
| ID | Prediction | Computed on | Supported if |
|---|---|---|---|
| **P1** | On full-buffer goodput there is almost no learnable room around the base rule | M3, run `A2C_case`, residual set, vs **Fixed** | 95 % upper bound **< 0.5 %** |
| **P2** | Around the non-oracle base there is learnable room over the combined table | M1, run `NR2`, residual set, vs **Combined table** | 95 % lower bound **> 0** |
| **P3** | That room is larger around the non-oracle base than around the oracle base | M1, (run `NR2`) − (run `M1`), residual set, vs **Combined table**; same traces, joint resampling | 95 % lower bound of the difference **> 0** |
| **P4** | Slow users have less learnable room over the Context table than faster users | M1, run `Context table`, full set, vs **Context table**; (speed classes 2–3) − (speed class 1, < 10 m/s) | 95 % lower bound of the difference **> 0** |

The four intervals are not adjusted for multiplicity; each prediction is reported separately and none changes a pre-registered claim of the paper.

## 6. Pre-registered wording
| Outcome | Paper statement |
|---|---|
| P1 supported | "On full-buffer goodput the learnable per-decision headroom around the base rule is below 0.5 % (+x %, 95 % CI [a, b] %), consistent with the learned policy leaving its base rule alone." |
| P1 not supported | "On full-buffer goodput the learnable per-decision headroom around the base rule is +x % (95 % CI [a, b] %); the collapse of the learned policy to its base rule is not explained by a lack of such headroom." |
| P2 supported | "Around the non-oracle base, a learner that sees the gNB-observable features has per-decision headroom over the combined table (+x %, 95 % CI [a, b] %)." |
| P2 not supported | "Around the non-oracle base, the per-decision headroom over the combined table is not distinguishable from zero (+x %, 95 % CI [a, b] %); the NR2 margin is not explained by myopic headroom." |
| P3 supported | "The headroom is larger around the non-oracle base than around the oracle base (difference +x points, 95 % CI [a, b]), in line with the NR2 result." |
| P3 not supported | "The headroom around the non-oracle base is not larger than around the oracle base (difference x points, 95 % CI [a, b]); the NR2 advantage is not explained by myopic headroom." |
| P4 supported | "Users slower than 10 m/s have less learnable headroom over the Context table than faster users (difference +x points, 95 % CI [a, b]), consistent with the slow-user loss." |
| P4 not supported | "Learnable headroom over the Context table does not differ detectably between slow and faster users (difference x points, 95 % CI [a, b]); the slow-user loss is not explained by it." |
| HR1 not run | "The headroom of a learner over calibrated tables was not measured." |

Every statement is accompanied by the scope sentence: "The headroom is per decision, for the first transmission, in expected useful bits, computed through the simulator's link abstraction; effects on later decisions are not included."

## 7. Statistics and multiplicity
No scheme-versus-comparator test is added, so R1, R2 and the Bonferroni pool of R7 are unchanged; HR1 adds **no** cases or scheme evaluations to the registry or the robustness ledger. Its four predictions are reported with intervals, never as Holm-tested claims.

## 8. Stage specification for the runner (`Optimized/v17x/stage_hr1.m`, full mode)
1. Gate: `AMENDMENTS.md` contains Amendment 7 and `FREEZE.sha256` lists this file and `hr_stats.py`; `sha256sum -c FREEZE.sha256` passes.
2. For each case: read the trace and CRN bases from `results_v17_<case>.mat`, assert the values in §2, and run the runs of §2 on the 500 traces with `hr_instrument_v17` (bit-identity re-checked on the first 20 evaluation traces against the frozen evaluator; any difference halts the stage, R6).
3. Write the logs of §2 to `Dataset/hr/full/`. Preflight (R5) on 2 traces per run; basis = the per-trace times measured in `REPORT_hr1.txt` §4 (0.24–0.63 s per trace and run); pause at 1.5×. Projected (10 seeds per learned run): M1 tables ≈ 9 min, M1 `M1` ≈ 52 min, `NR2` ≈ 43 min; M3 tables ≈ 7 min, `A2C_case` ≈ 35 min; ≈ 2.4 h sequential, ≈ 1.5 h with 2 workers (R8).
4. Then run `python3 paper/analysis/hr_stats.py` (needs numpy, h5py, scikit-learn; projected 2–4 h: 9 runs × 2 models × 5 folds × 7 actions, about 6 × 10⁵ decisions in each learned run) and copy `hr_report.txt` into `Dataset/hr/full/`. The script's model settings and seeds are frozen; it is not re-run with other settings.

## 9. Results
*(empty until run)*
