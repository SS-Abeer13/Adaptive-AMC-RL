"""Define and test 'residual A2C matches FixedPU exactly' (M3, M4) at the seed x trace level.

Deterministic comparators are stored in seed row 0 only (other rows NaN);
each RL seed row is compared with that row, trace by trace.
Output: paper/analysis/out/m3_identity.txt
"""
import sys, os, numpy as np; sys.path.insert(0, os.path.dirname(__file__))
import v17mat
os.makedirs(os.path.join(os.path.dirname(__file__), 'out'), exist_ok=True)
lines = []
for tag in ['M3_gp_rtt8', 'M4_gp_rtt0']:
    s, o, c, f = v17mat.load(os.path.join(os.path.dirname(__file__), f'../../Optimized/v17/Dataset/results_v17_{tag}.mat'))
    lines.append(f'== {tag}')
    for rl in ['Deep A2C v17', 'Deep A2C v17 (best-on-val)', 'Deep A2C v17 (ensemble)']:
        for key in ['primary', 'cell_tp', 'jain', 'edge_tp']:
            ref = o[key]['FixedPU (Oracle)'][0]
            a = o[key][rl]
            rows = [i for i in range(a.shape[0]) if not np.all(np.isnan(a[i]))]
            d = np.abs(a[rows] - ref)
            ident_traces = int(np.sum(d == 0))
            lines.append(f'  {rl:28s} {key:8s} seeds={len(rows):2d} traces=500 '
                         f'identical_cells={ident_traces}/{d.size} max|diff|={d.max():.3e}')
txt = '\n'.join(lines); print(txt)
open(os.path.join(os.path.dirname(__file__), 'out', 'm3_identity.txt'), 'w').write(txt + '\n')
