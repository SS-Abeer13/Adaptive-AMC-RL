# Manuscript and submission checklist (TMLCN; portable to OJ-COMS / OJVT)

Started at Checkpoint 4 (4 Nov 2026). It is extended in Phases 7–8. Sources: `paper/venue/venue_decision.md` (TMLCN confirmations).

## A. Before submission (author)
- [ ] Confirm the **page limit** on the TMLCN submission portal (ieee.atyponrex.com/journal/MLCN). Target 13–15 pages.
- [ ] Confirm the APC (**US$2,160** for 2026 submissions; member discounts) and the funding source.
- [ ] ORCID iDs for all authors.
- [ ] Choose the backup route if needed: OJ-COMS → OJVT (TVT only if its portal allows ≥ 14 pages at submission).

## B. arXiv / preprint (IEEE Electronic Posting Policy)
- [ ] If posted before or at submission, the **first screen of the preprint** must read exactly:
  > "This work has been submitted to the IEEE for possible publication. Copyright may be transferred without notice, after which this version may no longer be accessible."
- [ ] On acceptance: add the IEEE copyright notice to posted versions and send IEEE the URL of the primary posting.
- [ ] After publication: replace the posted version with the full IEEE citation, or the accepted manuscript with the copyright notice and citation. **Do not post the final IEEE PDF.** Never present a preprint as the published version.

## C. AI-use disclosure (IEEE Author Center, PSPB Operations Manual §8.2.1)
- [ ] In the **Acknowledgments**, disclose AI-generated content (text, figures, images, code). Name the AI system, identify the sections concerned, and briefly state the level of use. Draft wording, to be adjusted by the author to the actual use:
  > "Parts of this manuscript's text, the analysis scripts in Section VI and the literature verification scripts were prepared with the assistance of [AI system name and version]. The AI system was used to [draft and edit text in Sections …; write and check analysis code; verify bibliographic records]. All numerical results were produced by the authors' simulator and were checked against the archived result files. The authors take full responsibility for the content."
- [ ] Editing and grammar-only use: disclosure is not required but is recommended (covered by the wording above).
- [ ] No AI system is listed as an author.

## D. Content that must be in the main text or appendices (reviewers may not open code)
- [ ] Information table (which scheme uses which signals); FixedPU described as a class oracle.
- [ ] Full evaluation protocol: comparators, calibration budgets, CRN, splits, decision rules, fairness guard, multiplicity paragraph.
- [ ] Pitfalls section and the "results withdrawn or superseded" table.
- [ ] Hyper-parameters, complexity (parameters, MACs), and training cost in an appendix.
- [ ] Seed-level statistics (hierarchical bootstrap) next to the trace-level tests.

## E. Supplementary material (uploaded as separate files at submission; review not guaranteed)
- [ ] Case registry (108 rows, with `correction` column) as CSV + PDF table.
- [ ] Per-case full comparator tables.
- [ ] Code and data link (GitHub/Zenodo). TMLCN "strongly encourages" a GitHub link in the camera-ready version.

## F. Wording rules (pre-registrations + Checkpoints)
- [ ] No "definitive", "proves", "firmly", "hype".
- [ ] "Calibrated rules built on the learner's cues" until G6 is done. "Same-information" only if M1 beats the G6 combined comparator.
- [ ] M2 is described only as a replication.
- [ ] LOLLA: cite arXiv 2606.23110v1 Table V(a) for 254/185/171 Mbps. Frame it as a reporting recommendation.
- [ ] The gain vs OLLA is quoted with the warm-up result if W1 changes it materially.

## G. Desk-reject checklist (checked 12 Nov 2026 on the v10b build)
| Check | Status | Note |
|---|---|---|
| Scope sentence in the first lines of the abstract | ✅ | "We study downlink link adaptation in a simulated multi-user NR-like cell…" |
| Contributions visible on p. 1 | ✅ | One-sentence C1–C4 preview on p. 1; full list on p. 2 |
| Abstract ≤ 250 words | ✅ | 243 words (pdftotext count) |
| Figures legible in grayscale | ✅ | Checked pp. 9–13 rendered in gray; series differ by marker shape and fill, not colour alone |
| Length 13–15 pp | ⚠️ | Main text ends on p. 14 (Conclusion); references and Appendices A–E bring the PDF to 18 pp. **Confirm the portal limit.** If the limit counts all pages, move Appendices B–E (full tables, calibrated tables, programme table, registry) to the supplement → about 15–16 pp |
| Recent references, TMLCN references | ✅ | 47 references; about half of the cited years are 2022 or later; Cyrus+ (TMLCN 2025) cited |
| Minimal self-citation | ✅ | None (author list still to be completed — re-check after) |
| Data and code statement | ⚠️ | Section present; **Zenodo DOI placeholder** |
| AI-use disclosure | ⚠️ | Placeholder in Acknowledgments; wording in Section C above |
| arXiv notice | ⚠️ | Only if posted; exact IEEE text in Section B |
| Numbers audit | ✅ | `audit_numbers.csv`: 1 315 numeric tokens, 924 from macros, 46 from pending values, 8 intended literals, 6 checked by hand (actor 57-128-96-3; learning rates), 0 unmatched |
| Citations vs bibliography | ✅ | 47 cited keys, all in refs.bib, all VERIFIED in lit/verification_report.csv; no UNVERIFIED entries; 0 BibTeX warnings |
| No withdrawn or superseded result presented as valid | ✅ | v7/v8 withdrawn, v15/v16 RTT>0 superseded, G10 M1-recipe negative and NR-G10 reported together |
| check_pending --final | ✅ | "OK (final gate passed)" |
| Freeze hashes | ✅ | FREEZE.sha256 v8, 14/14 OK at session start; HR1 logs 9/9 OK |

## H. Placeholders the authors must fill
- [ ] Author names, affiliations, ORCID iDs (`main.tex` \author).
- [ ] Funding and grant numbers (Acknowledgments).
- [ ] Conflicts of interest (Acknowledgments and portal).
- [ ] AI-assistance disclosure text (Acknowledgments; Section C).
- [ ] Zenodo DOI (availability statement in `sec_conclusion.tex`, cover letter, README of the release).
- [ ] Cover letter: date, corresponding author, optional exclusions.

## I. Portal upload set (`paper/submission/`)
- `manuscript.pdf` — main PDF (18 pp, IEEEtran journal).
- `latex_source.zip` — compiles stand-alone with pdflatex (main.tex, sections, generated numbers, tables, figures, refs.bib and main.bbl, IEEEtran class).
- `supplementary_material.pdf` — supplement (registry, full tables, freeze timeline). Note: built before HR1; HR1 values are in the main text and in `paper/analysis/out/hr_*.csv`.
- `cover_letter.md` → paste or convert to PDF.
- `response_letter_skeleton.md` — for the revision round.
- `audit_numbers.csv` — internal, not for upload.
Confirm on the portal: file types accepted, whether a separate graphical abstract or highlights are required, the page-count rule, and keywords from the IEEE taxonomy.
