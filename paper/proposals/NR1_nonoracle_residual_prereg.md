# Pre-registration: NR1, residual on a non-oracle base under realistic HARQ (v17n)

**Status:** PROPOSAL for Checkpoint 5. **Class: nice-to-have (recommended).** It is the only way to remove limitation #25 (oracle-class inheritance) for M1.

## 1. Background (campaign check, 4 Nov 2026)
- The base rule is selected automatically on 20 calibration traces as the better of {Fixed, FixedPU} (`selectBaseRule_v17.m` L36–50).
- **The non-oracle Fixed base was used** in v13 X1/X1_edf/X2, v14 Y0/Y0_noshape/Y1–Y3, v15 Z2/Z3 and v16 K2–K4.
- The **valid WINs with a non-oracle base** are v13 X2, v14 Y0_base, v14 Y0_noshape and v16 K2. All are **RTT-0 deadline cases under the delivered-bits PF variant** (S08a, S08b).
- **At RTT 8 under v17, M1 used the FixedPU (class-oracle) base; there is no non-oracle run.** v16 K1/L1 (fixed_class, RTT 8) are superseded.
- These are cited in the paper as partial evidence (reviewer_attacks #25).

## 2. Question
Does the M1 result survive when the residual policy acts on the **non-oracle Fixed** base (one global offset) instead of the FixedPU class oracle?

## 3. Design
- **Configuration:** identical to M1 (RTT 8, 8 processes, `pf_avg = 'scheduled'`, drain, useful bits, 3000 episodes, 10 seeds, residual δ ∈ {−1, 0, +1}, shaping c = 0.5). The **one change** is that the base rule is forced to `fixed`.
- **Code:** a new optional flag `env.base_rule_force` in a copy `n1/selectBaseRule_v17n.m`. When it is set, it skips the comparison. Default behaviour must stay bit-identical (test).
- **Training seeds:** fresh, base_seed 24042, blocks +201..+210.
- **Evaluation:** **M1's evaluation traces and CRN** (500001–500500 / 510001+). This deliberate reuse makes the paired comparison with M1's comparators and M1's oracle-base policy exact. It is a design ablation of the base rule, not a new claim about the regime.
- **Comparators:** stored M1 values for the 9 comparators (the calibrated tables are identical by construction; checked).

## 4. Pre-registered rules and wording
- The same "beats" machinery (Holm over 9 + CI). Also a paired test of NR1 vs the M1 oracle-base primary.
- **NR1 beats all 9:** "The deadline gain does not depend on the class-oracle base: with a single global offset as base, residual A2C still beat every comparator (+x % vs the best rule)."
- **NR1 passes Claim A but fails Claim B:** "Under realistic HARQ timing, the gain over calibrated rules relies on the class information supplied by the oracle base rule." This goes in the abstract scope and the limitations, and C2 is qualified.
- **The NR1 vs M1 difference** is reported with its CI in either case.

## 5. Compute (basis 0.14 s per training episode, 0.095 s per evaluation)
- Training: 30,000 episodes ≈ **70 min**.
- Evaluation: (10 A2C + 10 best-on-val + 1 ensemble) × 500 ≈ **17 min**.
- Calibration and preflight ≈ 5 min.
- **Total ≈ 1.5 h.**

## 6. Multiplicity
This adds 1 case (M1-NR) with up to 3 rows. It is a design ablation.

## 7. Claude Code prompt
> In `Optimized/v17/`, implement NR1 as in `paper/proposals/NR1_nonoracle_residual_prereg.md` (frozen).
> 1. Create `n1/selectBaseRule_v17n.m` (copy) with an optional `env.base_rule_force` ('fixed' | 'fixed_class'). Without the field, the output must be bit-identical to `selectBaseRule_v17` (write a test).
> 2. Add case `N1_dl_rtt8_fixedbase` to a copy `n1/v17n_setup.m`: M1's struct with `base_rule_force = 'fixed'`, base_seed 24042, and M1's `trace_seed_base` / `crn_seed_base`. Make `runComparison` use the new selector via the path order of a copied `n1/runComparison_v17n.m`. Change only the selector call.
> 3. Run a preflight (2 episodes, 2 seeds, 6 traces), then the full case. Verify that the calibrated `fixed_offset`, `class_tab` and `ctx_tab` equal M1's. Stop if not.
> 4. Compute REPLCMP/REPL/REPLSEED (Holm over 9) and a paired NR1 vs M1-primary comparison on the 500 traces. Write `Dataset/fill_summary_v17n.txt` and `README_v17n.md` with the verdict per §4. Branch `v17n`.
