import os, re, csv
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'paper', 'manuscript', 'figs')
RL, OL, CAL, GR, INK = '#2a78d6', '#eb6834', '#1baf7a', '#8a8f98', '#222222'
plt.rcParams.update({'font.family': 'serif', 'font.serif': ['Times New Roman', 'Liberation Serif', 'DejaVu Serif'],
    'font.size': 8, 'axes.labelsize': 8, 'axes.titlesize': 8, 'xtick.labelsize': 7.5, 'ytick.labelsize': 7.5, 'legend.fontsize': 7.5,
    'axes.linewidth': 0.6, 'pdf.fonttype': 42, 'axes.spines.top': False, 'axes.spines.right': False,
    'axes.grid': True, 'grid.color': '#dddddd', 'grid.linewidth': 0.4, 'axes.axisbelow': True, 'mathtext.fontset': 'stix'})
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
# IEEE two-column: column 3.5 in, text width 7.16 in. Figures are exported at exactly
# these widths so that LaTeX includes them at scale 1 and font sizes print as set
# (minimum 7 pt). The figure canvas is adjusted until the tight bounding box has
# the target width; the height is kept as designed.
COL_IN, FULL_IN, PAD_IN = 3.5, 7.16, 0.02
def save(fig, name):
    w0, h0 = fig.get_size_inches()
    target = FULL_IN if w0 > 5 else COL_IN
    for _ in range(6):
        fig.canvas.draw()
        bb = fig.get_tightbbox(fig.canvas.get_renderer())
        tw, th = bb.width + 2 * PAD_IN, bb.height + 2 * PAD_IN
        w, h = fig.get_size_inches()
        if abs(tw - target) < 0.005 and abs(th - h0) < 0.01:
            break
        fig.set_size_inches(w + (target - tw), h + (h0 - th))
    fig.savefig(os.path.join(OUT, name + '.pdf'), bbox_inches='tight', pad_inches=PAD_IN)
    fig.savefig(os.path.join(OUT, name + '-1.png'), bbox_inches='tight', pad_inches=PAD_IN, dpi=200)
    plt.close(fig)
