import os, re, csv
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'paper', 'manuscript', 'figs')
RL, OL, CAL, GR, INK = '#2a78d6', '#eb6834', '#1baf7a', '#8a8f98', '#222222'
plt.rcParams.update({'font.family': 'serif', 'font.serif': ['Times New Roman', 'Liberation Serif', 'DejaVu Serif'],
    'font.size': 7.5, 'axes.labelsize': 7.5, 'xtick.labelsize': 7, 'ytick.labelsize': 7, 'legend.fontsize': 7,
    'axes.linewidth': 0.6, 'pdf.fonttype': 42, 'axes.spines.top': False, 'axes.spines.right': False,
    'axes.grid': True, 'grid.color': '#dddddd', 'grid.linewidth': 0.4, 'axes.axisbelow': True})
# role -> (colour, marker)
STYLE = {'Baseline': (GR, 's'), 'OLLA': (OL, 'o'), 'OLLA (tuned target)': (OL, 'D'), 'Multi-OLLA': (OL, '^'),
         'Fixed': (CAL, 's'), 'FixedPU (Oracle)': (CAL, 'P'), 'Context table': (CAL, 'D'),
         'Bandit (global)': (GR, 'v'), 'Bandit (delay class)': (GR, 'X'),
         'Deep A2C v17': (RL, 'o'), 'Deep A2C v17 (ensemble)': (RL, 'h')}
LABEL = {'Baseline': 'Baseline', 'OLLA': 'OLLA', 'OLLA (tuned target)': 'OLLA (tuned)', 'Multi-OLLA': 'Multi-OLLA',
         'Fixed': 'Fixed', 'FixedPU (Oracle)': 'FixedPU (class oracle)', 'Context table': 'Context table',
         'Bandit (global)': 'Bandit (global)', 'Bandit (delay class)': 'Bandit (delay class)',
         'Deep A2C v17': 'Residual A2C (primary)', 'Deep A2C v17 (ensemble)': 'Ensemble'}
def prim():
    out = {}
    for l in open(os.path.join(ROOT, 'Optimized/v17/Dataset/fill_summary_v17.txt'), encoding='utf-8'):
        if l.startswith('PRIM|'):
            p = l.rstrip('\n').split('|'); m, v = p[3].split('=')
            out[(p[1], p[2])] = (float(v), float(p[4].split('=')[1]))
    return out
def core():
    return {(r['case_tag'], r['scheme'], r['comparator']): r for r in csv.DictReader(open(os.path.join(ROOT, 'Optimized/v17/paper/table_core.csv')))}
def save(fig, name):
    fig.savefig(os.path.join(OUT, name + '.pdf'), bbox_inches='tight'); plt.close(fig)
