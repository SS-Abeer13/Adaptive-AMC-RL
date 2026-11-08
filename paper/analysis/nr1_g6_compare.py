"""Secondary, descriptive (NR1 prereg section 4): NR1 per-seed-mean on-time per trace vs the G6
re-calibrated comparators and vs the M1 oracle-base primary, on M1's 500 evaluation traces (CRN).
Same estimator as run_cmp_stats in Optimized/v17x/stage_nr1.m: margin = 100*mean(d)/mean(b),
90% t-interval of the paired difference, two-sided Wilcoxon signed-rank (normal approximation).
NR1 per-seed values were not saved by stage_nr1 (only the seed mean), so no seed-level inference here.
Output: paper/analysis/out/nr1_g6_compare.csv
"""
import os, sys, csv, numpy as np, h5py
from scipy import stats
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import v17mat
R = os.path.join(here, '..', '..', 'Optimized')
nr1 = np.asarray(h5py.File(os.path.join(R, 'v17x/Dataset/ckpt/nr1/eval.mat'), 'r')['out']['nr1_prim']).ravel()
g6 = h5py.File(os.path.join(R, 'v17x/Dataset/ckpt/g6c/eval.mat'), 'r')['out']
s, o, _, _ = v17mat.load(os.path.join(R, 'v17/Dataset/results_v17_M1_dl_rtt8.mat'))
A = o['primary']['Deep A2C v17']; m1 = A[~np.all(np.isnan(A), axis=1)].mean(axis=0)
C = [('Context-joint-500', np.asarray(g6['prim_ctxj500']).ravel()), ('Context-500', np.asarray(g6['prim_ctx500']).ravel()),
     ('Fixed-500', np.asarray(g6['prim_fixed500']).ravel()), ('FixedPU-500', np.asarray(g6['prim_pu500']).ravel()),
     ('OLLA-tuned-500', np.asarray(g6['prim_olla500']).ravel()), ('M1 primary (oracle base)', m1)]
rows = []
for name, b in C:
    d = nr1 - b; n = len(d); bm = b.mean(); se = d.std(ddof=1) / np.sqrt(n); q = stats.t.ppf(0.95, n - 1)
    p = stats.wilcoxon(nr1, b, zero_method='wilcox', correction=False, method='approx').pvalue
    rows.append(dict(comparator=name, nr1_mean=round(nr1.mean(), 4), cmp_mean=round(bm, 4), margin_pct=round(100 * d.mean() / bm, 3),
                     ci90_lo=round(100 * (d.mean() - q * se) / bm, 3), ci90_hi=round(100 * (d.mean() + q * se) / bm, 3),
                     diff_pp=round(100 * d.mean(), 3), wilcoxon_p=f'{p:.3g}'))
    print(rows[-1])
with open(os.path.join(here, 'out', 'nr1_g6_compare.csv'), 'w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
