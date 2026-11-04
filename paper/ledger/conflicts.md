# Conflicts found during evidence consolidation (Phase 1)

Each conflict below was resolved by source priority (raw summaries > README §6 / paper CSVs > registry > Project notes > top-level README). Severity: 🔴 changes what the paper may claim · 🟠 a number or wording fix · 🟢 cosmetic.

## A. Errors in the top-level `README.md` (prompt §2.4): status check

All five known errors are **still present** in `README.md` as of commit `8616a9a`. None has been fixed.

| # | README.md says | Raw evidence | Resolution |
|---|---|---|---|
| A1 🟠 | "Primary **single-seed** Deep A2C: +1.58 %" | `Deep A2C v17` = mean over 10 seeds (REPLSEED L114, 10 seed means) | Use "10-seed mean" |
| A2 🔴 | v15/v16 artefact explained as RL-specific ("RL transmitted higher-MCS packets … scheduler disproportionately grant[ed] it more slots") and "+37 % to +44 %" | README_v17 §1: Baseline alone rose 3.466 → 4.837 Mbps (RTT 8, 1 → 8 processes); the artefact inflated **every** scheme | Describe it as a scheduler artefact affecting all schemes |
| A3 🟠 | Replications listed as "v10 E4c, v13 X1, v14 Y0, v16 K2" | v13 X1 primary failed Claim B (README_v13 §7.2); E4c is exploratory | Use X2, Y0, K2, M2 (see multiplicity.md §4) |
| A4 🔴 | "selecting action 0 **>99 %** of the time" | ACT L293/L397: 92.3 % (M3), 76.3 % (M4), and these count all users per TTI (see C2) | Use 92 % / 76 % with the correct denominator, or better a re-cut (gaps G1) |
| A5 🔴 | Mechanism: "+1 offset, >85 % share during busy HARQ processes … conservative on retransmissions" | `table_action_by_state.csv`: the ≥3-busy bin holds only 8,150 decisions (1.3 %); retransmission actions are no-ops (`harqTransmit_v17.m` L27–31 reuses the stored MCS) | Do not state a mechanism from this table until it is re-cut |
| A6 🔴 | "**Definitive** WIN", "**firmly refutes**", "confirming the advantage is **structural**" | Wording not allowed by the pre-registrations (prompt rule 3) | Banned words list for the manuscript |

The repo README is not a paper source. Fixing it is optional housekeeping and was **not done** here, so as not to touch files outside `paper/` without your approval.

## B. Case-count conflicts

| # | Conflict | Resolution |
|---|---|---|
| B1 🟠 | README_v17 §6.2 and §6.8: "39 registered cases across v10–v17"; top-level README: 67 | 39 is the v10–v15 registry count carried over from README_v16 §2. Registry: v10–v17 = **49**, v9–v17 = **67** cases / **108** rows. Use 67/108 (multiplicity.md) |
| B2 🟢 | README_v17 §2.2: "78 data rows preserved"; §6.9 and release README: "90 rows"; file: 108 | Snapshots at different times (v16 → v17 → v9 rows added in commit `8616a9a`). The file is the truth: 108 |
| B3 🟢 | README_v16 §C7 "project total 35" vs its own §2 "39 unique cases" | Internal inconsistency in v16; superseded by the registry |
| B4 🟢 | Registry gives `n_seeds = 10` for the M3 offset-800 row; v17_setup `n_seeds_a2c_offset = 5` for M3; REPLSEED L358 shows 5 seeds + 5 NaN | 5 seeds. Registry field wrong for that row |

## C. Conflicts that change what may be claimed

| # | Conflict | Evidence | Consequence |
|---|---|---|---|
| C1 🔴 | `v17/paper/figures/margin_vs_rtt.*` is captioned as a v17 result | `generate_v17_figures.m` L67–70 hard-codes v16 K1/K2/K3/K4 and v15 Z2 values (K1 −1.94 %, superseded) and labels two of them "v17" | ⛔ Never use. Rebuild from `table_harq_ablation.csv` |
| C2 🔴 | "δ = 0 in 92 % / 76 % of decisions" (prompt §2.2, README_v17 §6.7) | `runComparison_v17.m` L330–332 accumulates `act(b0+1:end, :)` over **all N = 10 users** every TTI. PF serves one user per TTI, so about 90 % of counted "decisions" have no effect. M3: all 10 seed means are **identical** to FixedPU to 4 decimals (SEEDS L290), so on effective decisions the greedy policy is (almost) always δ = 0 | Report as "the policy is behaviourally identical to its base rule (identical goodput on all 500 traces for all 10 seeds)". Drop the 92 % figure or restate its denominator. Same caveat for the M1/M2 histograms and the `acthist_*` figures |
| C3 🔴 | Prompt §2.4 says `table_action_by_state.csv` "includes unscheduled users" | `diag_action_by_state_v17.m` uses `sch_log`, which logs **only scheduled users** after burn-in (`evalPolicy_v17.m` L489–501). The real flaw is different: the slack and busy-process bins **mix in retransmissions**, where δ is a no-op. The "retransmission conservatism" finding (README_v17 §6.7 item 1) describes actions with no effect | Re-cut to scheduled **new** transmissions only (gaps G1). Drop finding 1 |
| C4 🔴 | Proposed contribution 2: "the open-loop mapping beats OLLA at a 10 % target" | True in v9 gp_O (+4.5 %, L9–10) and v16 K4 (Baseline 2.8768 vs OLLA 2.7249). **Reversed in v17**: OLLA beats Baseline by +7.4 % (M3) and +6.9 % (M4) | The claim is PF-definition dependent. It cannot be a contribution unless stated as such (see C5) |
| C5 🔴 | Registry marks every pre-v17 RTT-0 case "valid". README_v17 says M2 replicates "under the corrected PF" | Pre-v17 engines update the PF average with **delivered** bits (`evalPolicy_v9.m` L212, `evalPolicy_v16.m` L526: `ema*tpr`), so a NACKed user's average does not rise. v17 uses the **scheduled** rate. README_v17 §2.1 shows this changes Baseline goodput by +10 % even at RTT 0 (3.2941 → 3.6293, legacy engine) | v9–v16 RTT-0 results are internally valid but use a **different PF definition**. v13 X2, v14 Y0 and v16 K2 are replications of the *direction* of the effect under another scheduler variant, not exact replications. The paper should state this. It is arguably a strength: the RTT-0 effect holds under both PF variants |
| C6 🟠 | v14 "shaping helps" as a mechanism for the win | Y0_noshape (unshaped) also met WIN (+0.21 % vs Fixed, registry case 50); shaping adds +0.23 % (paired) | Shaping improves the margin but is not necessary for the RTT-0 win. Word it that way |
| C7 🟠 | v13 X1 per-seed-mean row in the registry shows `win = 1` | README_v13 §4: the pre-registered primary scheme was the ensemble (failed) | Note in the registry supplement: "not the pre-registered scheme" |
| C8 🟠 | Prompt §2.1 v10: slot-stealing policy "bimodal −4/+2, ~1.4 vs 2.8 Mbps" | `matlab_v10b_check.log` L17: 58 % at −3, 35.8 % at +2 (actions −4…+2). Campaign E1_train: A2C 1.38 vs OLLA 2.92 Mbps (v9 A2C was 2.80) | Use "−3/+2", 1.38 vs 2.92 |
| C9 🟠 | Prompt §2.1 v9: "open-loop Baseline beats OLLA-10 % by about 5 %" | v9 gp_O: 3.0554 vs 2.9233 = +4.5 % | Use +4.5 % (and see C4) |
| C10 🟢 | README_v17 §3.1 OLLA "step 0.1/0.9" | `defaultEnv_v17.m` L100–101: target 0.10, down-step 0.5 dB → up-step 0.5·0.1/0.9 ≈ 0.056 dB | Describe as 10 % target, Δdown = 0.5 dB |
| C11 🟢 | Prompt §2.2 calls FixedPU a "per-class oracle table" | FixedPU uses the true speed/delay class (hence "Oracle"). It is the **base rule** of the residual A2C in all four v17 cases (BASE_RULE lines) | Define clearly. Note that residual A2C at δ = 0 *is* FixedPU, which is why M3 equals FixedPU exactly |
| C12 🟢 | README_v17 §6.8 training-length sentence uses margins vs the best rule (+0.34 → +1.58); `table_training_length.csv` uses margins vs Fixed (+0.62 → +1.87) | Both correct, different comparators | Pick one in the paper (recommend vs best rule = Context) and say which |
| C13 🟢 | README_v17 §6.9: table_core includes "TOST equivalences" | `table_core.csv` has no TOST column (TOST only appears in CMP lines) | Minor; TOST is available from CMP lines if needed |

## D. Unverifiable here

- Project notes `claude/amc_*` (priority 4) are in the claude.ai Project, not in this repo. I could not open them. Claims sourced only from them: none in the ledger. The E4c fresh-only numbers come from README_v12 §1, which cites that note.
- `papers/v8_draft/AMC_full_paper_v8_rev1_source.md` has not been read yet. It is reserved for Phase 2 (system-model notation and reference candidates).

## E. Citation errors found in Phase 2 (literature)

| # | Where | Error | Resolution |
|---|---|---|---|
| E1 🟠 | `Optimized/v17/evalPolicy_v17.m` L4 (and earlier versions): "Multi-OLLA … (arXiv:2604.20459)" | Ahsen et al. 2026 is a **rank-dependent** multi-offset OLLA. Our Multi-OLLA is a fast/slow integrator blend, a different method | In the paper, describe our Multi-OLLA on its own terms. Cite Ahsen et al. only as "multi-offset OLLA variants exist". The code comment is left untouched (frozen code); noted here |
| E2 🟠 | v8 draft ref [2] | Pedersen 2007 DOI 10.1109/VETECF.2007.380 points to a different paper | Correct DOI: 10.1109/vetecf.2007.378 |
| E3 🟢 | v8 draft ref [8] | Dahlman book DOI not registered | Do not cite with that DOI |
| E4 🟢 | prompt §4.1 | "Ahsen et al. (IEEE OJ-COMS)" | No OJ-COMS version exists; arXiv preprint only |
| E5 🟢 | prompt §4.1 | "Park 2015" | It is a GLOBECOM 2015 paper, not a letter |
