from common import *
import numpy as np
H = {r['case']: r for r in csv.DictReader(open(os.path.join(ROOT, 'Optimized/v17/paper/headroom.csv')))}
TL = {r['case_tag']: r for r in csv.DictReader(open(os.path.join(ROOT, 'Optimized/v17/paper/table_training_length.csv')))}
fig, (a, b) = plt.subplots(1, 2, figsize=(7.16, 2.5), gridspec_kw={'width_ratios': [1.5, 1]})
cases = ['M1_dl_rtt8', 'M2_dl_rtt0', 'M3_gp_rtt8', 'M4_gp_rtt0']; lab = ['M1', 'M2', 'M3', 'M4']
for i, c in enumerate(cases):
    fx = float(H[c]['fixed'])
    for k, (key, col, mk, nm) in enumerate([('genie', GR, 's', 'genie'), ('hindsight', OL, 'D', 'hindsight')]):
        v = 100 * (float(H[c][key]) / fx - 1)
        a.plot(i + (k - 0.5) * 0.18, v, mk, color=col, ms=5, label=nm if i == 0 else None)
a.axhline(0, color=INK, lw=0.7); a.set_xticks(range(4)); a.set_xticklabels(lab); a.set_ylabel('Headroom over Fixed (%)'); a.legend(frameon=False); a.grid(axis='x', visible=False)
for i, c in enumerate(['M1_dl_rtt8', 'M2_dl_rtt0']):
    r = TL[c]; y = [float(r['pct_800ep']), float(r['pct_3000ep'])]
    b.plot([0, 1], y, '-o', color=RL if i == 0 else GR, ms=4.5, lw=1.2, label=['M1', 'M2'][i])
b.axhline(0, color=INK, lw=0.7); b.set_xticks([0, 1]); b.set_xticklabels(['800 ep.', '3000 ep.']); b.set_xlim(-0.3, 1.3); b.grid(axis='x', visible=False)
b.set_ylabel('A2C margin vs Fixed (%)'); b.legend(frameon=False)
save(fig, 'f5_headroom')
