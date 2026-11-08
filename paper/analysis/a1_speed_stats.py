"""A1: M1 primary (per-seed mean) vs the v17 Context table (10-trace calibration) by user speed class.
Source: Optimized/v17x/Dataset/a1_peruser.mat (stage_a1; per-user on-time counts, REPRO diff 0).
Margin = 100 * (on-time ratio RL / on-time ratio Context - 1), pooled over the user-traces of a class,
RL counts averaged over seeds.  95% CIs: bootstrap over the 500 traces, and hierarchical (seeds, then traces), B=20000, seed 20261108.
The hierarchical CI is the one reported (it carries seed variance, as Rule R2 requires).
Output: paper/analysis/out/a1_speed_stats.csv
"""
import os, csv, numpy as np, h5py
here = os.path.dirname(os.path.abspath(__file__))
h = h5py.File(os.path.join(here, '../../Optimized/v17x/Dataset/a1_peruser.mat'), 'r')
g = lambda k: np.asarray(h[k])           # MATLAB (eval,N) -> (N,eval); (seed,eval,N) -> (N,eval,seed)
OKA, RESA = g('okU_a2c'), g('resU_a2c')      # (N,eval,seed)
okA, resA = OKA.mean(axis=2), RESA.mean(axis=2)
okC, resC, sp = g('okU_ctxtab'), g('resU_ctxtab'), g('speeds')
rng = np.random.default_rng(20261108); B = 20000; T = sp.shape[1]
S = OKA.shape[2]
idx = [rng.integers(0, T, T) for _ in range(B)]
sidx = [rng.integers(0, S, S) for _ in range(B)]
rows = []
for lab, m in [('lo', sp < 10), ('mid', (sp >= 10) & (sp <= 20)), ('hi', sp > 20), ('all', np.ones_like(sp, bool))]:
    def marg(ti):
        mm = m[:, ti]
        return 100 * (((okA[:, ti] * mm).sum() / (resA[:, ti] * mm).sum()) / ((okC[:, ti] * mm).sum() / (resC[:, ti] * mm).sum()) - 1)
    def hmarg(ti, si):
        mm = m[:, ti]; a = OKA[:, ti][:, :, si].mean(axis=2); r = RESA[:, ti][:, :, si].mean(axis=2)
        return 100 * (((a * mm).sum() / (r * mm).sum()) / ((okC[:, ti] * mm).sum() / (resC[:, ti] * mm).sum()) - 1)
    pt = marg(np.arange(T)); bs = np.array([marg(ti) for ti in idx])
    hb = np.array([hmarg(ti, si) for ti, si in zip(idx, sidx)])
    rows.append(dict(speed_class=lab, share_user_traces=round(m.mean(), 4), margin_pct=round(pt, 3),
                     ci95_lo=round(np.percentile(bs, 2.5), 3), ci95_hi=round(np.percentile(bs, 97.5), 3),
                     hier_ci95_lo=round(np.percentile(hb, 2.5), 3), hier_ci95_hi=round(np.percentile(hb, 97.5), 3)))
    print(rows[-1])
with open(os.path.join(here, 'out', 'a1_speed_stats.csv'), 'w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
