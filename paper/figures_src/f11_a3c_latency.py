"""Fig. a3c: per-TTI decision-time CDF (benchmark A3c). PLACEHOLDER until A3c has run.

Input (written by the A3c benchmark; not yet produced):
  Optimized/v17x/Dataset/a3c_tti_us.csv   columns: scheme,us   one row per measured TTI
      (per-TTI decision time for all users of the slot, in microseconds; raw, not corrected)
      scheme in {Residual A2C, Fixed, Context-joint, OLLA}
  Optimized/v17x/Dataset/a3c_meta.json    {"platform": str, "users": int, "floor_us": float}
      floor_us = timer + OS noise floor, measured with an empty timed region on the same platform
Output:
  paper/manuscript/figs/f11_a3c_latency.pdf (+ -1.png)
  Optimized/v17x/Dataset/a3c_summary.csv: medians (raw), p99.9 with the noise floor subtracted,
      and the share of TTIs under each slot length (computed on RAW times, i.e. conservatively).
      These are the values to copy into pending_values.csv (item A3c).
Reporting rule (author's instruction, 11 Nov 2026): medians and noise-floor-corrected tails only;
no real-time feasibility claim, in particular none at 120 kHz.
Usage: python f11_a3c_latency.py [--data DIR] [--out DIR]
"""
import argparse, json, csv, os
import numpy as np
from common import *

SLOTS = [(15, 1000.0), (30, 500.0), (60, 250.0), (120, 125.0)]   # kHz, slot length in us (TS 38.211: 1 ms / 2^mu)
ORDER = [('Residual A2C', RL, '-'), ('Fixed', CAL, '--'), ('Context-joint', CAL, '-.'), ('OLLA', OL, ':')]

ap = argparse.ArgumentParser()
ap.add_argument('--data', default=os.path.join(ROOT, 'Optimized', 'v17x', 'Dataset'))
ap.add_argument('--out', default=OUT)
a = ap.parse_args()
src = os.path.join(a.data, 'a3c_tti_us.csv')
if not os.path.exists(src):
    raise SystemExit(f'A3c output not found ({src}); the manuscript keeps the placeholder figure.')
meta = json.load(open(os.path.join(a.data, 'a3c_meta.json')))
T = {}
for r in csv.DictReader(open(src, newline='')):
    T.setdefault(r['scheme'], []).append(float(r['us']))
T = {k: np.sort(np.asarray(v)) for k, v in T.items()}
missing = [k for k, _, _ in ORDER if k not in T]
if missing: raise SystemExit(f'schemes missing in {src}: {missing}')

fig, ax = plt.subplots(figsize=(3.5, 2.6))
for k, col, ls in ORDER:
    x = T[k]; y = np.arange(1, len(x) + 1) / len(x)
    ax.step(x, y, where='post', color=col, ls=ls, lw=1.2, label=k)
res = T['Residual A2C']; rows = []
for khz, us in SLOTS:
    share = 100 * np.mean(res <= us)
    ax.axvline(us, color=GR, lw=0.6)
    ax.text(us, 1.02, f'{khz} kHz: {share:.1f} %', rotation=90, ha='center', va='bottom', fontsize=7, color=INK, transform=ax.get_xaxis_transform())
ax.set_xscale('log'); ax.set_ylim(0, 1); ax.set_xlabel(r'Per-TTI decision time ($\mu$s)'); ax.set_ylabel('CDF')
ax.legend(loc='upper center', bbox_to_anchor=(0.5, -0.28), ncol=4, frameon=False, fontsize=7, handlelength=1.8, columnspacing=0.9, handletextpad=0.4)
import common; common.OUT = a.out
save(fig, 'f11_a3c_latency')

with open(os.path.join(a.data, 'a3c_summary.csv'), 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['scheme', 'n_tti', 'median_us_raw', 'p99_9_us_floor_corrected'] + [f'share_le_{k}kHz_pct_raw' for k, _ in SLOTS])
    for k, _, _ in ORDER:
        x = T[k]
        w.writerow([k, len(x), f'{np.median(x):.1f}', f'{max(0.0, np.percentile(x, 99.9) - meta["floor_us"]):.1f}'] + [f'{100 * np.mean(x <= us):.1f}' for _, us in SLOTS])
print('wrote', os.path.join(a.out, 'f11_a3c_latency.pdf'), 'and a3c_summary.csv')
