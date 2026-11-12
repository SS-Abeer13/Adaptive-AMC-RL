# Meta-review — "When Does Deep Reinforcement Learning Help Link Adaptation? A Pre-Registered Evaluation Against Calibrated Rules" (draft v10, target IEEE TMLCN)

## Per-reviewer verdicts
- **alfa** — Major revision: the methodological point is valuable, but the decisive statistical claims rest on under-powered seed-level inference, post hoc design selection, a single-seed estimand that the ensemble result contradicts, and an over-read headroom analysis.
- **bravo** — Major revision: the +3.35 % NR2 gain cannot be attributed to learning rather than to the richer state, action prior and reward, because there is no component ablation and no information-matched non-learned control.
- **charlie** — Major revision: the "pre-registered/confirmatory" framing, the tuning of the strongest comparator, simulator validity, the thin seed and operating-point evidence for the recommended recipe, and the incomplete release do not yet support the conclusions.
- **delta** — Major revision: no in-MAC/dApp latency for the recommended policy, no second link-level or testbed environment, and the artefact release is still a placeholder.

## Common concerns
- **"Pre-registered / confirmatory" is stronger than the design supports** (alfa, bravo, charlie, delta). Recipe, comparator and NR2 were fixed after M1, G6 and NR1 results; only NR2 is a clean confirmatory test. charlie: "A pre-registration written after the exploratory phase protects only against analytic flexibility within NR2."
- **Trace-level p-values (4.6e-27) and the Bonferroni bookkeeping are over-read or inconsistent** (alfa, bravo, charlie, delta). alfa: "A p of 10⁻²⁷ is therefore a statement about a quantity the authors themselves say is not what a practitioner experiences." Factors 972 vs 1 260 and case counts 67/76 need one reconciliation table.
- **Headroom analysis (HR1) is over-interpreted** (alfa, bravo, charlie). The abstract's causal sentence and the "estimate headroom first" recommendation are not validated; the 0.24-point difference explains under 10 % of the 2.7-point realised gap.
- **Comparator quality: degenerate bandits (41.8 %), duplicated rows, and a combined table that is under-searched, grid-clipped and not information-matched** (alfa, bravo, charlie, delta). bravo: "In effect the paper compares a rich-state learner against a coarse-state table and credits the difference to learning."
- **No non-RL learned control on the same features** (alfa, bravo, charlie): deploy the HR1 gradient-boosted predictor (or a hand-written busy/slack/burst rule) as a scheme.
- **Single simulator with an SINR-to-BLER abstraction; no second environment** (alfa, charlie, delta).
- **Operating-point generality is thin** (alfa, bravo, charlie, delta): neighbouring points use 5 seeds, single-cue comparators only, and the recipe was changed after the original recipe failed there.
- **Recommended configuration lacks the diagnostics of the original** (alfa, bravo, charlie, delta): no speed breakdown, warm-up, fairness/edge or action analysis for NR2.
- **Release, disclosures and authors are placeholders** (alfa, bravo, charlie, delta).
- **Section VI-D.3 reads as two drafts** (alfa, bravo, charlie).
- **"58 % removed by re-calibration" conflates re-calibration with adding a richer comparator** (alfa, charlie).

## Unique concerns
- Seed-level estimand: the ten-seed ensemble (0.6306) beats the combined table by far more than the per-seed mean; the conclusion should be scoped to single-policy deployment (alfa; charlie mentions it as a minor point).
- Percentile hierarchical bootstrap with 10 (or 5) top-level clusters may under-cover; use a seed-level t/BCa interval or mixed model, align R1/R2 levels, add a power calculation (alfa).
- Missing component ablation of the recipe (features, logit bias, deviation penalty, reward shaping) (bravo).
- Decision latency measured in Python on a laptop for the oracle-base policy; the recommended policy is untimed; no description of how the features reach a DU/dApp via E3 (delta).
- Deployment robustness: distribution shift, guardrails, which seed to deploy (delta).
- Literature screening protocol is not auditable (charlie; alfa minor).

## Ranking
1. **bravo** — names the single most consequential gap (learning vs information/prior attribution) and gives a cheap, concrete distinguishing test.
2. **alfa** — the deepest statistical critique (estimand, cluster bootstrap coverage, p-value meaning, 58 % decomposition), each with an actionable fix.
3. **charlie** — a thorough design critique of the pre-registration chain and comparator asymmetry, largely overlapping alfa and bravo.
4. **delta** — the right venue-specific systems questions (latency, placement, realism), but these are partly acknowledged limitations rather than flaws in the claims made.

## Verdict synthesis
**Major revision.** All four reviewers agree. The protocol, the honest negative results and the failure ledger are valued by every reviewer. The blocking issues are framing and attribution, not fraud or error: the confirmatory status must be limited to NR2; trace-level p-values must yield to seed-level evidence; the headroom analysis must not carry causal weight; and the recommended recipe needs either an information-matched non-RL control or narrower wording. Several fixes are text-only (framing, p-values, HR1 wording, VI-D.3 rewrite, 58 % decomposition, count reconciliation, placeholders). Others need new runs or analyses (GBT/hand-rule comparators, NR2 diagnostics from logged data, seed-level re-analysis, a second environment, in-MAC latency) and should be proposed rather than run in this round.
