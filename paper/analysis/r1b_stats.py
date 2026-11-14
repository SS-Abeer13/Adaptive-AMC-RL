"""R1b statistics: one-step supervised learner trained on observed ACK/NACK (FROZEN with
paper/proposals/R1b_ack_prereg.md, Amendment 9).

Inputs : Optimized/v17x/Dataset/presub/pertrace.csv            (NR2, M1, comparators, R1 schemes; unchanged)
         Optimized/v17x/Dataset/presub/r1b/pertrace_r1b.csv    (GBT-res-ACK, GBT-full-ACK; same format)
         Optimized/v17x/Dataset/presub/r1b/r1b_calib_xfit.csv  (trace, mcs, p_hat, ack1, explored)
         Optimized/v17x/Dataset/presub/r1b/r1b_deploy_acks.csv (scheme, trace, mcs, p_hat, ack1)
Outputs: paper/analysis/out/r1b_R1.csv, r1b_secondary.csv, r1b_reliability.csv, r1b_verdicts.txt, r1b_pending_values.csv
Run    : python3 paper/analysis/r1b_stats.py [--indir DIR] [--out DIR]
Test   : python3 paper/analysis/r1b_stats.py --selftest      (synthetic data only)
"""
import argparse, csv, os, sys
import numpy as np
from scipy import stats

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
from nr2_stats import r1, holm, seed_level                                    # frozen (NR2)
from presub_stats import classify, load_pertrace, get, check_pairing, write  # frozen (Amendment 8)

XS = ['GBT-res-ACK', 'GBT-full-ACK']
R1_TWIN = {'GBT-res-ACK': 'GBT-res', 'GBT-full-ACK': 'GBT-full'}
SEC_CMP = ['ctxj500', 'fixed500', 'ctx500']
NBINS, ECE_FLAG = 10, 0.05

def merge(P, Q):
    for k, v in Q.items():
        if k in P: raise SystemExit(f'duplicate (trace_set, scheme) {k} in both pertrace files')
        P[k] = v
    return P

def family(P, ts):
    A = get(P, ts, 'NR2', list(range(1, 11)))
    xs = [x for x in XS if get(P, ts, x) is not None]
    if A is None or not xs: return [], {}
    check_pairing(P, ts, ['NR2'] + xs)
    a = A.mean(axis=0); rows = [dict(r1(a, get(P, ts, x)), scheme=x, trace_set=ts) for x in xs]
    outs = {}
    for r, h in zip(rows, holm(np.array([r['p'] for r in rows]))):
        sl = seed_level(A, get(P, ts, r['scheme']))
        r.update(holm_p=h, hier95_lo=sl['hier95_lo'], hier95_hi=sl['hier95_hi'], seeds_above=sl['seeds_above'], n_seeds=sl['n_seeds'])
        r['outcome'] = classify(r, h, sl['hier95_lo']); outs[r['scheme']] = r['outcome']
    return rows, outs

def consequence(outs):
    v = [outs.get(x) for x in XS if x in outs]
    if not v: return 'not run'
    if any(o == 'LOSES' for o in v): return 'an ACK-trained learner beat NR2'
    if any(o == 'MATCH' for o in v): return 'an ACK-trained learner matched NR2'
    if len(v) == len(XS) and all(o == 'BEATS' for o in v): return 'NR2 beat both ACK-trained learners'
    return 'not robust across seeds / inconclusive'

def secondary(P):
    rows = []
    for x in XS:
        xv = get(P, 'NR2', x)
        if xv is None: continue
        cs = [c for c in SEC_CMP if get(P, 'NR2', c) is not None]
        if cs:
            check_pairing(P, 'NR2', [x] + cs)
            rr = [dict(r1(xv, get(P, 'NR2', c)), scheme=x, comparator=c, trace_set='NR2') for c in cs]
            for r, h in zip(rr, holm(np.array([r['p'] for r in rr]))): r['holm_p'] = h; r['beats'] = int(h < 0.05 and r['ci90_lo'] > 0); rows.append(r)
        tw = get(P, 'NR2', R1_TWIN[x])
        if tw is not None:
            check_pairing(P, 'NR2', [x, R1_TWIN[x]])
            rows.append(dict(r1(xv, tw), scheme=x, comparator=R1_TWIN[x] + ' (true-SINR labels)', trace_set='NR2', holm_p='', beats=''))
    m1, _ = family(P, 'M1')
    for r in m1: r['comparator'] = 'NR2 (M1 traces, secondary)'
    return rows + m1

def wilson(k, n, z=1.959964):
    if n == 0: return float('nan'), float('nan')
    p = k / n; d = 1 + z * z / n; c = p + z * z / (2 * n); h = z * np.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return (c - h) / d, (c + h) / d

def reliability(p, y, label):
    p = np.asarray(p, float); y = np.asarray(y, float); n = len(p)
    order = np.argsort(p, kind='mergesort'); edges = np.array_split(order, NBINS)
    rows, ece = [], 0.0
    for b, idx in enumerate(edges):
        if len(idx) == 0: continue
        mp, ar = p[idx].mean(), y[idx].mean(); lo, hi = wilson(int(y[idx].sum()), len(idx))
        ece += len(idx) / n * abs(mp - ar)
        rows.append(dict(set=label, bin=b + 1, n=len(idx), mean_p_hat=mp, ack_rate=ar, wilson95_lo=lo, wilson95_hi=hi))
    brier = float(np.mean((p - y) ** 2))
    summ = dict(set=label, bin='all', n=n, mean_p_hat=p.mean(), ack_rate=y.mean(), brier=brier, ece=ece)
    return rows + [summ], ece, brier

def read_csv(path):
    return list(csv.DictReader(open(path, newline='', encoding='utf-8'))) if os.path.exists(path) else None

def run(indir, out):
    os.makedirs(out, exist_ok=True); txt, pv = [], []
    P = load_pertrace(os.path.join(indir, 'pertrace.csv')) if os.path.exists(os.path.join(indir, 'pertrace.csv')) else {}
    q = os.path.join(indir, 'r1b', 'pertrace_r1b.csv')
    if os.path.exists(q): P = merge(P, load_pertrace(q))
    rows, outs = family(P, 'NR2')
    write(os.path.join(out, 'r1b_R1.csv'), rows)
    if rows:
        txt.append('R1b primary (NR2 traces, Holm over %d): ' % len(rows) + '; '.join(
            f"{r['scheme']}: {r['outcome']} ({r['margin_pct']:+.2f}% [{r['ci90_lo']:+.2f}, {r['ci90_hi']:+.2f}], hier [{r['hier95_lo']:+.2f}, {r['hier95_hi']:+.2f}])" for r in rows))
        txt.append('R1b consequence: ' + consequence(outs))
        for r in rows:
            k = r['scheme'].replace('-', '').lower()
            pv += [(f'outcome_{k}', r['outcome']), (f'margin_{k}', f"{r['margin_pct']:.2f}"), (f'ci_lo_{k}', f"{r['ci90_lo']:.2f}"),
                   (f'ci_hi_{k}', f"{r['ci90_hi']:.2f}"), (f'hier_lo_{k}', f"{r['hier95_lo']:.2f}"), (f'hier_hi_{k}', f"{r['hier95_hi']:.2f}")]
    else: txt.append('R1b: not run')
    write(os.path.join(out, 'r1b_secondary.csv'), secondary(P))
    rel = []
    X = read_csv(os.path.join(indir, 'r1b', 'r1b_calib_xfit.csv'))
    if X:
        r, e, b = reliability([float(x['p_hat']) for x in X], [float(x['ack1']) for x in X], 'calibration (cross-fitted), all'); rel += r
        txt.append(f'p_hat calibration (cross-fitted, all): ECE {e:.4f}, Brier {b:.4f}' + (' -> poorly calibrated' if e > ECE_FLAG else ''))
        pv += [('ece_xfit', f'{e:.3f}'), ('brier_xfit', f'{b:.3f}')]
        ex = [x for x in X if int(float(x['explored'])) == 1]
        if ex:
            r, e2, b2 = reliability([float(x['p_hat']) for x in ex], [float(x['ack1']) for x in ex], 'calibration (cross-fitted), explored'); rel += r
            txt.append(f'p_hat calibration (cross-fitted, explored): ECE {e2:.4f}, Brier {b2:.4f}')
    D = read_csv(os.path.join(indir, 'r1b', 'r1b_deploy_acks.csv'))
    if D:
        for s in XS:
            d = [x for x in D if x['scheme'] == s]
            if d:
                r, e3, b3 = reliability([float(x['p_hat']) for x in d], [float(x['ack1']) for x in d], f'deployment {s}, NR2 traces'); rel += r
                txt.append(f'p_hat calibration (deployment {s}): ECE {e3:.4f}, Brier {b3:.4f}')
    write(os.path.join(out, 'r1b_reliability.csv'), rel)
    open(os.path.join(out, 'r1b_verdicts.txt'), 'w', encoding='utf-8').write('\n'.join(txt) + '\n')
    with open(os.path.join(out, 'r1b_pending_values.csv'), 'w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh); w.writerow(['item', 'key', 'value', 'source_file', 'date'])
        for k, v in pv: w.writerow(['R1B', k, v, 'paper/analysis/out/r1b_*.csv', ''])
    print('\n'.join(txt)); return txt

def selftest():
    import tempfile
    rng = np.random.default_rng(11); T = 500
    base = rng.uniform(0.5, 0.7, T); noise = lambda s: rng.normal(0, s, T)
    A = np.array([base * 1.03 + noise(0.01) for _ in range(10)])
    with tempfile.TemporaryDirectory() as d:
        ind = os.path.join(d, 'in'); os.makedirs(os.path.join(ind, 'r1b'))
        with open(os.path.join(ind, 'pertrace.csv'), 'w', newline='') as fh:
            w = csv.writer(fh); w.writerow(['trace_set', 'scheme', 'seed', 'trace', 'value'])
            for s in range(10):
                for t in range(T): w.writerow(['NR2', 'NR2', s + 1, t + 1, A[s, t]])
            for k, f in [('ctxj500', 1.0), ('fixed500', 0.98), ('ctx500', 0.99), ('GBT-res', 1.06), ('GBT-full', 1.09)]:
                v = base * f + noise(0.01)
                for t in range(T): w.writerow(['NR2', k, 0, t + 1, v[t]])
        with open(os.path.join(ind, 'r1b', 'pertrace_r1b.csv'), 'w', newline='') as fh:
            w = csv.writer(fh); w.writerow(['trace_set', 'scheme', 'seed', 'trace', 'value'])
            for k, f in [('GBT-res-ACK', 1.0), ('GBT-full-ACK', 1.08)]:
                v = base * f + noise(0.01)
                for t in range(T): w.writerow(['NR2', k, 0, t + 1, v[t]])
        n = 20000; ph = rng.uniform(0.05, 0.95, n); y = (rng.uniform(size=n) < ph).astype(int)
        with open(os.path.join(ind, 'r1b', 'r1b_calib_xfit.csv'), 'w', newline='') as fh:
            w = csv.writer(fh); w.writerow(['trace', 'mcs', 'p_hat', 'ack1', 'explored'])
            for i in range(n): w.writerow([i % 500 + 1, rng.integers(0, 28), ph[i], y[i], int(i % 2)])
        with open(os.path.join(ind, 'r1b', 'r1b_deploy_acks.csv'), 'w', newline='') as fh:
            w = csv.writer(fh); w.writerow(['scheme', 'trace', 'mcs', 'p_hat', 'ack1'])
            for i in range(n): w.writerow(['GBT-full-ACK', i % 500 + 1, 10, min(0.99, ph[i] + 0.25), y[i]])   # over-confident
        out = os.path.join(d, 'out'); run(ind, out)
        res = {r['scheme']: r['outcome'] for r in csv.DictReader(open(os.path.join(out, 'r1b_R1.csv')))}
        rel = list(csv.DictReader(open(os.path.join(out, 'r1b_reliability.csv'))))
        sec = list(csv.DictReader(open(os.path.join(out, 'r1b_secondary.csv'))))
    assert res == {'GBT-res-ACK': 'BEATS', 'GBT-full-ACK': 'LOSES'}, res
    e_ok = float(next(r['ece'] for r in rel if r['bin'] == 'all' and r['set'].startswith('calibration (cross-fitted), all')))
    e_bad = float(next(r['ece'] for r in rel if r['bin'] == 'all' and r['set'].startswith('deployment')))
    assert e_ok < 0.02 and e_bad > 0.1, (e_ok, e_bad)
    _, _, b = reliability(ph, y, 'x'); assert abs(b - np.mean((ph - y) ** 2)) < 1e-12
    assert any('true-SINR' in r['comparator'] for r in sec)
    import nr2_stats, presub_stats
    assert r1 is nr2_stats.r1 and holm is nr2_stats.holm and seed_level is nr2_stats.seed_level and classify is presub_stats.classify
    print(f'SELFTEST PASS: outcomes {res}; ECE calibrated {e_ok:.4f}, miscalibrated {e_bad:.4f}')

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--indir', default=os.path.join(ROOT, 'Optimized', 'v17x', 'Dataset', 'presub'))
    ap.add_argument('--out', default=os.path.join(HERE, 'out'))
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args()
    selftest() if a.selftest else run(a.indir, a.out)
