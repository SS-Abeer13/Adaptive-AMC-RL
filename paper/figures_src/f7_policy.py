from common import *
import numpy as np
A = os.path.join(ROOT, 'paper/analysis/out')
a1 = {r['speed_class']: r for r in csv.DictReader(open(os.path.join(A, 'a1_speed_stats.csv')))}
g1 = {r['bin']: r for r in csv.DictReader(open(os.path.join(A, 'g1_seed_consistency.csv')))}
fig, axs = plt.subplots(1, 2, figsize=(7.16, 2.2), gridspec_kw={'width_ratios': [0.8, 1.4], 'wspace': 0.35})
# (a) A1: margin vs the v17 Context table by speed class, hierarchical 95 % CI
ax = axs[0]
cls = [('lo', '< 10 m/s'), ('mid', '10-20 m/s'), ('hi', '> 20 m/s'), ('all', 'all users')]
for j, (k, l) in enumerate(cls):
    m, lo, hi = float(a1[k]['margin_pct']), float(a1[k]['hier_ci95_lo']), float(a1[k]['hier_ci95_hi'])
    col = OL if hi < 0 else (GR if k == 'all' else RL)
    ax.bar(j, m, color=col, width=0.62, alpha=0.9); ax.errorbar(j, m, yerr=[[m - lo], [hi - m]], color=INK, capsize=2, lw=0.8)
    ax.text(j, -0.12, f"{100 * float(a1[k]['share_user_traces']):.0f} %", ha='center', va='top', fontsize=6, color=GR, transform=ax.get_xaxis_transform())
ax.axhline(0, color=INK, lw=0.7); ax.set_xticks(range(len(cls))); ax.set_xticklabels([c[1] for c in cls]); ax.grid(axis='x', visible=False)
ax.set_ylabel('Margin vs Context table (%)'); ax.set_title('(a) By user speed', fontsize=7.5, loc='left')
# (b) G1: share of delta = +1 on scheduled new transmissions, pooled bar, whiskers = min/max over the 10 seeds
ax = axs[1]
bins = [('busy_0', 'busy\n0'), ('busy_1_2', 'busy\n1-2'), ('busy_ge3', 'busy\n>=3'), (None, ''), ('slack_gt_0.6', 'slack\n>0.6'),
        ('slack_0.3_0.6', 'slack\n0.3-0.6'), ('slack_le_0.3', 'slack\n<=0.3'), (None, ''), ('calm', 'calm'), ('burst', 'burst')]
for j, (k, l) in enumerate(bins):
    if k is None: continue
    r = g1[k]; m, lo, hi = float(r['pct_plus1']), float(r['plus1_seed_min']), float(r['plus1_seed_max'])
    ax.bar(j, m, color=RL, width=0.62, alpha=0.9); ax.errorbar(j, m, yerr=[[m - lo], [hi - m]], color=INK, capsize=2, lw=0.8)
    ax.text(j, 1.02, f"{float(r['share_of_decisions']):.0f} %", ha='center', va='bottom', fontsize=5.8, color=GR, transform=ax.get_xaxis_transform())
ax.axhline(float(g1['all']['pct_plus1']), color=GR, lw=0.7, ls='--')
ax.set_xticks([j for j, (k, l) in enumerate(bins) if k]); ax.set_xticklabels([l for k, l in bins if k], fontsize=6.3)
ax.set_ylim(0, 100); ax.grid(axis='x', visible=False); ax.set_ylabel(r'Share of $\delta=+1$ (%)')
ax.set_title('(b) Residual action by state', fontsize=7.5, loc='left', pad=9)
save(fig, 'f7_policy')
