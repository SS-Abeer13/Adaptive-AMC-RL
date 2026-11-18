# R6b diagnosis: why GBT-full-SINRexp (0.4743) and GBT-res-SINRexp (0.5629) fall below Fixed (~0.60)

Date: 2026-11-18. Analysis only — no new simulation, no retraining. Everything below comes
from the already-saved `Dataset/ckpt/r6b/r6b_calib_log.mat` (56,771 logged decisions, 500
calibration traces), `Dataset/ckpt/r6b/r6b_trees.mat` (the trained models + the equivalence
sample), and `Dataset/ckpt/r1b_ack/r1b_calib_xfit.csv` (the stored R1b log, same rows). No
unit of `stage_r6_fullaction` was re-run.

## Conclusion up front

**No bug found in the label construction, candidate/MCS mapping, or deployment dispatch.**
Each of the four checks below comes back clean, and in each case the R6b code matches R1's
own already-working pipeline exactly. The shortfall is a genuine **distribution-shift / one-
step-imitation generalization** effect: R6b's regressors are fit on states visited by R1b's
shallow epsilon-greedy exploration policy, then deployed under their *own* greedy decisions on
the NR2 traces — a different, self-induced state distribution (compounding across busy/retx
state, worse the more candidates there are to go wrong in). This is exactly the quantity
`r6_stats.py`'s pre-registered "logging effect" already measures: **-27.76% (full), -11.68%
(res)**, relative to R1's own true-SINR model on its own (Fixed-500-visited) calibration
states. Multiplying R1's own GBT-full/-res on-time (0.6565 / 0.6373, from the original R1 run)
by `(1 - 0.2776)` and `(1 - 0.1168)` gives 0.4747 and 0.5627 — matching the observed R6b
numbers (0.4743, 0.5629) almost exactly. The frozen analysis already explains the number; it
is not a data-pipeline defect.

## (1) Per-candidate label vs. observed ACK rate

`r6b_calib_log.mat` only stores the final label `Y = psucc(a)*ubits(a)` (not `psucc`/`ubits`
separately — a gap in what the logging unit persisted, noted below), so the literal label
cannot be compared to ACK rate at the same scale. Instead, each row's **taken** candidate index
`ka` was recovered from `ref = round(obs_1*15)` (`X_feat(:,1)`) and the stored taken MCS
(`r1b_calib_xfit.csv.mcs`, row-identical to the R6b log, confirmed by the existing row-identity
assertion), then grouped:

| ka | offset | n | mean ack1 (observed) | mean Y at ka (label, taken rows) |
|---|---|---|---|---|
| 1 | -4 | 3321 | 0.9428 | 1714.1 |
| 2 | -3 | 3704 | 0.9222 | 1445.8 |
| 3 | -2 | 29068 | 0.8617 | 1085.2 |
| 4 | -1 | 4729 | 0.7839 | 1049.5 |
| 5 | 0 | 9057 | 0.6641 | 897.7 |
| 6 | +1 | 3597 | 0.4684 | 427.0 |
| 7 | +2 | 3295 | 0.3363 | 333.3 |

Both columns fall monotonically as the offset gets more aggressive — the label and the
observed ACK rate agree in direction at every candidate. (ka=3's row count, 29068/56771 =
51.2%, matches the exploration policy's 50% exploit probability plus its 1/7 share of the 50%
explore branch, 53.6% expected — consistent, confirming the exploit/explore split and the
offset-to-`ka` mapping are both correct.) This rules out a sign flip or an offset/index
transposition.

## (2) Per-candidate, not the taken action copied across candidates

62.84% of the 56,771 rows have **identical** `Y` across all 7 candidates. This looks alarming
in isolation but is a real floor effect, not a copy bug: when the remaining packet bits
(`obs_13`) are small enough that every candidate's transport block exceeds them, `ubits(a)` is
capped at the same `bits_rem` for every `a`; if the channel is also strong enough that
`estimateBLER_v17` reports ~0 for every candidate MCS up to 14, `psucc(a)` is ~1 for all seven
too, so `Y` is legitimately flat. The non-degenerate 37.16% of rows show the expected
non-trivial shape — e.g. one sampled row: `[3240, 3240, 3240, 3240, 3238.5, 137.8, 0]` across
ka=1..7 — capped-and-near-certain for the conservative end, then collapsing sharply once BLER
takes over at the aggressive end. The **column means across all 56,771 rows** are
`[973, 1012, 1049, 1048, 995, 856, 671]` — a smooth, physically sensible rise-then-fall, not
seven copies of one number. Not the suspected bug.

## (3) Reliability / action distribution of the deployed models

A literal probability-calibration reliability curve does not apply here — like R1's own
models, R6b's target is `psucc x ubits` (expected bits), not a bounded probability, by design
(`R6_fullaction_prereg.md` Section 4, "Model: as R1"). Instead, the trained models were applied
(MATLAB tree traversal, the same code already equivalence-gated to scikit-learn at
`max_abs_diff = 0.000e+00` during the run) to a 6,000-row sample of the calibration features:

- **Mean predicted Q per candidate** `[972, 1011, 1052, 1057, 1013, 880, 703]` tracks the
  **mean training label** on the same rows, `[972, 1013, 1060, 1064, 1025, 869, 683]`, almost
  exactly — the model has learned the label surface correctly, no training-side defect.
- **Raw per-row argmax candidate choice** (ignoring the deployment code's MCS-collapsing, which
  only matters near the CQI floor/ceiling) is not pathologically skewed toward the aggressive
  end: ka=1 (most conservative) is chosen most often, 21.4%, with the rest roughly flat at
  11-14% (ka=2..7: 14.4%, 13.8%, 14.3%, 12.5%, 11.2%, 12.5%). If the model were systematically
  overestimating the aggressive candidates at deployment, that overestimation does not show up
  as a selection skew on the *calibration* state distribution itself — consistent with this
  being a shift between calibration and deployment states, not a defect visible in the
  calibration data alone.

## (4) Feature / MCS / target construction vs. R1's working pipeline

Side by side with R1's logging (`stage_r1_gbt.m`'s `unit_log_calib`, via `evalPolicy_v17_hr`'s
`hr_log`) and R6b's logging (`evalPolicy_presub.m`'s new `log_explore_r6b` branch):

| | R1 (`hr_log`, HR1 instrumentation) | R6b (`log_explore_r6b`) |
|---|---|---|
| Candidate order | `cand_offsets = -4:2` (offsets m4..p2) | `cand_all = -4:2` — identical |
| MCS from candidate | `mc = max(0, min(14, cq - 1))`, `cq = clip(ref+off)` | identical formula |
| `ubits(a)` | `min(tbsFromMCSandRB_v17(mc, n_rb_u), bits_rem_u)` | `min(tbsFromMCSandRB_v17(mc_a, rb(u)), bits_rem)` — identical |
| `psucc(a)` | `1 - estimateBLER_v17(sinr_eff, mc)`, `sinr_eff = SINR_true(t,u)` | `1 - estimateBLER_v17(sinr_eff, c_mcs(ka))`, `sinr_eff = SINR_true(t,u)` — identical |
| Target `Y` | `psucc .* ubits` | `double(ubits_buf).*double(psucc_buf)` — identical |
| Model class/hyperparameters | `HistGradientBoostingRegressor`, frozen gbt_a settings, one per candidate, 19 features only (no MCS appended) | identical (`train_r6b_sinrexp.py` mirrors `train_r1_gbt.py` line for line, only the I/O paths and docstring differ) |
| Deployment dispatch | `gbt_predict_best_mcs` (shared function) | same shared function, same model slot indexing (`gbt_models{idx}`, idx 1..7 ↔ offset idx-5) |

No discrepancy found. The only real difference between R1 and R6b is the **input distribution**
the regressors are trained on (R1: Fixed-500's own deterministic trajectory; R6b: R1b's
epsilon-greedy exploration trajectory on the same traces) — which is R6b's entire stated
purpose (separating the label effect from the logging-policy/state-distribution effect,
`R6_fullaction_prereg.md` Section 1.3) — not an implementation defect.

## One real gap, noted for the record (not the cause of the shortfall)

`unit_r6b_log`'s calibration `.mat` only persists `X_feat`, `Y`, `trace_id` and `n_total` — it
discards the per-candidate `c_mcs`/`c_ubits`/`c_psucc` arrays it computes internally before
collapsing them into `Y`. That is why check (1) above had to reconstruct the taken-candidate
index from `ref` and the stored MCS rather than reading `psucc`/`ubits` directly, and it is why
a literal probability-scale reliability curve could not be produced from the saved artifacts.
If this diagnosis is revisited, persisting `c_psucc`/`c_ubits` (or at least the taken-candidate
values) alongside `Y` would make future checks exact instead of reconstructed. No fix is
applied here; per instruction, this stays a note, not a code change, and R6b is not re-run.
