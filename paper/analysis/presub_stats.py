"""Pre-submission analyses R1-R5 (FROZEN with paper/proposals/R_presub_prereg.md, Amendment 8).

Inputs (written by the MATLAB stages r3_nr2diag, r1_gbt, r2_rule, r5_seeds), in Optimized/v17x/Dataset/presub/:
  pertrace.csv  trace_set, scheme, seed, trace, value      (seed = 0 for deterministic schemes)
  peruser.csv   scheme, seed, trace, user, ok, res, speed_mps   (NR2 traces; R3)
  actions.csv   seed, trace, busy, slack_frac, has_packet, speed_mps, burst, action   (NR2 traces; R3)
Outputs (paper/analysis/out/): presub_R1R2.csv, presub_R1R2_secondary.csv, presub_R3_speed.csv, presub_R3_warm.csv,
  presub_R3_fair.csv, presub_R3_actions.csv, presub_R4.csv, presub_R5.csv, presub_verdicts.txt, presub_pending_values.csv
Run : python3 paper/analysis/presub_stats.py [--indir DIR] [--out DIR]
Test: python3 paper/analysis/presub_stats.py --selftest     (synthetic data only)
The R1 statistics, Holm and the hierarchical seed-level bootstrap are the frozen functions of nr2_stats.py.
"""
import argparse, csv, os, sys, itertools
import numpy as np
from scipy import stats

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
from nr2_stats import r1, holm, seed_level, FAMILY as NR2_FAMILY   # frozen (NR2_confirmatory_prereg.md)

XS = ['GBT-res', 'GBT-full', 'Rule', 'Rule-cal']
SEC_CMP = ['ctxj500', 'fixed500', 'ctx500']
G_FAMILY = ['Baseline', 'OLLA', 'OLLA (tuned target)', 'Multi-OLLA', 'Fixed', 'FixedPU (Oracle)', 'Context table', 'Bandit (global)', 'Bandit (delay class)']
G_SINGLE = ['Fixed', 'FixedPU (Oracle)', 'Context table']
MATCH_TOL = 0.5          # % (prereg 5.1)
B_BCA, RNG_BCA = 20000, 20261113
SPEED_EDGES = [10.0, 20.0]

# ------------------------------------------------------------------ input
def load_pertrace(path):
    D = {}
    for r in csv.DictReader(open(path, newline='', encoding='utf-8')):
        D.setdefault((r['trace_set'], r['scheme']), {}).setdefault(int(r['seed']), {})[int(r['trace'])] = float(r['value'])
    out = {}
    for k, by_seed in D.items():
        seeds = sorted(by_seed); traces = sorted(by_seed[seeds[0]])
        for s in seeds:
            if sorted(by_seed[s]) != traces: raise SystemExit(f'{k} seed {s}: trace set differs from seed {seeds[0]}')
        out[k] = dict(seeds=seeds, traces=traces, M=np.array([[by_seed[s][t] for t in traces] for s in seeds]))
    return out

def get(P, ts, scheme, seeds=None):
    """(S, T) matrix for seeded schemes, 1-D vector for deterministic ones (seed 0)."""
    e = P.get((ts, scheme))
    if e is None: return None
    if e['seeds'] == [0]: return e['M'][0]
    if seeds is None: return e['M']
    idx = [e['seeds'].index(s) for s in seeds if s in e['seeds']]
    if len(idx) != len(seeds): return None
    return e['M'][idx]

def check_pairing(P, ts, names):
    tr = {tuple(P[(ts, n)]['traces']) for n in names if (ts, n) in P}
    if len(tr) > 1: raise SystemExit(f'{ts}: schemes are not evaluated on the same traces: {names}')

# ------------------------------------------------------------------ R1 / R2
def classify(r, holm_p, hier_lo):
    if holm_p < 0.05 and r['ci90_lo'] > 0:
        return 'BEATS' if hier_lo > 0 else 'BEATS-TRACE'
    if holm_p < 0.05 and r['ci90_hi'] < 0: return 'LOSES'
    if abs(r['margin_pct']) <= MATCH_TOL and r['ci90_lo'] <= 0 <= r['ci90_hi']: return 'MATCH'
    return 'INCONCLUSIVE'

def consequence(outs):
    v = [outs[x] for x in XS if x in outs]
    if not v: return 'not run'
    if len(v) == len(XS) and all(o == 'BEATS' for o in v): return 'keep: the gain needs more than a one-step learner or a designed rule'
    if any(o == 'LOSES' for o in v): return 'reframe: a non-RL scheme beat NR2'
    if any(o == 'MATCH' for o in v): return 'reframe: a non-RL scheme matched NR2; deep RL not needed for this gain'
    return 'keep with qualifier for the schemes not beaten robustly'

def primary_family(P, ts, nr2_seeds):
    A = get(P, ts, 'NR2', nr2_seeds)
    xs = [x for x in XS if get(P, ts, x) is not None]
    if A is None or not xs: return [], {}
    check_pairing(P, ts, ['NR2'] + xs)
    a = A.mean(axis=0); rows = []
    for x in xs:
        r = r1(a, get(P, ts, x)); r['scheme'] = x; rows.append(r)
    hp = holm(np.array([r['p'] for r in rows]))
    outs = {}
    for r, h in zip(rows, hp):
        sl = seed_level(A, get(P, ts, r['scheme']))
        r.update(holm_p=h, hier95_lo=sl['hier95_lo'], hier95_hi=sl['hier95_hi'], seeds_above=sl['seeds_above'], n_seeds=sl['n_seeds'])
        r['outcome'] = classify(r, h, sl['hier95_lo']); outs[r['scheme']] = r['outcome']
    return rows, outs

def secondary_vs_comparators(P, ts):
    rows = []
    for x in XS:
        xv = get(P, ts, x)
        cs = [c for c in SEC_CMP if get(P, ts, c) is not None]
        if xv is None or not cs: continue
        check_pairing(P, ts, [x] + cs)
        rr = [dict(r1(xv, get(P, ts, c)), scheme=x, comparator=c, trace_set=ts) for c in cs]
        for r, h in zip(rr, holm(np.array([r['p'] for r in rr]))):
            r['holm_p'] = h; r['beats'] = int(h < 0.05 and r['ci90_lo'] > 0); rows.append(r)
    return rows

# ------------------------------------------------------------------ R4
def seed_margins(A, c): return 100 * (A.mean(axis=1) / c.mean() - 1)

def bca(x, B=B_BCA, seed=RNG_BCA, alpha=0.05):
    x = np.asarray(x, float); n = len(x); th = x.mean()
    rng = np.random.default_rng(seed)
    bs = x[rng.integers(0, n, (B, n))].mean(axis=1)
    p0 = np.mean(bs < th); p0 = min(max(p0, 1.0 / (B + 1)), 1 - 1.0 / (B + 1))
    z0 = stats.norm.ppf(p0)
    jk = np.array([np.delete(x, i).mean() for i in range(n)]); d = jk.mean() - jk
    den = 6 * (np.sum(d ** 2) ** 1.5)
    acc = np.sum(d ** 3) / den if den > 0 else 0.0
    q = []
    for z in [stats.norm.ppf(alpha / 2), stats.norm.ppf(1 - alpha / 2)]:
        adj = stats.norm.cdf(z0 + (z0 + z) / (1 - acc * (z0 + z)))
        q.append(np.percentile(bs, 100 * adj))
    return q[0], q[1]

def signflip_p(x):
    x = np.asarray(x, float); n = len(x); obs = abs(x.mean())
    cnt = 0
    for signs in itertools.product([1, -1], repeat=n):
        if abs((x * np.array(signs)).mean()) >= obs - 1e-12: cnt += 1
    return cnt / 2 ** n

def t_power(delta, sd, n, alpha=0.05):
    if sd <= 0: return 1.0
    df = n - 1; nc = delta / (sd / np.sqrt(n)); tc = stats.t.ppf(1 - alpha / 2, df)
    return float(1 - stats.nct.cdf(tc, df, nc) + stats.nct.cdf(-tc, df, nc))

def mde(sd, n, power=0.8, alpha=0.05):
    lo, hi = 0.0, 1.0
    while t_power(hi, sd, n, alpha) < power: hi *= 2
    for _ in range(200):
        mid = (lo + hi) / 2
        if t_power(mid, sd, n, alpha) < power: lo = mid
        else: hi = mid
    return hi

def r4_row(name, A, c):
    m = seed_margins(A, c); n = len(m); sd = m.std(ddof=1)
    tq = stats.t.ppf(0.975, n - 1); se = sd / np.sqrt(n)
    bl, bh = bca(m); sl = seed_level(A, c)
    hier_pos = sl['hier95_lo'] > 0; new_pos = [m.mean() - tq * se > 0, bl > 0]
    cat = 'unchanged' if all(p == hier_pos for p in new_pos) else ('weaker' if hier_pos else 'stronger')
    return dict(comparison=name, n_seeds=n, mean_seed_margin=m.mean(), sd=sd, t95_lo=m.mean() - tq * se, t95_hi=m.mean() + tq * se,
                bca95_lo=bl, bca95_hi=bh, signflip_p=signflip_p(m), hier95_lo=sl['hier95_lo'], hier95_hi=sl['hier95_hi'],
                power_at_observed=t_power(m.mean(), sd, n), mde80_n10=mde(sd, 10), mde80_n5=mde(sd, 5), category=cat)

# ------------------------------------------------------------------ R5
def r5_nr2(P):
    A = get(P, 'NR2', 'NR2', list(range(1, 21)))
    if A is None: return None
    names = [k for _, k in NR2_FAMILY]
    if any(get(P, 'NR2', k) is None for k in names): return None
    check_pairing(P, 'NR2', ['NR2'] + names)
    a = A.mean(axis=0); rows = [dict(r1(a, get(P, 'NR2', k)), comparator=k) for k in names]
    for r, h in zip(rows, holm(np.array([r['p'] for r in rows]))): r['holm_p'] = h; r['beats'] = int(h < 0.05 and r['ci90_lo'] > 0)
    prim = next(r for r in rows if r['comparator'] == 'ctxj500'); sl = seed_level(A, get(P, 'NR2', 'ctxj500'))
    tp = prim['beats'] == 1; spass = sl['hier95_lo'] > 0
    v = 'CONFIRM' if tp and spass else 'TRACE' if tp else 'REVERSE' if (prim['holm_p'] < 0.05 and prim['ci90_hi'] < 0) else 'NULL'
    return dict(analysis='NR2-20', verdict=v, holds=(v == 'CONFIRM'), margin=prim['margin_pct'], ci90_lo=prim['ci90_lo'], ci90_hi=prim['ci90_hi'],
                holm_p=prim['holm_p'], hier95_lo=sl['hier95_lo'], hier95_hi=sl['hier95_hi'], seeds_above=sl['seeds_above'], n_seeds=sl['n_seeds'],
                win=all(r['beats'] == 1 for r in rows))

def best_single(P, ts):
    return max(G_SINGLE, key=lambda k: get(P, ts, k).mean())

def r5_cell(P, ts):
    A = get(P, ts, 'NRG10', list(range(1, 11)))
    if A is None or any(get(P, ts, k) is None for k in G_FAMILY): return None
    check_pairing(P, ts, ['NRG10'] + G_FAMILY)
    a = A.mean(axis=0); rows = [dict(r1(a, get(P, ts, k)), comparator=k) for k in G_FAMILY]
    for r, h in zip(rows, holm(np.array([r['p'] for r in rows]))): r['holm_p'] = h; r['beats'] = int(h < 0.05 and r['ci90_lo'] > 0)
    best = best_single(P, ts); prim = next(r for r in rows if r['comparator'] == best); sl = seed_level(A, get(P, ts, best))
    ok = all(r['beats'] == 1 for r in rows) and sl['hier95_lo'] > 0
    return dict(analysis=f'NRG10-10 {ts}', verdict='PASS' if ok else 'WEAKENS', holds=ok, best_rule=best, margin=prim['margin_pct'],
                ci90_lo=prim['ci90_lo'], ci90_hi=prim['ci90_hi'], holm_p=prim['holm_p'], hier95_lo=sl['hier95_lo'], hier95_hi=sl['hier95_hi'],
                seeds_above=sl['seeds_above'], n_seeds=sl['n_seeds'], win=all(r['beats'] == 1 for r in rows))

# ------------------------------------------------------------------ R3 (descriptive)
def speed_class(v): return 0 if v < SPEED_EDGES[0] else (1 if v < SPEED_EDGES[1] else 2)

def r3_speed(U, cmp_names, B=20000, seed=20261114):
    """Pooled user-trace on-time ratio by speed class; NR2 = mean over seeds; hierarchical seed x trace bootstrap."""
    rows = []
    nr2 = [r for r in U if r['scheme'] == 'NR2']; seeds = sorted({r['seed'] for r in nr2}); traces = sorted({r['trace'] for r in nr2})
    ti = {t: i for i, t in enumerate(traces)}; si = {s: i for i, s in enumerate(seeds)}
    for c in cmp_names:
        cr = [r for r in U if r['scheme'] == c]
        if not cr: continue
        for k, lab in enumerate(['<10 m/s', '10-20 m/s', '>20 m/s']):
            okA = np.zeros((len(seeds), len(traces))); resA = np.zeros_like(okA); okC = np.zeros(len(traces)); resC = np.zeros(len(traces))
            for r in nr2:
                if speed_class(r['speed_mps']) == k: okA[si[r['seed']], ti[r['trace']]] += r['ok']; resA[si[r['seed']], ti[r['trace']]] += r['res']
            for r in cr:
                if speed_class(r['speed_mps']) == k: okC[ti[r['trace']]] += r['ok']; resC[ti[r['trace']]] += r['res']
            if resC.sum() == 0: continue
            est = 100 * (np.mean(okA.sum(1) / resA.sum(1)) / (okC.sum() / resC.sum()) - 1)
            rng = np.random.default_rng(seed); bs = np.empty(B)
            for b in range(B):
                s_ = rng.integers(0, len(seeds), len(seeds)); t_ = rng.integers(0, len(traces), len(traces))
                ra = okA[np.ix_(s_, t_)].sum(1) / np.maximum(resA[np.ix_(s_, t_)].sum(1), 1e-12)
                bs[b] = 100 * (ra.mean() / (okC[t_].sum() / max(resC[t_].sum(), 1e-12)) - 1)
            rows.append(dict(comparator=c, speed=lab, share_user_traces=None, margin_pct=est, hier95_lo=np.percentile(bs, 2.5), hier95_hi=np.percentile(bs, 97.5)))
    return rows

def r3_fair(U, c='ctxj500'):
    def per_trace(rows):
        by = {}
        for r in rows:
            if r['res'] > 0: by.setdefault(r['trace'], []).append(r['ok'] / r['res'])
        return by
    out = []
    nr2 = [r for r in U if r['scheme'] == 'NR2']; cr = [r for r in U if r['scheme'] == c]
    if not nr2 or not cr: return out
    jain = lambda x: (np.sum(x) ** 2) / (len(x) * np.sum(np.square(x))) if np.sum(np.square(x)) > 0 else 1.0
    seeds = sorted({r['seed'] for r in nr2})
    jA = np.mean([np.mean([jain(np.array(v)) for v in per_trace([r for r in nr2 if r['seed'] == s]).values()]) for s in seeds])
    eA = np.mean([np.percentile(np.concatenate([np.array(v) for v in per_trace([r for r in nr2 if r['seed'] == s]).values()]), 5) for s in seeds])
    pc = per_trace(cr)
    jC = np.mean([jain(np.array(v)) for v in pc.values()]); eC = np.percentile(np.concatenate([np.array(v) for v in pc.values()]), 5)
    out.append(dict(comparator=c, jain_nr2=jA, jain_cmp=jC, jain_diff=jA - jC, edge5_nr2=eA, edge5_cmp=eC,
                    edge5_change_pct=100 * (eA / eC - 1) if eC > 0 else float('nan'),
                    guard_flag=int((jC - jA) > 0.02 or (eC > 0 and 100 * (eA / eC - 1) < -10))))
    return out

def r3_actions(Acts):
    seeds = sorted({r['seed'] for r in Acts})
    bins = [('all', lambda r: True), ('busy=0', lambda r: r['busy'] == 0), ('busy>=1', lambda r: r['busy'] >= 1),
            ('slack<=0.6', lambda r: r['has_packet'] == 1 and r['slack_frac'] <= 0.6), ('slack>0.6', lambda r: r['has_packet'] == 1 and r['slack_frac'] > 0.6),
            ('speed<10', lambda r: speed_class(r['speed_mps']) == 0), ('speed10-20', lambda r: speed_class(r['speed_mps']) == 1), ('speed>20', lambda r: speed_class(r['speed_mps']) == 2),
            ('burst', lambda r: r['burst'] == 1), ('calm', lambda r: r['burst'] == 0)]
    rows = []
    for name, f in bins:
        sub = [r for r in Acts if f(r)]
        if not sub: continue
        row = dict(bin=name, share_of_decisions=100 * len(sub) / len(Acts))
        for a, lab in [(-1, 'minus'), (0, 'zero'), (1, 'plus')]:
            row[f'pct_{lab}'] = 100 * np.mean([r['action'] == a for r in sub])
            per = [100 * np.mean([r['action'] == a for r in sub if r['seed'] == s]) for s in seeds if any(r['seed'] == s for r in sub)]
            row[f'pct_{lab}_seed_min'] = min(per); row[f'pct_{lab}_seed_max'] = max(per)
        rows.append(row)
    return rows

# ------------------------------------------------------------------ main
def fmt(v):
    if isinstance(v, (bool, np.bool_)): return 'yes' if v else 'no'
    if isinstance(v, (float, np.floating)): return f'{v:.4g}'
    return v

def write(path, rows):
    if not rows: return
    keys = list(dict.fromkeys(k for r in rows for k in r))
    with open(path, 'w', newline='', encoding='utf-8') as fh:
        w = csv.DictWriter(fh, fieldnames=keys); w.writeheader()
        for r in rows: w.writerow({k: fmt(r.get(k, '')) for k in keys})

def run(indir, out):
    os.makedirs(out, exist_ok=True); txt = []; pv = []
    pt = os.path.join(indir, 'pertrace.csv')
    P = load_pertrace(pt) if os.path.exists(pt) else {}
    # R1/R2
    rows, outs = primary_family(P, 'NR2', list(range(1, 11)))
    if rows:
        for r in rows: r['trace_set'] = 'NR2'
        write(os.path.join(out, 'presub_R1R2.csv'), rows)
        txt.append('R1/R2 primary (NR2 traces, Holm over %d): ' % len(rows) + '; '.join(f"{r['scheme']}: {r['outcome']} ({r['margin_pct']:+.2f}% [{r['ci90_lo']:+.2f}, {r['ci90_hi']:+.2f}], hier [{r['hier95_lo']:+.2f}, {r['hier95_hi']:+.2f}])" for r in rows))
        txt.append('R1/R2 consequence for C2: ' + consequence(outs))
        for r in rows:
            k = r['scheme'].replace('-', '').lower()
            pv += [(f'outcome_{k}', r['outcome']), (f'margin_{k}', f"{r['margin_pct']:.2f}"), (f'ci_lo_{k}', f"{r['ci90_lo']:.2f}"), (f'ci_hi_{k}', f"{r['ci90_hi']:.2f}"),
                   (f'hier_lo_{k}', f"{r['hier95_lo']:.2f}"), (f'hier_hi_{k}', f"{r['hier95_hi']:.2f}")]
    else: txt.append('R1/R2: not run')
    sec = secondary_vs_comparators(P, 'NR2')
    rows_m1, outs_m1 = primary_family(P, 'M1', list(range(1, 11)))
    for r in rows_m1: r['trace_set'] = 'M1 (secondary)'; r['comparator'] = 'NR2'
    write(os.path.join(out, 'presub_R1R2_secondary.csv'), sec + rows_m1)
    if rows_m1: txt.append('R1/R2 secondary (M1 traces): ' + '; '.join(f"{r['scheme']}: {r['outcome']}" for r in rows_m1))
    # R3
    up = os.path.join(indir, 'peruser.csv'); ap = os.path.join(indir, 'actions.csv')
    if os.path.exists(up):
        U = [dict(scheme=r['scheme'], seed=int(r['seed']), trace=int(r['trace']), user=int(r['user']), ok=float(r['ok']), res=float(r['res']), speed_mps=float(r['speed_mps']))
             for r in csv.DictReader(open(up, newline='', encoding='utf-8'))]
        write(os.path.join(out, 'presub_R3_speed.csv'), r3_speed(U, ['ctxj500', 'ctx500']))
        write(os.path.join(out, 'presub_R3_fair.csv'), r3_fair(U))
        txt.append('R3 speed and fairness: written')
    else: txt.append('R3 speed/fairness: not run')
    if get(P, 'NR2', 'olla_warm200') is not None and get(P, 'NR2', 'NR2', list(range(1, 11))) is not None:
        a = get(P, 'NR2', 'NR2', list(range(1, 11))).mean(axis=0)
        wr = [dict(r1(a, get(P, 'NR2', k)), comparator=k) for k in ['olla_warm200', 'olla'] if get(P, 'NR2', k) is not None]
        write(os.path.join(out, 'presub_R3_warm.csv'), wr); txt.append('R3 warm-up: ' + '; '.join(f"vs {r['comparator']} {r['margin_pct']:+.2f}%" for r in wr))
    else: txt.append('R3 warm-up: not run')
    if os.path.exists(ap):
        Acts = [dict(seed=int(r['seed']), trace=int(r['trace']), busy=int(float(r['busy'])), slack_frac=float(r['slack_frac']), has_packet=int(float(r['has_packet'])),
                     speed_mps=float(r['speed_mps']), burst=int(float(r['burst'])), action=int(float(r['action']))) for r in csv.DictReader(open(ap, newline='', encoding='utf-8'))]
        write(os.path.join(out, 'presub_R3_actions.csv'), r3_actions(Acts)); txt.append('R3 actions: written')
    else: txt.append('R3 actions: not run')
    # R4
    r4 = []
    A = get(P, 'M1', 'M1', list(range(1, 11))); c = get(P, 'M1', 'ctxj500')
    if A is not None and c is not None: r4.append(r4_row('M1 vs Context-joint-500', A, c))
    A = get(P, 'NR2', 'NR2', list(range(1, 11))); c = get(P, 'NR2', 'ctxj500')
    if A is not None and c is not None: r4.append(r4_row('NR2 vs Context-joint-500', A, c))
    for ts in ['G2', 'G3']:
        A = get(P, ts, 'NRG10', list(range(1, 6)))
        if A is not None and all(get(P, ts, k) is not None for k in G_SINGLE):
            b = best_single(P, ts); r4.append(r4_row(f'NR-G10 {ts} vs {b}', A, get(P, ts, b)))
    write(os.path.join(out, 'presub_R4.csv'), r4)
    txt.append('R4: ' + ('; '.join(f"{r['comparison']}: t [{r['t95_lo']:+.2f}, {r['t95_hi']:+.2f}], BCa [{r['bca95_lo']:+.2f}, {r['bca95_hi']:+.2f}], sign-flip p={r['signflip_p']:.3g}, MDE80 n=10 {r['mde80_n10']:.2f}, n=5 {r['mde80_n5']:.2f} -> {r['category']}" for r in r4) if r4 else 'not run'))
    # R5
    r5 = [x for x in [r5_nr2(P), r5_cell(P, 'G2'), r5_cell(P, 'G3')] if x]
    write(os.path.join(out, 'presub_R5.csv'), r5)
    txt.append('R5: ' + ('; '.join(f"{r['analysis']}: {r['verdict']} ({'holds' if r['holds'] else 'weakens'}; {r['margin']:+.2f}%, hier [{r['hier95_lo']:+.2f}, {r['hier95_hi']:+.2f}], {r['seeds_above']}/{r['n_seeds']} seeds)" for r in r5) if r5 else 'not run'))
    for r in r5:
        k = r['analysis'].replace(' ', '_').replace('-', '').lower()
        pv += [(f'r5_{k}_verdict', r['verdict']), (f'r5_{k}_margin', f"{r['margin']:.2f}"), (f'r5_{k}_hier_lo', f"{r['hier95_lo']:.2f}"), (f'r5_{k}_hier_hi', f"{r['hier95_hi']:.2f}")]
    open(os.path.join(out, 'presub_verdicts.txt'), 'w', encoding='utf-8').write('\n'.join(txt) + '\n')
    with open(os.path.join(out, 'presub_pending_values.csv'), 'w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh); w.writerow(['item', 'key', 'value', 'source_file', 'date'])
        for k, v in pv: w.writerow(['PRESUB', k, v, 'paper/analysis/out/presub_*.csv', ''])
    print('\n'.join(txt))
    return txt

# ------------------------------------------------------------------ self-test (synthetic data only)
def selftest():
    import tempfile
    rng = np.random.default_rng(7); T = 500
    base = rng.uniform(0.5, 0.7, T)
    noise = lambda s: rng.normal(0, s, T)
    A = np.array([base * 1.03 + noise(0.01) + rng.normal(0, 0.002) for _ in range(10)])   # NR2 ~ +3 %
    a = A.mean(0)
    sch = {'GBT-res': base * 1.0 + noise(0.01),            # NR2 beats it by ~3 %
           'GBT-full': a + noise(0.003),                    # matches NR2
           'Rule': base * 1.08 + noise(0.01),               # beats NR2
           'Rule-cal': a * 0.992 + (lambda z: z - z.mean())(noise(0.15))}             # noisy: margin about +0.8 %, CI covers 0
    with tempfile.TemporaryDirectory() as d:
        ind = os.path.join(d, 'in'); os.makedirs(ind)
        with open(os.path.join(ind, 'pertrace.csv'), 'w', newline='') as fh:
            w = csv.writer(fh); w.writerow(['trace_set', 'scheme', 'seed', 'trace', 'value'])
            for s in range(10):
                for t in range(T): w.writerow(['NR2', 'NR2', s + 1, t + 1, A[s, t]])
            for k, v in sch.items():
                for t in range(T): w.writerow(['NR2', k, 0, t + 1, v[t]])
            for t in range(T): w.writerow(['NR2', 'ctxj500', 0, t + 1, base[t]])
            # remaining synthetic inputs, to exercise R3-R5 end to end
            for s in range(10, 20):
                v = base * 1.03 + noise(0.01)
                for t in range(T): w.writerow(['NR2', 'NR2', s + 1, t + 1, v[t]])
            for k in [k for _, k in NR2_FAMILY if k != 'ctxj500'] + ['olla_warm200']:
                v = base * rng.uniform(0.85, 1.0) + noise(0.01)
                for t in range(T): w.writerow(['NR2', k, 0, t + 1, v[t]])
            for s in range(10):
                v = base * 1.005 + noise(0.01) + rng.normal(0, 0.01)
                for t in range(T): w.writerow(['M1', 'M1', s + 1, t + 1, v[t]])
            for t in range(T): w.writerow(['M1', 'ctxj500', 0, t + 1, base[t]])
            for ts in ['G2', 'G3']:
                for s in range(10):
                    v = base[:300] * 1.02 + rng.normal(0, 0.01, 300)
                    for t in range(300): w.writerow([ts, 'NRG10', s + 1, t + 1, v[t]])
                for k in G_FAMILY:
                    v = base[:300] * (1.0 if k in G_SINGLE else 0.9) + rng.normal(0, 0.01, 300)
                    for t in range(300): w.writerow([ts, k, 0, t + 1, v[t]])
        with open(os.path.join(ind, 'peruser.csv'), 'w', newline='') as fh:
            w = csv.writer(fh); w.writerow(['scheme', 'seed', 'trace', 'user', 'ok', 'res', 'speed_mps'])
            for t in range(40):
                sp = rng.uniform(3, 30, 10)
                for u in range(10):
                    for s in range(3): w.writerow(['NR2', s + 1, t + 1, u + 1, rng.integers(3, 8), 8, sp[u]])
                    for c in ['ctxj500', 'ctx500']: w.writerow([c, 0, t + 1, u + 1, rng.integers(3, 8), 8, sp[u]])
        with open(os.path.join(ind, 'actions.csv'), 'w', newline='') as fh:
            w = csv.writer(fh); w.writerow(['seed', 'trace', 'busy', 'slack_frac', 'has_packet', 'speed_mps', 'burst', 'action'])
            for i in range(3000):
                w.writerow([i % 10 + 1, i // 10 + 1, rng.integers(0, 3), rng.uniform(), 1, rng.uniform(3, 30), rng.integers(0, 2), rng.integers(-1, 2)])
        out = os.path.join(d, 'out'); run(ind, out)
        for f in ['presub_R1R2.csv', 'presub_R1R2_secondary.csv', 'presub_R3_speed.csv', 'presub_R3_warm.csv', 'presub_R3_fair.csv',
                  'presub_R3_actions.csv', 'presub_R4.csv', 'presub_R5.csv', 'presub_verdicts.txt', 'presub_pending_values.csv']:
            assert os.path.exists(os.path.join(out, f)), f
        r5 = {r['analysis']: r['verdict'] for r in csv.DictReader(open(os.path.join(out, 'presub_R5.csv')))}
        assert r5['NR2-20'] == 'CONFIRM' and r5['NRG10-10 G2'] == 'PASS', r5
        res = {r['scheme']: r['outcome'] for r in csv.DictReader(open(os.path.join(out, 'presub_R1R2.csv')))}
    want = {'GBT-res': 'BEATS', 'GBT-full': 'MATCH', 'Rule': 'LOSES', 'Rule-cal': 'INCONCLUSIVE'}
    assert res == want, (res, want)
    # exact sign flip vs brute force
    x = np.array([1.2, -0.3, 0.8, 0.5, -0.1, 0.9, 0.4])
    bf = sum(abs(np.mean(x * np.array(s))) >= abs(x.mean()) - 1e-12 for s in itertools.product([1, -1], repeat=len(x))) / 2 ** len(x)
    assert abs(signflip_p(x) - bf) < 1e-15
    # BCa close to percentile for a symmetric sample
    y = np.linspace(-1, 1, 41); lo, hi = bca(y)
    bs = y[np.random.default_rng(RNG_BCA).integers(0, len(y), (B_BCA, len(y)))].mean(1)
    assert abs(lo - np.percentile(bs, 2.5)) < 0.02 and abs(hi - np.percentile(bs, 97.5)) < 0.02
    # power vs closed form (noncentral t) and MDE consistency
    sd, n, dlt = 1.3, 10, 1.0; df = n - 1; nc = dlt / (sd / np.sqrt(n)); tc = stats.t.ppf(0.975, df)
    assert abs(t_power(dlt, sd, n) - (1 - stats.nct.cdf(tc, df, nc) + stats.nct.cdf(-tc, df, nc))) < 1e-12
    assert abs(t_power(mde(sd, n), sd, n) - 0.8) < 1e-6
    # the R1 machinery is the frozen one
    import nr2_stats
    assert r1 is nr2_stats.r1 and holm is nr2_stats.holm and seed_level is nr2_stats.seed_level
    print('SELFTEST PASS: outcomes', res)

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--indir', default=os.path.join(ROOT, 'Optimized', 'v17x', 'Dataset', 'presub'))
    ap.add_argument('--out', default=os.path.join(HERE, 'out'))
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args()
    selftest() if a.selftest else run(a.indir, a.out)
