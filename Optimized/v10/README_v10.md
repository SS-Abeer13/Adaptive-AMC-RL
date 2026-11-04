# v10 — cases where a learned link-adaptation policy has a structural advantage

Written **before** any v10 result was produced (20 Oct 2026). v10 = v9 + optional switches;
with the defaults v10 reproduces v9 bit-for-bit (checked: identical channel, CQI and
OLLA / Baseline / Multi-OLLA / Fixed throughput on a test trace).

## Why v9 showed no A2C gain
Under physical mobility each user's channel is quasi-stationary and the feedback is
reliable, so OLLA (or one fixed offset) is close to optimal and the learned policy only
adds exploration noise. A learned policy can only win where OLLA's assumptions break
*and* the policy observes something OLLA cannot use. Each case below creates exactly one
such gap, gives A2C one extra **gNB-observable** cue, and gives the simple methods the
same cue through a calibrated context table.

| Case | Environment change | Extra A2C cue (gNB-side) | Why OLLA cannot exploit it |
|---|---|---|---|
| E1_train | none (v9 headline point) | none | control: narrowed actions −4…+2, 1500 episodes, entropy 0.03→0.001, actor lr 3e-4 |
| E2_stale | 60–120 km/h, CQI delay 4–10 TTI, one CQI report every 5 TTI (held) | report age; report minus the user's long-run report mean | the report is noise around the mean after decorrelation; the best correction depends on the report's own deviation and age, OLLA applies one average offset |
| E3_cellcue | stronger (12 dB), shorter (40 TTI) cell-wide bursts; CQI delay 4–10 | cell-wide NACK rate pooled over all users | per-user OLLA only learns of a burst from its own NACKs (scheduled ~1 in 10 TTIs) and from CQI after 4–10 TTIs; the pooled rate reveals it in 1–2 TTIs |
| E4_deadline | packets with a 10-TTI budget (12 kbit, every 20 TTI, outdoor users); primary metric = on-time delivery ratio; A2C reward = +1 on time, −1 missed | deadline slack, remaining bits | OLLA holds one BLER target; the best risk depends on the slack (aggressive early, safe near the deadline) |

Ablations `*_nofeat`: same environment, same comparators, A2C without the extra cue —
shows whether any gain comes from the cue rather than from the environment.

## Comparators (all calibrated on calibration traces, disjoint from evaluation traces, on the primary metric)
Baseline, OLLA, **OLLA with tuned target BLER** (grid 1–50 %), Multi-OLLA, Fixed, FixedPU
(per-class oracle), **Context table** (OLLA + one offset per bin of the same cue A2C gets,
coordinate ascent over −4…+2), UCB bandit (global, delay class). Warm-OLLA and
Fixed-Online were dropped (weaker than OLLA / FixedPU in v9). Common random numbers,
100 evaluation traces, 5 seeds, PF, Tier O.

## Pre-registered win criterion (per case)
A2C wins a case iff, on the primary metric, it beats **every** comparator with
Holm-adjusted Wilcoxon p < 0.05 **and** a 90 % CI lower bound > 0 (`WIN|...|=1`).
Reported for every case whatever the outcome; no case is dropped and no case is
re-tuned after its result is seen. A positive result against OLLA only, or against
everything except the context table, is reported as such (partial).

## Run
`run_v10_headless.bat` (preflight, then campaign). Progress: `Dataset/fill_summary_v10.txt`
(STEP / ERROR / WIN lines), full log `logs/fill_v10.log`. Resumable: rerun the .bat and
finished points are skipped.

## Follow-up (pre-registered 20 Oct 2026, 23:40 — after v10 / v10b, before these runs)
v10 E4 gave a partial win (beats every comparator except the best fixed offset, +0.21 %, n.s.);
the goodput cases E1–E3 gave no win (v10 reward defect, v10b = OLLA-equivalent policy).
Two runs, same win criterion, reward = on-time, nothing else re-tuned:
- **E4c_deadline** — E4 exactly as before, 300 evaluation traces (the first 100 are the v10
  traces), to settle the tie with Fixed. Reported as a confirmation of E4, not a new case.
- **E5_mixed** — users alternate 4-TTI and 10-TTI latency budgets. A single fixed offset
  cannot suit both. A2C also observes its own budget; to keep the comparison fair the
  context table uses budget class × slack (6 bins), so a calibrated per-class rule has the
  same information. Ablation `E5_mixed_nofeat` (no slack / budget cue).
- Note on multiplicity: with E4 counted once, five cases were tested in total; a win is
  reported together with that count.
