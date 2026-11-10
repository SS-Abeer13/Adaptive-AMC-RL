from common import *
P = prim(); C = core(); case = 'M1_dl_rtt8'
order = ['Baseline', 'OLLA', 'Multi-OLLA', 'Fixed', 'FixedPU (Oracle)', 'Context table', 'Deep A2C v17']
fig, ax = plt.subplots(figsize=(3.5, 2.6))
for i, s in enumerate(order):
    v, ci = P[(case, s)]; c, m = STYLE[s]
    ax.errorbar(100 * v, i, xerr=100 * ci, fmt=m, color=c, ms=5, capsize=2, lw=1, mec='white', mew=0.5)
ax.set_yticks(range(len(order))); ax.set_yticklabels([LABEL[s] for s in order]); ax.invert_yaxis()
ax.set_xlabel('On-time delivery in M1 (% of packets)')
ax.set_xlim(50, 66); ax.grid(axis='y', visible=False)
for s, dy in [('OLLA', 'OLLA'), ('Context table', 'Context table')]:
    r = C[(case, 'Deep A2C v17', s)]
    i = order.index(s); ax.annotate(f"A2C {float(r['pct_margin']):+.2f} %", (100 * P[(case, s)][0] + 100 * P[(case, s)][1] + 0.4, i), va='center', fontsize=7, color=RL)
save(fig, 'f1_thesis')
