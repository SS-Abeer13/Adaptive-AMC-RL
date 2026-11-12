"""Fig. 12: HR1 learnable one-step headroom against the observed margin, per policy and comparator.

Headroom: paper/analysis/out/hr_values.csv (frozen HR1 run), residual set (base offset +-1),
run = the learned policy's own decisions, both pre-specified estimators (gbt_a, gbt_b), 95 % CI.
Observed margin: paired trace-level margin of the learned policy with its 90 % CI, from
  M1  : Optimized/v17x/Dataset/table_cal500.csv  (comparators re-calibrated on 500 traces)
  NR2 : paper/analysis/out/nr2_stats.csv          (same comparators, fresh traces and seeds)
  M3  : Optimized/v17/paper/table_core.csv        (original comparators; no combined table in M3)
The two quantities are in different units (expected useful bits of one first transmission
versus on-time ratio or goodput over a trace), so the figure compares them only qualitatively.
"""
import csv, os
import numpy as np
from common import plt, save, ROOT, RL, INK, GR

def rd(*p): return list(csv.DictReader(open(os.path.join(ROOT, *p), newline='')))
HV = rd('paper', 'analysis', 'out', 'hr_values.csv')
def hr(case, run, table, est):
    for r in HV:
        if (r['case'], r['run'], r['table'], r['action_set']) == (case, run, table, 'residual') and r['estimator'].startswith(est):
            return float(r['headroom_pct']), float(r['ci95_lo']), float(r['ci95_hi'])
    raise KeyError((case, run, table, est))
def obs(rows, key, name):
    for r in rows:
        if r[key] == name:
            return float(r['margin_pct'] if 'margin_pct' in r else r['pct_margin']), float(r['ci90_lo']), float(r['ci90_hi'])
    raise KeyError(name)
C5 = rd('Optimized', 'v17x', 'Dataset', 'table_cal500.csv')
N2 = rd('paper', 'analysis', 'out', 'nr2_stats.csv')
TC = [r for r in rd('Optimized', 'v17', 'paper', 'table_core.csv') if r['case_tag'] == 'M3_gp_rtt8' and r['scheme'] == 'Deep A2C v17']
TABLES = [('Fixed', 'Fixed'), ('FixedPU', 'FixedPU'), ('Context table', 'Context'), ('Combined table', 'Combined')]
PANELS = [('M1 policy (M1)', 'M1_dl_rtt8', 'M1', lambda t: obs(C5, 'comparator', {'Fixed': 'Fixed-500', 'FixedPU': 'FixedPU-500', 'Context table': 'Context-500', 'Combined table': 'Context-joint-500'}[t])),
          ('NR2 policy (M1)', 'M1_dl_rtt8', 'NR2', lambda t: obs(N2, 'comparator', {'Fixed': 'Fixed-500', 'FixedPU': 'FixedPU-500', 'Context table': 'Context-500', 'Combined table': 'Context-joint-500'}[t])),
          ('Goodput policy (M3)', 'M3_gp_rtt8', 'A2C_case', lambda t: None if t == 'Combined table' else obs(TC, 'comparator', {'Fixed': 'Fixed', 'FixedPU': 'FixedPU (Oracle)', 'Context table': 'Context table'}[t]))]

fig, axs = plt.subplots(1, 3, figsize=(7.16, 1.95), sharey=True)
y = np.arange(len(TABLES))[::-1]
for ax, (title, case, run, ob) in zip(axs, PANELS):
    ax.axvline(0, color=GR, lw=0.6, zorder=1)
    for yi, (t, lab) in zip(y, TABLES):
        for dy, est, face in [(0.22, 'gbt_a', RL), (0.0, 'gbt_b', 'white')]:
            v, lo, hi = hr(case, run, t, est)
            ax.plot([lo, hi], [yi + dy] * 2, color=RL, lw=1.0, zorder=2)
            ax.plot(v, yi + dy, 'o', ms=4.2, mfc=face, mec=RL, mew=0.9, zorder=3)
        o = ob(t)
        if o is None:
            ax.text(0.03, yi - 0.24, 'margin not evaluated', fontsize=6.5, color=GR, va='center', transform=ax.get_yaxis_transform())
        else:
            ax.plot([o[1], o[2]], [yi - 0.24] * 2, color=INK, lw=1.0, zorder=2)
            ax.plot(o[0], yi - 0.24, 'X', ms=4.8, mfc=INK, mec=INK, zorder=3)
    ax.set_title(title, pad=3)
    ax.set_xlabel('%')
    ax.set_yticks(y); ax.set_yticklabels([l for _, l in TABLES])
    ax.set_ylim(-0.6, len(TABLES) - 0.4)
    ax.grid(axis='y', visible=False)
h = [plt.Line2D([], [], marker='o', ls='-', lw=1.0, color=RL, mfc=RL, ms=4.2, label='Headroom, gbt_a (95 % CI)'),
     plt.Line2D([], [], marker='o', ls='-', lw=1.0, color=RL, mfc='white', mec=RL, ms=4.2, label='Headroom, gbt_b (95 % CI)'),
     plt.Line2D([], [], marker='X', ls='-', lw=1.0, color=INK, ms=4.8, label='Observed margin (90 % CI)')]
fig.legend(handles=h, loc='lower center', ncol=3, frameon=False, bbox_to_anchor=(0.5, -0.02))
fig.subplots_adjust(bottom=0.30, wspace=0.12)
save(fig, 'f12_hr1_headroom')
