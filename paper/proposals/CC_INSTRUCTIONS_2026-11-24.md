# Instructions for Claude Code (PC), 24 Nov 2026: fresh-trace confirmation (Amendment 13)

**Repository:** `D:\Adaptive AMC A2C+QL`, branch `paper`.

**How to work through this:**
- Do the tasks **in order**.
- Stop and report at the first failed acceptance check.
- **Nothing is retrained, refitted or re-tuned.**

**Before you start, the author does two things by hand:**
1. Copy the Round 2 manuscript files into `paper/manuscript/`.
2. Copy `FT_fresh_trace_prereg.md` into `paper/proposals/`.
3. Copy this file into `paper/proposals/` as `CC_INSTRUCTIONS_2026-11-24.md`. It is committed with the freeze in Task 3.

---

## 0. Ground rules (unchanged from 19 Nov, repeated because they matter)

**Files**
- You own `Optimized/`.
- Under `paper/`, only **create the new files named in a task** and stage the files a task names. Never edit existing files; the one exception is the append to `AMENDMENTS.md` and `FREEZE.sha256` in Task 3.
- **Never run `git checkout`, `restore`, `reset`, `stash` or `clean` on `paper/`** or on the whole tree.
- Never edit a file listed in `paper/proposals/FREEZE.sha256`.
- Never change shared simulator functions. New code goes into `Optimized/v17x/ft/`.

**Git**
- If `.git/index.lock` exists, wait 30 s and check again. Never delete a lock you did not create.
- Stage files by name. Never `git add -A` or `git add .`.
- Keep line endings; commit no CR/LF-only changes.
- Commit identity: `SS-Abeer13 <155192927+SS-Abeer13@users.noreply.github.com>`.
- **No Claude author, no `Co-Authored-By`, no `Claude-Session` line, and no mention of Claude in commit messages.**
- Push after each task. Never force-push.

**Every stage**
- Preflight, plus the 1.5× compute rule with `APPROVE_<stage>.txt`.
- Heartbeat lines.
- Rule R6: one retry, then halt.
- Checkpoints keyed by a hash of every `.m` file in `Optimized/v17x/ft/` and the config.

**Reporting**
- Paste key lines, not paraphrases.
- No claims beyond the data.

---

## Task 0: State check (~10 min, read-only)

1. Report how far the 19 Nov instructions got:
   - is Amendment 12 / Freeze v14 committed (give the hash)?
   - Steps 2–4 done or not;
   - if `eot_summary.txt` exists, paste it in full.
2. `cd paper/proposals && sha256sum -c FREEZE.sha256`: paste the summary line.
3. `git status --short paper/manuscript`: list the changed Round 2 files. Don't commit them yet.

**Acceptance:** the freeze verifies, and the state is reported.

---

## Task 1: Commit the Round 2 manuscript (~10 min)

1. Build `paper/manuscript/main.tex` (pdflatex, bibtex, pdflatex ×2).
2. The log must contain **no `!` errors and no undefined references or citations**. Paste the page count.
3. Stage by name only:
   - `main.tex`, `refs.bib`;
   - `sec_intro.tex`, `sec_related.tex`, `sec_system.tex`, `sec_method.tex`, `sec_protocol.tex`, `sec_results.tex`, `sec_discussion.tex`, `sec_conclusion.tex`, `sec_appendix.tex`;
   - `ROUND1_NOTES.md`, `ROUND2_SKELETON.md`.
4. `git diff --cached --stat` must show no CR/LF-only rewrites.
5. Commit `paper: Round 2 rewrite (comparator-ladder structure, insight-first text)`, then push.

**Check while you are there:** do the GBT-ACK learners use the 19 features of the **current frame only**, or 3 stacked frames as A2C does? Quote the line that builds their feature matrix.

---

## Task 2: Write the FT stats script and validate it on synthetic data only (~1 h)

1. Write `paper/analysis/ft_stats.py`, implementing §4 of `paper/proposals/FT_fresh_trace_prereg.md` **exactly**:
   - the symmetric per-fit rule;
   - the Holm families;
   - the crossed hierarchical bootstrap: **one shared trace-ID sample per replicate across all resampled RL seeds**, 10,000 replicates, fixed seed;
   - the family verdicts;
   - H3 through NR2's existing frozen verdict function. Import it; don't copy it.
2. Reuse the input layout of `r6_stats.py`.
3. `--selftest` on synthetic data with known answers. It must cover at least:
   - all 4 fits clearly better → "holds";
   - 2 of 4 better → "fit-dependent";
   - null → "does not replicate";
   - one fit worse → "reverses".
4. **It must never read a file under `Dataset/ft/`.**
5. Write `paper/proposals/FT_objects.sha256`: SHA-256 of every object in §2 of the prereg. Every file must exist and load.

**Acceptance**
- The selftest passes, with all four synthetic cases correct.
- `FT_objects.sha256` lists 37 schemes' files, or explains any shared file.

---

## Task 3: Freeze Amendment 13 (~10 min)

1. Append to `paper/proposals/AMENDMENTS.md` (append only, no rewrite):
   > **Amendment 13 (24 Nov 2026), Freeze v15.** Fresh-trace confirmation of the frozen policies (FT), symmetric seed check (S-SYM) and supervised-learner timing (T-GBT). Spec: `FT_fresh_trace_prereg.md`; objects: `FT_objects.sha256`; analysis: `paper/analysis/ft_stats.py` (selftest only). Written after the external review and the Round 2 rewrite; no FT trace existed at freeze time. Multiplicity: +1 case, +9 primary and +16 secondary tests.
2. Copy `FREEZE.sha256` to `FREEZE_v14.sha256` (or to the current version name). Then add the three new files to `FREEZE.sha256`.
3. `sha256sum -c FREEZE.sha256`: all OK.
4. Stage by name (`AMENDMENTS.md`, `FREEZE.sha256`, the `FREEZE_v14` copy, `FT_fresh_trace_prereg.md`, `FT_objects.sha256`, `CC_INSTRUCTIONS_2026-11-24.md`, `paper/analysis/ft_stats.py`), commit `prereg: Amendment 13 / Freeze v15 (FT fresh-trace confirmation, S-SYM, T-GBT)`, then push.
5. **Report the hash. It is the freeze commit.** No FT trace may be generated before it.

---

## Task 4 (GATED on Task 3): Run FT (time from the preflight)

1. **Disjointness:** assert in code that the trace, CRN and decision-draw ranges of §3 overlap no range used so far. Print the list of ranges checked.
2. **Env check:** compare the FT env with the frozen NR2 env field by field. Any difference stops the stage.
3. **REPRO (hard stop):** traces 1–20 of the **NR2** set, every scheme of §2, through the FT code path. They must reproduce the stored per-trace values **exactly**.
4. **Preflight:** 5 calibration traces; projected hours; `APPROVE_ft.txt` under the 1.5× rule.
5. **Run:** all 37 schemes on FT traces 1–500, as-run accounting. Save `Optimized/v17x/Dataset/ft/pertrace_ft_asrun.csv`.
   - **No summaries, plots or prints of FT results until every scheme has finished all 500 traces.**
6. **Only if the `_eot` evaluator passed its bit-identity gate:** repeat the run in `'resolved'` mode into `pertrace_ft_resolved.csv`, with the exposure counters from the as-run pass.
7. Run `ft_stats.py` **unchanged** on the as-run file, then on the resolved file into a separate output folder.
8. Commit `results(ft): fresh-trace confirmation of the frozen policies`, then push.

**Acceptance**
- REPRO is exact.
- `Optimized/v17x/Dataset/ft/ft_summary.txt` gives, per family and per fit:
  - margin;
  - 90 % trace CI;
  - 95 % hierarchical CI;
  - Holm p;
  - RL seeds ahead;
  - the per-fit verdict and the family verdict;
  - the selected wording row.
- It also gives the on-time ratio of every scheme on FT traces, next to its NR2-trace value.

---

## Task 5: S-SYM (analysis only; can run while Task 4 trains nothing)

1. Run the symmetric rule on the stored R1c per-trace files (NR2 traces, G2, G3) and on R6a. Use an analysis-only script, `Optimized/v17x/ft/ssym.py`.
2. Output `Optimized/v17x/Dataset/ft/ssym_summary.txt`, one row per frozen comparison:
   - the frozen verdict next to the symmetric verdict;
   - whether the frozen bootstrap used one shared trace sample per replicate (quote the code line).
3. Commit `analysis(ssym): symmetric seed-level check of frozen R1c/R6 verdicts`.

---

## Task 6: T-GBT timing (calibration traces only)

1. Reuse the A3c benchmark harness and protocol: the same CPU, single thread, high priority, timer floor subtracted.
2. Time GBT-res-ACK and GBT-full-ACK fit 1 over the complete decision: feature build, scoring of every candidate MCS, argmax.
3. Output `Optimized/v17x/Dataset/ft/tgbt_timing.txt`:
   - the median and the corrected p99.9 next to the stored A3c values for residual A2C;
   - the share of TTIs within the slot at 15/30/60/120 kHz.
4. Commit `results(tgbt): decision time of the supervised learner`.

---

## Final report (paste back to the author)

- **If any FT family verdict is not "holds on fresh traces", or H3 is not CONFIRM, put that first.**
- Then:
  - `ft_summary.txt` in full;
  - the resolved-mode summary, if it was run;
  - `ssym_summary.txt`;
  - `tgbt_timing.txt`;
  - the disjointness list;
  - the REPRO lines;
  - every acceptance line;
  - the commit hashes;
  - the feature-frame answer from Task 1.
- List any `paper/` file you think needs a change. Do not change it.

---

## Prompt for Claude Code (paste as is)

> Follow `paper/proposals/CC_INSTRUCTIONS_2026-11-24.md` (copy of the 24 Nov instructions) task by task, in order, stopping at the first failed acceptance check. The pre-registration is `paper/proposals/FT_fresh_trace_prereg.md`. **No FT trace may be generated before Task 3's freeze commit exists.** Ground rules in §0 apply throughout, in particular: never run checkout/restore/reset/stash/clean on `paper/`, stage files by name only, commit as SS-Abeer13 with no Claude attribution of any kind. End with the final report as specified.
