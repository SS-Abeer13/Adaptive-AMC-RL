# Round 1 revision notes (24 Nov 2026)

Draft v13 → Round 1. **24 pages → 9 pages. Main text ≈ 15,300 → ≈ 4,650 words** (appendix ≈ 1,000).
Every number still comes from `numbers.tex` / `pending_values.tex` macros. No number was typed by hand.

## What changed
- **One story:** the "comparator ladder". Rung 1 = OLLA, rung 2 = calibrated rules, rung 3 = supervised one-step learner.
- **New abstract:** problem → motivation → method → findings in two sentences. No result numbers.
- **New intro:** plain problem statement, motivation, the research question, approach, findings, 3 contributions (was 5).
- **No stage codes in the main text** (M1, NR2, R1c, R6, G2/G3, HR1, …). Codes now appear only in Appendix E, which maps each check to its code.
- **Related work:** SALAD description corrected (ACK/NACK-based SINR estimation, hypothesis-testing MCS selection, BLER-target control). O-RAN digression removed.
- **New Table III:** what each controller observes, computes per candidate, is trained on, and its actions (review issue 2).
- **"Same information" wording removed.** The combined table's oracle speed class and the supervised learner's per-candidate payload calculation are stated openly.
- **Protocol:** half a page. It states the test order plainly: the supervised comparisons came after the RL confirmation and reuse its traces (review issue 1).
- **New Fig. 2:** the ladder bar chart (pgfplots, drawn from the macros).
- **Tables:** short noun-phrase captions; explanations moved to table notes. The summary table was removed (it repeated numbers).
- **Citations:** `\usepackage{cite}` added → compressed and sorted, e.g. [2]–[7]. Numbering follows first appearance. Acronyms protected in titles (LTE, 5G, QoS, HSDPA, …). Ferrari Dacrema's name fixed. Published venues added for A3C (ICML), Agarwal (NeurIPS), Saravanan (NBDT 2020). Wilcoxon pages fixed.
- **Pitfalls:** moved to a short Appendix D. The slot-stealing text now matches the numbers (it was a goodput *loss*, not a gain).

## Removed from the main paper (should live in the supplement — check that it is there)
- Registry summary and the "valid WIN" table (review issue 3 is fixed there, in Round 2)
- HR1 headroom analysis and its figure (f12)
- Per-seed figure (f4), forest plot (f3), headroom bounds (f5), robustness figure (f6), policy-behaviour figure (f7), PF-timing figure (f8), protocol figure (f9), NR2 verdict figure (f10), latency CDF (f11)
- R1 true-SINR learners, R1c transfer rows, R4 alternative seed intervals, speed breakdown, Deviation D1 details, NR-G10 per-cell combined table
- Terms table, full stage table (replaced by the short map in App. E)

## Please check (facts I inferred while rewriting)
1. The supervised learner uses the 19 features of the **current frame only** (Table III). The old text said "the 19 observable features"; A2C uses 3 stacked frames.
2. "Fixed captures X % of the original policy's gain over OLLA" refers to the original Fixed rule and the original (oracle-base) policy.
3. The fairness claim "at least that of the RL policy" rests on the Jain index of the old Table attrib.
4. The discussion's timing sentence uses `\Athreec{med_resid}`.

## Round 2 (evidence)
- End-of-trace accounting result (Amendment 12) and the PF-definition diagnostic → limitations; abstract qualifier if a headline verdict changes. A TODO comment is in `sec_discussion.tex`.
- Fresh-trace evaluation of the frozen RL and supervised policies (new amendment, no retraining).
- Symmetric seed-level check; registry eligibility fields; R6b numbers; time the supervised learner; DOI/archive; S5 reference.
- Decide which removed figures to restore (my suggestion: a per-seed plot of RL vs the supervised learner).

## Round 3 (language)
- Read-aloud pass by the author and supervisor; adapt to the target journal's template (Computer Communications uses `elsarticle`).
- Full citation audit against the source papers (2025–2026 entries especially).
