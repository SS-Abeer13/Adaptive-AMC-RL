# Paper status

**Branch:** `claude/magical-heisenberg-iek5sg` (session branch; mirrored to `paper-draft` when push access allows; see the last line).
**Current phase:** 2 (literature research), in progress. Next stop: **Checkpoint 2**.

## Checkpoint 1: approved 4 Nov 2026, with conditions. Status of each condition

| Condition | Done | Where |
|---|---|---|
| 67 cases / 108 evaluations; both views (67 project-wide, 7 cases / 18 evaluations superseded; 49 from v10) | ✅ | ledger M06; multiplicity.md §6 draft paragraph |
| M1 project-wide Bonferroni (8.8e-10 over 972) in the multiplicity paragraph | ✅ | multiplicity.md §6 |
| M2 strictly a replication | ✅ | ledger R16, G3e, M05 |
| X1: `correction` column, no overwrite; corrected verdict used everywhere | ✅ | `Optimized/case_registry.csv` (+2 copies, + builder); ledger H13, M03 (9 valid WIN cases) |
| Drop "open-loop beats OLLA" as a contribution; keep it as a pitfalls example | ✅ | ledger H05 |
| "Both PF variants" limited to the RTT-0 deadline wins; v15/v16 RTT > 0 never cited as support | ✅ | ledger S08b, H17 |
| Verify that pre-v17 RTT-0 runs used the delivered-bits PF update; log file and line | ✅ | ledger S08a (v9, v13, v14, v16; eval and training) |
| Goodput negative result from v17 M3/M4 only | ✅ | ledger H04 |
| Withhold 92 %/76 % and the action-by-state table | ✅ | ledger R23, R24 → NOT USABLE |
| Define "M3 matches FixedPU exactly" | ✅ | ledger R19a: bit-identical goodput, cell throughput, Jain, edge5 in 5000/5000 seed × trace cells; M4 is **not** identical |
| G1 MATLAB script + spec | ✅ | `Optimized/v17/g1/`, `paper/analysis/G1_SPEC.md` (the existing logs are insufficient; instrumented re-evaluation, no training) |
| README fixes as a separate commit with ledger IDs | ✅ | commit `7d085c9` (README.md, README_v17 + release, registry, figure script) |
| `margin_vs_rtt` script reads only v17 CSVs; image marked "do not use" | ✅ | `generate_v17_figures.m`; asset_inventory.md |
| G3 now (sign test, seed t-test, hierarchical bootstrap) | ✅ | `paper/analysis/g3_seed_stats.py`, `out/g3_seed_stats.csv`; ledger G3a–G3f |
| G6, G10 pre-registration proposals | ✅ | `paper/proposals/` |
| Triage of the other gaps | ✅ | gaps.md (Triage) |

## Author actions pending (on the PC)
1. Run `addpath('g1'); g1_recut_v17` in `Optimized\v17` (≈ 20–60 min). Send back `paper/g1/g1_summary.txt` and `g1_action_by_state.csv`.
2. Run `generate_v17_figures` to regenerate `margin_vs_rtt`.
3. Decide on G6 and G10 at Checkpoint 5 (≈ 3–6 h and ≈ 4.5 h compute).

## Notes
- G3 changes two earlier statements. The M1 resid-800 "win" does not survive seed resampling, and M2 vs the Context table has a hierarchical 95 % CI that includes 0. Both are now in the ledger.

## Next step
Phase 2 literature: `paper/lit/` (search_log, bibliography.bib, lit_matrix.csv, gap_analysis.md), then Checkpoint 2.
