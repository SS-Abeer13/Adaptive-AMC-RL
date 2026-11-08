from common import *
import numpy as np
D = os.path.join(ROOT, 'Optimized/v17x/Dataset')
r = {(x['cell'], x['scheme']): x for x in csv.DictReader(open(os.path.join(D, 'a6_pf_timing.csv')))}
fig, axs = plt.subplots(1, 2, figsize=(3.5, 1.9), gridspec_kw={'wspace': 0.55})
cfg = [('rtt0_np1', 'RTT 0\n1 proc.'), ('rtt8_np1', 'RTT 8\n1 proc.'), ('rtt8_np8', 'RTT 8\n8 proc.')]
for ax, (met, lab) in zip(axs, [('goodput', 'Baseline goodput (Mbps)'), ('jain', 'Baseline Jain index')]):
    for k, (mode, col, dx, nm) in enumerate([('acked', OL, -0.17, 'ACK-time PF'), ('scheduled', RL, 0.17, 'scheduling-time PF')]):
        for j, (c, _) in enumerate(cfg):
            x = r[(f'{mode}_{c}', 'Baseline')]
            m, lo, hi = float(x[met + '_mean']), float(x[met + '_ci_lo']), float(x[met + '_ci_hi'])
            ax.bar(j + dx, m, width=0.32, color=col, alpha=0.9, label=nm if j == 0 else None)
            ax.errorbar(j + dx, m, yerr=[[m - lo], [hi - m]], color=INK, capsize=1.5, lw=0.7)
    ax.set_xticks(range(3)); ax.set_xticklabels([c[1] for c in cfg], fontsize=6); ax.set_ylabel(lab); ax.grid(axis='x', visible=False)
axs[1].set_ylim(0.3, 0.6)
fig.legend(*axs[0].get_legend_handles_labels(), loc='upper center', bbox_to_anchor=(0.5, 1.06), ncol=2, frameon=False, fontsize=6)
save(fig, 'f8_pftiming')
