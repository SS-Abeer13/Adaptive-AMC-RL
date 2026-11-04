"""G3: seed-level and hierarchical (seed x trace) inference for the v17 deadline cases.

Margin definition (same as table_core.csv): 100 * (mean(RL) / mean(comparator) - 1),
RL averaged over seeds and traces, deterministic comparator averaged over traces.
Output: paper/analysis/out/g3_seed_stats.csv and .txt
"""
import sys, os, csv, numpy as np
from scipy import stats
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import v17mat
rng = np.random.default_rng(20261104)
rng_seed = np.random.default_rng(20261105)   # seed-mean bootstrap only (added after Checkpoint 5)
B = 20000
os.makedirs(os.path.join(here, 'out'), exist_ok=True)
rows, log = [], []

def hier_boot(A, c, B):
    """A: (S,T) RL per seed x trace; c: (T,) comparator. Resample seeds, then traces (shared across seeds, CRN pairing kept)."""
    S, T = A.shape
    out = np.empty(B)
    for b in range(B):
        si = rng.integers(0, S, S); ti = rng.integers(0, T, T)
        out[b] = 100 * (A[np.ix_(si, ti)].mean() / c[ti].mean() - 1)
    return out

def trace_boot(a, c, B):
    T = len(a); out = np.empty(B)
    for b in range(B):
        ti = rng.integers(0, T, T); out[b] = 100 * (a[ti].mean() / c[ti].mean() - 1)
    return out

for tag, schemes in [('M1_dl_rtt8', ['Deep A2C v17', 'Deep A2C v17 (resid-800)', 'Deep A2C v17 (offset)']),
                     ('M2_dl_rtt0', ['Deep A2C v17', 'Deep A2C v17 (resid-800)'])]:
    s, o, _, _ = v17mat.load(os.path.join(here, f'../../Optimized/v17/Dataset/results_v17_{tag}.mat'))
    P = o['primary']
    for rl in schemes:
        A = P[rl]; A = A[~np.all(np.isnan(A), axis=1)]
        for cmp in ['Context table', 'Fixed', 'FixedPU (Oracle)']:
            c = P[cmp][0]
            S = A.shape[0]
            point = 100 * (A.mean() / c.mean() - 1)
            seed_m = 100 * (A.mean(axis=1) / c.mean() - 1)           # per-seed margins
            n_pos = int(np.sum(seed_m > 0))
            p_sign = stats.binomtest(n_pos, S, 0.5, alternative='greater').pvalue
            t_res = stats.ttest_1samp(seed_m, 0.0)
            t_ci = stats.t.interval(0.90, S - 1, loc=seed_m.mean(), scale=stats.sem(seed_m))
            # bootstrap over the S seed margins only (traces fixed): resample seeds with replacement
            sb = np.array([seed_m[rng_seed.integers(0, S, S)].mean() for _ in range(B)])
            t95 = stats.t.interval(0.95, S - 1, loc=seed_m.mean(), scale=stats.sem(seed_m))
            hb = hier_boot(A, c, B)
            tb = trace_boot(A.mean(axis=0), c, B)
            r = dict(case=tag, scheme=rl, comparator=cmp, n_seeds=S, n_traces=A.shape[1],
                     margin_pct=round(point, 3),
                     seeds_above=f'{n_pos}/{S}', sign_test_p_one_sided=f'{p_sign:.3g}',
                     seed_t_p_two_sided=f'{t_res.pvalue:.3g}',
                     seed_t_ci90_lo=round(t_ci[0], 3), seed_t_ci90_hi=round(t_ci[1], 3),
                     seed_margin_min=round(seed_m.min(), 3), seed_margin_max=round(seed_m.max(), 3),
                     trace_boot_ci90_lo=round(np.percentile(tb, 5), 3), trace_boot_ci90_hi=round(np.percentile(tb, 95), 3),
                     hier_boot_ci90_lo=round(np.percentile(hb, 5), 3), hier_boot_ci90_hi=round(np.percentile(hb, 95), 3),
                     hier_boot_ci95_lo=round(np.percentile(hb, 2.5), 3), hier_boot_ci95_hi=round(np.percentile(hb, 97.5), 3),
                     seed_t_ci95_lo=round(t95[0], 3), seed_t_ci95_hi=round(t95[1], 3),
                     seedmean_boot_ci90_lo=round(np.percentile(sb, 5), 3), seedmean_boot_ci90_hi=round(np.percentile(sb, 95), 3),
                     seedmean_boot_ci95_lo=round(np.percentile(sb, 2.5), 3), seedmean_boot_ci95_hi=round(np.percentile(sb, 97.5), 3),
                     hier_boot_p_le0=f'{(np.sum(hb <= 0) + 1) / (B + 1):.3g}')
            rows.append(r)
            log.append(f"{tag} | {rl} vs {cmp}: margin {point:+.2f}% | seeds>0 {n_pos}/{S} (sign p={p_sign:.3g}) | "
                       f"seed-t 90% CI [{t_ci[0]:+.2f},{t_ci[1]:+.2f}] p={t_res.pvalue:.3g} | "
                       f"trace-boot 90% [{np.percentile(tb,5):+.2f},{np.percentile(tb,95):+.2f}] | "
                       f"seed-mean boot 95% [{np.percentile(sb,2.5):+.2f},{np.percentile(sb,97.5):+.2f}] seed-t 95% [{t95[0]:+.2f},{t95[1]:+.2f}] | "
                       f"hier-boot 90% [{np.percentile(hb,5):+.2f},{np.percentile(hb,95):+.2f}] "
                       f"95% [{np.percentile(hb,2.5):+.2f},{np.percentile(hb,97.5):+.2f}] P(<=0)={r['hier_boot_p_le0']}")
with open(os.path.join(here, 'out', 'g3_seed_stats.csv'), 'w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
open(os.path.join(here, 'out', 'g3_seed_stats.txt'), 'w').write(f'B={B}, rng seed 20261104\n' + '\n'.join(log) + '\n')
print('\n'.join(log))
