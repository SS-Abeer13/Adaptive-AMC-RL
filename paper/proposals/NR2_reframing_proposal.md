# Proposal: reframing the paper if NR2 passes (NOT APPLIED)

**Status:** proposal for the authors, 8 Nov 2026. It applies **only if** NR2 returns **CONFIRM and WIN** (`NR2_confirmatory_prereg.md` §4; `paper/analysis/out/nr2_verdict.txt` says "reframing gate … OPEN"). With any other NR2 outcome this file is closed and the manuscript keeps its current framing. Nothing here changes a frozen text, a decision rule or a reported number.

## 1. What changes and what does not

| Element | Now | After CONFIRM + WIN |
|---|---|---|
| Pre-registered primary result | M1 (residual A2C on the FixedPU class-oracle base) | **unchanged**: M1 stays the pre-registered primary and is reported first in VI-A/B with all its numbers, including the R2 failure against the combined table |
| Recommended configuration | none (M1 is described, not recommended) | **residual A2C on the non-oracle Fixed base** (one calibrated global offset), trained as in M1 |
| Evidence for the recommendation | NR1 (design ablation on M1 traces, no seed level) | **NR1** (exploratory/design ablation) **+ NR2** (confirmatory: fresh traces and seeds, frozen comparator, trace and seed level) |
| Oracle limitation | "the residual inherits the class oracle; NR1 suggests it is not needed" | "the recommended configuration uses no oracle information; the comparator it beats (combined table) does" |
| R2 qualifier in abstract/C2 | required for M1 vs combined table | still required **for M1**; the recommended configuration is stated without it, with its hierarchical CI |
| "same-information" | only with the R2 qualifier (M1) | may describe NR2 vs the combined table only as "against a rule with **more** information (the oracle speed class)", never as same-information |

## 2. Proposed text changes (drafts; numbers come from `\NRtwo{...}` macros)
- **Title:** unchanged. A sub-clause is not needed; the question stays "when does deep RL help".
- **Abstract**, after the M1 sentences: "A residual policy on a non-oracle base rule, found in a design ablation and confirmed in a pre-registered replication on fresh traces and seeds, beat the same combined table at trace level and across training seeds (+x %, hierarchical 95 % CI [a, b] %), although that table uses the true speed class and the policy does not."
- **C2** becomes two sentences: the pre-registered M1 result with its R2 qualifier; then "We recommend the non-oracle residual configuration: in a confirmatory replication (NR2) it beat every calibrated comparator, robustly across seeds."
- **VI-G**: NR1 and NR2 move into a subsection "A non-oracle configuration (NR1, NR2)" after G6, with a table in the format of Table VI (trace and seed level) and a short chronology: M1 pre-registered → G6 → R2 failure → NR1 (ablation) → NR2 (confirmation).
- **Discussion VIII-B ("Calibrate first")**: the base-rule paragraph becomes the main practical message: a non-oracle base calibrated on enough traces plus a learned residual; the class oracle selected on 20 calibration traces was the weaker base (Fixed-500 is +0.82 % above FixedPU-500 on the evaluation traces). Mechanism statements stay "consistent with".
- **Limitations:** remove "NR2 pending"; keep "the recommendation was chosen after seeing NR1 and G6 results; only NR2 is confirmatory" and the operating-point restriction (G10 tested M1-type policies on the oracle/selected base, not the non-oracle recipe, unless G10's selector chose Fixed in a cell).

## 3. What the reframing must not do
- It must not relabel NR1 or NR2 as the primary pre-registered result, or drop any M1 number.
- It must not claim generality beyond M1's operating point (G10 did not test the non-oracle recipe at every cell).
- It must not use NR1's descriptive margin over the combined table as evidence; only NR2's.
- It must not extend "robust across seeds" to M1.

## 4. If NR2 returns TRACE, NULL or REVERSE
The current framing stays. The NR2 wording row is inserted where `\wordingsel{NR2}` already sits (VI-G, limitations). For NULL/REVERSE the discussion's base-rule paragraph is shortened to the descriptive Fixed-500 vs FixedPU-500 comparison, and NR1 is described as not replicated.
