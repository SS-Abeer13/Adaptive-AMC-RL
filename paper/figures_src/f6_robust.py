from common import *
import numpy as np
# (a) G6: M1 primary vs the re-calibrated comparators: trace-level 90 % CI (thick) and hierarchical seed x trace 95 % CI (thin)
D = os.path.join(ROOT, 'Optimized/v17x/Dataset'); A = os.path.join(ROOT, 'paper/analysis/out')
tc = {r['comparator']: r for r in csv.DictReader(open(os.path.join(D, 'table_cal500.csv')))}
sd = {r['comparator']: r for r in csv.DictReader(open(os.path.join(A, 'g6_seed_stats.csv')))}
order = ['Context-joint-500', 'Context-500', 'Fixed-500', 'FixedPU-500']
lab = {'Context-joint-500': 'Combined table', 'Context-500': 'Context table\n(re-calibrated)', 'Fixed-500': 'Fixed\n(re-calibrated)', 'FixedPU-500': 'FixedPU, class oracle\n(re-calibrated)'}
fig, axs = plt.subplots(1, 2, figsize=(7.16, 2.35), gridspec_kw={'width_ratios': [1, 1.15], 'wspace': 0.9})
ax = axs[0]
for j, c in enumerate(order):
    m, lo, hi = float(tc[c]['margin_pct']), float(tc[c]['ci90_lo']), float(tc[c]['ci90_hi'])
    hl, hh = float(sd[c]['hier_boot_ci95_lo']), float(sd[c]['hier_boot_ci95_hi'])
    col = OL if hl <= 0 else RL
    ax.plot([hl, hh], [j + 0.16, j + 0.16], color=col, lw=0.9, alpha=0.75)
    ax.plot([lo, hi], [j - 0.06, j - 0.06], color=col, lw=3.2, solid_capstyle='butt')
    ax.plot(m, j - 0.06, 'o', color='white', mec=col, ms=4, mew=1.1)
ax.axvline(0, color=INK, lw=0.7)
ax.set_yticks(range(len(order))); ax.set_yticklabels([lab[c] for c in order]); ax.invert_yaxis(); ax.grid(axis='y', visible=False)
ax.set_xlabel('Margin of residual A2C (M1) over the comparator (%)')
ax.plot([], [], color=INK, lw=3.2, label='trace level, 90 % CI'); ax.plot([], [], color=INK, lw=0.9, label='seed$\\times$trace, 95 % CI')
ax.set_xlim(-0.6, 5.2); ax.legend(loc='upper right', frameon=False, fontsize=7)
ax.set_title('(a) Re-calibrated comparators', fontsize=8, loc='left')
# (b) other checks: W1 (warm-up) and NR1 (non-oracle base), trace level 90 % CI
tw = {r['comparator']: r for r in csv.DictReader(open(os.path.join(D, 'table_warmup.csv')))}
tn = {r['comparator']: r for r in csv.DictReader(open(os.path.join(D, 'table_nr1.csv')))}
ng = {r['comparator']: r for r in csv.DictReader(open(os.path.join(A, 'nr1_g6_compare.csv')))}
rows = [('Cold OLLA: vs Context table', tw['Context table']['cold_margin_pct'], tw['Context table']['cold_ci90_lo'], tw['Context table']['cold_ci90_hi'], RL),
        ('Warm-up: vs Context table', tw['Context table']['warm_margin_pct'], tw['Context table']['warm_ci90_lo'], tw['Context table']['warm_ci90_hi'], RL),
        ('Warm-up: vs Fixed', tw['Fixed']['warm_margin_pct'], tw['Fixed']['warm_ci90_lo'], tw['Fixed']['warm_ci90_hi'], RL),
        ('Non-oracle base: vs Context table', tn['Context table']['nr1_margin_pct'], tn['Context table']['ci90_lo'], tn['Context table']['ci90_hi'], CAL),
        ('Non-oracle base: vs combined table*', ng['Context-joint-500']['margin_pct'], ng['Context-joint-500']['ci90_lo'], ng['Context-joint-500']['ci90_hi'], CAL),
        ('Non-oracle base: vs M1 policy', tn['M1 (Oracle-base primary)']['nr1_margin_pct'], tn['M1 (Oracle-base primary)']['ci90_lo'], tn['M1 (Oracle-base primary)']['ci90_hi'], CAL)]
ax = axs[1]
for j, (l, m, lo, hi, col) in enumerate(rows):
    m, lo, hi = float(m), float(lo), float(hi)
    ax.plot([lo, hi], [j, j], color=col, lw=3.2, solid_capstyle='butt'); ax.plot(m, j, 'o', color='white', mec=col, ms=4, mew=1.1)
ax.axvline(0, color=INK, lw=0.7)
ax.set_yticks(range(len(rows))); ax.set_yticklabels([r[0] for r in rows]); ax.invert_yaxis(); ax.grid(axis='y', visible=False)
ax.set_xlabel('Margin (%), trace level, 90 % CI')
ax.set_title('(b) Warm-up check and non-oracle base', fontsize=8, loc='left')
ax.text(1.0, -0.30, '* secondary, descriptive', transform=ax.transAxes, ha='right', fontsize=7, color=GR)
save(fig, 'f6_robust')
