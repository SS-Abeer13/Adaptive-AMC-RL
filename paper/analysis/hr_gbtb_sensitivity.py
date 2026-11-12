"""HR1 sensitivity: the P1-P4 verdicts with the second pre-specified estimator (gbt_b) alone.

Not pre-registered as a decision rule. The prereg (paper/proposals/HR1_headroom_prereg.md, Sec. 3)
takes the larger of gbt_a and gbt_b as the learnable estimate; this script reports what the verdicts
would be if gbt_b had been the only estimator. It imports the FROZEN hr_stats.py unchanged.

P1, P2 : read from hr_values.csv (gbt_b rows of the frozen run).
P3, P4 : recomputed here from the logs with gbt_b only, same folds, same bootstrap design
         (per-trace resampling, B = 20000), separate rng seed 20261112.
Check  : the gbt_b point estimates recomputed here must match hr_values.csv to 0.01 points.

Run: python3 paper/analysis/hr_gbtb_sensitivity.py [--logdir DIR] [--out DIR]
Out: paper/analysis/out/hr_gbtb_sensitivity.csv
"""
import argparse, csv, os, sys
import numpy as np
import h5py

HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import hr_stats as H   # frozen

def find_logs(logdir):
    found = {}
    for fn in sorted(os.listdir(logdir)):
        if fn.startswith('hr_log_') and fn.endswith('.mat'):
            f = h5py.File(os.path.join(logdir, fn), 'r')
            txt = lambda k: ''.join(chr(c) for c in np.array(f[k]).flatten())
            found[(txt('tag'), txt('sch_saved_name'))] = os.path.join(logdir, fn)
    return found

def gbtb_values(values_csv):
    out = {}
    for r in csv.DictReader(open(values_csv)):
        if r['estimator'].startswith('gbt_b'):
            out[(r['case'], r['run'], r['table'], r['action_set'])] = (float(r['headroom_pct']), float(r['ci95_lo']), float(r['ci95_hi']))
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--logdir', default=os.path.join(H.ROOT, 'Optimized', 'v17x', 'Dataset', 'hr', 'full'))
    ap.add_argument('--out', default=os.path.join(HERE, 'out'))
    ap.add_argument('--B', type=int, default=H.B_DEFAULT)
    a = ap.parse_args()
    V = gbtb_values(os.path.join(a.out, 'hr_values.csv'))
    found = find_logs(a.logdir); rng = np.random.default_rng(20261112); prm = H.MODELS['gbt_b']
    rows = []
    h = V[('M3_gp_rtt8', 'A2C_case', 'Fixed', 'residual')]
    rows.append(dict(id='P1', estimator='gbt_b', estimate=h[0], lo=h[1], hi=h[2], verdict='supported' if h[2] < 0.5 else 'not supported', source='hr_values.csv'))
    h = V[('M1_dl_rtt8', 'NR2', 'Combined table', 'residual')]
    rows.append(dict(id='P2', estimator='gbt_b', estimate=h[0], lo=h[1], hi=h[2], verdict='supported' if h[1] > 0 else 'not supported', source='hr_values.csv'))
    # P3: (NR2 run) - (M1 run), residual set, over the combined table, joint resampling of traces
    comb = H.PART['Combined table']; st = {}
    for run in ['NR2', 'M1']:
        P = H.prepare(H.load(found[('M1_dl_rtt8', run)]), 'M1_dl_rtt8')
        qi = lambda ch: P['q'][np.arange(P['n']), ch]
        num = qi(H.learn_choice(P, H.predict(P, prm), P['act_res'])); den = qi(H.table_choice(P, comb))
        st[run] = (P, num, den); print(run, 'fitted', flush=True)
    assert np.array_equal(np.unique(st['NR2'][0]['tr']), np.unique(st['M1'][0]['tr']))
    T = len(np.unique(st['NR2'][0]['tr'])); idx = rng.integers(0, T, (a.B, T))
    b1 = H.boot_ratio(*st['NR2'], a.B, rng, idx); b2 = H.boot_ratio(*st['M1'], a.B, rng, idx)
    for run, b in [('NR2', b1), ('M1', b2)]:
        ref = V[('M1_dl_rtt8', run, 'Combined table', 'residual')][0]
        assert abs(b[0] - ref) < 0.01, f'gbt_b point estimate for {run} ({b[0]:.3f}) does not reproduce hr_values.csv ({ref:.3f})'
    d = b1[3] - b2[3]; dci = np.percentile(d, [2.5, 97.5])
    rows.append(dict(id='P3', estimator='gbt_b', estimate=b1[0] - b2[0], lo=dci[0], hi=dci[1], verdict='supported' if dci[0] > 0 else 'not supported', source='recomputed'))
    # P4: Context-table run, full set, over the Context table; (speed classes 2-3) - (speed class 1)
    P = H.prepare(H.load(found[('M1_dl_rtt8', 'Context table')]), 'M1_dl_rtt8')
    qi = lambda ch: P['q'][np.arange(P['n']), ch]
    num = qi(H.learn_choice(P, H.predict(P, prm), P['act_full'])); den = qi(H.table_choice(P, H.PART['Context table']))
    ref = V[('M1_dl_rtt8', 'Context table', 'Context table', 'full')][0]
    tot = 100 * (num.sum() / den.sum() - 1)
    assert abs(tot - ref) < 0.01, f'gbt_b Context-table headroom ({tot:.3f}) does not reproduce hr_values.csv ({ref:.3f})'
    slow = P['D']['speed_class'] == 1; ut = np.unique(P['tr']); inv = np.searchsorted(ut, P['tr'])
    grp = lambda m: (np.bincount(inv, num * m, len(ut)), np.bincount(inv, den * m, len(ut)))
    (fn, fd), (sn, sd) = grp(~slow), grp(slow)
    r = lambda n_, d_: 100 * (n_.sum(-1) / d_.sum(-1) - 1)
    idx = rng.integers(0, len(ut), (a.B, len(ut)))
    est = r(fn, fd) - r(sn, sd); bd = r(fn[idx], fd[idx]) - r(sn[idx], sd[idx]); bci = np.percentile(bd, [2.5, 97.5])
    rows.append(dict(id='P4', estimator='gbt_b', estimate=est, lo=bci[0], hi=bci[1], verdict='supported' if bci[0] > 0 else 'not supported', source='recomputed'))
    with open(os.path.join(a.out, 'hr_gbtb_sensitivity.csv'), 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0])); w.writeheader()
        for x in rows: w.writerow({k: (f'{v:.3f}' if isinstance(v, float) else v) for k, v in x.items()})
    for x in rows: print(x)

if __name__ == '__main__':
    main()
