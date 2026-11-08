from common import *
import sys, numpy as np, h5py
sys.path.insert(0, os.path.join(ROOT, 'paper', 'analysis'))
import v17mat
T = open(os.path.join(ROOT, 'Optimized/v17/Dataset/fill_summary_v17.txt'), encoding='utf-8').read()
G = {(r['case'], r['scheme'], r['comparator']): r for r in csv.DictReader(open(os.path.join(ROOT, 'paper/analysis/out/g3_seed_stats.csv')))}
G6 = {r['comparator']: r for r in csv.DictReader(open(os.path.join(ROOT, 'paper/analysis/out/g6_seed_stats.csv')))}
def seeds(case):
    m = re.search(rf'REPLSEED\|{case}\|pf\|a2c_seed_means=\[([0-9. ]+)\]\|best_rule=Context table\(([0-9.]+)\)', T)
    return np.array(m.group(1).split(), float), float(m.group(2))
# per-seed margins of M1 against the G6 combined table (same estimator as g6_seed_stats.py)
s_, o_, _, _ = v17mat.load(os.path.join(ROOT, 'Optimized/v17/Dataset/results_v17_M1_dl_rtt8.mat'))
A = o_['primary']['Deep A2C v17']; A = A[~np.all(np.isnan(A), axis=1)]
cj = np.asarray(h5py.File(os.path.join(ROOT, 'Optimized/v17x/Dataset/ckpt/g6c/eval.mat'), 'r')['out']['prim_ctxj500']).ravel()
rows = []
s, ctx = seeds('M1_dl_rtt8'); r = G[('M1_dl_rtt8', 'Deep A2C v17', 'Context table')]
rows.append(('M1 vs Context table\n(original, 10 traces)', 100 * (s / ctx - 1), float(r['seedmean_boot_ci95_lo']), float(r['seedmean_boot_ci95_hi']), RL))
r = G6['Context-joint-500']
rows.append(('M1 vs combined table\n(re-cal., 500 traces)', 100 * (A.mean(axis=1) / cj.mean() - 1), float(r['seedmean_boot_ci95_lo']), float(r['seedmean_boot_ci95_hi']), OL))
s, ctx = seeds('M2_dl_rtt0'); r = G[('M2_dl_rtt0', 'Deep A2C v17', 'Context table')]
rows.append(('M2 vs Context table\n(original, 10 traces)', 100 * (s / ctx - 1), float(r['seedmean_boot_ci95_lo']), float(r['seedmean_boot_ci95_hi']), GR))
fig, ax = plt.subplots(figsize=(3.5, 2.6))
for j, (lab, d, lo, hi, col) in enumerate(rows):
    ax.plot(d, [j] * len(d) + np.linspace(-0.18, 0.18, len(d)), 'o', color=col, ms=3.5, mec='white', mew=0.4)
    m = d.mean(); ax.errorbar(m, j + 0.36, xerr=[[m - lo], [hi - m]], fmt='D', color=INK, ms=4, capsize=2, lw=1)
    ax.text(ax.get_xlim()[1] if False else 5.3, j, f'{int(np.sum(d > 0))}/{len(d)} > 0', va='center', ha='right', fontsize=6.3, color=INK)
ax.axvline(0, color=INK, lw=0.7)
ax.set_yticks([0.1, 1.1, 2.1]); ax.set_yticklabels([r_[0] for r_ in rows], fontsize=6.5); ax.invert_yaxis(); ax.grid(axis='y', visible=False)
ax.set_xlim(-2.6, 5.5)
ax.set_xlabel('Per-seed margin (%)')
ax.plot([], [], 'o', color=GR, label='one training seed'); ax.plot([], [], 'D', color=INK, label='mean, 95 % seed-bootstrap CI')
ax.legend(loc='lower left', frameon=False, fontsize=6.2, bbox_to_anchor=(0.0, -0.33), ncol=2)
save(fig, 'f4_seeds')
