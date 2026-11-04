# Pre-registration: W1, warm-up robustness of the M1 comparison (v17w)

**Status:** PROPOSAL for Checkpoint 5. **Class: essential** (Checkpoint 4). **No retraining**: stored policies and stored calibrated tables are used.

## 1. Question
In v17, every scheme starts each 200-TTI trace with a cold OLLA loop (`olla_warm_ttis = 0`). Scoring begins after a 50-TTI burn-in. Does the size of the gain over OLLA (+11.96 %, R06), or the result against calibrated rules (Claim B), depend on that cold start?

## 2. Design
- **Traces:** M1 evaluation traces 500001–500500 with CRN 510001+, as in M1.
- **Warm-up:** `env.olla_warm_ttis = 200`.
  - The frozen evaluator (`evalPolicy_v17.m` L30–60) prepends 200 **unscored** TTIs from an independent channel segment of the same users. The segment's outcome draws are common to all schemes on a trace.
  - Each scheme runs its **own** policy during the warm-up: OLLA, Fixed, FixedPU, Context and the bandits update their loops; the A2C policies act with their own state.
  - Returned metrics exclude the warm-up (L673–676). On-time counting starts after warm-up + burn-in (`trafficInit_v17`).
- **Known exception (pre-stated):** the frozen code applies the warm-up only to OLLA-based schemes (`useOLLA`), so **Baseline is evaluated without warm-up**. Baseline is outside Claims A and B and is reported for completeness with this note. We do not change the frozen code.
- **Schemes:** the 9 comparators, the M1 primary (10 seeds) and the ensemble. Offset-800 and resid-800 are not re-run.
- **Calibrated tables:** the stored M1 tables (`results.env`) form the **primary** analysis. A secondary analysis re-calibrates Fixed/FixedPU/Context on 20 calibration traces with `calib_warm = true` (cheap) and reports them alongside.

## 3. Pre-registered rules
- **Primary claim of the paper stays the cold-start Claim B** (vs calibrated rules). W1 is a robustness check of it, and of the size of the gain vs OLLA.
- The same "beats" machinery as v17 C3: Holm over 9, 90 % CI lower bound > 0, plus the hierarchical bootstrap as a secondary.
- **Reporting:**
  - The gain over OLLA (and tuned OLLA) is reported **both cold and warm** in the results table.
  - If the two 90 % CIs of the margin over tuned OLLA do **not** overlap, the abstract and introduction quote the **warm-up** number, and the cold number moves to the results text.
  - If Claim B **fails** under warm-up, C2 is qualified in the abstract ("with loops started at the beginning of each trace") and the warm-up result is stated in the results and limitations. If Claim B **passes**, the text says the result is robust to a 200-TTI warm-up.

## 4. Compute (basis 0.095 s per 200-TTI evaluation, so ≈ 0.19 s per 400-TTI run)
- Runs: (9 comparators, of which 2 bandits × 10 seeds, so 7 + 20 = 27) + 10 A2C + 1 ensemble = **38 × 500 = 19,000** runs.
- Time: **≈ 1.0 h**, plus about 10 min for the secondary re-calibration and a preflight.

## 5. Multiplicity
This adds 1 case (M1-warm200) with 2 rows. It is a robustness check, not a new claim.

## 6. Claude Code prompt
> In `Optimized/v17/`, implement W1 exactly as in `paper/proposals/W1_warmup_prereg.md` (frozen).
> 1. Write `w1/w1_eval_warmup.m`. Load `Dataset/results_v17_M1_dl_rtt8.mat` (`env`, `policies`, scheme list). Set `env.olla_warm_ttis = 200`; keep everything else. Regenerate M1's evaluation traces and CRN draws as `runComparison_v17.m` L183–191 does. Evaluate the 9 comparators (same ptypes and policy sources as `runComparison_v17.m` L206–232 and L300–316; bandits for all 10 seeds), `Deep A2C v17` (10 seeds) and `Deep A2C v17 (ensemble)` with the frozen `evalPolicy_v17.m`. Compute per-trace primary with `userMetric_v17` and goodput, Jain and edge5 as in `runComparison_v17.m`.
> 2. Sanity check: with `olla_warm_ttis = 0`, re-evaluate 20 traces and require bit-identity with stored `metrics.primary` for every scheme. Stop if not.
> 3. Compute REPLCMP/REPL/REPLSEED with the functions of `analyze_v17_replication.m` (Holm over 9). Write `Dataset/fill_summary_v17w.txt` and `paper/table_warmup.csv`, with cold and warm margins side by side (cold = stored M1).
> 4. Secondary: re-calibrate Fixed, FixedPU and Context with `env.calib_warm = true` on 20 calibration traces (`calibrateFixedClass_v17`, `calibrateCtx_v17`), re-evaluate those three under warm-up, and report them in a separate table.
> 5. Write `README_v17w.md` with the verdict per §3. Note that Baseline has no warm-up in the frozen code. Branch `v17w`.
