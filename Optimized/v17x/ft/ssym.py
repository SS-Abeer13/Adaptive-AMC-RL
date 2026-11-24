"""S-SYM: Symmetric seed-level sensitivity check on frozen R1c and R6a verdicts (Amendment 13, Section 6).
Analysis-only script reading stored per-trace files under Optimized/v17x/Dataset/presub/.
Outputs Optimized/v17x/Dataset/ft/ssym_summary.txt.
"""
import os
import sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
ANALYSIS_DIR = os.path.join(ROOT, 'paper', 'analysis')
sys.path.insert(0, ANALYSIS_DIR)

import r1c_stats
import r6_stats
from nr2_stats import r1, holm
from presub_stats import get, check_pairing
from ft_stats import classify_sym, crossed_hier_boot


def main():
    indir = os.path.join(ROOT, 'Optimized', 'v17x', 'Dataset', 'presub')
    outdir = os.path.join(ROOT, 'Optimized', 'v17x', 'Dataset', 'ft')
    os.makedirs(outdir, exist_ok=True)

    P_r1c = r1c_stats.load(indir)
    P_r6 = r6_stats.load(indir)

    rows = []

    # 1. R1c comparisons: (NR2, M1fit), (G2, cellfit), (G3, cellfit) primary; (G2, M1fit), (G3, M1fit) secondary
    for ts, kind, role in [
        ('NR2', 'M1fit', 'R1c primary (replication)'),
        ('G2', 'cellfit', 'R1c primary (cell)'),
        ('G3', 'cellfit', 'R1c primary (cell)'),
        ('G2', 'M1fit', 'R1c secondary (transfer)'),
        ('G3', 'M1fit', 'R1c secondary (transfer)'),
    ]:
        A = r1c_stats.rl_matrix(P_r1c, ts)
        names = [(s, k, f'{s}-{kind}{k}') for s in r1c_stats.SCHEMES for k in r1c_stats.FITS
                 if get(P_r1c, ts, f'{s}-{kind}{k}') is not None]
        if A is None or not names:
            continue
        rl_name = 'NR2' if ts == 'NR2' else 'NRG10'
        check_pairing(P_r1c, ts, [rl_name] + [n for _, _, n in names])
        a = A.mean(axis=0)
        fit_recs = []
        for s, k, n in names:
            x = get(P_r1c, ts, n)
            r = r1(a, x)
            fit_recs.append((s, k, n, x, r))
        hps = holm(np.array([rec[4]['p'] for rec in fit_recs]))
        for (s, k, n, x, r), hp in zip(fit_recs, hps):
            hlo, hhi, _, _ = crossed_hier_boot(A, x)
            frozen_v = r1c_stats.classify_r1c(r, hp, hlo)
            sym_v = classify_sym(r, hp, hlo, hhi)
            rows.append(dict(
                group=f'{role}: {ts} {s} ({kind})',
                fit=k,
                margin=r['margin_pct'],
                ci90=(r['ci90_lo'], r['ci90_hi']),
                hier95=(hlo, hhi),
                holm_p=hp,
                frozen=frozen_v,
                sym=sym_v,
            ))

    # 2. R6a comparisons: RL-full vs GBT-full-ACK fits 1-4 (primary), and RL-full vs GBT-res-ACK fits 1-4 (secondary)
    A_r6 = get(P_r6, 'NR2', 'RL-full', r6_stats.SEEDS)
    for sup, role in [('GBT-full-ACK', 'R6a primary'), ('GBT-res-ACK', 'R6a secondary')]:
        names = [(k, f'{sup}-M1fit{k}') for k in r6_stats.FITS if get(P_r6, 'NR2', f'{sup}-M1fit{k}') is not None]
        if A_r6 is None or not names:
            continue
        check_pairing(P_r6, 'NR2', ['RL-full'] + [n for _, n in names])
        a = A_r6.mean(axis=0)
        fit_recs = []
        for k, n in names:
            x = get(P_r6, 'NR2', n)
            r = r1(a, x)
            fit_recs.append((k, n, x, r))
        hps = holm(np.array([rec[3]['p'] for rec in fit_recs]))
        for (k, n, x, r), hp in zip(fit_recs, hps):
            hlo, hhi, _, _ = crossed_hier_boot(A_r6, x)
            frozen_v = r6_stats.classify(r, hp, hlo)
            sym_v = classify_sym(r, hp, hlo, hhi)
            rows.append(dict(
                group=f'{role}: NR2 RL-full vs {sup}',
                fit=k,
                margin=r['margin_pct'],
                ci90=(r['ci90_lo'], r['ci90_hi']),
                hier95=(hlo, hhi),
                holm_p=hp,
                frozen=frozen_v,
                sym=sym_v,
            ))

    lines = [
        'S-SYM: Symmetric Seed-Level Check of Frozen R1c and R6a Verdicts (Amendment 13, Section 6)',
        'Frozen bootstrap shared-trace check:',
        '  nr2_stats.py:51-52: `si = rng.integers(0, S, S); ti = rng.integers(0, T, T)`',
        '                      `hb[b] = 100 * (A[np.ix_(si, ti)].mean() / c[ti].mean() - 1)`',
        '  Both r1c_stats.py:73 and r6_stats.py:74 call nr2_stats.seed_level(A, ...).',
        '  Answer: YES -- every frozen hierarchical bootstrap replicate used ONE shared trace-ID sample `ti` across all resampled RL seeds `si`.',
        '',
        'Comparison | Fit | Margin | 90% CI | 95% Hier CI | Holm p | Frozen Verdict | Symmetric Verdict | Agreement',
        '-' * 120,
    ]
    n_changed = 0
    for row in rows:
        agree = ((row['frozen'] == 'LOSES' and row['sym'] == 'SUP-BEATS') or
                 (row['frozen'] == 'BEATS' and row['sym'] == 'RL-BEATS') or
                 (row['frozen'] in ('INCONCLUSIVE', 'MATCH', 'BEATS-TRACE') and row['sym'] == 'INCONCLUSIVE'))
        if not agree:
            n_changed += 1
        lines.append(
            f"{row['group']} | fit={row['fit']} | {row['margin']:+.2f}% | "
            f"[{row['ci90'][0]:+.2f}, {row['ci90'][1]:+.2f}] | "
            f"[{row['hier95'][0]:+.2f}, {row['hier95'][1]:+.2f}] | "
            f"{row['holm_p']:.3g} | {row['frozen']} | {row['sym']} | {'YES' if agree else 'CHANGED'}"
        )
    lines.append('-' * 120)
    lines.append(f'Total comparisons checked: {len(rows)} | Directional verdict changes under symmetric rule: {n_changed}')

    out_path = os.path.join(outdir, 'ssym_summary.txt')
    text = '\n'.join(lines) + '\n'
    with open(out_path, 'w', encoding='utf-8') as fh:
        fh.write(text)
    print(text)


if __name__ == '__main__':
    main()
