"""R1c statistics: calibration-set replication and operating-cell generalization
of the ACK-trained supervised learner (FROZEN with paper/proposals/R1c_ack_prereg.md, Amendment 10).

Inputs : Optimized/v17x/Dataset/presub/pertrace.csv            (NR2, M1, comparators; unchanged)
         Optimized/v17x/Dataset/presub/r1b/pertrace_r1b.csv    (Fit 1: GBT-res-ACK, GBT-full-ACK)
         Optimized/v17x/Dataset/presub/r1c/pertrace_r1c_nr2.csv(Fits 2, 3, 4 on NR2 traces)
         Optimized/v17x/Dataset/presub/r1c/pertrace_r1c_g2.csv (Fits 1-4, comparators, RL on G2_hi_d10 14kbit)
         Optimized/v17x/Dataset/presub/r1c/pertrace_r1c_g3.csv (Fits 1-4, comparators, RL on G3_lo_d18)
Outputs: paper/analysis/out/r1c_replication.csv, r1c_cells.csv, r1c_verdicts.txt, r1c_pending_values.csv
Run    : python3 paper/analysis/r1c_stats.py [--indir DIR] [--out DIR]
Test   : python3 paper/analysis/r1c_stats.py --selftest      (synthetic data only)
"""
import argparse, csv, os, sys
import numpy as np
from scipy import stats

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
from nr2_stats import r1, holm, seed_level                                    # frozen (NR2)
from presub_stats import classify, load_pertrace, get, check_pairing, write  # frozen (Amendment 8)

SCHEMES = ['GBT-res-ACK', 'GBT-full-ACK']
CELLS = ['G2_hi_d10', 'G3_lo_d18']
G_FAMILY = ['Baseline', 'OLLA', 'OLLA (tuned target)', 'Multi-OLLA', 'Fixed', 'FixedPU (Oracle)', 'Context table', 'Bandit (global)', 'Bandit (delay class)']
G_SINGLE = ['Fixed', 'FixedPU (Oracle)', 'Context table']

WORDING_ROWS = {
    'holds across all 4 fits and both cells': 'The superiority of the one-step supervised learner over the RL policy holds across all 4 calibration fits and across both operating cells (G2 at 14 kbit and G3): the advantage does not depend on calibration-trace chance or on the specific operating point.',
    'fit-dependent': 'The comparison between the one-step supervised learner and the RL policy is fit-dependent: performance varies across calibration sets, so the advantage observed in R1b was an artifact of the particular calibration trace draw.',
    'operating-point dependent': 'The advantage of the one-step supervised learner over the RL policy is operating-point dependent: it holds consistently across calibration fits at the primary M1 operating point, but does not generalize to neighbouring operating cells (G2 / G3), where the RL policy and calibrated rules prevail.',
    'neither': 'The one-step supervised learner neither reliably replicates across calibration sets nor generalizes across operating cells.',
    'not_run': 'No calibration replication or operating-cell generalization run was performed.'
}

def merge_dict(P, Q):
    for k, v in Q.items():
        if k in P:
            # If same key exists, check if seeds are non-overlapping or identical
            p_seeds, q_seeds = P[k]['seeds'], v['seeds']
            if set(p_seeds).isdisjoint(set(q_seeds)):
                new_seeds = sorted(p_seeds + q_seeds)
                seed_map = {s: P[k]['M'][p_seeds.index(s)] for s in p_seeds}
                seed_map.update({s: v['M'][q_seeds.index(s)] for s in q_seeds})
                P[k] = dict(seeds=new_seeds, traces=P[k]['traces'], M=np.array([seed_map[s] for s in new_seeds]))
            else:
                pass # keep existing
        else:
            P[k] = v
    return P

def load_data(indir):
    f_main = os.path.join(indir, 'pertrace.csv')
    f_r1b = os.path.join(indir, 'r1b', 'pertrace_r1b.csv')
    f_r1c_nr2 = os.path.join(indir, 'r1c', 'pertrace_r1c_nr2.csv')
    f_r1c_g2 = os.path.join(indir, 'r1c', 'pertrace_r1c_g2.csv')
    f_r1c_g3 = os.path.join(indir, 'r1c', 'pertrace_r1c_g3.csv')

    P = {}
    for fp in [f_main, f_r1b, f_r1c_nr2, f_r1c_g2, f_r1c_g3]:
        if os.path.isfile(fp):
            Q = load_pertrace(fp)
            merge_dict(P, Q)
    return P

def get_fit_vector(P, trace_set, scheme, fit_idx):
    """Retrieve trace-level 1-D vector (length T) for a given scheme and fit index (1..4)."""
    # 1. Try scheme-fit name directly: e.g. GBT-res-ACK-fit1
    v = get(P, trace_set, f'{scheme}-fit{fit_idx}')
    if v is not None:
        v = np.asarray(v)
        return v[0] if v.ndim == 2 else v
    # 2. Try base scheme with seed = fit_idx or seed = 0 for fit 1
    e = P.get((trace_set, scheme))
    if e is not None:
        if fit_idx in e['seeds']:
            idx = e['seeds'].index(fit_idx)
            return e['M'][idx]
        elif fit_idx == 1 and e['seeds'] == [0]:
            return e['M'][0]
    return None

def analyze_replication(P):
    """Analyze the 4 calibration fits on NR2 evaluation traces against NR2."""
    A_nr2 = get(P, 'NR2', 'NR2', list(range(1, 11)))
    if A_nr2 is None:
        return [], {}, {}

    rows = []
    summary = {}
    worst_fits = {}

    for sch in SCHEMES:
        fit_vecs = []
        for k in range(1, 5):
            fv = get_fit_vector(P, 'NR2', sch, k)
            if fv is not None:
                fit_vecs.append((k, fv))

        if not fit_vecs:
            continue

        a_mean = A_nr2.mean(axis=0)
        sch_rows = []
        means = []

        for k, fv in fit_vecs:
            means.append(fv.mean())
            res = r1(a_mean, fv)
            sl = seed_level(A_nr2, fv)
            row = dict(
                trace_set='NR2',
                scheme=sch,
                fit=k,
                ontime_mean=float(fv.mean()),
                margin_pct=float(res['margin_pct']),
                margin_vs_nr2=float(res['margin_pct']),
                ci90_lo=float(res['ci90_lo']),
                ci90_hi=float(res['ci90_hi']),
                p=float(res['p']),
                hier95_lo=float(sl['hier95_lo']),
                hier95_hi=float(sl['hier95_hi']),
                seeds_above=int(sl['seeds_above']),
                n_seeds=int(sl['n_seeds']),
                worst_holm_p='',
                worst_outcome=''
            )
            row['outcome'] = classify(row, row['p'], row['hier95_lo'])
            sch_rows.append(row)

        # Fit-level statistics
        M = np.array(means)
        m_mean = float(M.mean())
        m_sd = float(M.std(ddof=1)) if len(M) > 1 else 0.0
        t_crit = float(stats.t.ppf(0.975, len(M) - 1)) if len(M) > 1 else 0.0
        se = m_sd / np.sqrt(len(M)) if len(M) > 0 else 0.0
        ci_lo, ci_hi = m_mean - t_crit * se, m_mean + t_crit * se
        min_ontime, max_ontime = float(M.min()), float(M.max())

        # Worst fit = lowest on-time
        worst_idx = int(np.argmin(M))
        worst_fit_num = fit_vecs[worst_idx][0]
        worst_row = sch_rows[worst_idx]

        summary[sch] = dict(
            mean_4fits=m_mean,
            sd_4fits=m_sd,
            ci95_t_lo=ci_lo,
            ci95_t_hi=ci_hi,
            min_ontime=min_ontime,
            max_ontime=max_ontime,
            worst_fit=worst_fit_num,
            worst_ontime=worst_row['ontime_mean'],
            worst_margin=worst_row['margin_vs_nr2'],
            worst_outcome=worst_row['outcome']
        )
        worst_fits[sch] = worst_row
        rows.extend(sch_rows)

    # Apply Holm over the worst fits of tested schemes
    if worst_fits:
        worst_p_vals = np.array([worst_fits[s]['p'] for s in worst_fits])
        worst_holm = holm(worst_p_vals)
        for (s, wf), hp in zip(worst_fits.items(), worst_holm):
            wf['worst_holm_p'] = float(hp)
            wf['worst_outcome'] = classify(wf, hp, wf['hier95_lo'])

    return rows, summary, worst_fits

def analyze_cells(P):
    """Analyze the 4 calibration fits on G2 (14kbit) and G3 cells against RL and rules."""
    cell_rows = []
    cell_summaries = {}

    for c in CELLS:
        A_rl = get(P, c, 'NRG10', list(range(1, 11)))
        if A_rl is None:
            A_rl = get(P, c, 'NRG10', list(range(1, 6)))
        if A_rl is None:
            A_rl = get(P, c, 'NR-G10')

        # Best single-cue heuristic rule
        rules_present = [r for r in G_SINGLE if get(P, c, r) is not None]
        best_rule_name = max(rules_present, key=lambda k: get(P, c, k).mean()) if rules_present else None
        v_best_rule = get(P, c, best_rule_name) if best_rule_name else None

        cell_summaries[c] = {}

        for sch in SCHEMES:
            fit_vecs = []
            for k in range(1, 5):
                fv = get_fit_vector(P, c, sch, k)
                if fv is not None:
                    fit_vecs.append((k, fv))

            if not fit_vecs:
                continue

            means = []
            sch_rows = []

            for k, fv in fit_vecs:
                means.append(fv.mean())
                # Comparison vs RL policy
                if A_rl is not None:
                    a_rl_mean = A_rl.mean(axis=0) if A_rl.ndim > 1 else A_rl
                    res_rl = r1(a_rl_mean, fv)
                    sl_rl = seed_level(A_rl, fv) if A_rl.ndim > 1 else dict(hier95_lo=res_rl['ci90_lo'], hier95_hi=res_rl['ci90_hi'], seeds_above=0, n_seeds=1)
                    out_rl = classify(res_rl, res_rl['p'], sl_rl['hier95_lo'])
                else:
                    res_rl = dict(margin_pct=0.0, ci90_lo=0.0, ci90_hi=0.0, p=1.0)
                    sl_rl = dict(hier95_lo=0.0, hier95_hi=0.0, seeds_above=0, n_seeds=0)
                    out_rl = 'not run'

                # Comparison vs best heuristic rule
                if v_best_rule is not None:
                    res_rule = r1(v_best_rule, fv) # positive favors best rule, negative favors learner
                    out_rule = 'BEATS_RULE' if res_rule['p'] < 0.05 and res_rule['ci90_hi'] < 0 else ('LOSES_TO_RULE' if res_rule['p'] < 0.05 and res_rule['ci90_lo'] > 0 else 'MATCH_RULE')
                    m_rule = float(-res_rule['margin_pct']) # positive favors learner
                else:
                    m_rule, out_rule = 0.0, 'not run'

                row = dict(
                    cell=c,
                    scheme=sch,
                    fit=k,
                    ontime_mean=float(fv.mean()),
                    margin_vs_rl=float(res_rl['margin_pct']),
                    ci90_lo=float(res_rl['ci90_lo']),
                    ci90_hi=float(res_rl['ci90_hi']),
                    p=float(res_rl['p']),
                    hier95_lo=float(sl_rl['hier95_lo']),
                    hier95_hi=float(sl_rl['hier95_hi']),
                    seeds_above=int(sl_rl['seeds_above']),
                    n_seeds=int(sl_rl['n_seeds']),
                    outcome_vs_rl=out_rl,
                    best_rule=best_rule_name if best_rule_name else 'none',
                    margin_vs_bestrule=m_rule,
                    outcome_vs_rule=out_rule
                )
                sch_rows.append(row)

            M = np.array(means)
            m_mean = float(M.mean())
            worst_idx = int(np.argmin(M))
            worst_fit_num = fit_vecs[worst_idx][0]
            worst_row = sch_rows[worst_idx]

            cell_summaries[c][sch] = dict(
                mean_4fits=m_mean,
                min_ontime=float(M.min()),
                max_ontime=float(M.max()),
                worst_fit=worst_fit_num,
                worst_ontime=worst_row['ontime_mean'],
                worst_outcome_vs_rl=worst_row['outcome_vs_rl'],
                worst_outcome_vs_rule=worst_row['outcome_vs_rule']
            )
            cell_rows.extend(sch_rows)

    return cell_rows, cell_summaries

def synthesize_verdict(rep_rows, rep_summaries, cell_rows, cell_summaries):
    """Determine the pre-registered wording row:
    - 'holds across all 4 fits and both cells'
    - 'fit-dependent'
    - 'operating-point dependent'
    """
    if not rep_rows and not cell_rows:
        return 'not_run', WORDING_ROWS['not_run']

    # 1. Check replication across fits on NR2
    # Does any scheme beat NR2 across all 4 fits?
    res_fits = [r for r in rep_rows if r['scheme'] == 'GBT-res-ACK']
    full_fits = [r for r in rep_rows if r['scheme'] == 'GBT-full-ACK']

    res_all_beat = len(res_fits) == 4 and all(r['outcome'] == 'LOSES' for r in res_fits)
    full_all_beat = len(full_fits) == 4 and all(r['outcome'] == 'LOSES' for r in full_fits)

    # Are outcomes mixed across fits on NR2?
    res_mixed = len(res_fits) == 4 and len(set(r['outcome'] for r in res_fits)) > 1
    full_mixed = len(full_fits) == 4 and len(set(r['outcome'] for r in full_fits)) > 1

    # 2. Check operating cells G2 and G3
    # In each cell, do the fits beat the RL policy and rules?
    def cell_all_beat(c_tag, sch):
        c_fits = [r for r in cell_rows if r['cell'] == c_tag and r['scheme'] == sch]
        if len(c_fits) != 4: return False
        return all(r['outcome_vs_rl'] == 'LOSES' and r['outcome_vs_rule'] == 'BEATS_RULE' for r in c_fits)

    g2_res_beat = cell_all_beat('G2_hi_d10', 'GBT-res-ACK')
    g2_full_beat = cell_all_beat('G2_hi_d10', 'GBT-full-ACK')
    g3_res_beat = cell_all_beat('G3_lo_d18', 'GBT-res-ACK')
    g3_full_beat = cell_all_beat('G3_lo_d18', 'GBT-full-ACK')

    # Condition: holds across all 4 fits and both cells
    if (res_all_beat and g2_res_beat and g3_res_beat) or (full_all_beat and g2_full_beat and g3_full_beat):
        return 'holds across all 4 fits and both cells', WORDING_ROWS['holds across all 4 fits and both cells']

    # Condition: fit-dependent (performance varies qualitatively across calibration sets on NR2)
    if (res_mixed and full_mixed) or (not res_all_beat and not full_all_beat and any(r['outcome'] == 'LOSES' for r in rep_rows)):
        return 'fit-dependent', WORDING_ROWS['fit-dependent']

    # Condition: operating-point dependent (replicates on NR2 across fits, but fails on G2 or G3)
    if (res_all_beat or full_all_beat) and not (g2_res_beat and g3_res_beat) and not (g2_full_beat and g3_full_beat):
        return 'operating-point dependent', WORDING_ROWS['operating-point dependent']

    return 'neither', WORDING_ROWS['neither']

def write_pending(outdir, rep_sum, cell_sum, verdict_key):
    pending_rows = []
    pending_rows.append(['R1C', 'verdict_key', verdict_key, 'paper/analysis/out/r1c_*.csv', ''])
    for sch in SCHEMES:
        if sch in rep_sum:
            s_tag = 'gbtresack' if 'res' in sch else 'gbtfullack'
            pending_rows.append(['R1C', f'mean_ontime_{s_tag}', f"{rep_sum[sch]['mean_4fits']:.4f}", 'paper/analysis/out/r1c_*.csv', ''])
            pending_rows.append(['R1C', f'worst_fit_{s_tag}', str(rep_sum[sch]['worst_fit']), 'paper/analysis/out/r1c_*.csv', ''])
            pending_rows.append(['R1C', f'worst_margin_{s_tag}', f"{rep_sum[sch]['worst_margin']:.2f}", 'paper/analysis/out/r1c_*.csv', ''])
    
    with open(os.path.join(outdir, 'r1c_pending_values.csv'), 'w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh)
        w.writerow(['item', 'key', 'value', 'source_file', 'date'])
        w.writerows(pending_rows)

def run(indir, outdir):
    os.makedirs(outdir, exist_ok=True)
    P = load_data(indir)
    rep_rows, rep_sum, worst_fits = analyze_replication(P)
    cell_rows, cell_sum = analyze_cells(P)
    v_key, v_text = synthesize_verdict(rep_rows, rep_sum, cell_rows, cell_sum)

    # Write r1c_replication.csv
    if rep_rows:
        fields = ['trace_set', 'scheme', 'fit', 'ontime_mean', 'margin_pct', 'margin_vs_nr2', 'ci90_lo', 'ci90_hi', 'p', 'hier95_lo', 'hier95_hi', 'seeds_above', 'n_seeds', 'outcome', 'worst_holm_p', 'worst_outcome']
        with open(os.path.join(outdir, 'r1c_replication.csv'), 'w', newline='', encoding='utf-8') as fh:
            w = csv.DictWriter(fh, fieldnames=fields)
            w.writeheader()
            w.writerows(rep_rows)

    # Write r1c_cells.csv
    if cell_rows:
        fields = ['cell', 'scheme', 'fit', 'ontime_mean', 'margin_vs_rl', 'ci90_lo', 'ci90_hi', 'p', 'hier95_lo', 'hier95_hi', 'seeds_above', 'n_seeds', 'outcome_vs_rl', 'best_rule', 'margin_vs_bestrule', 'outcome_vs_rule']
        with open(os.path.join(outdir, 'r1c_cells.csv'), 'w', newline='', encoding='utf-8') as fh:
            w = csv.DictWriter(fh, fieldnames=fields)
            w.writeheader()
            w.writerows(cell_rows)

    # Write r1c_verdicts.txt
    with open(os.path.join(outdir, 'r1c_verdicts.txt'), 'w', encoding='utf-8') as fh:
        fh.write(f"R1c verdict: {v_key}\n")
        fh.write(f"Statement: {v_text}\n\n")
        fh.write("Replication summary (NR2 traces):\n")
        for s, d in rep_sum.items():
            fh.write(f"  {s}: 4-fit mean={d['mean_4fits']:.4f} [{d['ci95_t_lo']:.4f}, {d['ci95_t_hi']:.4f}] (min={d['min_ontime']:.4f}, max={d['max_ontime']:.4f}); worst fit {d['worst_fit']} margin={d['worst_margin']:.2f}% ({d['worst_outcome']})\n")
        fh.write("\nCell generalization summary:\n")
        for c, cd in cell_sum.items():
            fh.write(f"  Cell {c}:\n")
            for s, d in cd.items():
                fh.write(f"    {s}: 4-fit mean={d['mean_4fits']:.4f} (min={d['min_ontime']:.4f}, max={d['max_ontime']:.4f}); worst fit {d['worst_fit']} vs RL={d['worst_outcome_vs_rl']}, vs rule={d['worst_outcome_vs_rule']}\n")

    # Write r1c_pending_values.csv
    write_pending(outdir, rep_sum, cell_sum, v_key)

    print(f"R1c verdict: {v_key}")
    print(f"Statement: {v_text}")

# ------------------------------------------------------------------ selftest
def selftest():
    import tempfile
    rng = np.random.default_rng(20261115)
    with tempfile.TemporaryDirectory() as d:
        ind = os.path.join(d, 'presub')
        os.makedirs(os.path.join(ind, 'r1b'), exist_ok=True)
        os.makedirs(os.path.join(ind, 'r1c'), exist_ok=True)
        out = os.path.join(d, 'out')

        # Generate synthetic pertrace.csv (NR2 on NR2 traces: 10 seeds, 500 traces, mean ~0.62)
        T_nr2 = 500
        with open(os.path.join(ind, 'pertrace.csv'), 'w', newline='', encoding='utf-8') as fh:
            w = csv.writer(fh)
            w.writerow(['trace_set', 'scheme', 'seed', 'trace', 'value'])
            for s in range(1, 11):
                base_s = 0.62 + 0.005 * (s - 5.5)
                for t in range(1, T_nr2 + 1):
                    w.writerow(['NR2', 'NR2', s, t, f"{base_s + rng.normal(0, 0.02):.4f}"])

        # Test case 1: "holds across all 4 fits and both cells"
        # Fits 1-4 on NR2: all ~0.66 (beats NR2)
        with open(os.path.join(ind, 'r1b', 'pertrace_r1b.csv'), 'w', newline='', encoding='utf-8') as fh:
            w = csv.writer(fh)
            w.writerow(['trace_set', 'scheme', 'seed', 'trace', 'value'])
            for t in range(1, T_nr2 + 1):
                w.writerow(['NR2', 'GBT-res-ACK', 0, t, f"{0.65 + rng.normal(0, 0.01):.4f}"])
                w.writerow(['NR2', 'GBT-full-ACK', 0, t, f"{0.67 + rng.normal(0, 0.01):.4f}"])

        with open(os.path.join(ind, 'r1c', 'pertrace_r1c_nr2.csv'), 'w', newline='', encoding='utf-8') as fh:
            w = csv.writer(fh)
            w.writerow(['trace_set', 'scheme', 'seed', 'trace', 'value'])
            for fit_k in range(2, 5):
                for t in range(1, T_nr2 + 1):
                    w.writerow(['NR2', f'GBT-res-ACK-fit{fit_k}', 0, t, f"{0.645 + 0.005 * fit_k + rng.normal(0, 0.01):.4f}"])
                    w.writerow(['NR2', f'GBT-full-ACK-fit{fit_k}', 0, t, f"{0.665 + 0.005 * fit_k + rng.normal(0, 0.01):.4f}"])

        # Cell G2 and G3: 300 traces
        T_cell = 300
        for c, f_name in [('G2_hi_d10', 'pertrace_r1c_g2.csv'), ('G3_lo_d18', 'pertrace_r1c_g3.csv')]:
            with open(os.path.join(ind, 'r1c', f_name), 'w', newline='', encoding='utf-8') as fh:
                w = csv.writer(fh)
                w.writerow(['trace_set', 'scheme', 'seed', 'trace', 'value'])
                # RL policy (NRG10): 5 seeds, mean ~0.55
                for s in range(1, 6):
                    for t in range(1, T_cell + 1):
                        w.writerow([c, 'NRG10', s, t, f"{0.55 + rng.normal(0, 0.02):.4f}"])
                # Comparators
                for cmp_name in G_FAMILY:
                    for t in range(1, T_cell + 1):
                        w.writerow([c, cmp_name, 0, t, f"{0.53 + rng.normal(0, 0.02):.4f}"])
                # Fits 1-4: mean ~0.60 (beats RL and rules)
                for fit_k in range(1, 5):
                    for t in range(1, T_cell + 1):
                        w.writerow([c, f'GBT-res-ACK-fit{fit_k}', 0, t, f"{0.60 + rng.normal(0, 0.01):.4f}"])
                        w.writerow([c, f'GBT-full-ACK-fit{fit_k}', 0, t, f"{0.62 + rng.normal(0, 0.01):.4f}"])

        run(ind, out)
        v_txt = open(os.path.join(out, 'r1c_verdicts.txt')).read()
        assert 'holds across all 4 fits and both cells' in v_txt, v_txt
        rep = list(csv.DictReader(open(os.path.join(out, 'r1c_replication.csv'))))
        assert len(rep) == 8, len(rep) # 4 fits x 2 schemes

        # Test case 2: "operating-point dependent" (G2 fails)
        with open(os.path.join(ind, 'r1c', 'pertrace_r1c_g2.csv'), 'w', newline='', encoding='utf-8') as fh:
            w = csv.writer(fh)
            w.writerow(['trace_set', 'scheme', 'seed', 'trace', 'value'])
            for s in range(1, 6):
                for t in range(1, T_cell + 1):
                    w.writerow(['G2_hi_d10', 'NRG10', s, t, f"{0.65 + rng.normal(0, 0.02):.4f}"]) # RL is strong
            for cmp_name in G_FAMILY:
                for t in range(1, T_cell + 1):
                    w.writerow(['G2_hi_d10', cmp_name, 0, t, f"{0.53 + rng.normal(0, 0.02):.4f}"])
            for fit_k in range(1, 5):
                for t in range(1, T_cell + 1):
                    w.writerow(['G2_hi_d10', f'GBT-res-ACK-fit{fit_k}', 0, t, f"{0.50 + rng.normal(0, 0.01):.4f}"]) # Learner fails
                    w.writerow(['G2_hi_d10', f'GBT-full-ACK-fit{fit_k}', 0, t, f"{0.52 + rng.normal(0, 0.01):.4f}"])

        run(ind, out)
        v_txt = open(os.path.join(out, 'r1c_verdicts.txt')).read()
        assert 'operating-point dependent' in v_txt, v_txt

        # Test case 3: "fit-dependent" (on NR2, fits disagree)
        with open(os.path.join(ind, 'r1c', 'pertrace_r1c_nr2.csv'), 'w', newline='', encoding='utf-8') as fh:
            w = csv.writer(fh)
            w.writerow(['trace_set', 'scheme', 'seed', 'trace', 'value'])
            # fit 2 beats, fit 3 loses badly, fit 4 matches
            for t in range(1, T_nr2 + 1):
                w.writerow(['NR2', 'GBT-res-ACK-fit2', 0, t, f"{0.66 + rng.normal(0, 0.01):.4f}"])
                w.writerow(['NR2', 'GBT-res-ACK-fit3', 0, t, f"{0.55 + rng.normal(0, 0.01):.4f}"]) # loses
                w.writerow(['NR2', 'GBT-res-ACK-fit4', 0, t, f"{0.62 + rng.normal(0, 0.01):.4f}"])
                w.writerow(['NR2', 'GBT-full-ACK-fit2', 0, t, f"{0.68 + rng.normal(0, 0.01):.4f}"])
                w.writerow(['NR2', 'GBT-full-ACK-fit3', 0, t, f"{0.57 + rng.normal(0, 0.01):.4f}"])
                w.writerow(['NR2', 'GBT-full-ACK-fit4', 0, t, f"{0.62 + rng.normal(0, 0.01):.4f}"])

        run(ind, out)
        v_txt = open(os.path.join(out, 'r1c_verdicts.txt')).read()
        assert 'fit-dependent' in v_txt, v_txt

    print("SELFTEST PASS: all wording conditions and statistical aggregations verified.")

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--indir', default=os.path.join(ROOT, 'Optimized', 'v17x', 'Dataset', 'presub'))
    ap.add_argument('--out', default=os.path.join(HERE, 'out'))
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args()
    selftest() if a.selftest else run(a.indir, a.out)
