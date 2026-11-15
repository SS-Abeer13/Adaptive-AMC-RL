"""R1c statistics: calibration-draw replication and per-cell test of the ACK-trained one-step learner
(FROZEN with paper/proposals/R1c_ack_prereg.md, Amendment 10a, Freeze v12).

Inputs (Optimized/v17x/Dataset/presub/):
  pertrace_G2corrected.csv   NR2, M1 and cell comparators, RL policies (NR2 seeds 1-10; NRG10 seeds 1-10 per cell,
                             G2 seeds 6-10 = the corrected 14 kbit re-evaluation of Deviation D1). Must exist.
  r1b/pertrace_r1b.csv       M1 fit 1 (R1b) on the NR2 traces: GBT-res-ACK, GBT-full-ACK (seed 0)
  r1c/pertrace_r1c.csv       trace_set in {NR2, G2, G3}; schemes <S>-M1fit<k> (k = 2..4 on NR2; k = 1..4 in the cells,
                             transfer) and <S>-cellfit<k> (k = 1..4, cells only), S in {GBT-res-ACK, GBT-full-ACK}; seed 0
Outputs (paper/analysis/out/): r1c_fits.csv, r1c_rules.csv, r1c_summary.csv, r1c_verdicts.txt, r1c_pending_values.csv
Run : python3 paper/analysis/r1c_stats.py [--indir DIR] [--out DIR]
Test: python3 paper/analysis/r1c_stats.py --selftest     (synthetic data only)
"""
import argparse, csv, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
from nr2_stats import r1, holm, seed_level                         # frozen (NR2)
from presub_stats import load_pertrace, get, check_pairing, write  # frozen (Amendment 8)

SCHEMES = ['GBT-res-ACK', 'GBT-full-ACK']
FITS = [1, 2, 3, 4]
CELLS = ['G2', 'G3']
G_FAMILY = ['Baseline', 'OLLA', 'OLLA (tuned target)', 'Multi-OLLA', 'Fixed', 'FixedPU (Oracle)', 'Context table', 'Bandit (global)', 'Bandit (delay class)']
MATCH_TOL = 0.5
FAV = ('LOSES', 'MATCH')          # outcomes favourable to the learner (margin = RL vs learner; LOSES = the learner beats RL)

WORDING = {
    'holds across all fits and both cells': 'Across four independent calibration draws, the one-step learner trained on observed ACK/NACK beat or matched the RL policy on the NR2 traces, and, trained on each neighbouring cell\'s own calibration traces, beat or matched the cell\'s RL policy and beat all nine calibrated comparators in both cells.',
    'replicates across fits, cell-dependent': 'The result was consistent across the four calibration draws in every trace set, but cell-dependent: the learner beat or matched the RL policy on the NR2 traces and in [cell], not in [other cell].',
    'operating-point dependent': 'The result was consistent across the four calibration draws, but held only at the M1 operating point: in neither neighbouring cell did the cell-trained learner both beat or match the RL policy and beat all nine calibrated comparators.',
    'cells hold, fit-dependent': 'In both neighbouring cells the cell-trained learner held across all four calibration draws, but on the NR2 traces the comparison with the RL policy depends on the calibration draw.',
    'depends on the calibration draw': 'The comparison between the one-step learner and the RL policy depends on the calibration draw: the four independent draws gave different outcomes.',
    'neither': 'The one-step learner trained on observed ACK/NACK neither held against the RL policy across calibration draws nor generalized to the neighbouring cells.',
    'not run': 'No calibration-draw replication or per-cell test of the ACK-trained learner was run.',
}

def classify_r1c(r, holm_p, hier_lo):
    """Amendment 10a: MATCH = Holm not significant and |margin| < 0.5 %."""
    if holm_p < 0.05 and r['ci90_lo'] > 0: return 'BEATS' if hier_lo > 0 else 'BEATS-TRACE'
    if holm_p < 0.05 and r['ci90_hi'] < 0: return 'LOSES'
    if holm_p >= 0.05 and abs(r['margin_pct']) < MATCH_TOL: return 'MATCH'
    return 'INCONCLUSIVE'

def load(indir):
    main = os.path.join(indir, 'pertrace_G2corrected.csv')
    if not os.path.exists(main): raise SystemExit('pertrace_G2corrected.csv missing: the G2 RL comparator must be the corrected (D1) one')
    P = load_pertrace(main)
    for f in [os.path.join(indir, 'r1b', 'pertrace_r1b.csv'), os.path.join(indir, 'r1c', 'pertrace_r1c.csv')]:
        if os.path.exists(f):
            for k, v in load_pertrace(f).items():
                if k in P: raise SystemExit(f'duplicate (trace_set, scheme) {k}')
                P[k] = v
    for s in SCHEMES:                                    # R1b's model is M1 fit 1
        if ('NR2', s) in P: P[('NR2', f'{s}-M1fit1')] = P.pop(('NR2', s))
    return P

def rl_matrix(P, ts):
    return get(P, ts, 'NR2' if ts == 'NR2' else 'NRG10', list(range(1, 11)))

def fits_vs_rl(P, ts, kind):
    """All fits x schemes of one kind ('M1fit' or 'cellfit') in one trace set vs the 10-seed RL policy; Holm over the family."""
    A = rl_matrix(P, ts)
    names = [(s, k, f'{s}-{kind}{k}') for s in SCHEMES for k in FITS if get(P, ts, f'{s}-{kind}{k}') is not None]
    if A is None or not names: return []
    check_pairing(P, ts, ['NR2' if ts == 'NR2' else 'NRG10'] + [n for _, _, n in names])
    a = A.mean(axis=0); rows = []
    for s, k, n in names:
        x = get(P, ts, n); r = r1(a, x)
        rows.append(dict(trace_set=ts, kind=kind, scheme=s, fit=k, ontime=float(x.mean()), rl_ontime=float(a.mean()), **r))
    for r, h in zip(rows, holm(np.array([r['p'] for r in rows]))):
        sl = seed_level(A, get(P, ts, f"{r['scheme']}-{kind}{r['fit']}"))
        r.update(holm_p=h, hier95_lo=sl['hier95_lo'], hier95_hi=sl['hier95_hi'], seeds_above=sl['seeds_above'], n_seeds=sl['n_seeds'])
        r['outcome_vs_rl'] = classify_r1c(r, h, sl['hier95_lo'])
    return rows

def beats_rules(P, ts, name):
    """'beats rules' = R1 against every member of the cell's family of 9, Holm over 9."""
    x = get(P, ts, name); cs = [c for c in G_FAMILY if get(P, ts, c) is not None]
    if x is None or len(cs) != len(G_FAMILY): return None, []
    check_pairing(P, ts, [name] + cs)
    rr = [dict(r1(x, get(P, ts, c)), trace_set=ts, scheme=name, comparator=c) for c in cs]
    for r, h in zip(rr, holm(np.array([r['p'] for r in rr]))): r['holm_p'] = h; r['beats'] = int(h < 0.05 and r['ci90_lo'] > 0)
    return all(r['beats'] == 1 for r in rr), rr

def state(fav):
    """Fit consistency within a trace set and scheme: 'holds' (all 4 favourable), 'fails' (none), 'split' (otherwise)."""
    if len(fav) != len(FITS): return 'incomplete'
    return 'holds' if all(fav) else ('fails' if not any(fav) else 'split')

def verdict(st):
    n, g2, g3 = st.get('NR2'), st.get('G2'), st.get('G3')
    if n is None and g2 is None and g3 is None: return 'not run'
    if 'incomplete' in (n, g2, g3) or None in (n, g2, g3): return 'not run'
    if n == 'holds' and g2 == 'holds' and g3 == 'holds': return 'holds across all fits and both cells'
    if n == 'split' and g2 == 'holds' and g3 == 'holds': return 'cells hold, fit-dependent'
    if 'split' in (n, g2, g3): return 'depends on the calibration draw'
    if n == 'holds' and (g2 == 'holds') != (g3 == 'holds'): return 'replicates across fits, cell-dependent'
    if n == 'holds': return 'operating-point dependent'
    return 'neither'

def run(indir, out):
    os.makedirs(out, exist_ok=True)
    P = load(indir); fit_rows, rule_rows, summ, txt, pv = [], [], [], [], []
    states = {s: {} for s in SCHEMES}
    for ts, kind, role in [('NR2', 'M1fit', 'primary: replication'), ('G2', 'cellfit', 'primary: cell'), ('G3', 'cellfit', 'primary: cell'),
                           ('G2', 'M1fit', 'secondary: transfer'), ('G3', 'M1fit', 'secondary: transfer')]:
        rows = fits_vs_rl(P, ts, kind)
        for r in rows:
            r['role'] = role
            if ts in CELLS:
                b, rr = beats_rules(P, ts, f"{r['scheme']}-{kind}{r['fit']}")
                r['beats_rules'] = '' if b is None else ('yes' if b else 'no'); rule_rows += [dict(x, role=role) for x in rr]
            else: r['beats_rules'] = 'n/a'
            r['favourable'] = (r['outcome_vs_rl'] in FAV) and (ts == 'NR2' or r['beats_rules'] == 'yes')
        fit_rows += rows
        for s in SCHEMES:
            sr = [r for r in rows if r['scheme'] == s]
            if not sr: continue
            o = np.array([r['ontime'] for r in sr]); st = state([r['favourable'] for r in sr])
            worst = min(sr, key=lambda r: r['ontime'])
            summ.append(dict(role=role, trace_set=ts, kind=kind, scheme=s, n_fits=len(sr), state=st, mean_ontime=o.mean(), min_ontime=o.min(), max_ontime=o.max(),
                             rl_ontime=sr[0]['rl_ontime'], worst_fit=worst['fit'], worst_margin=worst['margin_pct'], worst_outcome=worst['outcome_vs_rl'],
                             outcomes=' '.join(f"{r['fit']}:{r['outcome_vs_rl']}" for r in sr)))
            if role.startswith('primary'): states[s][ts] = st
    write(os.path.join(out, 'r1c_fits.csv'), fit_rows); write(os.path.join(out, 'r1c_rules.csv'), rule_rows); write(os.path.join(out, 'r1c_summary.csv'), summ)
    for s in SCHEMES:
        v = verdict(states[s]); txt.append(f'{s}: {v} | states {states[s]}'); txt.append(f'  statement: {WORDING[v]}')
        pv.append((f"verdict_{s.replace('-', '').lower()}", v))
    for r in summ:
        txt.append(f"  [{r['role']}] {r['trace_set']} {r['scheme']}: {r['state']}; mean on-time {r['mean_ontime']:.4f} (min {r['min_ontime']:.4f}, max {r['max_ontime']:.4f}) vs RL {r['rl_ontime']:.4f}; outcomes {r['outcomes']}")
    open(os.path.join(out, 'r1c_verdicts.txt'), 'w', encoding='utf-8').write('\n'.join(txt) + '\n')
    with open(os.path.join(out, 'r1c_pending_values.csv'), 'w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh); w.writerow(['item', 'key', 'value', 'source_file', 'date'])
        for k, v in pv: w.writerow(['R1C', k, v, 'paper/analysis/out/r1c_*.csv', ''])
    print('\n'.join(txt)); return states

# ------------------------------------------------------------------ self-test (synthetic data only)
def selftest():
    import tempfile
    rng = np.random.default_rng(20261115)
    def make(d, nr2_lvls, cell_lvls, rule_lvl=0.53):
        ind = os.path.join(d, 'presub'); os.makedirs(os.path.join(ind, 'r1b'), exist_ok=True); os.makedirs(os.path.join(ind, 'r1c'), exist_ok=True)
        with open(os.path.join(ind, 'pertrace_G2corrected.csv'), 'w', newline='') as fh:
            w = csv.writer(fh); w.writerow(['trace_set', 'scheme', 'seed', 'trace', 'value'])
            for s in range(1, 11):
                v = 0.62 + rng.normal(0, 0.003) + rng.normal(0, 0.01, 500)
                for t in range(500): w.writerow(['NR2', 'NR2', s, t + 1, v[t]])
            for c in CELLS:
                for s in range(1, 11):
                    v = 0.55 + rng.normal(0, 0.003) + rng.normal(0, 0.01, 300)
                    for t in range(300): w.writerow([c, 'NRG10', s, t + 1, v[t]])
                for k in G_FAMILY:
                    v = rule_lvl + rng.normal(0, 0.01, 300)
                    for t in range(300): w.writerow([c, k, 0, t + 1, v[t]])
        with open(os.path.join(ind, 'r1b', 'pertrace_r1b.csv'), 'w', newline='') as fh:
            w = csv.writer(fh); w.writerow(['trace_set', 'scheme', 'seed', 'trace', 'value'])
            for s in SCHEMES:
                v = nr2_lvls[0] + rng.normal(0, 0.01, 500)
                for t in range(500): w.writerow(['NR2', s, 0, t + 1, v[t]])
        with open(os.path.join(ind, 'r1c', 'pertrace_r1c.csv'), 'w', newline='') as fh:
            w = csv.writer(fh); w.writerow(['trace_set', 'scheme', 'seed', 'trace', 'value'])
            for s in SCHEMES:
                for k in [2, 3, 4]:
                    v = nr2_lvls[k - 1] + rng.normal(0, 0.01, 500)
                    for t in range(500): w.writerow(['NR2', f'{s}-M1fit{k}', 0, t + 1, v[t]])
                for c in CELLS:
                    for k in FITS:
                        for kind in ['cellfit', 'M1fit']:
                            v = cell_lvls[c][k - 1] + rng.normal(0, 0.01, 300)
                            for t in range(300): w.writerow([c, f'{s}-{kind}{k}', 0, t + 1, v[t]])
        return ind
    cases = [([0.66] * 4, {'G2': [0.60] * 4, 'G3': [0.60] * 4}, 'holds across all fits and both cells'),
             ([0.66] * 4, {'G2': [0.60] * 4, 'G3': [0.50] * 4}, 'replicates across fits, cell-dependent'),
             ([0.66] * 4, {'G2': [0.50] * 4, 'G3': [0.50] * 4}, 'operating-point dependent'),
             ([0.66, 0.58, 0.66, 0.58], {'G2': [0.60] * 4, 'G3': [0.60] * 4}, 'cells hold, fit-dependent'),
             ([0.66] * 4, {'G2': [0.60, 0.50, 0.60, 0.60], 'G3': [0.60] * 4}, 'depends on the calibration draw'),
             ([0.58] * 4, {'G2': [0.50] * 4, 'G3': [0.50] * 4}, 'neither'),
             ([0.6201] * 4, {'G2': [0.5501] * 4, 'G3': [0.5501] * 4}, None)]   # MATCH with RL everywhere (MATCH counts as favourable)
    for nr2_l, cell_l, want in cases:
        with tempfile.TemporaryDirectory() as d:
            st = run(make(d, nr2_l, cell_l), os.path.join(d, 'out'))
            got = {s: verdict(st[s]) for s in SCHEMES}
            if want is not None: assert all(g == want for g in got.values()), (want, got)
            else:
                rows = list(csv.DictReader(open(os.path.join(d, 'out', 'r1c_fits.csv'))))
                assert all(r['outcome_vs_rl'] == 'MATCH' for r in rows if r['trace_set'] == 'NR2'), [r['outcome_vs_rl'] for r in rows]
    # MATCH definition and classification order
    assert classify_r1c(dict(margin_pct=0.3, ci90_lo=-0.1, ci90_hi=0.7), 0.20, -0.5) == 'MATCH'
    assert classify_r1c(dict(margin_pct=0.3, ci90_lo=0.05, ci90_hi=0.55), 0.04, 0.01) == 'BEATS'
    assert classify_r1c(dict(margin_pct=0.6, ci90_lo=-0.2, ci90_hi=1.4), 0.30, -0.5) == 'INCONCLUSIVE'
    assert classify_r1c(dict(margin_pct=-3.0, ci90_lo=-3.5, ci90_hi=-2.5), 1e-6, -4.0) == 'LOSES'
    # the D1 rule: without the corrected file the script refuses to run
    with tempfile.TemporaryDirectory() as d:
        try: load(d); raise AssertionError('load() must refuse without pertrace_G2corrected.csv')
        except SystemExit: pass
    import nr2_stats, presub_stats
    assert r1 is nr2_stats.r1 and holm is nr2_stats.holm and seed_level is nr2_stats.seed_level and load_pertrace is presub_stats.load_pertrace
    print('SELFTEST PASS: all six wording rows, the MATCH definition and the D1 input rule verified')

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--indir', default=os.path.join(ROOT, 'Optimized', 'v17x', 'Dataset', 'presub'))
    ap.add_argument('--out', default=os.path.join(HERE, 'out'))
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args()
    selftest() if a.selftest else run(a.indir, a.out)
