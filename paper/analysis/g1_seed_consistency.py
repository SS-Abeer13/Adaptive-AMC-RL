"""G1 follow-up (G1_SPEC section 5): is the delta pattern consistent across the 10 seeds?
Input: Optimized/v17/paper/g1/g1_log_M1_dl_rtt8.mat (raw decision log; L = [seed, trace, user, act_idx,
slack, is_retx, busy, t, delay, speed, burst, ref, b_i, sent, rem]).  Scheduled new transmissions only.
For each bin: pooled share of delta = +1 / 0 / -1, share of decisions, and the min/max over seeds of the
delta = +1 share.  Output: paper/analysis/out/g1_seed_consistency.csv
"""
import os, csv, numpy as np, h5py
here = os.path.dirname(os.path.abspath(__file__))
L = h5py.File(os.path.join(here, '../../Optimized/v17/paper/g1/g1_log_M1_dl_rtt8.mat'), 'r')['L'][()].T
L = L[L[:, 5] == 0]                     # new transmissions
seed, act, slack, busy, burst, bi = L[:, 0], L[:, 3], L[:, 4], L[:, 6], L[:, 10], L[:, 12]
frac = slack / 10.0
bins = [('all', np.ones(len(L), bool)), ('busy_0', busy == 0), ('busy_1_2', (busy >= 1) & (busy <= 2)), ('busy_ge3', busy >= 3),
        ('slack_le_0.3', frac <= 0.3), ('slack_0.3_0.6', (frac > 0.3) & (frac <= 0.6)), ('slack_gt_0.6', frac > 0.6),
        ('calm', burst == 0), ('burst', burst == 1), ('base_m3', bi == -3), ('base_m2', bi == -2)]
rows = []
for name, m in bins:
    per = [100 * np.mean(act[m & (seed == s)] == 3) for s in range(1, 11) if np.any(m & (seed == s))]
    rows.append(dict(bin=name, n=int(m.sum()), share_of_decisions=round(100 * m.mean(), 2),
                     pct_plus1=round(100 * np.mean(act[m] == 3), 2), pct_zero=round(100 * np.mean(act[m] == 2), 2),
                     pct_minus1=round(100 * np.mean(act[m] == 1), 2),
                     plus1_seed_min=round(min(per), 2), plus1_seed_max=round(max(per), 2)))
    print(rows[-1])
with open(os.path.join(here, 'out', 'g1_seed_consistency.csv'), 'w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
# within-seed contrasts: does the +1 share rise with busy processes / tight slack / bursts in every seed?
def share(m, s): mm = m & (seed == s); return 100 * np.mean(act[mm] == 3)
B = dict(bins)
con = []
for name, a, b in [('busy_1_2_vs_busy_0', 'busy_1_2', 'busy_0'), ('slack_le_0.6_vs_gt_0.6', None, 'slack_gt_0.6'), ('burst_vs_calm', 'burst', 'calm')]:
    ma = (frac <= 0.6) if a is None else B[a]
    d = [share(ma, s) - share(B[b], s) for s in range(1, 11)]
    con.append(dict(contrast=name, seeds_positive=sum(x > 0 for x in d), diff_min_pp=round(min(d), 2), diff_max_pp=round(max(d), 2),
                    pooled_a=round(100 * np.mean(act[ma] == 3), 2), pooled_b=round(100 * np.mean(act[B[b]] == 3), 2),
                    share_a=round(100 * ma.mean(), 2)))
    print(con[-1])
with open(os.path.join(here, 'out', 'g1_seed_contrasts.csv'), 'w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=list(con[0].keys())); w.writeheader(); w.writerows(con)
