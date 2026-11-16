"""Descriptive tables derived from the frozen pre-submission outputs (not pre-registered as decision rules).

1. R3 action shares of the NR2 policies on the NR2 traces, as residual steps delta in {-1, 0, +1} around the
   Fixed base (-2), on scheduled new transmissions whose offset was not clipped (actions.csv: offset -3/-2/-1 =
   delta -1/0/+1; offset 0 = the base clipped at the CQI floor, excluded and counted). Pooled over the 10 seeds,
   with the min/max over seeds. Source: Optimized/v17x/Dataset/presub/actions.csv (stage r3_nr2diag).
2. Side metrics on the 500 NR2 traces from the exact-path audit (Optimized/v17x/Dataset/audit_exact_side_metrics.mat,
   commit c436b98: every on-time ratio reproduces the stored value exactly). The script asserts that the on-time
   ratios equal the means of the frozen per-trace files to 5e-5.
Outputs: paper/analysis/out/r3_delta_shares.csv, paper/analysis/out/presub_side_metrics.csv
Run: python3 paper/analysis/presub_derived.py
"""
import csv, os
import numpy as np
import scipy.io as sio

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
DS = os.path.join(ROOT, 'Optimized', 'v17x', 'Dataset'); OUT = os.path.join(HERE, 'out')

def speed_class(v): return 0 if v < 10 else (1 if v < 20 else 2)

def delta_shares():
    rows = list(csv.DictReader(open(os.path.join(DS, 'presub', 'actions.csv'), newline='')))
    n_all = len(rows)
    R = [dict(seed=int(r['seed']), busy=int(float(r['busy'])), slack=float(r['slack_frac']), pk=int(float(r['has_packet'])),
              sp=float(r['speed_mps']), burst=int(float(r['burst'])), d=int(float(r['action'])) + 2) for r in rows if int(float(r['action'])) != 0]
    assert all(r['d'] in (-1, 0, 1) for r in R)
    bins = [('all', lambda r: True), ('busy0', lambda r: r['busy'] == 0), ('busy1', lambda r: r['busy'] >= 1),
            ('slacklo', lambda r: r['pk'] == 1 and r['slack'] <= 0.6), ('slackhi', lambda r: r['pk'] == 1 and r['slack'] > 0.6),
            ('slow', lambda r: speed_class(r['sp']) == 0), ('mid', lambda r: speed_class(r['sp']) == 1), ('fast', lambda r: speed_class(r['sp']) == 2),
            ('burst', lambda r: r['burst'] == 1), ('calm', lambda r: r['burst'] == 0)]
    seeds = sorted({r['seed'] for r in R}); out = []
    for name, f in bins:
        sub = [r for r in R if f(r)]
        row = dict(bin=name, n=len(sub), share_pct=100 * len(sub) / len(R), n_all=n_all, n_clipped=n_all - len(R))
        for d, lab in [(-1, 'minus'), (0, 'zero'), (1, 'plus')]:
            row[f'pct_{lab}'] = 100 * np.mean([r['d'] == d for r in sub])
            per = [100 * np.mean([r['d'] == d for r in sub if r['seed'] == s]) for s in seeds if any(r['seed'] == s for r in sub)]
            row[f'pct_{lab}_min'] = min(per); row[f'pct_{lab}_max'] = max(per)
        out.append(row)
    return out

def pertrace_means():
    m = {}
    for f in [os.path.join(DS, 'presub', 'pertrace.csv'), os.path.join(DS, 'presub', 'r1b', 'pertrace_r1b.csv')]:
        acc = {}
        for r in csv.DictReader(open(f, newline='')):
            if r['trace_set'] == 'NR2' and not (r['scheme'] == 'NR2' and int(r['seed']) > 10):   # NR2: the 10 frozen seeds (R5 seeds 11-20 excluded)
                acc.setdefault(r['scheme'], []).append(float(r['value']))
        m.update({k: float(np.mean(v)) for k, v in acc.items()})
    return m

def side_metrics(means):
    s = sio.loadmat(os.path.join(DS, 'audit_exact_side_metrics.mat'), squeeze_me=True, struct_as_record=False)['res']
    key = {'NR2': 'NR2', 'Context_joint': 'ctxj500', 'GBT_res': 'GBT-res', 'GBT_full': 'GBT-full', 'GBT_res_ACK': 'GBT-res-ACK', 'GBT_full_ACK': 'GBT-full-ACK'}
    out = []
    for f, k in key.items():
        x = getattr(s, f)
        assert abs(float(x.ontime) - means[k]) < 5e-5, (k, float(x.ontime), means[k])
        out.append(dict(scheme=k, ontime=float(x.ontime), goodput_mbps=float(x.goodput), bler1=float(x.bler1), jain=float(x.jain),
                        edge5=float(x.edge5), edge10=float(x.edge10), bottom_decile_mean=float(x.bot_dec)))
    for k in ['Rule', 'Rule-cal', 'fixed500', 'ctx500']:
        out.append(dict(scheme=k, ontime=means[k]))
    return out

def write(path, rows):
    keys = list(dict.fromkeys(k for r in rows for k in r))
    with open(path, 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=keys); w.writeheader()
        for r in rows: w.writerow({k: (f'{v:.6g}' if isinstance(v, float) else v) for k, v in r.items()})

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    d = delta_shares(); write(os.path.join(OUT, 'r3_delta_shares.csv'), d)
    m = pertrace_means(); s = side_metrics(m); write(os.path.join(OUT, 'presub_side_metrics.csv'), s)
    for r in d: print(f"{r['bin']:8s} n={r['n']:7d} -1 {r['pct_minus']:5.2f}  0 {r['pct_zero']:5.2f}  +1 {r['pct_plus']:5.2f}")
    for r in s: print(r)
