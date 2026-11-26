"""FT statistics: fresh-trace confirmation of frozen policies (Amendment 13, Freeze v15).
Implements Section 4 and Section 5 of paper/proposals/FT_fresh_trace_prereg.md.

Inputs (per-trace CSV: trace_set, scheme, seed, trace, value):
  - Default input: Optimized/v17x/Dataset/ft/pertrace_ft_asrun.csv (trace_set='FT')
  - Optional --nr2-ref: NR2-trace per-trace CSVs to print NR2-trace on-time alongside FT on-time.
Outputs:
  - ft_primary.csv, ft_secondary.csv, ft_schemes.csv, ft_summary.txt
Run : python paper/analysis/ft_stats.py [--in CSV] [--out DIR]
Test: python paper/analysis/ft_stats.py --selftest   (synthetic data only; never reads Dataset/ft/)
"""
import argparse
import csv
import os
import sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)

from nr2_stats import r1, holm, seed_level as nr2_seed_level  # frozen (NR2_confirmatory_prereg.md)
from presub_stats import load_pertrace, get, check_pairing, write  # frozen (Amendment 8)

TS = 'FT'
FITS = [1, 2, 3, 4]
SEEDS = list(range(1, 11))
B_HIER = 10000
BOOT_SEED = 20261124

S2_RULES = [
    ('Baseline', 'baseline'),
    ('OLLA', 'olla'),
    ('OLLA-tuned-500', 'olla_tuned500'),
    ('Multi-OLLA', 'multi_olla'),
    ('Fixed-500', 'fixed500'),
    ('Context-500', 'ctx500'),
    ('Rule', 'Rule'),
    ('Rule-cal', 'Rule-cal'),
]

WORDING_H12 = {
    'holds': 'On a fresh trace bank, evaluated once after all policies were frozen, every fit of the supervised learner again beat RL, with the same action set and with the full one.',
    'fit-dependent': 'On a fresh trace bank, the supervised learner beat RL for some calibration draws but not all; the ranking depends on the draw.',
    'does not replicate': 'On a fresh trace bank, the difference between the supervised learner and RL was not significant; the headline ranking did not replicate.',
    'reverses': 'On a fresh trace bank, RL beat the supervised learner for at least one draw; the headline ranking reversed.',
}


def crossed_hier_boot(A, c, B=B_HIER, seed=BOOT_SEED):
    """Crossed hierarchical bootstrap: one shared trace-ID sample per replicate across resampled RL seeds."""
    rng = np.random.default_rng(seed)
    S, T = A.shape
    seed_m = 100.0 * (A.mean(axis=1) / c.mean() - 1.0)
    seeds_ahead = int(np.sum(seed_m > 0))
    hb = np.empty(B, dtype=float)
    chunk = 500
    for b0 in range(0, B, chunk):
        m = min(chunk, B - b0)
        si = rng.integers(0, S, size=(m, S))
        ti = rng.integers(0, T, size=(m, T))
        row_means = A[:, ti].mean(axis=2)  # (S, m)
        a_boot = row_means[si, np.arange(m)[:, None]].mean(axis=1)
        c_boot = c[ti].mean(axis=1)
        hb[b0:b0 + m] = 100.0 * (a_boot / c_boot - 1.0)
    return float(np.percentile(hb, 2.5)), float(np.percentile(hb, 97.5)), seeds_ahead, S


def classify_sym(r, holm_p, hier_lo, hier_hi):
    """Symmetric per-fit rule (Amendment 13 Section 4)."""
    if holm_p < 0.05 and r['ci90_hi'] < 0 and hier_hi < 0:
        return 'SUP-BEATS'
    if holm_p < 0.05 and r['ci90_lo'] > 0 and hier_lo > 0:
        return 'RL-BEATS'
    return 'INCONCLUSIVE'


def family_verdict(outcomes):
    """Family verdict for FT-H1 and FT-H2 (Amendment 13 Section 4)."""
    if len(outcomes) != len(FITS):
        return 'not run'
    if any(o == 'RL-BEATS' for o in outcomes):
        return 'reverses'
    n_sup = sum(1 for o in outcomes if o == 'SUP-BEATS')
    if n_sup == len(FITS):
        return 'holds on fresh traces'
    if n_sup >= 1:
        return 'fit-dependent'
    return 'does not replicate'


def h3_verdict(r, sl):
    """H3 uses NR2's frozen verdict rule (CONFIRM / TRACE / NULL / REVERSE)."""
    trace_pass = (r['p'] < 0.05 and r['ci90_lo'] > 0)
    seed_pass = (sl['hier95_lo'] > 0)
    if trace_pass and seed_pass:
        return 'CONFIRM'
    if trace_pass:
        return 'TRACE'
    if r['p'] < 0.05 and r['ci90_hi'] < 0:
        return 'REVERSE'
    return 'NULL'


def eval_fit_family(P, ts, rl_name, sup_name, family_id):
    """Evaluate one 4-fit comparison family (RL vs sup fits 1..4, Holm over 4)."""
    A = get(P, ts, rl_name, SEEDS)
    if A is None:
        return []
    fit_names = [(k, f'{sup_name}-M1fit{k}') for k in FITS if get(P, ts, f'{sup_name}-M1fit{k}') is not None]
    if not fit_names:
        return []
    check_pairing(P, ts, [rl_name] + [n for _, n in fit_names])
    a = A.mean(axis=0)
    rows = []
    for k, n in fit_names:
        x = get(P, ts, n)
        r = r1(a, x)
        rows.append(dict(
            family=family_id,
            comparison=f'{rl_name} vs {sup_name}',
            fit=k,
            rl_ontime=float(a.mean()),
            cmp_ontime=float(x.mean()),
            **r,
        ))
    hps = holm(np.array([r['p'] for r in rows]))
    for r, hp in zip(rows, hps):
        x = get(P, ts, f"{sup_name}-M1fit{r['fit']}")
        hlo, hhi, sa, ns = crossed_hier_boot(A, x)
        r.update(
            holm_p=float(hp),
            hier95_lo=hlo,
            hier95_hi=hhi,
            seeds_ahead=sa,
            n_seeds=ns,
            verdict=classify_sym(r, hp, hlo, hhi),
        )
    return rows


def eval_s1_family(P, ts):
    """FT-S1: GBT-full-ACK fits 1-4 vs NR2 AND GBT-res-ACK fits 1-4 vs RL-full (Holm over 8)."""
    pairs = []
    for rl_name, sup_name in [('NR2', 'GBT-full-ACK'), ('RL-full', 'GBT-res-ACK')]:
        A = get(P, ts, rl_name, SEEDS)
        if A is None:
            continue
        for k in FITS:
            n = f'{sup_name}-M1fit{k}'
            x = get(P, ts, n)
            if x is not None:
                pairs.append((rl_name, sup_name, k, A, x))
    if not pairs:
        return []
    rows = []
    for rl_name, sup_name, k, A, x in pairs:
        a = A.mean(axis=0)
        r = r1(a, x)
        rows.append(dict(
            family='FT-S1',
            comparison=f'{rl_name} vs {sup_name}',
            fit=k,
            rl_ontime=float(a.mean()),
            cmp_ontime=float(x.mean()),
            **r,
        ))
    hps = holm(np.array([r['p'] for r in rows]))
    for (rl_name, sup_name, k, A, x), r, hp in zip(pairs, rows, hps):
        hlo, hhi, sa, ns = crossed_hier_boot(A, x)
        r.update(
            holm_p=float(hp),
            hier95_lo=hlo,
            hier95_hi=hhi,
            seeds_ahead=sa,
            n_seeds=ns,
            verdict=classify_sym(r, hp, hlo, hhi),
        )
    return rows


def eval_s2_family(P, ts):
    """FT-S2: NR2 vs the other 8 frozen rules (Holm over 8)."""
    A = get(P, ts, 'NR2', SEEDS)
    if A is None:
        return []
    a = A.mean(axis=0)
    avail = []
    for label, key in S2_RULES:
        x = get(P, ts, key)
        if x is None:
            x = get(P, ts, label)
        if x is not None:
            avail.append((label, x))
    if not avail:
        return []
    rows = []
    for label, x in avail:
        r = r1(a, x)
        rows.append(dict(
            family='FT-S2',
            comparison=f'NR2 vs {label}',
            fit=0,
            rl_ontime=float(a.mean()),
            cmp_ontime=float(x.mean()),
            **r,
        ))
    hps = holm(np.array([r['p'] for r in rows]))
    for (_, x), r, hp in zip(avail, rows, hps):
        hlo, hhi, sa, ns = crossed_hier_boot(A, x)
        r.update(
            holm_p=float(hp),
            hier95_lo=hlo,
            hier95_hi=hhi,
            seeds_ahead=sa,
            n_seeds=ns,
            verdict=classify_sym(r, hp, hlo, hhi),
        )
    return rows


def select_wording(v1, v2):
    if v1 == 'reverses' or v2 == 'reverses':
        return WORDING_H12['reverses']
    if v1 == 'does not replicate' or v2 == 'does not replicate':
        return WORDING_H12['does not replicate']
    if v1 == 'fit-dependent' or v2 == 'fit-dependent':
        return WORDING_H12['fit-dependent']
    if v1 == 'holds on fresh traces' and v2 == 'holds on fresh traces':
        return WORDING_H12['holds']
    return 'Incomplete primary families.'


def normalize_fit1(P, ts):
    for s in ['GBT-res-ACK', 'GBT-full-ACK']:
        if (ts, s) in P and (ts, f'{s}-M1fit1') not in P:
            P[(ts, f'{s}-M1fit1')] = P[(ts, s)]


def run(in_csv, out_dir, ts=TS, nr2_ref_dir=None):
    os.makedirs(out_dir, exist_ok=True)
    P = load_pertrace(in_csv)
    normalize_fit1(P, ts)

    h1 = eval_fit_family(P, ts, 'NR2', 'GBT-res-ACK', 'FT-H1')
    h2 = eval_fit_family(P, ts, 'RL-full', 'GBT-full-ACK', 'FT-H2')

    v1 = family_verdict([r['verdict'] for r in h1])
    v2 = family_verdict([r['verdict'] for r in h2])

    # FT-H3: NR2 vs Context-joint-500 using NR2 frozen seed_level & verdict rule
    h3_rows = []
    v3 = 'not run'
    A_nr2 = get(P, ts, 'NR2', SEEDS)
    cj = get(P, ts, 'ctxj500')
    if cj is None:
        cj = get(P, ts, 'Context-joint-500')
    if A_nr2 is not None and cj is not None:
        check_pairing(P, ts, ['NR2', 'ctxj500' if get(P, ts, 'ctxj500') is not None else 'Context-joint-500'])
        r = r1(A_nr2.mean(axis=0), cj)
        sl = nr2_seed_level(A_nr2, cj)
        v3 = h3_verdict(r, sl)
        h3_rows.append(dict(
            family='FT-H3',
            comparison='NR2 vs Context-joint-500',
            fit=0,
            rl_ontime=float(A_nr2.mean()),
            cmp_ontime=float(cj.mean()),
            holm_p=float(r['p']),
            hier95_lo=float(sl['hier95_lo']),
            hier95_hi=float(sl['hier95_hi']),
            seeds_ahead=sl['seeds_above'],
            n_seeds=sl['n_seeds'],
            verdict=v3,
            **r,
        ))

    s1 = eval_s1_family(P, ts)
    s2 = eval_s2_family(P, ts)

    prim = h1 + h2 + h3_rows
    sec = s1 + s2

    write(os.path.join(out_dir, 'ft_primary.csv'), prim)
    write(os.path.join(out_dir, 'ft_secondary.csv'), sec)

    # Per-scheme summary table (FT on-time, plus NR2-trace on-time if provided)
    nr2_ref = {}
    if nr2_ref_dir and os.path.isdir(nr2_ref_dir):
        for fname in ['pertrace_G2corrected.csv', os.path.join('r1b', 'pertrace_r1b.csv'),
                      os.path.join('r1c', 'pertrace_r1c.csv'), os.path.join('r6', 'pertrace_r6.csv')]:
            fpath = os.path.join(nr2_ref_dir, fname)
            if os.path.exists(fpath):
                refP = load_pertrace(fpath)
                normalize_fit1(refP, 'NR2')
                for (rts, rsch), entry in refP.items():
                    if rts == 'NR2':
                        nr2_ref[rsch] = float(entry['M'].mean())

    scheme_rows = []
    for (pts, sch), entry in sorted(P.items()):
        if pts != ts:
            continue
        ft_val = float(entry['M'].mean())
        nr2_val = nr2_ref.get(sch, float('nan'))
        scheme_rows.append(dict(scheme=sch, n_seeds=len(entry['seeds']), n_traces=len(entry['traces']),
                                ft_ontime=f'{ft_val:.6f}',
                                nr2_ontime=f'{nr2_val:.6f}' if np.isfinite(nr2_val) else 'NA'))
    write(os.path.join(out_dir, 'ft_schemes.csv'), scheme_rows)

    wrow = select_wording(v1, v2)
    lines = [
        f'FT Summary (trace_set={ts})',
        f'FT-H1 (GBT-res-ACK fits 1-4 vs NR2): {v1}',
        f'FT-H2 (GBT-full-ACK fits 1-4 vs RL-full): {v2}',
        f'FT-H3 (NR2 vs Context-joint-500): {v3}',
        f'Wording (H1/H2): "{wrow}"',
        '',
        '--- Primary Comparisons ---',
    ]
    for r in prim:
        lines.append(
            f"{r['family']} | {r['comparison']} | fit={r['fit']} | "
            f"margin={r['margin_pct']:+.2f}% | 90% CI [{r['ci90_lo']:+.2f}, {r['ci90_hi']:+.2f}] | "
            f"95% hier CI [{r['hier95_lo']:+.2f}, {r['hier95_hi']:+.2f}] | "
            f"Holm p={r['holm_p']:.3g} | RL seeds ahead={r['seeds_ahead']}/{r['n_seeds']} | {r['verdict']}"
        )
    lines.append('')
    lines.append('--- Secondary Comparisons ---')
    for r in sec:
        lines.append(
            f"{r['family']} | {r['comparison']} | fit={r['fit']} | "
            f"margin={r['margin_pct']:+.2f}% | 90% CI [{r['ci90_lo']:+.2f}, {r['ci90_hi']:+.2f}] | "
            f"95% hier CI [{r['hier95_lo']:+.2f}, {r['hier95_hi']:+.2f}] | "
            f"Holm p={r['holm_p']:.3g} | RL seeds ahead={r['seeds_ahead']}/{r['n_seeds']} | {r['verdict']}"
        )
    lines.append('')
    lines.append('--- Scheme On-Time Ratios (FT vs NR2-trace) ---')
    for sr in scheme_rows:
        lines.append(f"{sr['scheme']:24s} | seeds={sr['n_seeds']:2d} | FT={sr['ft_ontime']} | NR2={sr['nr2_ontime']}")

    summary = '\n'.join(lines) + '\n'
    with open(os.path.join(out_dir, 'ft_summary.txt'), 'w', encoding='utf-8') as fh:
        fh.write(summary)
    print(summary)
    return dict(H1=v1, H2=v2, H3=v3, wording=wrow)


# ------------------------------------------------------------------ self-test (synthetic data only)
def selftest():
    import tempfile
    rng = np.random.default_rng(20261124)

    def make_csv(path, nr2_lvl, rlfull_lvl, res_lvls, full_lvls):
        base = rng.normal(0, 0.015, 500)
        def vec(lvl):
            return lvl + base + rng.normal(0, 0.003, 500)
        rows = []
        for s in SEEDS:
            v = vec(nr2_lvl + rng.normal(0, 0.0015))
            rows += [[TS, 'NR2', s, t + 1, v[t]] for t in range(500)]
            v2 = vec(rlfull_lvl + rng.normal(0, 0.0015))
            rows += [[TS, 'RL-full', s, t + 1, v2[t]] for t in range(500)]
        for k in FITS:
            vr = vec(res_lvls[k - 1])
            rows += [[TS, f'GBT-res-ACK-M1fit{k}', 0, t + 1, vr[t]] for t in range(500)]
            vf = vec(full_lvls[k - 1])
            rows += [[TS, f'GBT-full-ACK-M1fit{k}', 0, t + 1, vf[t]] for t in range(500)]
        vc = vec(0.600)
        rows += [[TS, 'ctxj500', 0, t + 1, vc[t]] for t in range(500)]
        for label, key in S2_RULES:
            v_r = vec(0.595)
            rows += [[TS, key, 0, t + 1, v_r[t]] for t in range(500)]
        with open(path, 'w', newline='', encoding='utf-8') as fh:
            w = csv.writer(fh)
            w.writerow(['trace_set', 'scheme', 'seed', 'trace', 'value'])
            w.writerows(rows)

    with tempfile.TemporaryDirectory() as td:
        # Case 1: all 4 fits clearly better -> holds on fresh traces
        c1 = os.path.join(td, 'c1.csv')
        make_csv(c1, 0.620, 0.630, [0.645, 0.646, 0.644, 0.647], [0.655, 0.656, 0.654, 0.657])
        r1_out = run(c1, os.path.join(td, 'out1'))
        assert r1_out['H1'] == 'holds on fresh traces', r1_out
        assert r1_out['H2'] == 'holds on fresh traces', r1_out
        assert r1_out['H3'] == 'CONFIRM', r1_out

        # Case 2: 2 of 4 better -> fit-dependent
        c2 = os.path.join(td, 'c2.csv')
        make_csv(c2, 0.620, 0.630, [0.645, 0.646, 0.620, 0.620], [0.655, 0.656, 0.630, 0.630])
        r2_out = run(c2, os.path.join(td, 'out2'))
        assert r2_out['H1'] == 'fit-dependent', r2_out
        assert r2_out['H2'] == 'fit-dependent', r2_out

        # Case 3: null -> does not replicate
        c3 = os.path.join(td, 'c3.csv')
        make_csv(c3, 0.620, 0.630, [0.620, 0.620, 0.620, 0.620], [0.630, 0.630, 0.630, 0.630])
        r3_out = run(c3, os.path.join(td, 'out3'))
        assert r3_out['H1'] == 'does not replicate', r3_out
        assert r3_out['H2'] == 'does not replicate', r3_out

        # Case 4: one fit worse -> reverses
        c4 = os.path.join(td, 'c4.csv')
        make_csv(c4, 0.620, 0.630, [0.645, 0.645, 0.645, 0.595], [0.655, 0.655, 0.655, 0.605])
        r4_out = run(c4, os.path.join(td, 'out4'))
        assert r4_out['H1'] == 'reverses', r4_out
        assert r4_out['H2'] == 'reverses', r4_out

    print('SELFTEST PASSED: all 4 synthetic cases verified (holds, fit-dependent, does not replicate, reverses).')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='in_csv', default=os.path.join(ROOT, 'Optimized', 'v17x', 'Dataset', 'ft', 'pertrace_ft_asrun.csv'))
    ap.add_argument('--out', default=os.path.join(ROOT, 'Optimized', 'v17x', 'Dataset', 'ft'))
    ap.add_argument('--nr2-ref', default=os.path.join(ROOT, 'Optimized', 'v17x', 'Dataset', 'presub'))
    ap.add_argument('--selftest', action='store_true')
    args = ap.parse_args()
    if args.selftest:
        selftest()
    else:
        run(args.in_csv, args.out, nr2_ref_dir=args.nr2_ref)


if __name__ == '__main__':
    main()
