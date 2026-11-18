"""R6 statistics: residual RL with the full action set (-4..+2) against the ACK-trained one-step learner
(FROZEN with paper/proposals/R6_fullaction_prereg.md, Amendment 11, Freeze v13).

Inputs (Optimized/v17x/Dataset/presub/):
  pertrace_G2corrected.csv   NR2 traces: NR2 (seeds 1-10), ctxj500, R1 GBT-res / GBT-full (seed 0). Must exist.
  r1b/pertrace_r1b.csv       GBT-res-ACK, GBT-full-ACK on the NR2 traces = M1 fit 1 (seed 0)
  r1c/pertrace_r1c.csv       <S>-M1fit<k>, k = 2..4, on the NR2 traces (seed 0)
  r6/pertrace_r6.csv         RL-full (seeds 1-10); optional GBT-res-SINRexp, GBT-full-SINRexp (seed 0); trace set NR2
Outputs (paper/analysis/out/): r6_fits.csv, r6_secondary.csv, r6_r6b.csv, r6_verdicts.txt, r6_pending_values.csv
Run : python3 paper/analysis/r6_stats.py [--indir DIR] [--out DIR]
Test: python3 paper/analysis/r6_stats.py --selftest     (synthetic data only)
"""
import argparse, csv, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
from nr2_stats import r1, holm, seed_level                         # frozen (NR2)
from presub_stats import load_pertrace, get, check_pairing, write  # frozen (Amendment 8)

TS = 'NR2'
RL = 'RL-full'
FITS = [1, 2, 3, 4]
MATCH_TOL = 0.5
SEEDS = list(range(1, 11))

WORDING = {
    'the supervised learner beats RL at both action sets': 'With the same action set as the one-step learner (offsets −4…+2), the RL policy still delivered fewer packets on time than the one-step learner trained on observed ACK/NACK, for each of the four calibration draws: the supervised learner beats RL at both action sets.',
    'the gap closes with the full action set': 'With the full action set (offsets −4…+2), the RL policy was no longer beaten by the one-step learner trained on observed ACK/NACK in any of the four calibration draws: the gap closes with the full action set.',
    'RL-full beats the supervised learner': 'With the full action set (offsets −4…+2), the RL policy beat the one-step learner trained on observed ACK/NACK for each of the four calibration draws, robustly across training seeds.',
    'depends on the calibration draw': 'With the full action set, the comparison between the RL policy and the one-step learner depends on the calibration draw: the four draws gave different outcomes.',
    'not run': 'No RL policy with the full action set was trained.',
}
STATE_TO_KEY = {'loses': 'the supervised learner beats RL at both action sets', 'closes': 'the gap closes with the full action set',
                'beats': 'RL-full beats the supervised learner', 'mixed': 'depends on the calibration draw', 'not run': 'not run'}

def classify(r, holm_p, hier_lo):
    """Identical to R1c's classify_r1c (margin = RL relative to the learner; MATCH = Holm n.s. and |margin| < 0.5 %)."""
    if holm_p < 0.05 and r['ci90_lo'] > 0: return 'BEATS' if hier_lo > 0 else 'BEATS-TRACE'
    if holm_p < 0.05 and r['ci90_hi'] < 0: return 'LOSES'
    if holm_p >= 0.05 and abs(r['margin_pct']) < MATCH_TOL: return 'MATCH'
    return 'INCONCLUSIVE'

def state(outcomes):
    if len(outcomes) != len(FITS): return 'not run'
    if all(o == 'LOSES' for o in outcomes): return 'loses'
    if all(o == 'BEATS' for o in outcomes): return 'beats'
    if not any(o == 'LOSES' for o in outcomes): return 'closes'
    return 'mixed'

def load(indir):
    main = os.path.join(indir, 'pertrace_G2corrected.csv')
    if not os.path.exists(main): raise SystemExit('pertrace_G2corrected.csv missing')
    P = load_pertrace(main)
    for f in [os.path.join(indir, 'r1b', 'pertrace_r1b.csv'), os.path.join(indir, 'r1c', 'pertrace_r1c.csv'), os.path.join(indir, 'r6', 'pertrace_r6.csv')]:
        if os.path.exists(f):
            for k, v in load_pertrace(f).items():
                if k in P: raise SystemExit(f'duplicate (trace_set, scheme) {k}')
                P[k] = v
    for s in ['GBT-res-ACK', 'GBT-full-ACK']:          # R1b's model is M1 fit 1 (as in R1c)
        if (TS, s) in P: P[(TS, f'{s}-M1fit1')] = P.pop((TS, s))
    return P

def vs_fits(P, A, scheme):
    """RL-full (seed mean) vs the four fits of one ACK scheme; Holm over 4; seed level vs the RL-full seeds."""
    names = [(k, f'{scheme}-M1fit{k}') for k in FITS if get(P, TS, f'{scheme}-M1fit{k}') is not None]
    if not names: return []
    check_pairing(P, TS, [RL] + [n for _, n in names])
    a = A.mean(axis=0); rows = []
    for k, n in names:
        x = get(P, TS, n); r = r1(a, x)
        rows.append(dict(comparison=f'{RL} vs {scheme}', fit=k, rl_ontime=float(a.mean()), learner_ontime=float(x.mean()), **r))
    for r, h in zip(rows, holm(np.array([r['p'] for r in rows]))):
        sl = seed_level(A, get(P, TS, f"{scheme}-M1fit{r['fit']}"))
        r.update(holm_p=h, hier95_lo=sl['hier95_lo'], hier95_hi=sl['hier95_hi'], seeds_above=sl['seeds_above'], n_seeds=sl['n_seeds'])
        r['outcome'] = classify(r, h, sl['hier95_lo'])
    return rows

def run(indir, out):
    os.makedirs(out, exist_ok=True)
    P = load(indir); txt, pv = [], []
    A = get(P, TS, RL, SEEDS) if (TS, RL) in P else None
    prim, sec, r6b = [], [], []
    if A is not None:
        prim = vs_fits(P, A, 'GBT-full-ACK')
        sec_res = vs_fits(P, A, 'GBT-res-ACK')
        st = state([r['outcome'] for r in prim])
        a = A.mean(axis=0)
        nr2 = get(P, TS, 'NR2', SEEDS); full = [get(P, TS, f'GBT-full-ACK-M1fit{k}') for k in FITS]
        if nr2 is not None and all(f is not None for f in full):
            n2 = nr2.mean(axis=0); gmean = float(np.mean([f.mean() for f in full]))
            closure = 100.0 * (a.mean() - n2.mean()) / (gmean - n2.mean()) if gmean != n2.mean() else float('nan')
            r = r1(a, n2); sl = seed_level(A, n2)
            sec.append(dict(comparison=f'{RL} vs NR2 (seed means; NR2 treated as fixed at seed level)', **r, hier95_lo=sl['hier95_lo'], hier95_hi=sl['hier95_hi'], seeds_above=sl['seeds_above'], n_seeds=sl['n_seeds']))
            sec.append(dict(comparison='gap closure (% of the NR2 to GBT-full-ACK gap)', margin_pct=closure))
        cj = get(P, TS, 'ctxj500')
        if cj is not None:
            check_pairing(P, TS, [RL, 'ctxj500'])
            r = r1(a, cj); sl = seed_level(A, cj)
            sec.append(dict(comparison=f'{RL} vs ctxj500', **r, hier95_lo=sl['hier95_lo'], hier95_hi=sl['hier95_hi'], seeds_above=sl['seeds_above'], n_seeds=sl['n_seeds']))
        sec += [dict(r, comparison=r['comparison'] + f" fit {r['fit']}") for r in sec_res]
    else:
        st = 'not run'
    # R6b, descriptive only
    for x in ['res', 'full']:
        se = get(P, TS, f'GBT-{x}-SINRexp')
        if se is None: continue
        for other, label in [(f'GBT-{x}', 'logging effect: SINRexp vs R1 (same labels and model form, different logs)'),
                             (f'GBT-{x}-ACK-M1fit1', 'label effect: ACK fit 1 vs SINRexp (same logs; label and model form change together)')]:
            o = get(P, TS, other)
            if o is None: continue
            check_pairing(P, TS, [f'GBT-{x}-SINRexp', other])
            r = r1(o, se) if 'ACK' in other else r1(se, o)
            r6b.append(dict(comparison=label, scheme=x, **r))
    write(os.path.join(out, 'r6_fits.csv'), prim); write(os.path.join(out, 'r6_secondary.csv'), sec); write(os.path.join(out, 'r6_r6b.csv'), r6b)
    key = STATE_TO_KEY[st]
    txt.append(f'R6a: {key} | state {st} | outcomes ' + ' '.join(f"{r['fit']}:{r['outcome']}" for r in prim))
    txt.append(f'  statement: {WORDING[key]}')
    for r in prim:
        txt.append(f"  fit {r['fit']}: RL-full {r['rl_ontime']:.4f} vs GBT-full-ACK {r['learner_ontime']:.4f}; margin {r['margin_pct']:+.2f} % [{r['ci90_lo']:.2f}, {r['ci90_hi']:.2f}], Holm p {r['holm_p']:.3g}, hier [{r['hier95_lo']:.2f}, {r['hier95_hi']:.2f}], seeds above {r['seeds_above']}/{r['n_seeds']}: {r['outcome']}")
    for r in sec:
        txt.append(f"  [secondary] {r['comparison']}: {r['margin_pct']:+.2f}" + (f" [{r['ci90_lo']:.2f}, {r['ci90_hi']:.2f}]" if 'ci90_lo' in r else ''))
    txt.append('R6b: ' + ('run' if r6b else 'not run'))
    for r in r6b: txt.append(f"  [R6b, observation] {r['scheme']} {r['comparison']}: {r['margin_pct']:+.2f} % [{r['ci90_lo']:.2f}, {r['ci90_hi']:.2f}]")
    open(os.path.join(out, 'r6_verdicts.txt'), 'w', encoding='utf-8').write('\n'.join(txt) + '\n')
    pv.append(('verdict', key)); pv.append(('state', st)); pv.append(('r6b', 'run' if r6b else 'not run'))
    with open(os.path.join(out, 'r6_pending_values.csv'), 'w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh); w.writerow(['item', 'key', 'value', 'source_file', 'date'])
        for k, v in pv: w.writerow(['R6', k, v, 'paper/analysis/out/r6_*.csv', ''])
    print('\n'.join(txt)); return st, bool(r6b)

# ------------------------------------------------------------------ self-test (synthetic data only)
def selftest():
    import tempfile
    rng = np.random.default_rng(20261117)
    def make(d, rl_lvl, fit_lvls, with_r6=True, with_r6b=False):
        ind = os.path.join(d, 'presub')
        for sub in ['r1b', 'r1c', 'r6']: os.makedirs(os.path.join(ind, sub), exist_ok=True)
        def wr(path, rows):
            with open(path, 'w', newline='') as fh:
                w = csv.writer(fh); w.writerow(['trace_set', 'scheme', 'seed', 'trace', 'value']); w.writerows(rows)
        base = rng.normal(0, 0.01, 500)                    # shared trace effect: pairing makes small level gaps detectable
        def vec(lvl): return lvl + base + rng.normal(0, 0.004, 500)
        rows = []
        for s in SEEDS:
            v = vec(0.62 + rng.normal(0, 0.002)); rows += [[TS, 'NR2', s, t + 1, v[t]] for t in range(500)]
        for sch, lvl in [('ctxj500', 0.60), ('GBT-res', 0.637), ('GBT-full', 0.656)]:
            v = vec(lvl); rows += [[TS, sch, 0, t + 1, v[t]] for t in range(500)]
        wr(os.path.join(ind, 'pertrace_G2corrected.csv'), rows)
        wr(os.path.join(ind, 'r1b', 'pertrace_r1b.csv'), [[TS, s, 0, t + 1, v[t]] for s, lv in [('GBT-res-ACK', 0.642), ('GBT-full-ACK', fit_lvls[0])] for v in [vec(lv)] for t in range(500)])
        rows = []
        for k in [2, 3, 4]:
            for s, lv in [('GBT-res-ACK', 0.645), ('GBT-full-ACK', fit_lvls[k - 1])]:
                v = vec(lv); rows += [[TS, f'{s}-M1fit{k}', 0, t + 1, v[t]] for t in range(500)]
        wr(os.path.join(ind, 'r1c', 'pertrace_r1c.csv'), rows)
        rows = []
        if with_r6:
            for s in SEEDS:
                v = vec(rl_lvl + rng.normal(0, 0.002)); rows += [[TS, RL, s, t + 1, v[t]] for t in range(500)]
        if with_r6b:
            for x, lv in [('res', 0.640), ('full', 0.668)]:
                v = vec(lv); rows += [[TS, f'GBT-{x}-SINRexp', 0, t + 1, v[t]] for t in range(500)]
        if rows: wr(os.path.join(ind, 'r6', 'pertrace_r6.csv'), rows)
        return ind
    cases = [(0.630, [0.671, 0.688, 0.673, 0.678], 'loses'),
             (0.690, [0.671, 0.672, 0.673, 0.674], 'beats'),
             (0.6715, [0.671, 0.672, 0.6712, 0.6718], 'closes'),
             (0.678, [0.671, 0.700, 0.673, 0.701], 'mixed')]
    for rl_lvl, fits, want in cases:
        with tempfile.TemporaryDirectory() as d:
            st, _ = run(make(d, rl_lvl, fits), os.path.join(d, 'out'))
            assert st == want, (want, st)
            v = list(csv.DictReader(open(os.path.join(d, 'out', 'r6_pending_values.csv'))))
            assert v[0]['value'] == STATE_TO_KEY[want], v
    with tempfile.TemporaryDirectory() as d:                       # R6a not run
        st, _ = run(make(d, 0.63, [0.671] * 4, with_r6=False), os.path.join(d, 'out'))
        assert st == 'not run'
    with tempfile.TemporaryDirectory() as d:                       # R6b present / absent does not change R6a
        st1, b1 = run(make(d, 0.630, [0.671, 0.688, 0.673, 0.678], with_r6b=True), os.path.join(d, 'o1'))
        assert st1 == 'loses' and b1
    with tempfile.TemporaryDirectory() as d:
        st2, b2 = run(make(d, 0.630, [0.671, 0.688, 0.673, 0.678], with_r6b=False), os.path.join(d, 'o2'))
        assert st2 == 'loses' and not b2
    # outcome classes and order (identical to R1c)
    assert classify(dict(margin_pct=0.3, ci90_lo=-0.1, ci90_hi=0.7), 0.20, -0.5) == 'MATCH'
    assert classify(dict(margin_pct=0.3, ci90_lo=0.05, ci90_hi=0.55), 0.04, 0.01) == 'BEATS'
    assert classify(dict(margin_pct=0.3, ci90_lo=0.05, ci90_hi=0.55), 0.04, -0.01) == 'BEATS-TRACE'
    assert classify(dict(margin_pct=0.6, ci90_lo=-0.2, ci90_hi=1.4), 0.30, -0.5) == 'INCONCLUSIVE'
    assert classify(dict(margin_pct=-3.0, ci90_lo=-3.5, ci90_hi=-2.5), 1e-6, -4.0) == 'LOSES'
    assert state(['LOSES', 'MATCH', 'LOSES', 'LOSES']) == 'mixed' and state(['MATCH', 'BEATS', 'BEATS-TRACE', 'INCONCLUSIVE']) == 'closes'
    import nr2_stats, presub_stats
    assert r1 is nr2_stats.r1 and holm is nr2_stats.holm and seed_level is nr2_stats.seed_level and load_pertrace is presub_stats.load_pertrace
    print('SELFTEST PASS: four state-based wording rows and not run, outcome classes, R6b independence and frozen functions verified')

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--indir', default=os.path.join(ROOT, 'Optimized', 'v17x', 'Dataset', 'presub'))
    ap.add_argument('--out', default=os.path.join(HERE, 'out'))
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args()
    selftest() if a.selftest else run(a.indir, a.out)
