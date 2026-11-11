"""NR-G10 vs the per-cell combined table (Context-joint) of G10. DESCRIPTIVE, NOT PRE-REGISTERED.

NR-G10 used the same evaluation traces and CRN as G10 (NR-G10 prereg sec. 2), so the
G10 per-trace values of the per-cell combined table can be paired with NR-G10's
per-trace values. Checks first that the nine shared comparators are bit-identical
in both files (pairing check) and that the hierarchical bootstrap reproduces the
stored NR-G10 R2 interval vs the Context table (method check). Same estimators as
g3_seed_stats.py (B = 20000, rng seed 20261104); no Holm, no verdict.
"""
import os, csv, h5py, numpy as np
from scipy import stats
here = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(here, '..', '..'))
D = os.path.join(ROOT, 'Optimized', 'v17x', 'Dataset', 'ckpt')
B = 20000

def load(f):
    h = h5py.File(f, 'r'); o = h['out']
    names = [''.join(chr(c) for c in np.array(h[r]).flatten()) for r in np.array(o['cmpNames']).flatten()]
    vals = [np.array(h[r]).flatten() for r in np.array(o['cmp_vals']).flatten()]
    d = {'names': names, 'vals': dict(zip(names, vals)), 'prim': np.array(o['rl_prim']).flatten()}
    if 'rl_seeds' in o: d['seeds'] = np.array(o['rl_seeds'])            # h5py: (seeds, traces)
    if 'r2_ci' in o: d['r2'] = np.array(o['r2_ci']).flatten()
    return d

def hier(A, c, rng):
    S, T = A.shape; out = np.empty(B)
    for b in range(B):
        si = rng.integers(0, S, S); ti = rng.integers(0, T, T)
        out[b] = 100 * (A[np.ix_(si, ti)].mean() / c[ti].mean() - 1)
    return out

rows, log = [], []
for cell in ['G2_hi_d10', 'G3_lo_d18']:
    g = load(os.path.join(D, 'g10', f'eval_{cell}.mat')); n = load(os.path.join(D, 'nr_g10', f'eval_{cell}.mat'))
    A = n['seeds']; A = A if A.shape[0] < A.shape[1] else A.T
    assert np.allclose(A.mean(0), n['prim'], atol=1e-12), 'seed mean != primary'
    same = {k: bool(np.array_equal(g['vals'][k], n['vals'][k])) for k in n['names']}
    assert all(same.values()), f'pairing check failed: {same}'
    # method check: reproduce stored R2 vs Context table
    ct = n['vals']['Context table']; rc = hier(A, ct, np.random.default_rng(20261104))
    rep = (np.percentile(rc, 2.5), np.percentile(rc, 97.5))
    c = g['vals']['Context-joint']; d = n['prim'] - c; T = len(d)
    m = 100 * d.mean() / c.mean(); se = d.std(ddof=1) / np.sqrt(T); t = stats.t.ppf(0.95, T - 1)
    lo, hi = 100 * (d.mean() - t * se) / c.mean(), 100 * (d.mean() + t * se) / c.mean()
    p = stats.wilcoxon(n['prim'], c).pvalue
    hb = hier(A, c, np.random.default_rng(20261104)); hlo, hhi = np.percentile(hb, 2.5), np.percentile(hb, 97.5)
    sm = 100 * (A.mean(1) / c.mean() - 1)
    rows.append(dict(cell=cell, comparator='Context-joint (G10 per-cell combined table)', label='descriptive, not pre-registered',
        n_traces=T, n_seeds=A.shape[0], ctxj_mean=round(c.mean(), 4), primary_mean=round(n['prim'].mean(), 4),
        margin_pct=round(m, 2), ci90_lo=round(lo, 2), ci90_hi=round(hi, 2), wilcoxon_p=f'{p:.2e}',
        hier_ci95_lo=round(hlo, 2), hier_ci95_hi=round(hhi, 2), seeds_above=int((sm > 0).sum()),
        ctx_vs_ctxj_pct=round(100 * (c.mean() / ct.mean() - 1), 2)))
    log.append(f'{cell}: pairing check OK (9 shared comparators bit-identical); '
               f'R2 vs Context table stored [{n["r2"][0]:.2f}, {n["r2"][1]:.2f}] reproduced [{rep[0]:.2f}, {rep[1]:.2f}]')
os.makedirs(os.path.join(here, 'out'), exist_ok=True)
with open(os.path.join(here, 'out', 'nr_g10_ctxj_descriptive.csv'), 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
open(os.path.join(here, 'out', 'nr_g10_ctxj_descriptive.txt'), 'w').write(
    'DESCRIPTIVE, NOT PRE-REGISTERED. B=20000, rng seed 20261104\n' + '\n'.join(log) + '\n' + '\n'.join(str(r) for r in rows) + '\n')
print(open(os.path.join(here, 'out', 'nr_g10_ctxj_descriptive.txt')).read())
