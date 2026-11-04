# Pre-registration A6: PF-timing demonstration for pitfall F8 (v17pf)

**STATUS: FROZEN (Checkpoint 5b, 4 Nov 2026), before any run started** (`AMENDMENTS.md`, amendment 1). Results go in §6 only. Common rules: `common_rules.md`. **Class: approved with the condition that it gets its own frozen text and joins the queue after G10.** It needs new evaluations (no training), so it is not a free analysis.

## 1. Question
Does the timing of the PF average update (at transmission time vs at ACK time) change the goodput and fairness of the **same** schemes on the **same** traces, and does the effect depend on HARQ round-trip time and the number of processes? Today the ACK-time numbers come from a 6-trace scan (README_v17 §1) and the scheduling-time numbers from different 20-trace runs, so they cannot share one honest figure (ledger H17, H17a).

## 2. Design (descriptive; no claim about RL)
- **Frozen v17 code**, M3's full-buffer goodput environment, `drain = true`, `useful_bits = true` in **both** arms. The only factors: `pf_avg ∈ {'acked','scheduled'}` and HARQ ∈ {(RTT 0, 1 process), (RTT 8, 1 process), (RTT 8, 8 processes)}: 6 cells.
- **Schemes:** Baseline, OLLA (10 % target), Fixed (offset −1, M3's calibrated value). All three are deterministic.
- **Traces:** 100 traces, seeds **800001–800100**, CRN **810001+**, identical in all 6 cells (code asserts disjointness from v9–v17, G6, G10).
- **Reported per cell and scheme:** goodput, Jain index, edge5, with 95 % CIs over traces. Paired differences between the two PF modes at equal HARQ settings, with 95 % CIs.
- **Gate:** before the stage runs, `test_equivalence_v17.m` (B2.1: `acked` + `drain = false` reproduces v16 bit for bit) must pass in the same session.

## 3. Pre-registered expectation and wording (no decision rule on a hypothesis; the wording follows the measurement)
- **Expectation E:** under `acked`, 8 processes at RTT 8 give a goodput more than 10 % above 1 process at RTT 8 for each of the three schemes, and Jain falls by more than 0.02; under `scheduled`, the 8-process / 1-process goodput ratio at RTT 8 lies in [0.97, 1.03] and |ΔJain| ≤ 0.02.
- **If E holds for all three schemes:** F8 shows it, and the text says "the timing of the PF average, not HARQ itself, accounts for the apparent gain in this diagnostic (goodput +x % to +y % across schemes)".
- **If E holds for some schemes only:** the text reports the measured range per scheme and drops "every scheme".
- **If E does not hold:** F8 and the pitfall paragraph are revised to the measured values; the H17 6-trace figure is then quoted only as the original diagnostic.
- **If A6 is not run:** F8 becomes a row of T5 with H17 (+39.6 % Baseline, 6 traces) and H17a (10–26 % across schemes, confounded).

## 4. Compute (basis `compute_basis.md`)
3 schemes × 6 cells × 100 traces = 1,800 evaluations × 0.095 s ≈ **3 min**, plus the equivalence test (≈ 2 min) and the preflight.

## 5. Multiplicity and the registry
A6 trains nothing and tests no hypothesis. It is added to the registry as **one case with role `diagnostic`** (no scheme-evaluation rows of an RL scheme): project total 73 cases after all runs (67 + W1 1 + G6 1 + NR1 1 + G10 2 + A6 1).

## 6. Stage specification for the runner (`Optimized/v17x/`, stage `a6`)
`stage_a6(ctx)`, `stage_a6_preflight(ctx)`. Units: `equiv_test`, `cell_<pfmode>_rtt<R>_np<P>` (6). Outputs: `fill_summary_v17pf.txt`, `a6_pf_timing.csv` (per cell and scheme: goodput, Jain, edge5, CIs; paired differences). Gate: the equivalence test passes.

## 7. Results
*(empty until run)*
