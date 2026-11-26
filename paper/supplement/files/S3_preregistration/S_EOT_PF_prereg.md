# Pre-registration: S-EOT, D-PF, D-RS — accounting and training-environment sensitivity of the frozen results

**Stage code:** `eot` (MATLAB, `Optimized/v17x/stage_eot.m`, evaluators in `Optimized/v17x/eot/`). D-PF is a unit of the same stage; D-RS is a calibration-trace diagnostic (`Optimized/v17x/eot/diag_rsched_retx.m`).
**Amendment:** 12 (`AMENDMENTS.md`). **Freeze:** v14 (`FREEZE.sha256`; the v13 list is kept as `FREEZE_v13.sha256`).
**Written:** 19 Nov 2026, after draft v13 (`e0398c2`) and the EOT tooling commit `17bf7d1`.

**What was known at freezing:**
- The 8 Nov code review (`claude/amc_code_review_2026-11-08.md`, code reading only) found three open issues:
  - **MEDIUM 1:** in the HARQ drain, ACKs complete packets without the deadline check, and unresolved packets leave the ratio;
  - **HIGH 2:** at RTT 0 the trainers average PF with ACKed bits, while the evaluation uses the scheduled rate;
  - **MEDIUM 2:** at RTT 8 the training-side PF scheduled rate on retransmissions is computed after the transmission, and can read the wrong HARQ process.
- `17bf7d1` built `env.eot_mode` (`'asrun'` | `'resolved'`). `'asrun'` is bit-identical to the frozen evaluators on calibration traces 60001–60020 for 15 scheme × case pairs (`Optimized/v17x/Dataset/eot/eot_equiv.txt`), and the unit tests in `Optimized/v17x/eot/test_eot.m` pass.

**Independence:** No `'resolved'` value on any evaluation trace exists at freezing, and no evaluation trace was opened for this pre-registration. Only calibration traces were run.

## 1. Purpose
These are **sensitivity analyses of frozen results, not new hypotheses.**
- They add no case and no registry row.
- Their p-values are **not** added to the project Bonferroni pool. They re-test the same comparisons under an alternative accounting or a training-consistent environment.
- Every frozen verdict stays as recorded. This analysis reports whether it would change.

## 2. S-EOT: end-of-trace accounting
**Definition of `'resolved'`** (as implemented in `17bf7d1`):
1. **Counting window.** A packet counts in `okU`/`resU` only if `arr > countFrom` **and** `dl ≤ T_end`, where `T_end` is the absolute last scored TTI, including any warm-up offset.
2. **Drain (RTT > 0).** At each drain TTI, feedback is processed first. Then every packet with `t > dl` expires, its processes are flushed and a miss is counted. This is the main-loop order, so an ACK counts only if it arrives at `t ≤ dl + 1`.
3. **RTT 0.** One expiry step runs at `T + 1`.
- Everything else is identical to `'asrun'`.

**Sets and schemes.** The stored traces, CRN matrices and each study's frozen decision-draw convention are used. No retraining, no new random streams, no new seed range.

| Set | Traces | Schemes |
|---|---|---|
| NR2 | 500 (`rng(1000000 + j)`, CRN `rng(1010000 + j)`) | NR2 seeds 1–10 and ensemble; M1 seeds 1–10 (NR2 secondary); R6a seeds 1–10; GBT-res-ACK and GBT-full-ACK M1 fits 1–4 (fit 1 = R1b); R1 true-SINR GBT-res and GBT-full; R2 rule and rule-cal; the 8 frozen comparators of the NR2 family |
| M1 | 500 (M1 range) | M1 seeds 1–10 and ensemble; the 9 v17 comparators; Fixed-500, FixedPU-500, Context-500, Context-joint-500, OLLA-tuned-500; NR1 policies if stored |
| G2 (14 kbit) and G3 | 300 each (R1c cell traces) | the cell's 10 RL seeds (G2 seeds 6–10 as corrected under D1); per-cell GBT-ACK fits 1–4 (res and full); the M1 transfer fits; the 9 frozen per-cell rules |

**Order of work:**
1. **`'asrun'` pass on all traces of all sets.** It must reproduce every stored per-trace value **exactly**. Any difference stops the stage and is reported. This pass also gives the exposure counters (`n_counted_asrun`, `n_counted_resolved`, `n_late_ack_asrun`, `n_censored_asrun`). Exposure is reported from this pass only, not from the approximate counters of the `'resolved'` pass.
2. **`'resolved'` pass** on the same traces and schemes.
3. **Statistics:** each study's frozen script, **unchanged in logic**, on the resolved per-trace inputs: `nr2_stats.py`, `presub_stats.py` (R1, R2), `r1b_stats.py`, `r1c_stats.py`, `r6_stats.py`, and the M1/G6 routines used for the frozen tables (the R1 rule, `g6_seed_stats.py`, `g3_seed_stats.py`).
   - Only input and output paths may change, with the output in `Optimized/v17x/Dataset/eot/out/`.
   - The diff of any path-only copy is reported.

**Summary.** `Optimized/v17x/Dataset/eot/eot_summary.txt` has one row per frozen labelled outcome. The outcomes are:
- the M1 per-comparator R1 and the R2 vs Context-joint-500;
- the G6 Claims A, B-500 and joint parity;
- the NR2 verdict and WIN;
- R1/R2 presub outcomes;
- the R1b outcome;
- the R1c outcome class per fit and cell;
- the R6a wording row.

Each row gives: as-run margin, resolved margin, shift in percentage points, as-run label, resolved label, changed (y/n).

**Expectation (not a decision rule).** Every scheme's on-time ratio falls under `'resolved'`. The largest margin shift in the headline comparisons is below 1 percentage point, and no frozen label changes.

**Wording rows** (per study; slot `EOT` in `wording.tex`):
- **(a)** "Under an end-of-trace accounting that counts only packets whose deadline falls inside the trace and applies the deadline during the HARQ drain, every frozen verdict is unchanged (largest margin shift x pp)."
- **(b)** "Under that accounting the following verdicts change: …; both are reported."
  - If (b) touches any headline comparison (any GBT-ACK fit vs NR2, or vs RL-full), the abstract carries the qualifier.
- **(c)** "not run".

## 3. D-PF: PF definition used in training at RTT 0 (M2, M4)
- **Code facts.** Quote the lines showing ACK-time PF averaging in the RTT 0 branches of `DeepA2C_Shared_v17.m` (serial and `rollout_episode_v17`) and `DeepPPO_Shared_v17.m`, and the scheduled-rate update in the RTT 8 branch.
- **Diagnostic.** Evaluate the **stored** M2 and M4 policies (every RL scheme in `results_v17_M2_dl_rtt0.mat` and `results_v17_M4_gp_rtt0.mat`) and all comparators, on their own evaluation traces, twice:
  - once with `env.pf_avg = 'scheduled'`, which must reproduce every stored per-trace value exactly;
  - once with `env.pf_avg = 'acked'`, the training definition. All schemes use it, so the comparison stays like for like.
- **Statistics.** The frozen v17 R1 rule (Holm over the case's comparator family) and R2 vs the best comparator, under both definitions. Output: `Optimized/v17x/Dataset/eot/pf_diag_M2_M4.txt`. Descriptive.
- **Wording rows:**
  - **(a)** "M2 and M4 policies were trained with ACK-time PF averaging and evaluated with scheduling-time averaging; evaluated under the training definition, their verdicts are unchanged."
  - **(b)** "… under the training definition, the M2/M4 verdict changes to …".
  - **(c)** "not run".
  - Under every row, the mismatch is disclosed as a limitation, and retraining with the matched definition is listed for the revision round.

## 4. D-RS: frequency of the retransmission scheduled-rate mismatch (RTT 8 training)
- **Setup:** calibration traces 60001–60100 only, with the RTT 8 training environment of `DeepA2C_Shared_v17`. The policy is NR2 seed 1, acting greedily, in a counter-only copy of the episode loop.
- **Reported quantities:**
  - the share of scheduled TTIs where the trainer's `r_sched` differs from the evaluator's;
  - the share of scheduled retransmissions on a process `p ≠ 1`;
  - the mean and 99th percentile of `|ΔR_emas|` at the next TTI;
  - the share of those TTIs where the PF-selected user would change.
- Descriptive. It produces one limitation sentence.
- **Not gated**, since it uses calibration traces only.

## 5. Compute
- About 113,000 evaluations: the `'asrun'` and `'resolved'` passes over about 56,500 scheme × trace pairs. Preflight: 0.116 s per evaluation (basis 0.095 s), so about 1.8 h on 2 workers.
- D-PF: about 1 h. D-RS: about 0.5 h.
- R5: the stage pauses if the measured rate exceeds 1.5 × 0.095 s.

## 6. Checkpoints
- Every unit stores a SHA-256 over `stage_eot.m`, all files in `Optimized/v17x/eot/`, and the key config (`eot_mode`, `pf_avg`, set, scheme list, smoke flag).
- A mismatch forces a recompute.

## 7. Gate
- S-EOT and D-PF must not touch any evaluation trace before:
  - this file and the updated `AMENDMENTS.md` are hashed in `FREEZE.sha256`;
  - those files are committed;
  - `sha256sum -c FREEZE.sha256` passes 23/23.
