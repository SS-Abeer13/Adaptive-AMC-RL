# Pre-registration: NR2, confirmatory replication of NR1 on fresh data (v17x stage `nr2`)

**STATUS: FROZEN (8 Nov 2026, Amendment 3).** §§1–8 and the analysis script `paper/analysis/nr2_stats.py` do not change after the freeze commit recorded in `paper/STATUS.md` and `FREEZE.sha256`. Results go in §10. Common rules: `common_rules.md` (R1–R9 apply unless stated otherwise here). **Run order: after G10.**

**Independence.** Written after NR1, G6, W1, A1, A3, A6 and G1 results were known (they motivate it), and before any NR2 run, preflight or trace generation. No NR2 trace, seed or output exists at freezing.

## 1. Why NR2
- NR1 (non-oracle Fixed base, offset −2) beat all 9 comparators and was +1.77 % above the M1 oracle-base policy (`table_nr1.csv`). A descriptive comparison put it +2.44 % [2.04, 2.85] above the G6 combined table (`paper/analysis/out/nr1_g6_compare.csv`).
- Three weaknesses stop NR1 from carrying a recommendation: (i) it was evaluated on **M1's evaluation traces**, on which the G6 comparison was also run; (ii) the NR1-vs-combined-table comparison was **secondary and descriptive**; (iii) `stage_nr1.m` saved only the seed mean per trace, so **Rule R2 cannot be applied**.
- M1 vs the combined table passes at trace level but **fails R2** (hierarchical 95 % CI [−0.30, +1.70] %; ledger G6b/G6e). Whether a configuration exists whose margin over the strongest calibrated rule is seed-robust is the open question of the paper.

## 2. Question
On fresh evaluation traces and fresh training seeds, does residual A2C on the **non-oracle Fixed base** beat the **frozen G6 combined table (Context-joint-500)** at trace level (R1) **and** at seed level (R2)?

## 3. Design (one change from NR1: fresh seeds and fresh evaluation traces)
- **Configuration:** identical to NR1 (`n1/` code path, `env.base_rule_force = 'fixed'`), i.e. M1's environment: RTT 8, 8 HARQ processes, `pf_avg = 'scheduled'`, drain, useful bits, deadline traffic (12 kbit / 20 TTI, budget 10 TTI), state tier O, residual δ ∈ {−1, 0, +1}, shaping c = 0.5, deviation penalty 0.02, logit bias 3, hyper-parameters of `v17_setup.m`.
- **Base rule:** Fixed with offset **−2, frozen**. It is not re-calibrated. The stage asserts that −2 equals both the NR1 calibrated offset (`ckpt/nr1/calib.mat`) and the Fixed-500 offset (`cal500_single.txt`); it stops otherwise.
- **Training:** **3000 episodes × 10 fresh seeds.** `base_seed = 25042`, seed blocks +201..+210 (seeds 25243–25252), the NR1 convention. Validation traces as in M1/NR1 (the training-time validation split, never evaluation traces).
- **Evaluation traces:** **500 fresh traces**, `rng(1000000 + j)` for the channel, `rng(1010000 + j)` for the CRN matrix U, `rng(1020000 + 100 j + 10 k + s)` for scheme k, seed s, j = 1…500.
- **Disjointness (asserted in code, R4):** the trace, CRN and decision ranges above must not intersect any range used so far: v9–v17 cases (evaluation 500001–570500 and CRN; calibration from 60001; validation from 80001; decision draws 77000+), G6 calibration 600001–600500 / 610001+, G10 720000–750500 and 901000–912500, A6 800001–810100, and the training seed blocks 20042–24252 and 31042–32252. The stage stops if any intersection is found.
- **Comparators (frozen, never re-searched):** loaded with the loaders of `stage_g6c.m`. `cal500_tables.txt` must have SHA-256 `94140b8c3405dc7107c2ef1b3d833fd2811fde47b2046516b8547ca331257f89` and `cal500_single.txt` `8ec52905dce4a61dcc9da329f9bd113068147fa0472ae5941ad0c43ec5821998`; the stage refuses to run otherwise.
- **REPRO gates before any fresh trace is generated:** (a) the eight comparators re-evaluated on M1 evaluation traces 1–20 reproduce `ckpt/g6c/eval.mat` (G6 rules) and `results_v17_M1_dl_rtt8.mat` (Baseline, OLLA, Multi-OLLA) **bit-identically**; (b) the stored M1 policies (10 seeds) re-evaluated on traces 1–20 reproduce the stored M1 per-trace values bit-identically. Any difference stops the stage.

## 4. Comparator family and decision rules
- **Primary scheme:** the **per-seed mean**: each of the 10 NR2 policies is evaluated on all 500 traces, and the per-trace on-time ratio is averaged over seeds.
- **Family (Holm over 8):** Baseline, OLLA, OLLA-tuned-500, Multi-OLLA, Fixed-500 (= the NR2 base rule), FixedPU-500, Context-500, **Context-joint-500 (primary comparator)**. The bandits are not in the family (they would need training on NR2's episodes; they were never close).
- **Trace level (R1):** margin = 100 · mean(d) / mean(b) with d the paired per-trace difference; 90 % t-interval of mean(d) scaled by mean(b); two-sided Wilcoxon signed-rank; Holm over the 8. "Beats X" = Holm p < 0.05 **and** 90 % CI lower bound > 0.
- **Seed level (R2):** vs Context-joint-500, the hierarchical bootstrap (B = 20,000; resample seeds, then traces with CRN pairing kept; RNG seed 20261104), the bootstrap over the 10 seed means (RNG seed 20261105) and the one-sided sign test over seed margins, all as in `paper/analysis/g3_seed_stats.py`. **Seed-robust** = hierarchical 95 % lower bound > 0.
- **Verdict (vs Context-joint-500):**
  - **CONFIRM** = beats at trace level **and** seed-robust.
  - **TRACE** = beats at trace level, not seed-robust.
  - **REVERSE** = Holm p < 0.05 and the 90 % CI upper bound < 0.
  - **NULL** = none of the above.
- **WIN** (reported with every verdict) = beats all 8.
- **Secondary (reported, not part of the verdict):** NR2 vs the M1 oracle-base policies re-evaluated on the fresh traces (paired, R1 machinery, no Holm), with the hierarchical CI; the deterministic ensemble of the 10 NR2 seeds; A1-style speed-class margins vs Context-joint-500 (hierarchical 95 % CIs).
- **Reframing gate** (`NR2_reframing_proposal.md`): CONFIRM **and** WIN.
- All statistics are computed by the frozen script `paper/analysis/nr2_stats.py` from `Optimized/v17x/Dataset/ckpt/nr2/eval.mat`; the MATLAB stage writes the data and its own trace-level table, and the two must agree: margins and CIs to two decimals, p-values within 5 % relative (else the stage is reported as inconsistent and no wording is selected).
- **Script validated before freezing:** run on the M1 per-seed values and the G6 comparator values, `nr2_stats.py` reproduces `table_cal500.csv` (margins and CIs exactly; Holm p within 1 % relative), the G6 seed-level result (5/10 seeds, hierarchical 95 % CI [−0.30, +1.70] %) and returns verdict **TRACE** for M1, as the corrected G6 reading requires.

## 5. Pre-registered wording (`paper/manuscript/wording.tex`, slot NR2)

| Verdict | Paper statement | Further effect |
|---|---|---|
| **CONFIRM** | "On fresh evaluation traces and fresh training seeds, the residual policy on a non-oracle base beat the frozen combined table at trace level and robustly across training seeds (+x %, hierarchical 95 % CI [a, b] %)." | If WIN as well: the reframing proposal may be put to the authors (§9). Otherwise C2 gains this sentence only |
| **TRACE** | "… beat the frozen combined table at trace level (+x %), but not robustly across training seeds (hierarchical 95 % CI [a, b] %)." | No reframing. NR1 and NR2 are reported as consistent at trace level; the R2 qualifier stays in the abstract |
| **NULL** | "… the margin … over the frozen combined table was not significant (+x %, 90 % CI [a, b] %); the NR1 margin did not replicate." | NR1's secondary comparison with the combined table is described as not replicated; limitation added |
| **REVERSE** | "… the frozen combined table beat the residual policy on a non-oracle base (x %); the NR1 margin did not replicate." | As NULL, and the abstract states that a calibrated rule beat the non-oracle residual on fresh data |
| not run | "NR2 had not been run at the time of writing." | — |

Numbers are filled from `nr2_stats.py` output into `pending_values.csv` (item NR2; keys in `pending_manifest.csv`). No other wording may be used for the NR2 result.

## 6. Compute (measured basis, not the 0.14 s/episode basis)
- Basis: the NR1 run on the same PC. Training 1044–2123 s per seed (median ≈ 1450 s); NR1 preflight 0.64 s per episode. Evaluation ≈ 0.07 s per 200-TTI trace (NR1: 731 s for 21 × 500 evaluations).
- Training: 10 × 3000 episodes ≈ **4.0 h** (range 2.9–5.9 h).
- Evaluation: (10 NR2 + 1 ensemble + 10 M1 + 8 comparators) × 500 = 14,500 evaluations ≈ **0.3 h**; REPRO gates ≈ 0.05 h; statistics (python) ≈ 0.05 h.
- **Total ≈ 4.4 h (range 3.3–6.3 h).** R5: the preflight basis for this stage is **0.64 s per episode**; the stage pauses if the measured rate exceeds 0.96 s.

## 7. Multiplicity
One new case (M1-NR2) with up to 3 registry rows (NR2 primary, NR2 ensemble, M1 re-evaluated). It is a confirmatory replication of a design ablation. The registry rows of the v17x stages, including NR2, are added before the counts in the paper are final.

## 8. Stage specification for the runner (`Optimized/v17x/`, stage `nr2`)
`stage_nr2(ctx)`, with `stage_nr2_preflight` (20 training episodes on seed 1 and 20 evaluation traces drawn from a **separate** preflight range 1030001–1030020, never from the evaluation range) and `stage_nr2_report` (R9: descriptive, calibration/REPRO information only). Units (each checkpointed, R6):
1. `check` — SHA-256 of both table files; base offset −2 equal in `ckpt/nr1/calib.mat` and `cal500_single.txt`; disjointness assertions of §3; `n1/selectBaseRule_v17n` default behaviour bit-identical (existing test).
2. `repro` — the REPRO gates of §3 on M1 traces 1–20.
3. `train_seed_K`, K = 1…10 — `DeepA2C_Shared_v17` with `base_seed + 200 + K`, 3000 episodes, checkpoint every 250 episodes; save the policy and learning curve.
4. `eval` — generate the 500 fresh traces; evaluate NR2 seeds 1–10, the NR2 ensemble, the 10 stored M1 policies and the 8 comparators. **Save per-seed per-trace arrays.**
5. `analysis` — trace-level table (`run_cmp_stats` of `stage_g6c.m`, Holm over 8), then call `python3 paper/analysis/nr2_stats.py` (or write `NEEDS_PYTHON_nr2.txt` and finish if python is unavailable; the statistics are then run by hand with the same script).

**Outputs** (`Optimized/v17x/Dataset/`): `ckpt/nr2/eval.mat` with `out.nr2_seeds` (10×500), `out.nr2_ens` (1×500), `out.m1_seeds` (10×500) and `out.cmp.<name>` (1×500) for `baseline, olla, olla_tuned500, multi_olla, fixed500, fixedpu500, ctx500, ctxj500`; per-user arrays `okU`/`resU`/`speeds` as in `stage_a1.m` (for the secondary speed breakdown); `table_nr2.csv`; `fill_summary_v17nr2.txt` (CONFIG, PRIMARY, REPLCMP lines, REPRO lines, hashes); `stage_nr2.done`. The script writes `paper/analysis/out/nr2_stats.csv`, `nr2_seed_stats.csv`, `nr2_verdict.txt` and `nr2_pending_values.csv`.

## 9. Claude Code prompt (for the runner on the PC)
> In `Optimized/v17x/`, implement stage `nr2` exactly as in `paper/proposals/NR2_confirmatory_prereg.md` (frozen; verify with `cd paper/proposals && sha256sum -c FREEZE.sha256`). Copy `stage_nr1.m` to `stage_nr2.m` and change only: seeds (`base_seed = 25042`), the fresh trace/CRN/decision ranges of §3 with the disjointness assertions, the frozen base offset −2 (no calibration unit; assert instead), the `check` and `repro` units, the 8-comparator family loaded with the loaders of `stage_g6c.m` (hash-checked), evaluation of the stored M1 policies, and the outputs of §8 (save per-seed arrays). Add `stage_nr2_preflight.m` (preflight range 1030001+, basis 0.64 s/episode) and `stage_nr2_report.m`. Register `nr2` in `run_v17x_all.m` **after `g10`**. Run the existing self-tests and a smoke run (`ctx.smoke`: 2 seeds, 2 episodes, 4 traces from the preflight range) and show me the outputs before any full run. Do not edit anything under `paper/`.

## 10. Results
*(empty until run)*
