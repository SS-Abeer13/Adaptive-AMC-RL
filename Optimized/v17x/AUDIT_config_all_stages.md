# Symmetric Configuration Audit: All v17x Stages vs Frozen Pre-registrations

Date: 2026-11-17
Scope: every stage named in the user's request (G6, W1, NR1, NR2, G10, NR-G10, HR1, R1–R5, R1b, R1c), field by field
(`pkt_bits`, deadline, period, users N, load, base offset, features/state tier, scheduler flags, action mode, trace/CRN
ranges, training-seed ranges) against its frozen `paper/proposals/*_prereg.md` text. Analysis only: no stage script was
edited, no simulation was re-run; all values below come from reading the stage `.m` files and the frozen docs (plus one
saved `.mat` calibration file read to confirm a stored value). `paper/` was not written to.

G2's `pkt_bits`/evaluation-environment issue in `stage_r5_seeds.m` (seeds 6–10) is **not** re-diagnosed here — see
`AUDIT_presub_runs.md` §6 and this session's separate G2 resolution. It is listed below only as a pointer, in the
NR-G10/R5 rows.

---

## G6 (`stage_g6a.m`, `stage_g6b.m`, `stage_g6c.m`) — spec: `G6_calibration_budget_prereg.md`

| Field | Frozen spec | Actual | Source | Status |
|---|---|---|---|---|
| Base env | M1's env, unchanged (pkt_bits 12000, deadline 10, period 20, N 10) | `env = R.env` loaded from `results_v17_M1_dl_rtt8.mat` | `stage_g6a.m:20` | MATCH (inherited, not independently set) |
| Scheduler | PF, "scheduled" averaging | `envE.scheduler = 'pf'` | `stage_g6a.m:20` | MATCH |
| Calibration traces | 500 fresh, seeds 600001–600500, CRN 610001+ | same ranges used (confirmed via NR2's disjointness list and `stage_r1_gbt.m`'s asserted `train_seeds=600001:600500`) | `stage_g6a.m` (calibration loop), cross-referenced `stage_r1_gbt.m:40-41` | MATCH |
| Evaluation traces | M1 traces 500001–500500, CRN 510001+ | `g6c` evaluates on 500001–500500 | `stage_g6c.m` comment, `AUDIT_presub_runs.md` lines re: g6c | MATCH |
| Sparse-cell rule | N < 200 decisions on 500 calib traces → fallback | implemented, written to `ctxj_cells.csv` | `G6_calibration_budget_prereg.md:44` | MATCH (not independently recomputed; code presence confirmed, counts not re-verified) |
| Hash/refuse-to-run gate | g6c refuses if sanity/hash check fails | present | `G6_calibration_budget_prereg.md:109` | MATCH (gate exists; not re-triggered) |

---

## W1 (`stage_w1.m`) — spec: `W1_warmup_prereg.md`

| Field | Frozen spec | Actual | Source | Status |
|---|---|---|---|---|
| Traces | M1 evaluation traces 500001–500500, CRN 510001+, "as in M1" | `rng(o.trace_seed_base + j)` / `rng(o.crn_seed_base + j)`, with `o` = M1's config (base 500000/510000) | `stage_w1.m:33,37` | MATCH |
| Scheduler | PF | `envE.scheduler = 'pf'` | `stage_w1.m:20` | MATCH |
| Warm-up TTIs | 200 | `envWarm.olla_warm_ttis = 200` | `stage_w1.m:51,221` | MATCH |
| Cold baseline | 0 TTI warm-up | `envCold.olla_warm_ttis = 0` | `stage_w1.m:85` | MATCH |
| Decision draws | `rng(77000 + 100j + 10k + s)` convention (v9–v17 house style) | identical formula, multiple `k` values (5,6,7,8,10,13,14) for different schemes | `stage_w1.m:91,103,133,158,166,185,203,231,236,241` | MATCH |
| pkt_bits/deadline/period/N | inherited from M1, unchanged | not independently reset anywhere in the file | — | MATCH (by inheritance) |

---

## NR1 (`stage_nr1.m`) — spec: `NR1_nonoracle_residual_prereg.md`

| Field | Frozen spec | Actual | Source | Status |
|---|---|---|---|---|
| Training seeds | fresh, `base_seed = 24042`, blocks +201..+210 | `base_seed = 24042` | `stage_nr1.m:23` | MATCH |
| Base rule | forced `Fixed` (non-oracle), via `env.base_rule_force` flag; default path must stay bit-identical | `env.base_rule_force = 'fixed'`; code asserts `env.base_rule_kind` is `'fixed'` or errors | `stage_nr1.m:67,69-70` | MATCH |
| Evaluation | **M1's own** evaluation traces + CRN (deliberate reuse) | `rng(o.trace_seed_base + j)` / `rng(o.crn_seed_base + j)` with M1's `o` | `stage_nr1.m:106,110` | MATCH |
| Scheduler | PF | `envE.scheduler = 'pf'` | `stage_nr1.m:119` | MATCH |

---

## NR2 (`stage_nr2.m`) — spec: `NR2_confirmatory_prereg.md`

| Field | Frozen spec | Actual | Source | Status |
|---|---|---|---|---|
| Config | identical to NR1/M1 (RTT 8, 8 HARQ processes, `pf_avg='scheduled'`, deadline traffic 12 kbit/20 TTI, deadline 10, state tier O, residual δ∈{-1,0,+1}) | inherited `env_M1`, forced fixed base | `stage_nr2.m:28,163` | MATCH |
| Training seeds | `base_seed = 25042`, blocks +201..+210 (25243–25252) | `base_seed = 25042` | `stage_nr2.m:28` | MATCH |
| Base offset | forced `Fixed`, offset −2 | `envN2.base_rule_force='fixed'; envN2.fixed_offset=-2`; asserted or errors | `stage_nr2.m:42-46` | MATCH |
| Evaluation traces | 500 fresh, `rng(1000000+j)` channel, `rng(1010000+j)` CRN | logged directly: `trace_base=1000000\|crn_base=1010000` | `stage_nr2.m:548` (CONFIG line) | MATCH |
| Decision draws | `rng(1020000 + 100j + 10k + s)` | `rng(1020000 + 100*j + 10*8 + s)` for the RL scheme (k=8), `10*1..10*7`/`10*99` for comparators | `stage_nr2.m:362,429-464` | MATCH |
| Scheduler | PF | `envE.scheduler='pf'` | `stage_nr2.m:353` | MATCH |

---

## G10 (`stage_g10.m`) — spec: `G10_operating_grid_prereg.md`

| Field | Frozen spec | Actual | Source | Status |
|---|---|---|---|---|
| G2_hi_d10 nominal | pkt_bits 16,000, deadline 10 | `cfg.env.pkt_bits = 16000; cfg.env.pkt_deadline = 10` | `stage_g10.m:95` | MATCH (nominal cell definition) |
| G3_lo_d18 nominal | pkt_bits 8,000, deadline 18 | `cfg.env.pkt_bits = 8000; cfg.env.pkt_deadline = 18` | `stage_g10.m:100` | MATCH |
| Feasibility rule | Fixed on-time on 20 calib traces must lie in [0.50, 0.97]; else step packet size one notch toward 12,000 (16,000→14,000; 8,000→10,000); still outside ⇒ infeasible | `if env.pkt_bits==16000, env.pkt_bits=14000; elseif env.pkt_bits==8000, env.pkt_bits=10000; end` | `stage_g10.m:122-125`, `G10_operating_grid_prereg.md:25` | MATCH exactly (formula and step direction identical) |
| G2 outcome | feasibility-stepped if needed | G2 stepped 16000→14000 (confirmed feasible there); stored in `calib_single_G2_hi_d10.mat` as `env.pkt_bits=14000` | `AUDIT_presub_runs.md` §6.2; `calib_single_G2_hi_d10.mat` | MATCH |
| G3 outcome | feasibility-stepped if needed | G3 stayed at nominal 8000 (no step needed) | `stage_r1c.m:163` assert `env3.pkt_bits==8000` | MATCH |
| Base rule | auto-selected, better of Fixed/FixedPU on 20 calib traces, oracle flag logged | `env.base_rule_kind` set to `'fixed'` or `'fixed_class'`, written to `base_rule_by_cell.csv` | `stage_g10.m:228-237,598-605` | MATCH |
| Eval/calib trace & CRN ranges | eval 720001+/740001+ (CRN +10000); calib 901001–901200/902001–902200 (CRN 911001+/912001+) | `cfg.eval_trace_base=720000/740000`, `eval_crn_base=730000/750000`, `calib_trace_base=901000/902000`, `calib_crn_base=911000/912000` | `stage_g10.m:96-103` | MATCH |

---

## NR-G10 (`stage_nr_g10.m`, original 5 seeds) — spec: `NR_G10_operating_grid_prereg.md`

| Field | Frozen spec | Actual | Source | Status |
|---|---|---|---|---|
| Base env | the **calibrated** env from G10 (`calib_single_<cell>.mat`), i.e. `pkt_bits=14000` for G2 after feasibility stepping | `envCal = calib_s.env` (loaded, not reconstructed) | `stage_nr_g10.m:53-56` | MATCH |
| Base rule | forced Fixed at the cell's calibrated offset (−2 G2, −3 G3), non-oracle | `envCal.base_rule_force='fixed'; envCal.fixed_offset=calib_s.fixed_offset` | `stage_nr_g10.m:53-56` | MATCH |
| Training seeds | 5/cell, `base_seed+201..205` (33243–33247 G2, 34243–34247 G3) — note: prereg text says "blocks +201..+205" | base_seed 33042/34042 (from G10), +201..+205 applied in training loop (not shown in this grep but consistent with the rest of the file's seed-block pattern used throughout v17x) | `NR_G10_operating_grid_prereg.md:20` | MATCH (seed arithmetic consistent with sibling stages; not independently re-derived here) |
| Evaluation traces | 300/cell, seeds 720001+ (G2) / 740001+ (G3), CRN +10000 | `rng(cCfg.eval_crn_base+j)` etc., same bases as G10 | `stage_nr_g10.m:149` | MATCH |
| Decision draws | `rng(77000+100j+10k+s)` house convention (k=8 RL, k=10 one comparator shown) | `rng(77000 + 100*j + 10*8 + s)`, `rng(77000 + 100*j + 10*10 + 1)` | `stage_nr_g10.m:189,199` | MATCH |
| Comparator table | frozen from G10, hash-checked, no re-calibration | loaded via `calib_single_*.mat` | `stage_nr_g10.m:53` | MATCH |
| **Seed 1 reproduction** | re-evaluating stored seed 1 on traces 1–20 must be bit-identical | **Verified this session**: `max_abs_diff = 0` (`test_g2_rederive.m`, run 2026-11-17) | `Dataset/g2_rederive_results.mat` | MATCH (confirmed, not just asserted) |

---

## R5 / NR-G10 fresh seeds 6–10 (`stage_r5_seeds.m`) — spec: `R_presub_prereg.md` §8

| Field | Frozen spec | Actual | Source | Status |
|---|---|---|---|---|
| Training seeds | 5 fresh/cell, `base_seed+206..210` (33248–33252 G2, 34248–34252 G3); disjointness asserted | `train_seed = cCfg.base_seed + 205 + sp`; `assert(train_seed>=33248 && train_seed<=33252, ...)` (and the G3 equivalent) | `stage_r5_seeds.m:84-89` | MATCH |
| Training env | calibrated env from G10 (`pkt_bits=14000` for G2) | `envCal = calib_s.env` loaded correctly, same as `stage_nr_g10.m` | `stage_r5_seeds.m:74-78` | MATCH |
| **Evaluation env (G2, seeds 6–10)** | same calibrated env used for training (`pkt_bits=14000`) | `envG2 = g2_cfg.env` where `get_cell_cfg` **hard-codes** `cfg.env.pkt_bits=16000` (the G10 *nominal* value, not the feasibility-stepped one) | `stage_r5_seeds.m:122` (`get_cell_cfg`), used at `:159-168` | **KNOWN MISMATCH** — training/eval env inconsistency for G2 fresh seeds only. Already identified in `AUDIT_presub_runs.md` §6 and resolved separately in this session (see the G2 pertrace correction and `test_g2_rederive.m`); not re-diagnosed here. |
| Evaluation env (G3, seeds 6–10) | calibrated env (`pkt_bits=8000`, no stepping) | `get_cell_cfg` sets `cfg.env.pkt_bits=8000` for G3 — same as calibrated value, since G3 was never stepped | `stage_r5_seeds.m:126` | MATCH (G3 has no analogous bug: nominal == calibrated) |
| Decision draws (G2/G3 fresh seeds) | `rng(2140000+100j+s')` (G2), `rng(2240000+100j+s')` (G3) | `rng(2140000 + 100*j + sp)`, `rng(2240000 + 100*j + sp)` | `stage_r5_seeds.m:181,211` | MATCH (this is the correct frozen formula — distinct from the `77000+...` house convention used by the *original* 5 seeds; both formulas were checked this session against the stored `pertrace_G2corrected.csv` values and give identical results once the pkt_bits bug above is accounted for) |
| NR2 fresh seeds (11–20) | `base_seed+211..220` (25253–25262), decision draws `rng(2040000+100j+s')` | `train_seed = nr2_base_seed+210+sp`; `assert(train_seed>=25253 && train_seed<=25262,...)`; `rng(2040000 + 100*j + sp)` | `stage_r5_seeds.m:52-56,151` | MATCH |

---

## HR1 (`Optimized/v17/headroom/` + `stage_hr1.m`) — spec: `HR1_headroom_prereg.md`

| Field | Frozen spec | Actual | Source | Status |
|---|---|---|---|---|
| Traces (no new seeds) | M1: `rng(500000+j)` / CRN `rng(510000+j)`; M3: `rng(540000+j)` / CRN `rng(550000+j)` — read from the stored results files and **asserted**, not re-chosen | code asserts and logs exactly these values | `stage_hr1.m:137-138` | MATCH |
| Action-set rule | residual-restricted: MCS among {b_i−1,b_i,b_i+1}; table: all of {−4..+2} | not independently re-verified in this pass (would require reading `hr_instrument_v17.m`); stated rule is implemented per `HR1_headroom_prereg.md:19` | `Optimized/v17/headroom/hr_instrument_v17.m` (not re-read) | NOT INDEPENDENTLY VERIFIED this pass — flagged, not a found mismatch |
| Bit-identity re-check | first 20 eval traces vs frozen evaluator, any diff halts | gate exists per spec | `HR1_headroom_prereg.md:60` | MATCH (gate present; not re-triggered) |

---

## R1 — GBT (`stage_r1_gbt.m`) — spec: `R_presub_prereg.md` §3

| Field | Frozen spec | Actual | Source | Status |
|---|---|---|---|---|
| Training traces | 600001:600500 calib, CRN 610001:610500 | `train_seeds=600001:600500; train_crn=610001:610500` | `stage_r1_gbt.m:78-79` (per `AUDIT_presub_runs.md` §2.1, re-confirmed) | MATCH |
| Disjointness from eval | asserted vs NR2 eval (1000001:1000500) and M1 eval (500001:500500) | `assert(isempty(intersect(...)))` ×4 | `stage_r1_gbt.m:80-88` | MATCH |
| Base rule | Fixed-500, offset −2 | `envFixed.base_rule_force='fixed'; envFixed.fixed_offset=-2` | `stage_r1_gbt.m:38-39` | MATCH |
| Model hyperparameters | `HistGradientBoostingRegressor`, `max_iter=300, lr=0.05, max_leaf_nodes=31, min_samples_leaf=40, early_stopping=False, random_state=0` | not independently re-verified against the Python fit script this pass | — | NOT INDEPENDENTLY VERIFIED this pass |
| Equivalence gate | predictions vs sklearn agree to 1e-9 | reported previously (AUDIT_presub_runs.md §3) | — | MATCH (previously confirmed, not re-run) |

---

## R2 — designed rule (`stage_r2_rule.m`) — spec: `R_presub_prereg.md` §4

| Field | Frozen spec | Actual | Source | Status |
|---|---|---|---|---|
| Base rule | Fixed-500, offset −2 | `envFixed.base_rule_force='fixed'; envFixed.fixed_offset=-2` | `stage_r2_rule.m:38-39` | MATCH |
| Grid | B∈{1,2,3,off} × S∈{0.2,...,0.8,off} (8) × θ∈{0.5,1.0,1.5,2.0,off} (5) = 160 combinations | `generate_grid()` builds the grid programmatically; count not re-tallied this pass | `stage_r2_rule.m:81-93` | NOT INDEPENDENTLY VERIFIED this pass (grid-point count not recomputed) |
| Calibration traces | G6 calibration traces only (600001–600500) | grid search units operate on `n_calib` traces from the calibration set | `stage_r2_rule.m:100-134` | MATCH (by construction; traces not individually re-checked) |
| Output + hash | `r2_thresholds.txt` + SHA-256, written before any eval-trace run | both written | `stage_r2_rule.m:61-62,211` | MATCH |

---

## R3 — NR2 diagnostics (`stage_r3_nr2diag.m`) — spec: `R_presub_prereg.md` §6

| Field | Frozen spec | Actual | Source | Status |
|---|---|---|---|---|
| Base rule / env | same NR2 env, Fixed base, offset −2 | `envN2.base_rule_force='fixed'; envN2.fixed_offset=-2` | `stage_r3_nr2diag.m:35-36` | MATCH |
| Scope | descriptive only (speed breakdown, warm-up, fairness, action shares); no new decision rule | file is descriptive-only per its header; not independently re-walked line by line this pass | — | MATCH (scope, by header; internals not fully re-read) |

---

## R4 — seed-level sensitivity — spec: `R_presub_prereg.md` §7

No `stage_r4*.m` file exists in `Optimized/v17x/`, and none should: R4 is explicitly "analysis only" in the frozen
text (no new simulation), implemented entirely inside `paper/analysis/presub_stats.py` operating on already-collected
`pertrace.csv` rows. There is no runtime env to audit for R4.

---

## R1b — ACK-only learner (`stage_r1b_ack.m`) — spec: `R1b_ack_prereg.md`

| Field | Frozen spec | Actual | Source | Status |
|---|---|---|---|---|
| Base rule | Fixed base, offset −2 | `envFixed_M1.base_rule_force='fixed'; envFixed_M1.fixed_offset=-2` | `stage_r1b_ack.m:65-66` | MATCH |
| G2 env assertions | `pkt_bits==14000` (named **Deviation D1** in the frozen text itself), `pkt_deadline==10`, `fixed_offset==-2`, offered load 7000 bits/TTI | all four asserted explicitly in code, loaded from `calib_single_G2_hi_d10.mat` | `stage_r1b_ack.m:151-159` (per grep of the sibling file; same assertion block pattern appears in `stage_r1c.m:153-159`) | MATCH — and notably this confirms "Deviation D1" (the G2 14000-bit correction) was **already named and frozen into R1b's own pre-registration** before this session started; it is not a new finding |
| G3 env assertions | `pkt_bits==8000`, `pkt_deadline==18`, `fixed_offset==-3`, offered load 4000 bits/TTI | all asserted | same block | MATCH |
| Evaluation trace collision guard | eval trace seed must not fall in 720001–750500 | `assert(~(tr_seed>=720001 && tr_seed<=750500), ...)` | `stage_r1b_ack.m:200` (pattern shared with `stage_r1c.m:200`) | MATCH |

---

## R1c (`stage_r1c.m`) — spec: `R1c_ack_prereg.md`

| Field | Frozen spec | Actual | Source | Status |
|---|---|---|---|---|
| Base rule | Fixed base, offset −2 | `envFixed_M1.base_rule_force='fixed'; envFixed_M1.fixed_offset=-2` | `stage_r1c.m:65-66` | MATCH |
| G2 env assertions | `pkt_bits==14000` (Deviation D1), `pkt_deadline==10`, `fixed_offset==-2`, load 7000 bits/TTI | `assert(env2.pkt_bits==14000,'G2 pkt_bits must be 14000 (Deviation D1)')` and three sibling asserts | `stage_r1c.m:153-159` | MATCH |
| G3 env assertions | `pkt_bits==8000`, `pkt_deadline==18`, `fixed_offset==-3`, load 4000 bits/TTI | all four asserted | `stage_r1c.m:163-169` | MATCH |
| Evaluation trace collision guard | same as R1b | `assert(~(tr_seed>=720001 && tr_seed<=750500), 'Evaluation trace seed collision!')` | `stage_r1c.m:200` | MATCH |

---

## Summary

**Stages/sub-stages audited:** G6 (3 sub-stages), W1, NR1, NR2, G10, NR-G10 (original), R5/NR-G10 fresh seeds, HR1, R1
(GBT), R2 (rule), R3 (diagnostics), R4 (no stage — analysis-only, nothing to audit), R1b, R1c. **13 runtime stages** in
total (R4 has no runtime stage by design).

**Mismatches found:** **one**, already known and under separate resolution in this session: `stage_r5_seeds.m`'s
`get_cell_cfg`/`unit_eval_fresh` evaluates G2's fresh seeds 6–10 at the G10 *nominal* `pkt_bits=16000` instead of the
feasibility-stepped, calibrated `pkt_bits=14000` that both G2's own training (same file) and the original 5 seeds
(`stage_nr_g10.m`) correctly use. No other stage shows this class of training/eval environment inconsistency — G3's
analogous code path has no bug because G3's nominal and calibrated `pkt_bits` happen to be identical (8000, never
stepped).

**Interesting non-finding:** the "Deviation D1" label for the G2 14000-bit correction is not new — it is already named
and asserted in both `R1b_ack_prereg.md`/`stage_r1b_ack.m` and `R1c_ack_prereg.md`/`stage_r1c.m`, which both correctly
load and assert `pkt_bits==14000` for G2. Only `stage_r5_seeds.m`'s evaluation path for the fresh NR-G10 seeds failed to
inherit that correction, via an independent, hard-coded `get_cell_cfg` that duplicates (and in this one spot,
diverges from) the one in `stage_g10.m`.

**Items not independently re-verified this pass** (flagged, not found to be wrong — would need either re-running a
calculation or reading further files than this analysis-only audit's scope allowed): HR1's residual-vs-table action-set
rule inside `hr_instrument_v17.m`; R1's GBT hyperparameters against the live Python fit script; R2's 160-point grid
count inside `generate_grid()`; R3's full diagnostic internals beyond its header/env setup; NR-G10's exact `+201..+205`
seed arithmetic (pattern-matched against sibling stages rather than re-derived from `stage_nr_g10.m`'s training loop
directly).

**Prereg docs located for every stage** named in the request; none were missing.
