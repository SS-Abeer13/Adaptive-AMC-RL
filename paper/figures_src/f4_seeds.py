from common import *
import numpy as np
T = open(os.path.join(ROOT, 'Optimized/v17/Dataset/fill_summary_v17.txt'), encoding='utf-8').read()
G = {(r['case'], r['scheme'], r['comparator']): r for r in csv.DictReader(open(os.path.join(ROOT, 'paper/analysis/out/g3_seed_stats.csv')))}
def seeds(case, tag):
    m = re.search(rf'REPLSEED\|{case}\|pf\|a2c_seed_means=\[([0-9. ]+)\]\|best_rule=Context table\(([0-9.]+)\)', T)
    return np.array(m.group(1).split(), float), float(m.group(2))
fig, ax = plt.subplots(figsize=(3.5, 2.4))
rows = [('M1_dl_rtt8', 'M1  residual A2C', RL), ('M2_dl_rtt0', 'M2  residual A2C', GR)]
for j, (cs, lab, col) in enumerate(rows):
    s, ctx = seeds(cs, '')
    d = 100 * (s / ctx - 1); ax.plot(d, [j] * len(d) + np.linspace(-0.18, 0.18, len(d)), 'o', color=col, ms=3.5, mec='white', mew=0.4)
    r = G[(cs, 'Deep A2C v17', 'Context table')]
    m = d.mean(); lo, hi = float(r['seedmean_boot_ci95_lo']), float(r['seedmean_boot_ci95_hi'])
    ax.errorbar(m, j + 0.38, xerr=[[m - lo], [hi - m]], fmt='D', color=INK, ms=4, capsize=2, lw=1)
ax.axvline(0, color=INK, lw=0.7)
ax.set_yticks([0.1, 1.1]); ax.set_yticklabels(['M1', 'M2']); ax.invert_yaxis(); ax.grid(axis='y', visible=False)
ax.set_xlabel('Per-seed margin vs Context table (%)')
ax.plot([], [], 'o', color=RL, label='one seed'); ax.plot([], [], 'D', color=INK, label='mean, 95 % seed-bootstrap CI'); ax.legend(loc='lower right', frameon=False)
save(fig, 'f4_seeds')
