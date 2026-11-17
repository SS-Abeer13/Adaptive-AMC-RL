"""HR1 (Plan 4): learnable myopic headroom over calibrated tables. FROZEN with
paper/proposals/HR1_headroom_prereg.md (Amendment 7). Do not edit after the freeze.

Input  : <logdir>/hr_log_<case>_<scheme>.mat (MATLAB v7.3; L_all = decisions x 65, COLS = names),
         written by Optimized/v17x/stage_hr1.m (full mode) on the evaluation traces.
Output : paper/analysis/out/hr_values.csv   (every run x table x action set x estimator)
         paper/analysis/out/hr_predictions.csv (P1-P4 with intervals and verdicts)
         paper/analysis/out/hr_report.txt
Run    : python3 paper/analysis/hr_stats.py [--logdir DIR] [--out DIR] [--B 20000]

Definitions (prereg section 3):
  candidate offsets a in {-4,...,+2}; q_i(a) = psucc_i(a) * ubits_i(a)   (expected useful bits of the first transmission)
  rule (a): offsets that map to the same MCS in a decision are one action (their q is asserted identical)
  rule (b): residual-restricted set = distinct MCS among {b_i-1, b_i, b_i+1} (b_i = base_rule_offset, clipped to [-4,+2]);
            table headroom uses all distinct MCS among {-4,...,+2}
  rule (c): full-buffer case: ubits = tbs (asserted)
  V_genie  = mean_i max_a q_i(a)
  V_table  = mean_i q_i(a_T(k_i)), a_T(k) = argmax_a of the cross-fitted cell mean of q(a) in cell k of the table's partition
  V_learn  = mean_i q_i(a_hat(x_i)), a_hat = argmax_a of the cross-fitted prediction m_a(x), x = obs_1..obs_19
  headroom = 100 (V - V_table) / V_table   [%]; learnable estimate = the larger of two pre-specified GBT models
"""
import argparse, csv, os, re
import numpy as np
import h5py
from sklearn.ensemble import HistGradientBoostingRegressor

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
OFFS = np.arange(-4, 3)                      # -4..+2
FEAT = [f'obs_{k}' for k in range(1, 20)]
PART = {'Fixed': [], 'FixedPU': ['delay_class', 'speed_class'], 'Context table': ['slack_bin'],
        'Combined table': ['slack_bin', 'delay_class', 'speed_class', 'busy_harq_bin']}
MODELS = {'gbt_a': dict(max_iter=300, learning_rate=0.05, max_leaf_nodes=31, min_samples_leaf=40, early_stopping=False, random_state=0),
          'gbt_b': dict(max_iter=600, learning_rate=0.03, max_leaf_nodes=63, min_samples_leaf=20, early_stopping=False, random_state=0)}
RUNS = {('M1_dl_rtt8', 'Fixed'): 'Fixed', ('M1_dl_rtt8', 'Context table'): 'Context table',
        ('M1_dl_rtt8', 'Context-joint-500'): 'Combined table', ('M1_dl_rtt8', 'M1'): None, ('M1_dl_rtt8', 'NR2'): None,
        ('M3_gp_rtt8', 'Fixed'): 'Fixed', ('M3_gp_rtt8', 'Context table'): 'Context table',
        ('M3_gp_rtt8', 'Context-joint-500'): 'Combined table', ('M3_gp_rtt8', 'A2C_case'): None}
FULLBUF = {'M3_gp_rtt8'}
K_FOLD, B_DEFAULT, RNG_SEED = 5, 20000, 20261111

def load(path):
    f = h5py.File(path, 'r')
    cols = [''.join(chr(c) for c in np.array(f[r]).flatten()) for r in np.array(f['COLS']).flatten()]
    L = np.array(f['L_all'])
    if L.shape[0] == len(cols) and L.shape[1] != len(cols): L = L.T
    assert L.shape[1] == len(cols) == 65, (path, L.shape, len(cols))
    return {c: L[:, i] for i, c in enumerate(cols)}

def prepare(D, case):
    n = len(D['t'])
    mcs = np.stack([D[f'mcs_{s}'] for s in ['m4', 'm3', 'm2', 'm1', '0', 'p1', 'p2']], 1)
    tbs = np.stack([D[f'tbs_{s}'] for s in ['m4', 'm3', 'm2', 'm1', '0', 'p1', 'p2']], 1)
    ub = np.stack([D[f'ubits_{s}'] for s in ['m4', 'm3', 'm2', 'm1', '0', 'p1', 'p2']], 1)
    ps = np.stack([D[f'psucc_{s}'] for s in ['m4', 'm3', 'm2', 'm1', '0', 'p1', 'p2']], 1)
    if case in FULLBUF:                                            # rule (c)
        assert np.array_equal(ub, tbs), 'full-buffer case: ubits must equal tbs'
    q = ps * ub
    # rule (a): identical MCS within a decision -> identical q (one action)
    for i in range(7):
        for j in range(i + 1, 7):
            same = mcs[:, i] == mcs[:, j]
            assert np.allclose(q[same, i], q[same, j]), 'offsets with the same MCS must have the same q'
    first = np.ones((n, 7), bool)                                  # first offset of each distinct MCS represents the action
    for j in range(1, 7):
        first[:, j] = ~np.any(mcs[:, :j] == mcs[:, [j]], axis=1)
    b = np.clip(np.rint(D['base_rule_offset']).astype(int), -4, 2)
    in_res = np.abs(OFFS[None, :] - b[:, None]) <= 1               # rule (b)
    # an offset belongs to the residual set if any offset in b-1..b+1 has its MCS
    res_mcs = np.where(in_res, mcs, np.nan)
    res_ok = np.array([[mcs[r, j] in set(res_mcs[r][~np.isnan(res_mcs[r])]) for j in range(7)] for r in range(n)])
    tr = D['trace_id'].astype(int); ut = np.unique(tr)
    fold = (np.searchsorted(ut, tr)) % K_FOLD
    X = np.stack([D[c] for c in FEAT], 1)
    return dict(n=n, mcs=mcs, q=q, first=first, act_full=first, act_res=first & res_ok, tr=tr, fold=fold, X=X, D=D)

def pick(score, allowed, mcs):
    """argmax over allowed actions; ties -> lower MCS (conservative)."""
    s = np.where(allowed, score, -np.inf)
    best = s.max(1, keepdims=True)
    cand = np.isclose(s, best) & allowed
    m = np.where(cand, mcs, np.inf)
    return np.argmin(m, 1)

def table_choice(P, cols):
    """cross-fitted best offset per cell (all distinct MCS in -4..+2)."""
    key = np.zeros(P['n'], int) if not cols else np.unique(np.stack([P['D'][c] for c in cols], 1), axis=0, return_inverse=True)[1].ravel()
    ch = np.zeros(P['n'], int)
    for k in range(K_FOLD):
        tr_, te = P['fold'] != k, P['fold'] == k
        glob = P['q'][tr_].mean(0)
        for cell in np.unique(key[te]):
            m = tr_ & (key == cell)
            mean = P['q'][m].mean(0) if m.any() else glob
            idx = te & (key == cell)
            ch[idx] = pick(np.broadcast_to(mean, (idx.sum(), 7)), P['act_full'][idx], P['mcs'][idx])
    return ch

def predict(P, params):
    pred = np.zeros((P['n'], 7))
    for k in range(K_FOLD):
        tr_, te = P['fold'] != k, P['fold'] == k
        for j in range(7):
            mdl = HistGradientBoostingRegressor(**params).fit(P['X'][tr_], P['q'][tr_, j])
            pred[te, j] = mdl.predict(P['X'][te])
    return pred

def learn_choice(P, pred, allowed):
    # rule (a): an action's prediction = mean over the offsets that share its MCS
    pa = np.array(pred)
    for j in range(7):
        same = P['mcs'] == P['mcs'][:, [j]]
        pa[:, j] = (pred * same).sum(1) / same.sum(1)
    return pick(pa, allowed, P['mcs'])

def per_trace(P, v):
    ut, inv = np.unique(P['tr'], return_inverse=True)
    return np.bincount(inv, v, len(ut)), np.bincount(inv, None, len(ut))

def boot_ratio(P, num_v, den_v, B, rng, idx=None):
    sn, c = per_trace(P, num_v); sd, _ = per_trace(P, den_v)
    T = len(c); idx = rng.integers(0, T, (B, T)) if idx is None else idx
    r = 100 * (sn[idx].sum(1) / sd[idx].sum(1) - 1)
    return 100 * (sn.sum() / sd.sum() - 1), np.percentile(r, [2.5, 97.5]), idx, r

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--logdir', default=os.path.join(ROOT, 'Optimized', 'v17x', 'Dataset', 'hr', 'full'))
    ap.add_argument('--out', default=os.path.join(HERE, 'out'))
    ap.add_argument('--B', type=int, default=B_DEFAULT)
    a = ap.parse_args(); os.makedirs(a.out, exist_ok=True)
    rng = np.random.default_rng(RNG_SEED); rows, store, log = [], {}, []
    found = {}
    for fn in sorted(os.listdir(a.logdir)):
        if fn.startswith('hr_log_') and fn.endswith('.mat'):
            f = h5py.File(os.path.join(a.logdir, fn), 'r')
            txt = lambda k: ''.join(chr(c) for c in np.array(f[k]).flatten())
            found[(txt('tag'), txt('sch_saved_name'))] = os.path.join(a.logdir, fn)
    missing = [k for k in RUNS if k not in found]
    if missing: raise SystemExit(f'missing logs for {missing}; found {sorted(found)}')
    for (case, scheme), own in RUNS.items():
        path = found[(case, scheme)]
        P = prepare(load(path), case)
        qi = lambda ch: P['q'][np.arange(P['n']), ch]
        vt = {T: qi(table_choice(P, cols)) for T, cols in PART.items()}
        vg = P['q'].max(1)
        vl = {}
        preds = {m: predict(P, prm) for m, prm in MODELS.items()}       # one cross-fitted fit per model, shared by both action sets
        for setname, allowed in [('full', P['act_full']), ('residual', P['act_res'])]:
            for mname in MODELS:
                vl[(setname, mname)] = qi(learn_choice(P, preds[mname], allowed))
        B = a.B; idx = rng.integers(0, len(np.unique(P['tr'])), (B, len(np.unique(P['tr']))))
        for T in PART:
            g, gci, _, _ = boot_ratio(P, vg, vt[T], B, rng, idx)
            rows.append(dict(case=case, run=scheme, table=T, action_set='genie (true SINR)', estimator='genie', headroom_pct=g, ci95_lo=gci[0], ci95_hi=gci[1], n_decisions=P['n']))
            for setname in ['full', 'residual']:
                est = {m: boot_ratio(P, vl[(setname, m)], vt[T], B, rng, idx) for m in MODELS}
                best = max(est, key=lambda m: est[m][0])
                for m in MODELS:
                    rows.append(dict(case=case, run=scheme, table=T, action_set=setname, estimator=m + (' (primary)' if m == best else ''),
                                     headroom_pct=est[m][0], ci95_lo=est[m][1][0], ci95_hi=est[m][1][1], n_decisions=P['n']))
                store[(case, scheme, T, setname)] = dict(P=P, num=vl[(setname, best)], den=vt[T], idx=idx, model=best)
        log.append(f'{case} | {scheme}: {P["n"]} decisions, {len(np.unique(P["tr"]))} traces')
    with open(os.path.join(a.out, 'hr_values.csv'), 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0])); w.writeheader()
        for r in rows: w.writerow({k: (f'{v:.3f}' if isinstance(v, float) else v) for k, v in r.items()})

    # ---------------- predictions (prereg section 5)
    pr = []
    def H(case, run, T, s): s_ = store[(case, run, T, s)]; return boot_ratio(s_['P'], s_['num'], s_['den'], a.B, rng, s_['idx'])
    # P1 goodput collapse: M3, A2C_case run, residual set, over Fixed: upper 95 % bound < 0.5 %
    h, ci, _, _ = H('M3_gp_rtt8', 'A2C_case', 'Fixed', 'residual')
    pr.append(dict(id='P1', statement='M3 residual-restricted learnable headroom over Fixed (A2C_case run) has 95 % upper bound < 0.5 %', estimate=h, lo=ci[0], hi=ci[1], verdict='supported' if ci[1] < 0.5 else 'not supported'))
    # P2 room for the recommended configuration: M1, NR2 run, residual set, over the combined table: lower bound > 0
    h, ci, _, _ = H('M1_dl_rtt8', 'NR2', 'Combined table', 'residual')
    pr.append(dict(id='P2', statement='M1 residual-restricted learnable headroom over the combined table around the non-oracle base (NR2 run) has 95 % lower bound > 0', estimate=h, lo=ci[0], hi=ci[1], verdict='supported' if ci[0] > 0 else 'not supported'))
    # P3 non-oracle vs oracle base: (NR2 run) - (M1 run), residual set, over the combined table; same traces, joint resampling
    s1, s2 = store[('M1_dl_rtt8', 'NR2', 'Combined table', 'residual')], store[('M1_dl_rtt8', 'M1', 'Combined table', 'residual')]
    a1 = boot_ratio(s1['P'], s1['num'], s1['den'], a.B, rng, s1['idx']); a2 = boot_ratio(s2['P'], s2['num'], s2['den'], a.B, rng, s1['idx'])
    assert np.array_equal(np.unique(s1['P']['tr']), np.unique(s2['P']['tr'])), 'NR2 and M1 runs must cover the same traces'
    d = a1[3] - a2[3]; dci = np.percentile(d, [2.5, 97.5])
    pr.append(dict(id='P3', statement='M1: residual-restricted headroom over the combined table is larger around the non-oracle base (NR2 run) than around the oracle base (M1 run): 95 % lower bound of the difference > 0', estimate=a1[0] - a2[0], lo=dci[0], hi=dci[1], verdict='supported' if dci[0] > 0 else 'not supported'))
    # P4 slow users: M1, Context-table run, full set, over the Context table: (speed classes 2-3) - (speed class 1) > 0
    s = store[('M1_dl_rtt8', 'Context table', 'Context table', 'full')]; P = s['P']; slow = P['D']['speed_class'] == 1
    ut = np.unique(P['tr']); inv = np.searchsorted(ut, P['tr'])
    def grp(mask):
        sn = np.bincount(inv, s['num'] * mask, len(ut)); sd = np.bincount(inv, s['den'] * mask, len(ut)); return sn, sd
    (fn, fd), (sn_, sd_) = grp(~slow), grp(slow)
    r = lambda n_, d_: 100 * (n_.sum(-1) / d_.sum(-1) - 1)
    est = r(fn, fd) - r(sn_, sd_); bd = r(fn[s['idx']], fd[s['idx']]) - r(sn_[s['idx']], sd_[s['idx']]); bci = np.percentile(bd, [2.5, 97.5])
    pr.append(dict(id='P4', statement='M1: learnable headroom over the Context table (Context-table run) is larger for users in speed classes 2-3 than in speed class 1 (< 10 m/s): 95 % lower bound of the difference > 0', estimate=est, lo=bci[0], hi=bci[1], verdict='supported' if bci[0] > 0 else 'not supported'))
    with open(os.path.join(a.out, 'hr_predictions.csv'), 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(pr[0])); w.writeheader()
        for p in pr: w.writerow({k: (f'{v:.3f}' if isinstance(v, float) else v) for k, v in p.items()})
    txt = [f'HR1 headroom analysis (B={a.B}, rng {RNG_SEED}, {K_FOLD}-fold cross-fitting by trace)'] + log + [f"{p['id']}: {p['verdict']} | {p['estimate']:.3f} [{p['lo']:.3f}, {p['hi']:.3f}] | {p['statement']}" for p in pr]
    open(os.path.join(a.out, 'hr_report.txt'), 'w').write('\n'.join(txt) + '\n'); print('\n'.join(txt))

if __name__ == '__main__':
    main()
