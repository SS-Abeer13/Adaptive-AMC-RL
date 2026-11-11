"""Assemble the supplementary material: case registry, comparator tables, pre-registrations
with hashes and freeze timeline. Run from the repository root or anywhere:
    python3 paper/supplement/build_supplement.py
Writes paper/supplement/files/ (S1-S3 + MANIFEST.sha256 + README.md) and
paper/supplement/supplement.tex. Compile with paper/supplement/make_pdf.sh (needs pandoc + LaTeX).
Nothing outside paper/supplement/ is modified.
"""
import csv, hashlib, os, re, shutil, subprocess
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
P = lambda *a: os.path.join(ROOT, *a)
OUT = os.path.join(HERE, 'files')
if os.path.isdir(OUT): shutil.rmtree(OUT)
for d in ['S1_registry', 'S2_comparator_tables', 'S3_preregistration']: os.makedirs(os.path.join(OUT, d))
GIT_ENV = dict(os.environ, TZ='Asia/Dhaka')   # the run PC's time zone (UTC+6); the runner heartbeat is written in local time
git = lambda *a: subprocess.run(['git', '-C', ROOT, *a], capture_output=True, text=True, env=GIT_ENV).stdout.strip()
sha = lambda f: hashlib.sha256(open(f, 'rb').read()).hexdigest()
def cp(src, sub, name=None):
    dst = os.path.join(OUT, sub, name or os.path.basename(src)); shutil.copyfile(src, dst); return dst

# ---------------- S1 registry
reg = cp(P('Optimized', 'case_registry.csv'), 'S1_registry')
rob = cp(P('paper', 'ledger', 'robustness_cases.csv'), 'S1_registry')
R = list(csv.DictReader(open(reg, newline=''))); RB = list(csv.DictReader(open(rob, newline='')))
n_cases = len({r['case_id'] for r in R}); n_rows = len(R)
rc, rr = sum(int(x['cases']) for x in RB), sum(int(x['rows']) for x in RB)

# ---------------- S2 comparator tables (stage, file, title)
T2 = [('v16', P('Optimized', 'v16', 'paper', 'table_core.csv'), 'v16 cases: residual A2C vs each comparator (trace level)'),
      ('v17', P('Optimized', 'v17', 'paper', 'table_core.csv'), 'v17 main round (M1--M4): every scheme vs each comparator (trace level)'),
      ('W1', P('Optimized', 'v17x', 'Dataset', 'table_warmup.csv'), 'W1: M1 against comparators with cold and warmed-up OLLA'),
      ('G6', P('Optimized', 'v17x', 'Dataset', 'table_cal500.csv'), 'G6: M1 against comparators re-calibrated on 500 traces'),
      ('NR1', P('Optimized', 'v17x', 'Dataset', 'table_nr1.csv'), 'NR1: residual on the non-oracle base, M1 traces'),
      ('NR2', P('Optimized', 'v17x', 'Dataset', 'table_nr2.csv'), 'NR2: confirmatory replication on fresh traces and seeds'),
      ('G10', P('Optimized', 'v17x', 'Dataset', 'table_cells.csv'), 'G10: M1 recipe at two neighbouring operating points'),
      ('NR-G10', P('Optimized', 'v17x', 'Dataset', 'table_cells_nr.csv'), 'NR-G10: non-oracle recipe at the two neighbouring operating points'),
      ('NR-G10 (descriptive)', P('paper', 'analysis', 'out', 'nr_g10_ctxj_descriptive.csv'), 'NR-G10 vs the G10 per-cell combined table (descriptive, not pre-registered)'),
      ('A6', P('Optimized', 'v17x', 'Dataset', 'a6_pf_timing.csv'), 'A6: PF-averaging definition and multi-process HARQ (rules only)'),
      ('A3c', P('Optimized', 'v17x', 'Dataset', 'table_a3c.csv'), 'A3c: per-TTI decision time (one laptop core; descriptive)')]
s2 = []
for tag, src, title in T2:
    name = re.sub(r'[^A-Za-z0-9]+', '_', tag).strip('_') + '__' + os.path.basename(src)
    s2.append((tag, cp(src, 'S2_comparator_tables', name), title, os.path.relpath(src, ROOT)))

# ---------------- S3 pre-registrations, hashes, freeze timeline
FZ = P('paper', 'proposals', 'FREEZE.sha256')
fz = [l.split() for l in open(FZ) if re.match(r'^[0-9a-f]{64}\s', l)]
for f in ['FREEZE.sha256', 'FREEZE_v1.sha256', 'FREEZE_v2.sha256', 'FREEZE_v3.sha256', 'FREEZE_v5.sha256', 'NR2_reframing_proposal.md']:
    if os.path.exists(P('paper', 'proposals', f)): cp(P('paper', 'proposals', f), 'S3_preregistration')
stage_of = {'W1_warmup_prereg.md': ('W1', 'w1', 'Optimized/v17x/Dataset/table_warmup.csv'),
            'NR1_nonoracle_residual_prereg.md': ('NR1', 'nr1', 'Optimized/v17x/Dataset/table_nr1.csv'),
            'G6_calibration_budget_prereg.md': ('G6', 'g6a', 'Optimized/v17x/Dataset/table_cal500.csv'),
            'A6_pf_timing_prereg.md': ('A6', 'a6', 'Optimized/v17x/Dataset/a6_pf_timing.csv'),
            'G10_operating_grid_prereg.md': ('G10', 'g10', 'Optimized/v17x/Dataset/table_cells.csv'),
            'NR2_confirmatory_prereg.md': ('NR2', 'nr2', 'Optimized/v17x/Dataset/table_nr2.csv'),
            'NR_G10_operating_grid_prereg.md': ('NR-G10', 'nr_g10', 'Optimized/v17x/Dataset/table_cells_nr.csv')}
hb = open(P('Optimized', 'v17x', 'logs', 'heartbeat_v17x.txt'), encoding='utf-8', errors='ignore').read().splitlines()
starts = [(l[:19], re.search(r'stages: ([^;]+);', l).group(1).split(',')) for l in hb if '| runner' in l and 'start (stages:' in l]
rows3 = []
for h, f in fz:
    src = os.path.normpath(os.path.join(P('paper', 'proposals'), f))
    ok = sha(src) == h
    cp(src, 'S3_preregistration')
    c = git('log', '--reverse', '--format=%h|%cd', '--date=format-local:%Y-%m-%d %H:%M', '-S', h, '--', 'paper/proposals/FREEZE.sha256').splitlines()
    fc, fd = c[0].split('|') if c else ('', '')
    st = stage_of.get(os.path.basename(f))
    first = rescommit = resdate = ''
    if st:
        s = [t for t, stg in starts if st[1] in [x.strip() for x in stg]]
        first = s[0] if s else ''
        r = git('log', '--reverse', '--format=%h|%cd', '--date=format-local:%Y-%m-%d %H:%M', '--diff-filter=A', '--', st[2]).splitlines()
        if r: rescommit, resdate = r[0].split('|')
    rows3.append(dict(file=os.path.basename(f), stage=st[0] if st else '', sha256=h, verifies='yes' if ok else 'NO',
                      freeze_commit=fc, freeze_time_utc6=fd, first_runner_start_utc6=first, results_commit=rescommit, results_time_utc6=resdate))
with open(os.path.join(OUT, 'S3_preregistration', 'freeze_timeline.csv'), 'w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows3[0])); w.writeheader(); w.writerows(rows3)
bad = [r['file'] for r in rows3 if r['verifies'] != 'yes']
late = [r['file'] for r in rows3 if r['first_runner_start_utc6'] and r['freeze_time_utc6'] and r['first_runner_start_utc6'][:16] < r['freeze_time_utc6']]
if bad or late: raise SystemExit(f'freeze check failed: hash mismatch {bad}, run before freeze {late}')

# ---------------- LaTeX
def esc(s):
    s = str(s)
    for a, b in [('\\', r'\textbackslash{}'), ('&', r'\&'), ('%', r'\%'), ('_', r'\_'), ('#', r'\#'), ('$', r'\$'), ('{', r'\{'), ('}', r'\}'), ('~', r'\textasciitilde{}'), ('^', r'\textasciicircum{}')]:
        s = s.replace(a, b)
    return s
def longtable(path, cols=None, caption='', size=r'\scriptsize', sep='3pt'):
    rows = list(csv.DictReader(open(path, newline='', encoding='utf-8')))
    cols = cols or list(rows[0])
    spec = '@{}' + 'l' * len(cols) + '@{}'
    head = ' & '.join(r'\textbf{' + esc(c) + '}' for c in cols) + r' \\'
    out = [size, r'\setlength{\tabcolsep}{' + sep + '}', r'\begin{longtable}{' + spec + '}', r'\caption{' + caption + r'}\\', r'\toprule', head, r'\midrule', r'\endfirsthead', r'\toprule', head, r'\midrule', r'\endhead']
    out += [' & '.join(esc(r[c]) for c in cols) + r' \\' for r in rows]
    out += [r'\bottomrule', r'\end{longtable}', r'\normalsize']
    return '\n'.join(out)
tex = [r'\documentclass[10pt]{article}', r'\usepackage[a4paper,margin=14mm]{geometry}', r'\usepackage{longtable,booktabs,pdflscape,array,calc}', r'\usepackage[hidelinks]{hyperref}', r'\setcounter{secnumdepth}{0}', r'\setcounter{tocdepth}{2}',
       r'\usepackage{fontspec}', r'\setmainfont{DejaVu Serif}', r'\setmonofont{DejaVu Sans Mono}[Scale=0.85]', r'\providecommand{\tightlist}{\setlength{\itemsep}{0pt}\setlength{\parskip}{0pt}}',
       r'\title{Supplementary material for ``When Does Deep Reinforcement Learning Help Link Adaptation? A Pre-Registered Evaluation Against Calibrated Rules''}',
       r'\date{Generated from repository commit ' + esc(git('rev-parse', '--short', 'HEAD')) + '}', r'\sloppy', r'\setlength{\emergencystretch}{3em}', r'\begin{document}', r'\maketitle', r'\tableofcontents', r'\clearpage',
       r'\section*{How to read this supplement}\addcontentsline{toc}{section}{How to read this supplement}',
       'All files are also provided as CSV or Markdown in the accompanying archive, with SHA-256 hashes in \\texttt{MANIFEST.sha256}. '
       f'S1 is the case registry: {n_cases} cases and {n_rows} scheme evaluations of the main round (v9--v17), plus the ledger of the {rc} cases and {rr} scheme evaluations of the pre-registered robustness checks ({n_cases + rc} cases, {n_rows + rr} scheme evaluations in total). '
       'S2 gives the per-case comparator tables that exist as result tables (v16, v17 and every robustness stage); for v9--v15 the registry row carries the margin over the best rule, and the per-trace results are in the code and data release. '
       'S3 lists every frozen pre-registration with its SHA-256 hash, the commit in which that hash entered \\texttt{FREEZE.sha256}, the first runner start of the stage (runner heartbeat); all times are UTC+6, the time zone of the run PC and the commit that added its results; the full texts follow. '
       'Margins are relative differences in percent, paired per trace; ``beats'' follows rule R1 of the paper (Holm-adjusted Wilcoxon $p<0.05$ and 90\\,\\% CI lower bound above zero).',
       r'\clearpage', r'\begin{landscape}', r'\section{S1. Case registry}',
       longtable(reg, ['case_id', 'version', 'tag', 'role', 'rl_scheme', 'primary_metric', 'rl_value', 'best_rule', 'margin_vs_best_rule_pct', 'claimA', 'claimB', 'win', 'holm_vs_best', 'n_seeds', 'n_traces', 'status'],
                 f'Registry of the main round: {n_cases} cases, {n_rows} scheme evaluations (\\texttt{{case\\_registry.csv}}; the \\texttt{{correction}} column is in the CSV).', r'\tiny', '1.6pt'),
       longtable(rob, ['stage', 'description', 'cases', 'rows', 'prereg'], f'Ledger of the pre-registered robustness checks: {rc} cases, {rr} scheme evaluations.', r'\scriptsize'),
       r'\section{S2. Comparator tables}']
SEL = {'A6': ['cell', 'pf_mode', 'rtt', 'nproc', 'scheme', 'goodput_mean', 'goodput_ci_lo', 'goodput_ci_hi', 'jain_mean', 'edge5_mean'],
       'NR-G10 (descriptive)': ['cell', 'n_traces', 'n_seeds', 'ctxj_mean', 'primary_mean', 'margin_pct', 'ci90_lo', 'ci90_hi', 'wilcoxon_p', 'hier_ci95_lo', 'hier_ci95_hi', 'seeds_above']}
for tag, path, title, src in s2:
    extra = ' Columns omitted here are in the CSV.' if tag in SEL else ''
    tex.append(longtable(path, SEL.get(tag), esc(title) + r' Source: \texttt{' + esc(src) + '}.' + extra, r'\tiny', '2pt'))
tex += [r'\section{S3. Pre-registrations, hashes and freeze timeline}',
        longtable(os.path.join(OUT, 'S3_preregistration', 'freeze_timeline.csv'), ['file', 'stage', 'verifies', 'freeze_commit', 'freeze_time_utc6', 'first_runner_start_utc6', 'results_commit', 'results_time_utc6'],
                  'Every frozen file verifies against \\texttt{FREEZE.sha256}. For each stage the hash entered the freeze file before the first runner start and before the results commit. Full hashes are in \\texttt{freeze\\_timeline.csv}.', r'\scriptsize'),
        r'\end{landscape}']
for h, f in fz:
    b = os.path.basename(f)
    if b.endswith('.md'):
        tex += [r'\clearpage', r'\subsection*{' + esc(b) + r'}\addcontentsline{toc}{subsection}{' + esc(b) + '}', r'\noindent SHA-256: \texttt{\footnotesize ' + h + r'}\par\medskip', r'\input{md_' + re.sub(r'[^A-Za-z0-9]', '_', b) + '.tex}']
tex.append(r'\end{document}')
open(os.path.join(HERE, 'supplement.tex'), 'w', encoding='utf-8', newline='\n').write('\n'.join(tex) + '\n')

# ---------------- README + manifest
open(os.path.join(OUT, 'README.md'), 'w', encoding='utf-8', newline='\n').write(f"""# Supplementary material

- `S1_registry/case_registry.csv`: main round, {n_cases} cases, {n_rows} scheme evaluations (v9--v17), with the `correction` column.
- `S1_registry/robustness_cases.csv`: pre-registered robustness checks, {rc} cases, {rr} scheme evaluations. Project total: {n_cases + rc} cases, {n_rows + rr} scheme evaluations.
- `S2_comparator_tables/`: per-case comparator tables (v16, v17, W1, G6, NR1, NR2, G10, NR-G10, NR-G10 descriptive, A6, A3c). For v9--v15 the registry row gives the margin over the best rule.
- `S3_preregistration/`: every frozen pre-registration and analysis script listed in `FREEZE.sha256`, the earlier freeze files, and `freeze_timeline.csv` (hash, freeze commit, first runner start, results commit).
- `MANIFEST.sha256`: SHA-256 of every file in this archive. Verify with `sha256sum -c MANIFEST.sha256` from this folder.

Generated by `paper/supplement/build_supplement.py` at repository commit {git('rev-parse', '--short', 'HEAD')}.
""")
man = []
for d, _, fs in os.walk(OUT):
    for x in sorted(fs):
        fp = os.path.join(d, x); rel = os.path.relpath(fp, OUT).replace(os.sep, '/')
        if rel != 'MANIFEST.sha256': man.append(f'{sha(fp)}  {rel}')
open(os.path.join(OUT, 'MANIFEST.sha256'), 'w', newline='\n').write('\n'.join(sorted(man, key=lambda l: l.split('  ')[1])) + '\n')
print(f'S1: {n_cases} cases / {n_rows} rows + {rc} / {rr}; S2: {len(s2)} tables; S3: {len(rows3)} frozen files, all verify, none run before freeze')
for r in rows3: print(f"  {r['file']:36s} {r['stage']:7s} freeze {r['freeze_commit']} {r['freeze_time_utc6']}  start {r['first_runner_start_utc6'] or '-':19s}  results {r['results_commit']} {r['results_time_utc6']}")
