"""G6 seed-level inference (EOT resolved variant; logic identical to paper/analysis/g6_seed_stats.py).
Only input and output paths modified.
"""
import sys, os, csv, numpy as np, h5py
from scipy import stats

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'paper', 'analysis'))

SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'Optimized', 'v17x', 'Dataset', 'eot', 'resolved_M1.mat')
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, 'Optimized', 'v17x', 'Dataset', 'eot', 'out'); os.makedirs(OUT, exist_ok=True)
B = 20000

def main():
    if not os.path.exists(SRC):
        print(f'INPUT MISSING: {SRC}'); return
    h = h5py.File(SRC, 'r')
    # m1_seeds in resolved_M1.mat
    A = np.asarray(h['out']['m1_seeds'][()], dtype=float)
    if (A.shape[0] > A.shape[1] or (A.shape[1] == 10 and A.shape[0] != 10)): A = A.T  # ensure (S, T)
    A = A[~np.all(np.isnan(A), axis=1)]

    CMPS = [('Context-joint-500', 'prim_ctxj500'), ('Context-500', 'prim_ctx500'), ('Fixed-500', 'prim_fixed500'),
            ('FixedPU-500', 'prim_pu500'), ('OLLA-tuned-500', 'prim_olla500')]
    rows, log = [], []
    for name, key in CMPS:
        rng = np.random.default_rng(20261104); rng_seed = np.random.default_rng(20261105)
        c = np.asarray(h['out']['cmp_g6c'][key][()], dtype=float).ravel()
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
        poi = float(np.mean((A > c[None, :]) + 0.5 * (A == c[None, :])))
        rng_p = np.random.default_rng(20261108); pb = np.empty(B // 4)
        for b in range(B // 4):
            si = rng_p.integers(0, S, S); ti = rng_p.integers(0, T, T); Ab = A[np.ix_(si, ti)]; cb = c[ti][None, :]
            pb[b] = np.mean((Ab > cb) + 0.5 * (Ab == cb))
        r = dict(comparator=name, n_seeds=S, n_traces=T, cmp_mean=round(c.mean(), 4), rl_mean=round(A.mean(), 4),
                 margin_pct=round(point, 3), seeds_above=f'{n_pos}/{S}', sign_test_p_one_sided=f'{p_sign:.3g}',
                 seed_margin_min=round(seed_m.min(), 3), seed_margin_max=round(seed_m.max(), 3),
                 seedmean_boot_ci95_lo=round(np.percentile(sb, 2.5), 3), seedmean_boot_ci95_hi=round(np.percentile(sb, 97.5), 3),
                 hier_boot_ci95_lo=round(lo95, 3), hier_boot_ci95_hi=round(hi95, 3),
                 hier_boot_p_le0=f'{(np.sum(hb <= 0) + 1) / (B + 1):.3g}', seed_robust_R2=int(lo95 > 0),
                 prob_improve=round(poi, 4), poi_ci95_lo=round(np.percentile(pb, 2.5), 4), poi_ci95_hi=round(np.percentile(pb, 97.5), 4))
        rows.append(r)
        log.append(f"M1 primary vs {name}: margin {point:+.2f}% | seeds>0 {n_pos}/{S} (sign p={p_sign:.3g}) | "
                   f"seed-mean boot 95% [{r['seedmean_boot_ci95_lo']:+.2f},{r['seedmean_boot_ci95_hi']:+.2f}] | "
                   f"hier 95% [{r['hier_boot_ci95_lo']:+.2f},{r['hier_boot_ci95_hi']:+.2f}] (p_le0={r['hier_boot_p_le0']}) | "
                   f"P(RL>cmp)={poi:.3f} [{r['poi_ci95_lo']:.3f},{r['poi_ci95_hi']:.3f}] | R2={r['seed_robust_R2']}")

    with open(os.path.join(OUT, 'g6_seed_stats.csv'), 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader(); w.writerows(rows)
    with open(os.path.join(OUT, 'g6_seed_stats.txt'), 'w') as f:
        f.write('\n'.join(log) + '\n')
    print('\n'.join(log))

if __name__ == '__main__':
    main()
