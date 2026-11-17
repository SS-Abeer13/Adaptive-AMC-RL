# G2 (Deviation D1) verification note — for the writing session

Date: 2026-11-17

## Question raised
`pertrace_G2corrected.csv`'s G2/NRG10 seeds 6–10 (0.5563 / 0.5486 / 0.5359 / 0.5595 / 0.5613) appeared to
disagree with a 15 Nov report from `cross_check_g2.m`, which gave 0.5476 / 0.5413 / 0.5277 / 0.5520 / 0.5539
for what looked like "the same frozen 14 kbit `stage_nr_g10` path." Seeds 1–5 matched in both, so the
suspicion was a decision-draw/CRN seed-formula mismatch between two scripts.

## What D1 already is (not new)
"Deviation D1" — G2's evaluation `pkt_bits` must be 14000 (the feasibility-stepped, calibrated value from
`stage_g10.m`), not the nominal 16000 — is already named and frozen into `paper/proposals/R1b_ack_prereg.md`
and `paper/proposals/R1c_ack_prereg.md`, and correctly asserted in `stage_r1b_ack.m`/`stage_r1c.m`. The
corrected file, `Dataset/presub/pertrace_G2corrected.csv` (identical to `pertrace_corrected.csv`, written
2026-11-15 per `AUDIT_presub_runs.md` §6), already substitutes the right values for (G2, NRG10, seeds 6–10)
without touching `pertrace.csv`. This note does not open a new deviation; it closes out a question about
the already-frozen one.

## Seed-formula check (this session, `test_g2_rederive.m`)
Two candidate decision-draw formulas for the R5 fresh seeds were checked on the frozen 14000-bit
`stage_nr_g10` environment (`envCal`, from `calib_single_G2_hi_d10.mat`), 300 traces (720001–720300,
CRN 730001+), the same 5 fresh policies (`ckpt/r5_seeds/train_G2_hi_d10_6..10.mat`):

- **Formula A** (the original `stage_nr_g10.m` house convention): `rng(77000 + 100*j + 10*8 + s)`, s = 6..10.
- **Formula B** (the one actually written into `R_presub_prereg.md` §8 and `stage_r5_seeds.m`'s own
  evaluation code, line 181): `rng(2140000 + 100*j + sp)`, sp = 1..5.

**Result: both formulas give numerically identical per-seed means** — 0.5563 / 0.5486 / 0.5359 / 0.5595 /
0.5613 — which match `pertrace_G2corrected.csv` exactly. There is no seed-formula discrepancy between the
two conventions on this environment. Seed 1's values were also re-derived and reproduce the stored frozen
`eval_G2_hi_d10.mat` values on traces 1–20 exactly (`max_abs_diff = 0`).

## Resolving the cross_check_g2.m report
`cross_check_g2.m` was re-run with `n_eval = 500` (matching NR2's trace count), not the frozen **300**-trace
NR-G10/G2 evaluation set (`stage_r5_seeds.m`'s `n_eval_g10 = 300`, `R_presub_prereg.md` §8: "evaluated on
the G10 traces of each cell"). Traces 301–500 (seeds 720301–720500) were never part of any pre-registered
G2 evaluation set.

Computing the same Formula-A decision draws over just traces 301–500 gives per-seed means 0.5345 / 0.5304 /
0.5154 / 0.5407 / 0.5428 — markedly lower than the first 300. Averaging all 500 traces together reproduces
the 15 Nov report **exactly**: 0.5476 / 0.5413 / 0.5277 / 0.5520 / 0.5539.

**Conclusion: `cross_check_g2.m`'s discrepancy is a diagnostic-script bug (wrong `n_eval`), not a flaw in
`pertrace_G2corrected.csv` or in Deviation D1's correction.** The committed correction is right. No further
data change is needed; `cross_check_g2.m` should use `n_eval = 300` if it is run again, to stay within the
pre-registered G10/NR-G10 trace set.

## Numbers for the record
- G2 RL (NRG10, 10 seeds pooled, 300 traces each, corrected `pkt_bits=14000`): mean on-time = **0.5501**.
- Best single-cue comparator (Context table), same traces: mean on-time = **0.5385**.
- Margin vs Context table: **+2.14%**, matching the frozen `presub_R5.csv` "Corrected" row in
  `AUDIT_presub_runs.md` §6.4 (90% CI [+1.69, +2.60], hierarchical 95% CI [+1.13, +3.19], 9/10 seeds above,
  PASS).

## Downstream impact
None. `stage_r1b_ack.m` and `stage_r1c.m` already assert and use the 14000-bit G2 environment independently
of `stage_r5_seeds.m`'s evaluation bug, and already cite `pertrace_G2corrected.csv` for G2 seeds 6–10 (R1c
prereg §4.1, "for G2, seeds 6–10 are the corrected 14 kbit re-evaluation of Deviation D1"). The only code
location that still has the stale `pkt_bits=16000` assumption is `stage_r5_seeds.m`'s own `get_cell_cfg`/
`unit_eval_fresh` (see `Optimized/v17x/AUDIT_config_all_stages.md`, R5/NR-G10 row) — it is not called again
after this correction, so it is a latent landmine for any future re-run of that stage rather than a currently
wrong result. Recommend fixing `get_cell_cfg`'s G2 case before `stage_r5_seeds` is ever re-run, but that is a
code change for a future session, not part of this verification.
