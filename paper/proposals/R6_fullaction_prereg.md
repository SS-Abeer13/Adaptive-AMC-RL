# Pre-registration: R6 — residual RL with the full action set (−4…+2) against the ACK-trained one-step learner

**Stage code:** `r6_fullaction` (MATLAB, `Optimized/v17x/stage_r6_fullaction.m`); optional part R6b uses a training script `Optimized/v17x/train_r6b_sinrexp.py`. Analysis: `paper/analysis/r6_stats.py`.
**Amendment:** 11 (`AMENDMENTS.md`). **Freeze:** v13 (`FREEZE.sha256`; the v12 hash list is kept as `FREEZE_v12.sha256`).
**Written:** 17 Nov 2026, after R1c (`e59b477`) and the internal review of draft v12 (`3757e1d`, `paper/review/review_v12_*.md`).

**What was known at freezing:**
- R1b and R1c: the one-step learner trained on observed ACK/NACK beats NR2 on the NR2 traces in every calibration draw:
  - GBT-res-ACK, which has NR2's action set (base ±1): NR2 margin −3.40 % (R1b); weakest R1c fit −3.10 %.
  - GBT-full-ACK, which chooses any offset in −4…+2: −7.58 % (R1b; also the weakest of the four R1c fits).
- All three internal reviewers named the action-set difference as the main confound of the headline.

**Independence:** No R6 policy, log, model or evaluation output exists at freezing. `r6_stats.py` was validated on synthetic data only (§9). The writing session opened no new evaluation data to prepare this text.

## 1. Questions
1. **R6a, primary.** With the same action set as GBT-full-ACK (offsets −4…+2), does the residual A2C recipe of NR2 still deliver fewer packets on time than the ACK-trained one-step learner?
   - The comparison is against each of the four calibration draws of R1c, on the NR2 traces.
   - It separates the learning method from the size of the action set.
2. **R6a, secondary (descriptive).**
   - How much of the NR2 → GBT-full-ACK gap does the wider action set close?
   - How does RL-full compare with NR2, with the combined table and with GBT-res-ACK?
3. **R6b, optional observation.** A true-SINR one-step model trained on the R1b exploration logs separates two effects in the R1b "twin" result (ACK-trained models beat their true-SINR twins):
   - the effect of the label;
   - the effect of the logging policy, i.e. the state distribution.

## 2. R6a: the RL-full policy
- **Recipe:** NR2's, unchanged:
  - the non-oracle Fixed base forced to offset −2 (`base_rule_force = 'fixed'`, `fixed_offset = -2`, asserted);
  - the M1 environment (`env_M1`: RTT 8, 8 HARQ processes, `pf_avg = 'scheduled'`, 12 kbit packets every 20 TTIs, deadline 10, N = 10);
  - state tier O (19 observable features, three stacked frames);
  - the shaped reward, the A2C hyper-parameters and 3000 episodes per seed.
- **The only change: the residual action set.**
  - `env.resid_actions = -2:4` (seven actions) instead of `[-1 0 1]`, so the transmitted offset is base + δ ∈ {−4, …, +2}, clipped to the CQI range as in NR2. This is the action set of GBT-full-ACK.
  - The actor's output width follows (`nA = numel(env.resid_actions)`), giving a 57-128-96-7 actor.
- **Unchanged, as in NR2:**
  - the logit bias +3 on δ = 0 (`resid_init_bias`);
  - the deviation penalty `resid_pen = 0.02` × |δ|. With the wider set this penalises large steps more, exactly as the NR2 rule does. It is kept so that only the action set changes.
- **Training seeds:** 10 fresh seeds, `base_seed = 27042`, seed blocks **+201…+210** (seeds 27243–27252). The stage asserts these are disjoint from every training seed used so far:
  - the v9–v17 main rounds;
  - NR1 24042+;
  - NR2 and R5 25042+201…+220;
  - G10 31042+ and 32042+;
  - NR-G10 and R5 33042+ and 34042+.
- **Default-path gate:** before training, NR2 seed 1 is re-evaluated on NR2 traces 1–20 with the unchanged `[-1 0 1]` configuration. It must reproduce the stored per-trace values exactly (`max_abs_diff = 0`), which shows that the code path used by every earlier stage is untouched.
- **Smoke gate:** one seed for 20 episodes on the preflight range 1030001–1030020. The stage logs the seven-action output width, the δ = 0 bias and that the transmitted offsets lie in −4…+2.

## 3. R6a: evaluation
- **Traces:** the NR2 confirmation traces, `rng(1000000 + j)` channel and `rng(1010000 + j)` CRN, j = 1…500. These are the traces of NR2, R1, R1b, R1c and R2, which are stored per trace.
- **Decision draws for RL-full:** `rng(2340000 + 100 j + s)`, s = 1…10. The stage asserts this range is disjoint from every earlier draw range:
  - 77000+;
  - 1020000+;
  - 1030000+;
  - R5 2040000–2270100;
  - R1b/R1c 3050000–3080500 and 4100000–4603500.
- **The RL policy acts greedily** (largest logit), as NR2 and the stored comparators were evaluated.
- **Comparators (stored per trace, paired):**
  - GBT-full-ACK M1 fits 1–4 (fit 1 = R1b, `presub/r1b/pertrace_r1b.csv`; fits 2–4 = R1c, `presub/r1c/pertrace_r1c.csv`);
  - GBT-res-ACK M1 fits 1–4;
  - NR2 (10 stored seeds);
  - the combined table `ctxj500` (`presub/pertrace_G2corrected.csv`).
- **REPRO gate:** before RL-full is evaluated, `ctxj500` and NR2 seed 1 are re-evaluated on traces 1–20 and must match the stored values exactly.
- **Logged for description:** the share of each δ ∈ {−2, …, +4} on scheduled new transmissions, per seed; and the share of decisions clipped at the CQI floor or ceiling.

## 4. R6b (optional): true-SINR one-step model on the exploration logs
- **Logs:** the R1b exploration pass is re-run on the G6 calibration traces 600001–600500 (CRN 610001+) with the identical streams `rng(3050000 + j)`.
  - The stage asserts that the logged (trace, decision, MCS, ack1, explored) rows are identical to the stored `presub/r1b/r1b_calib_xfit.csv`. It stops otherwise.
  - In addition, for every logged decision the analytic R1 labels q(x, a) = p_success(a) × useful_bits(a) are recorded, for every candidate a in −4…+2. These use the simulator's true SINR, exactly as in R1.
- **Model:** as R1:
  - frozen gbt_a settings;
  - one regressor per candidate offset;
  - the 19 observable features.
  It is deployed as `GBT-res-SINRexp` (base ±1) and `GBT-full-SINRexp` (−4…+2), both deterministic.
- **Gates:** the equivalence gate of R1b (SHA-256 per model; MATLAB vs scikit-learn on 1 000 logged decisions, max abs diff ≤ 1e-9).
- **Evaluation:** the NR2 traces with the same CRN; no decision draws (deterministic).
- **Reading (descriptive only; no decision rule, no verdict):**
  - *logging effect:* `GBT-x-SINRexp` vs R1 `GBT-x` (same labels and model form, different logs);
  - *label effect:* `GBT-x-ACK` (fit 1) vs `GBT-x-SINRexp` (same logs; ACK classifier with the MCS as input vs per-candidate true-SINR regressors, so label and model form change together). This is stated in the paper.
- **If R6b is not run**, it is reported as not run; R6a does not depend on it.

## 5. Decision rules (R6a primary)
**Margin** = RL-full (per-trace mean over its 10 seeds) relative to GBT-full-ACK fit k, in %. A positive margin favours RL. The comparison uses the frozen `r1` statistics (`nr2_stats.py`), with **Holm over the 4 fits**, and seed level via the frozen `seed_level`(RL-full seeds, fit k).

**Outcome per fit** (first match; identical to R1c's `classify_r1c`, MATCH tolerance 0.5 %):
- **BEATS** (RL-full beats the learner): Holm p < 0.05, 90 % CI lower bound > 0, and hierarchical 95 % lower bound > 0. With the hierarchical lower bound ≤ 0 the outcome is **BEATS-TRACE**.
- **LOSES** (the learner beats RL-full): Holm p < 0.05 and 90 % CI upper bound < 0.
- **MATCH:** Holm p ≥ 0.05 and |margin| < 0.5 %. This is a point-estimate rule, not an equivalence test, and is reported as such.
- **INCONCLUSIVE:** otherwise.

**State over the four fits:**
- **loses:** all four LOSES.
- **beats:** all four BEATS.
- **closes:** no fit LOSES and not all four BEATS.
- **mixed:** otherwise (some fits LOSES, some not).

## 6. Wording rows (R6a; first matching row)
| Key | Condition | Paper statement |
|---|---|---|
| `the supervised learner beats RL at both action sets` | loses | "With the same action set as the one-step learner (offsets −4…+2), the RL policy still delivered fewer packets on time than the one-step learner trained on observed ACK/NACK, for each of the four calibration draws: the supervised learner beats RL at both action sets." |
| `the gap closes with the full action set` | closes | "With the full action set (offsets −4…+2), the RL policy was no longer beaten by the one-step learner trained on observed ACK/NACK in any of the four calibration draws: the gap closes with the full action set." |
| `RL-full beats the supervised learner` | beats | "With the full action set (offsets −4…+2), the RL policy beat the one-step learner trained on observed ACK/NACK for each of the four calibration draws, robustly across training seeds." |
| `depends on the calibration draw` | mixed | "With the full action set, the comparison between the RL policy and the one-step learner depends on the calibration draw: the four draws gave different outcomes." |
| `not run` | stage not run or incomplete | "No RL policy with the full action set was trained." |

**Consequence for the paper:**
- *loses:* the headline stands at both action sets.
- *closes:* the headline is restricted to the matched residual action set, and the abstract states that the gap closes with the full set.
- *beats:* the headline changes. RL with the full action set is reported as the strongest learner, and the abstract, title and Section VII are rewritten around it.
- *mixed:* the headline is qualified as draw-dependent at the full action set.

In every case the frozen R1, R1b and R1c results stand as recorded.

**Secondary, descriptive (no effect on the verdict):**
- **Gap closure:** 100 × (mean RL-full − mean NR2) / (mean of the four GBT-full-ACK fits − mean NR2), in % of the gap.
- **RL-full vs NR2:**
  - trace-level `r1` on the per-trace seed means;
  - seed level via `seed_level`(RL-full seeds, NR2 seed mean), with NR2 treated as fixed (stated);
  - descriptive, since both are seeded.
- **RL-full vs `ctxj500`:** `r1` (no Holm; one comparison) and `seed_level`.
- **RL-full vs GBT-res-ACK fits 1–4:** `r1`, Holm over 4, `seed_level`, classified as above.
- The δ shares and the clipping shares.

## 7. Multiplicity
- R6a adds **1 case** (RL-full on the NR2 traces) with **1 scheme evaluation** (the 10-seed mean).
- R6b adds **1 case** (the true-SINR model on the exploration logs) with **2 scheme evaluations** (res, full).

**Total: +2 cases / +3 scheme evaluations.** Counted from this freeze, as for R1c, whether or not R6b is run. The project totals become **106 cases / 182 scheme evaluations**, and the Bonferroni pool becomes ≤ 1 820 tests (ten comparisons per evaluation, as before). The ledger row `R6` is added with this freeze, and the manuscript totals change at integration.

## 8. Compute and stage specification
**Units of `stage_r6_fullaction`** (preflight on 1030001–1030020; heartbeat, per-unit checkpoints, watchdog; registered in `run_v17x_all.m`):
1. `gate_default`: NR2 seed 1, traces 1–20, unchanged configuration; `max_abs_diff = 0`.
2. `smoke`: one seed, 20 episodes, the full action set; the assertions of §2.
3. `train_k` (k = 1…10): the RL-full seeds. Checkpoints go to `Dataset/ckpt/r6/train_seed_k.mat`, with their SHA-256 in `r6_models.sha256`.
4. `repro`: `ctxj500` and NR2 seed 1 on traces 1–20.
5. `eval`: RL-full seeds 1–10 on the 500 NR2 traces, plus the δ and clipping shares.
6. `r6b_log`, `r6b_fit`, `r6b_equiv`, `r6b_eval` (optional): §4.
7. `export`: writes `Dataset/presub/r6/pertrace_r6.csv` with columns `trace_set, scheme, seed, trace, value`:
   - schemes `RL-full` (seeds 1–10), `GBT-res-SINRexp` and `GBT-full-SINRexp` (seed 0), on trace set `NR2`;
   - plus `r6_actions.csv` (δ shares) and `REPORT_r6.txt`.

**Estimate** (basis: NR2's training, ≈ 3000 episodes × 10 seeds; the seven-action actor changes only the output layer; the GBT evaluation basis is R1c, ≈ 0.8 h per 500 traces):
| Work | Time |
|---|---|
| Gates and smoke | ≈ 10 min |
| Training, 10 seeds, 2 workers | ≈ 5–6 h |
| RL-full evaluation | ≈ 30 min |
| R6b logging re-run, fit and gate | ≈ 25 min |
| R6b evaluation, 2 schemes | ≈ 1.6 h |
| **Total** | **≈ 7.5–8.5 h; R6a alone ≈ 6–6.5 h** |

If time is short, R6b runs last or not at all.

**Post-run:** `python3 paper/analysis/r6_stats.py` **unchanged**.

## 9. Analysis script and validation
- `paper/analysis/r6_stats.py` imports the frozen `r1`, `holm`, `seed_level` (`nr2_stats.py`) and `load_pertrace`, `get`, `check_pairing`, `write` (`presub_stats.py`). It reads:
  - `presub/pertrace_G2corrected.csv` (NR2 seeds, `ctxj500`, R1 `GBT-res` / `GBT-full`);
  - `presub/r1b/pertrace_r1b.csv` (fit 1);
  - `presub/r1c/pertrace_r1c.csv` (fits 2–4);
  - `presub/r6/pertrace_r6.csv`.
- Outputs (`paper/analysis/out/`): `r6_fits.csv`, `r6_secondary.csv`, `r6_r6b.csv`, `r6_verdicts.txt`, `r6_pending_values.csv`.
- `--selftest` (synthetic data only) checks:
  - that each of the four state-based wording rows and `not run` are produced by a synthetic pattern built for it;
  - the outcome classes and their order (identical to R1c);
  - that a missing R6b part is reported as not run without affecting R6a;
  - that the statistics functions are the frozen ones.

  It passes (`SELFTEST PASS`).

## 10. What is not changed
All earlier frozen texts and scripts keep their hashes, apart from `AMENDMENTS.md`. All earlier results and verdicts stand as recorded, with Deviation D1. R6 adds a comparison; it replaces none.
