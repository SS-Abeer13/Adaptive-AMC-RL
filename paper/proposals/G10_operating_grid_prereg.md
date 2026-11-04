# Pre-registration proposal: G10, operating-point grid under the v17 configuration (v17c-grid)

**Status:** PROPOSAL for Checkpoint 5. Nothing has been run. Once approved, §§1–6 are frozen.
**Run by:** the author on the PC (MATLAB R2023a), with the frozen v17 code and **no code changes**: only case structs are added to a copy of `v17_setup.m`.

## 1. Question

The only load/deadline grid (v14 Y1–Y4) predates the v17 PF fix and ran at RTT 0. Its verdict was "operating-point specific". Does the M1 result (RTT 8, 8 processes, 12 kbit, 10-TTI budget) carry over to neighbouring loads and deadlines under the v17 configuration?

## 2. Cells

All cells use M1's configuration: RTT 8, 8 processes, `pf_avg = 'scheduled'`, drain, useful bits, the same comparators and calibration as v17, and residual A2C with 3000 episodes.

| Cell | Packet bits | Deadline (TTI) | Note |
|---|---|---|---|
| G1_lo_d10 | 8,000 | 10 | lighter load, M1 deadline |
| G2_hi_d10 | 16,000 | 10 | heavier load, M1 deadline |
| G3_lo_d18 | 8,000 | 18 | lighter load, budget allows 2 HARQ rounds |
| G4_hi_d18 | 16,000 | 18 | heavier load, 2 HARQ rounds |

**Why 10 and 18, not v14's 6 and 14.** With RTT 8, a 6-TTI budget means no retransmission can ever arrive in time, so HARQ would play no role. A budget of 18 (≤ the 20-TTI packet period) allows two feedback rounds. The rest of the setup mirrors v14: one load step either side of M1's 12 kbit.

**Feasibility rule (v14 C2, unchanged):** Fixed on-time ratio on 20 calibration traces must lie in [0.50, 0.97]. Otherwise move the packet size one step towards 12,000 (8,000 → 10,000; 16,000 → 14,000). If the cell is still outside, mark it infeasible and do not run it.

- **Seeds:** 5 per cell, residual A2C, 3000 episodes. Fresh seed blocks: base seeds 30042, 31042, 32042, 33042.
- **Traces:** 300 evaluation traces per cell. Trace seeds 700001+, 720001+, 740001+, 760001+, with CRN at +10000. All ranges are disjoint from v9–v17.
- **Primary scheme:** the 5-seed mean. The ensemble is secondary.

## 3. Decision rules

- **Per cell:** Claim A, Claim B and WIN, exactly as in v17 C3 (Holm over 9, 90 % CI lower bound > 0). The fairness guard is applied too.
- **Grid verdict** (same rule as v14 C4): **"robust"** if Claim A passes in ≥ 3 feasible cells **and** the margin vs the best calibrated rule is ≥ 0 in ≥ 3 feasible cells. Otherwise **"operating-point specific"**. The number of Claim B passes is also reported.
- **Seed-level check:** a hierarchical bootstrap 90 % CI (seed × trace) for each cell's margin vs the best rule. With 5 seeds this is reported as indicative only.

## 4. Pre-registered wording

| Verdict | Paper statement |
|---|---|
| robust, with Claim B in ≥ 3 cells | "Under realistic HARQ timing the gain over every comparator extended to neighbouring loads and deadlines (k of 4 cells; margins +a % to +b %)." |
| robust, Claim B in < 3 cells | "The gain over the OLLA family was robust across loads and deadlines (4/4 cells), while the margin over calibrated rules was non-negative in k cells but significant in only m." |
| operating-point specific | "The gain over calibrated rules is specific to the operating point studied (M1); at neighbouring loads/deadlines it was not reproduced (per-cell table)." This goes in the robustness section **and** the abstract's scope sentence. |

## 5. Compute estimate (from v17 M1 timing)

- M1 used 160.8 min of cumulative compute (`STEP|M1_dl_rtt8|done … elapsed_min=160.8`). That covered 10 × 3000 + 10 × 800 + 10 × 800 = 46,000 training episodes plus evaluation of 14 schemes on 500 traces, on 2 workers. This is an upper-bound rate of about 0.21 min per 1,000 episodes per worker.
- Per cell: 5 × 3000 = 15,000 episodes, about 15,000 / 46,000 × 161 ≈ **53 min**, plus evaluation on 300 traces and calibration, about **10–15 min**. So about **65 min per cell**.
- **Total: about 4.5 h** for 4 cells on 2 workers, plus a 20-trace feasibility check (~10 min). The memory limit (16 GB) needs `n_workers = 2`, as in v17.

## 6. Multiplicity

This adds **4 cases** (4 primary scheme evaluations + 4 secondary ensemble rows). Project total after the run: 71 cases (72 if G6 also runs). The grid is a robustness check. It cannot produce a new headline claim, and it can only narrow the M1 claim.

## 7. Results

*(empty until run)*
