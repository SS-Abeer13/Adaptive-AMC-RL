"""NR2 statistics (FROZEN with paper/proposals/NR2_confirmatory_prereg.md, section 4).
Input : Optimized/v17x/Dataset/ckpt/nr2/eval.mat (MATLAB v7.3): out.nr2_seeds (10x500), out.nr2_ens (1x500),
        out.m1_seeds (10x500), out.cmp.<name> (1x500) for the 8 comparators.
Output: paper/analysis/out/nr2_stats.csv (trace level, Holm over 8), nr2_seed_stats.csv (R2 and secondary),
        nr2_verdict.txt, nr2_pending_values.csv (rows for paper/manuscript/pending_values.csv, item NR2).
Run   : python3 paper/analysis/nr2_stats.py [path/to/eval.mat]
"""
import os, sys, csv, numpy as np, h5py
from scipy import stats

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', '..', 'Optimized', 'v17x', 'Dataset', 'ckpt', 'nr2', 'eval.mat')
OUT = os.path.join(HERE, 'out'); os.makedirs(OUT, exist_ok=True)
B = 20000
FAMILY = [('Baseline', 'baseline'), ('OLLA', 'olla'), ('OLLA-tuned-500', 'olla_tuned500'), ('Multi-OLLA', 'multi_olla'),
          ('Fixed-500', 'fixed500'), ('FixedPU-500', 'fixedpu500'), ('Context-500', 'ctx500'), ('Context-joint-500', 'ctxj500')]
PRIMARY = 'Context-joint-500'

def arr(h, *path):
    x = h['out']
    for p in path: x = x[p]
    return np.asarray(x[()], dtype=float)

def seeds_by_traces(a, n_traces=None):
    """MATLAB (S,T) arrays arrive transposed from h5py as (T,S); return (S,T)."""
    a = np.atleast_2d(a)
    return a.T if a.shape[0] > a.shape[1] else a

def r1(a, b):
    """Paired R1 statistics, identical to run_cmp_stats in the v17x stages."""
    d = a - b; n = len(d); bm = b.mean(); se = d.std(ddof=1) / np.sqrt(n); q = stats.t.ppf(0.95, n - 1)
    p = 1.0 if np.all(d == 0) else stats.wilcoxon(a, b, zero_method='wilcox', correction=False, method='approx').pvalue
    return dict(margin_pct=100 * d.mean() / bm, ci90_lo=100 * (d.mean() - q * se) / bm, ci90_hi=100 * (d.mean() + q * se) / bm, p=p)

def holm(ps):
    order = np.argsort(ps); out = np.empty(len(ps)); cur = 0.0
    for i, k in enumerate(order):
        cur = max(cur, min(1.0, ps[k] * (len(ps) - i))); out[k] = cur
    return out

def seed_level(A, c):
    """Hierarchical seed x trace bootstrap, seed-mean bootstrap and sign test (as g3_seed_stats.py)."""
    rng = np.random.default_rng(20261104); rng_seed = np.random.default_rng(20261105)
    S, T = A.shape
    seed_m = 100 * (A.mean(axis=1) / c.mean() - 1)
    n_pos = int(np.sum(seed_m > 0))
    p_sign = stats.binomtest(n_pos, S, 0.5, alternative='greater').pvalue
    sb = np.array([seed_m[rng_seed.integers(0, S, S)].mean() for _ in range(B)])
    hb = np.empty(B)
    for b in range(B):
        si = rng.integers(0, S, S); ti = rng.integers(0, T, T)
        hb[b] = 100 * (A[np.ix_(si, ti)].mean() / c[ti].mean() - 1)
    return dict(seeds_above=n_pos, n_seeds=S, sign_p=p_sign, seed_min=seed_m.min(), seed_max=seed_m.max(),
                boot95_lo=np.percentile(sb, 2.5), boot95_hi=np.percentile(sb, 97.5),
                hier95_lo=np.percentile(hb, 2.5), hier95_hi=np.percentile(hb, 97.5))

def main():
    h = h5py.File(SRC, 'r')
    A = seeds_by_traces(arr(h, 'nr2_seeds')); M1 = seeds_by_traces(arr(h, 'm1_seeds'))
    ens = arr(h, 'nr2_ens').ravel()
    a = A.mean(axis=0)                                   # primary scheme: per-seed mean
    if A.shape != (10, 500) or M1.shape != (10, 500): sys.exit(f'unexpected shapes {A.shape} {M1.shape}')
    cmp = {name: arr(h, 'cmp', key).ravel() for name, key in FAMILY}
    rows = []
    for name, _ in FAMILY:
        r = r1(a, cmp[name]); r['comparator'] = name; rows.append(r)
    hp = holm(np.array([r['p'] for r in rows]))
    for r, x in zip(rows, hp):
        r['holm_p'] = x; r['beats'] = int(x < 0.05 and r['ci90_lo'] > 0)
    with open(os.path.join(OUT, 'nr2_stats.csv'), 'w', newline='') as fh:
        w = csv.writer(fh); w.writerow(['comparator', 'margin_pct', 'ci90_lo', 'ci90_hi', 'wilcoxon_p', 'holm_p', 'beats'])
        for r in rows: w.writerow([r['comparator'], f"{r['margin_pct']:+.2f}", f"{r['ci90_lo']:.2f}", f"{r['ci90_hi']:.2f}", f"{r['p']:.3g}", f"{r['holm_p']:.3g}", r['beats']])
    prim = next(r for r in rows if r['comparator'] == PRIMARY)
    sl = seed_level(A, cmp[PRIMARY])
    trace_pass = prim['beats'] == 1; seed_pass = sl['hier95_lo'] > 0
    if trace_pass and seed_pass: verdict = 'CONFIRM'
    elif trace_pass: verdict = 'TRACE'
    elif prim['holm_p'] < 0.05 and prim['ci90_hi'] < 0: verdict = 'REVERSE'
    else: verdict = 'NULL'
    win = all(r['beats'] == 1 for r in rows)
    # secondary
    sec_m1 = r1(a, M1.mean(axis=0)); sec_ens = r1(ens, cmp[PRIMARY])
    with open(os.path.join(OUT, 'nr2_seed_stats.csv'), 'w', newline='') as fh:
        w = csv.writer(fh); w.writerow(['analysis', 'value'])
        for k, v in sl.items(): w.writerow([f'R2_vs_{PRIMARY}_{k}', f'{v:.4g}' if isinstance(v, float) else v])
        for k, v in sec_m1.items(): w.writerow([f'secondary_vs_M1_{k}', f'{v:.4g}'])
        for k, v in sec_ens.items(): w.writerow([f'secondary_ensemble_vs_{PRIMARY}_{k}', f'{v:.4g}'])
    txt = (f"NR2 verdict: {verdict} | WIN={'yes' if win else 'no'} | reframing gate (CONFIRM and WIN): {'OPEN' if verdict == 'CONFIRM' and win else 'closed'}\n"
           f"vs {PRIMARY}: margin {prim['margin_pct']:+.2f}% 90% CI [{prim['ci90_lo']:+.2f}, {prim['ci90_hi']:+.2f}] Holm p={prim['holm_p']:.3g}; "
           f"seeds>0 {sl['seeds_above']}/{sl['n_seeds']}; hierarchical 95% [{sl['hier95_lo']:+.2f}, {sl['hier95_hi']:+.2f}]\n"
           f"secondary vs M1 (oracle base): {sec_m1['margin_pct']:+.2f}% [{sec_m1['ci90_lo']:+.2f}, {sec_m1['ci90_hi']:+.2f}]\n")
    open(os.path.join(OUT, 'nr2_verdict.txt'), 'w').write(txt); print(txt)
    src = 'paper/analysis/out/nr2_stats.csv; nr2_seed_stats.csv'
    pv = [('verdict', verdict), ('win', 'yes' if win else 'no'), ('margin_ctxj', f"{prim['margin_pct']:.2f}"),
          ('ci_lo_ctxj', f"{prim['ci90_lo']:.2f}"), ('ci_hi_ctxj', f"{prim['ci90_hi']:.2f}"), ('holm_ctxj', f"{prim['holm_p']:.3g}"),
          ('seeds_above', str(sl['seeds_above'])), ('hier_lo', f"{sl['hier95_lo']:.2f}"), ('hier_hi', f"{sl['hier95_hi']:.2f}"),
          ('margin_m1', f"{sec_m1['margin_pct']:.2f}")]
    with open(os.path.join(OUT, 'nr2_pending_values.csv'), 'w', newline='') as fh:
        w = csv.writer(fh); w.writerow(['item', 'key', 'value', 'source_file', 'date'])
        for k, v in pv: w.writerow(['NR2', k, v, src, ''])

if __name__ == '__main__':
    main()
