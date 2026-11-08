"""G6 seed-level inference: M1 primary (v17, 10 seeds x 500 eval traces) vs the 500-trace
re-calibrated comparators of stage G6 (Optimized/v17x/Dataset/ckpt/g6c/eval.mat), same 500
evaluation traces with common random numbers.  Same estimators and RNG seeds as g3_seed_stats.py.
Rule R2: margin is seed-robust iff the hierarchical (seed x trace) 95% CI lower bound > 0.
Output: paper/analysis/out/g6_seed_stats.csv and .txt
"""
import sys, os, csv, numpy as np, h5py
from scipy import stats
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import v17mat
B = 20000
ROOT = os.path.join(here, '..', '..')
s, o, _, _ = v17mat.load(os.path.join(ROOT, 'Optimized/v17/Dataset/results_v17_M1_dl_rtt8.mat'))
A = o['primary']['Deep A2C v17']; A = A[~np.all(np.isnan(A), axis=1)]
h = h5py.File(os.path.join(ROOT, 'Optimized/v17x/Dataset/ckpt/g6c/eval.mat'), 'r')
CMPS = [('Context-joint-500', 'prim_ctxj500'), ('Context-500', 'prim_ctx500'), ('Fixed-500', 'prim_fixed500'),
        ('FixedPU-500', 'prim_pu500'), ('OLLA-tuned-500', 'prim_olla500')]
rows, log = [], []
for name, key in CMPS:
    rng = np.random.default_rng(20261104); rng_seed = np.random.default_rng(20261105)
    c = np.asarray(h['out'][key]).ravel()
    S, T = A.shape
    point = 100 * (A.mean() / c.mean() - 1)
    seed_m = 100 * (A.mean(axis=1) / c.mean() - 1)
    n_pos = int(np.sum(seed_m > 0))
    p_sign = stats.binomtest(n_pos, S, 0.5, alternative='greater').pvalue
    sb = np.array([seed_m[rng_seed.integers(0, S, S)].mean() for _ in range(B)])
    hb = np.empty(B)
    for b in range(B):
        si = rng.integers(0, S, S); ti = rng.integers(0, T, T)
        hb[b] = 100 * (A[np.ix_(si, ti)].mean() / c[ti].mean() - 1)
    lo95, hi95 = np.percentile(hb, [2.5, 97.5])
    r = dict(comparator=name, n_seeds=S, n_traces=T, cmp_mean=round(c.mean(), 4), rl_mean=round(A.mean(), 4),
             margin_pct=round(point, 3), seeds_above=f'{n_pos}/{S}', sign_test_p_one_sided=f'{p_sign:.3g}',
             seed_margin_min=round(seed_m.min(), 3), seed_margin_max=round(seed_m.max(), 3),
             seedmean_boot_ci95_lo=round(np.percentile(sb, 2.5), 3), seedmean_boot_ci95_hi=round(np.percentile(sb, 97.5), 3),
             hier_boot_ci95_lo=round(lo95, 3), hier_boot_ci95_hi=round(hi95, 3),
             hier_boot_p_le0=f'{(np.sum(hb <= 0) + 1) / (B + 1):.3g}', seed_robust_R2=int(lo95 > 0))
    rows.append(r)
    log.append(f"M1 primary vs {name}: margin {point:+.2f}% | seeds>0 {n_pos}/{S} (sign p={p_sign:.3g}) | "
               f"seed-mean boot 95% [{r['seedmean_boot_ci95_lo']:+.2f},{r['seedmean_boot_ci95_hi']:+.2f}] | "
               f"hier 95% [{lo95:+.2f},{hi95:+.2f}] | R2 seed-robust={r['seed_robust_R2']}")
os.makedirs(os.path.join(here, 'out'), exist_ok=True)
with open(os.path.join(here, 'out', 'g6_seed_stats.csv'), 'w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
open(os.path.join(here, 'out', 'g6_seed_stats.txt'), 'w').write(f'B={B}, rng seeds 20261104/20261105 (reset per comparator)\n' + '\n'.join(log) + '\n')
print('\n'.join(log))
