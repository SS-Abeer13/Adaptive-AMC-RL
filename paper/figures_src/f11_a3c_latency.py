"""Fig. a3c: per-TTI decision-time CDF from the A3c benchmark (Optimized/v17x/run_a3c.py).

Input (A3c output, committed 02ad6e7):
  Optimized/v17x/Dataset/cdf_data_N<users>.csv  quantile grid (column prob, 0..1 in steps of 0.001) of the
      per-TTI time in microseconds for each scheme; raw times, not corrected.
  Optimized/v17x/Dataset/table_a3c.csv          medians and tails; row "Noise floor (empty loop)" = timer floor.
Schemes shown (all single-threaded Python/NumPy, so the runtime is the same for all four):
  Residual A2C = NR2 full policy step (state construction + forward pass + action selection), NumPy
  Fixed, Context-joint, OLLA = NumPy implementations of the comparators.
Output:
  paper/manuscript/figs/f11_a3c_latency.pdf (+ -1.png)
  paper/analysis/out/a3c_summary.csv: per scheme the median (raw), the p99.9 minus the timer floor (the empty-loop
      p99.9), and the share of TTIs within each slot length, computed on RAW times (conservative). These are the A3c
      values in pending_values.csv.
Reporting rule (author, 11 Nov 2026): medians and noise-floor-corrected tails only; platform caveats; FLOPs as the
hardware-independent cost; no real-time feasibility claim, in particular none at 120 kHz.
Usage: python f11_a3c_latency.py [--users 10]
"""
import argparse, csv, os
import numpy as np
from common import *

SLOTS = [(15, 1000.0), (30, 500.0), (60, 250.0), (120, 125.0)]   # kHz, slot length in us (TS 38.211: 1 ms / 2^mu)
ORDER = [('Residual A2C', 'NR2_full_NumPy_us', RL, '-'), ('Fixed', 'Fixed_NumPy_us', CAL, '--'),
         ('Context-joint', 'Context_joint_NumPy_us', CAL, '-.'), ('OLLA', 'OLLA_NumPy_us', OL, ':')]
ap = argparse.ArgumentParser(); ap.add_argument('--users', type=int, default=10); a = ap.parse_args()
D = os.path.join(ROOT, 'Optimized', 'v17x', 'Dataset')
R = list(csv.DictReader(open(os.path.join(D, f'cdf_data_N{a.users}.csv'), newline='')))
p = np.array([float(r['prob']) for r in R])
Q = {col: np.array([float(r[col]) for r in R]) for _, col, _, _ in ORDER}
tab = {(int(r['users']), r['scheme'], r['runtime']): r for r in csv.DictReader(open(os.path.join(D, 'table_a3c.csv'), newline=''))}
floor = float(tab[(a.users, 'Noise floor (empty loop)', 'Python')]['p99_9_us'])
# consistency with the A3c table (medians and p99.9 must match the CDF grid)
for nm, sch in [('NR2_full_NumPy_us', 'NR2 (Full Policy Step)'), ('Fixed_NumPy_us', 'Fixed AMC'), ('Context_joint_NumPy_us', 'Context-joint'), ('OLLA_NumPy_us', 'OLLA')]:
    t = tab[(a.users, sch, 'NumPy')]
    assert abs(np.interp(0.5, p, Q[nm]) - float(t['median_us'])) < 0.05 and abs(np.interp(0.999, p, Q[nm]) - float(t['p99_9_us'])) < 0.05, nm

fig, ax = plt.subplots(figsize=(3.5, 2.6))
for lab, col, c, ls in ORDER:
    ax.plot(Q[col], p, color=c, ls=ls, lw=1.2, label=lab)
res = Q['NR2_full_NumPy_us']; rows = []
for khz, us in SLOTS:
    ax.axvline(us, color=GR, lw=0.6)
    ax.text(us, 1.02, f'{khz} kHz: {100 * np.interp(us, res, p):.1f} %', rotation=90, ha='center', va='bottom', fontsize=7, color=INK, transform=ax.get_xaxis_transform())
ax.set_xscale('log'); ax.set_ylim(0, 1); ax.set_xlabel(r'Per-TTI decision time ($\mu$s)'); ax.set_ylabel('CDF')
ax.legend(loc='upper center', bbox_to_anchor=(0.5, -0.28), ncol=4, frameon=False, fontsize=7, handlelength=1.8, columnspacing=0.9, handletextpad=0.4)
save(fig, 'f11_a3c_latency')

out = os.path.join(ROOT, 'paper', 'analysis', 'out', 'a3c_summary.csv')
with open(out, 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['users', 'scheme', 'column', 'median_us_raw', 'p99_9_us_raw', 'floor_us_empty_loop_p99_9', 'p99_9_us_floor_corrected'] + [f'share_le_{k}kHz_pct_raw' for k, _ in SLOTS])
    for lab, col, _, _ in ORDER:
        x = Q[col]; m, t9 = np.interp(0.5, p, x), np.interp(0.999, p, x)
        w.writerow([a.users, lab, col, f'{m:.1f}', f'{t9:.1f}', f'{floor:.1f}', f'{t9 - floor:.1f}'] + [f'{100 * np.interp(us, x, p):.1f}' for _, us in SLOTS])
print(open(out).read())
