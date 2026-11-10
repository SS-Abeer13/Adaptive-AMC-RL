from common import *
C = core(); cases = [('M1_dl_rtt8', 'M1  deadline, RTT 8'), ('M2_dl_rtt0', 'M2  deadline, RTT 0'), ('M3_gp_rtt8', 'M3  goodput, RTT 8'), ('M4_gp_rtt0', 'M4  goodput, RTT 0')]
cmps = ['OLLA', 'Fixed', 'FixedPU (Oracle)', 'Context table', 'Multi-OLLA']
fig, axs = plt.subplots(1, 4, figsize=(7.16, 2.5), sharey=True)
for ax, (cs, ttl) in zip(axs, cases):
    for i, k in enumerate(cmps):
        r = C[(cs, 'Deep A2C v17', k)]; m = float(r['pct_margin']); lo, hi = float(r['ci90_lo']), float(r['ci90_hi'])
        c, mk = STYLE[k]; filled = r['beats'] == '1'
        ax.errorbar(m, i, xerr=[[m - lo], [hi - m]], fmt=mk, color=RL, mfc=RL if filled else 'white', ms=5, capsize=2, lw=1)
    ax.axvline(0, color=INK, lw=0.7); ax.set_title(ttl, fontsize=8); ax.grid(axis='y', visible=False)
    ax.set_xlabel('margin of A2C (%)')
axs[0].set_yticks(range(len(cmps))); axs[0].set_yticklabels([LABEL[k] for k in cmps]); axs[0].invert_yaxis()
save(fig, 'f3_forest')
