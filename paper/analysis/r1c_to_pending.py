"""Turn the frozen R1c outputs into rows for paper/manuscript/pending_values.csv (item R1C).

Reads paper/analysis/out/r1c_summary.csv and r1c_verdicts.txt (written by the frozen r1c_stats.py) and writes
paper/analysis/out/r1c_pending_rows.csv; with --apply it replaces the R1C rows of pending_values.csv and sets
R1C to 'run' in pending_status.csv (line endings of both files are kept). The wording row of each scheme is
selected in the manuscript from the verdict key (\\wordingsel{R1Cres}{R1C}{verdict_res}{unrun}).
Run: python3 paper/analysis/r1c_to_pending.py [--apply]
"""
import csv, datetime, io, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
MS = os.path.join(ROOT, 'paper', 'manuscript')
SLUG = {'holds across all fits and both cells': 'holds', 'cells hold, fit-dependent': 'cellshold', 'depends on the calibration draw': 'draw',
        'replicates across fits, cell-dependent': 'celldep', 'operating-point dependent': 'oppoint', 'neither': 'neither', 'not run': 'unrun'}
SCH = {'GBT-res-ACK': 'res', 'GBT-full-ACK': 'full'}
TS = {'NR2': 'nrtwo', 'G2': 'gtwo', 'G3': 'gthree'}
CELLNAME = {'G2': 'G2', 'G3': 'G3'}

def rows():
    src = 'paper/analysis/out/r1c_summary.csv; r1c_verdicts.txt'; out = []
    add = lambda k, v: out.append(['R1C', k, v, src, datetime.date.today().isoformat()])
    txt = open(os.path.join(HERE, 'out', 'r1c_verdicts.txt'), encoding='utf-8').read()
    S = list(csv.DictReader(open(os.path.join(HERE, 'out', 'r1c_summary.csv'), newline='', encoding='utf-8')))
    for s, k in SCH.items():
        m = re.search(r'^' + re.escape(s) + r': (.+?) \| states', txt, re.M)
        if not m: raise SystemExit(f'no verdict for {s} in r1c_verdicts.txt')
        add(f'verdict_{k}', SLUG[m.group(1)])
        prim = {r['trace_set']: r for r in S if r['scheme'] == s and r['role'].startswith('primary')}
        hold = [c for c in ['G2', 'G3'] if c in prim and prim[c]['state'] == 'holds']
        fail = [c for c in ['G2', 'G3'] if c in prim and prim[c]['state'] != 'holds']
        add(f'cellhold_{k}', ', '.join(CELLNAME[c] for c in hold) or 'none'); add(f'cellfail_{k}', ', '.join(CELLNAME[c] for c in fail) or 'none')
        for r in S:
            if r['scheme'] != s: continue
            tag = TS[r['trace_set']] + ('tr' if r['role'].startswith('secondary') else '')
            add(f'state_{tag}_{k}', r['state']); add(f'mean_{tag}_{k}', f"{float(r['mean_ontime']):.4f}")
            add(f'min_{tag}_{k}', f"{float(r['min_ontime']):.4f}"); add(f'max_{tag}_{k}', f"{float(r['max_ontime']):.4f}")
            add(f'worstfit_{tag}_{k}', r['worst_fit']); add(f'worstmargin_{tag}_{k}', f"{float(r['worst_margin']):.2f}")
            add(f'worstout_{tag}_{k}', r['worst_outcome']); add(f'rl_{TS[r["trace_set"]]}', f"{float(r['rl_ontime']):.4f}")
    seen, uniq = set(), []
    for r in out:
        if r[1] not in seen: seen.add(r[1]); uniq.append(r)
    return uniq

def rewrite(path, keep, new, header):
    b = open(path, 'rb').read().decode('utf-8'); e = '\r\n' if '\r\n' in b else '\n'
    old = list(csv.reader(io.StringIO(b.replace('\r\n', '\n'))))
    body = [r for r in old[1:] if r and keep(r)] + new
    s = io.StringIO(); csv.writer(s, lineterminator='\n').writerows([old[0]] + body)
    open(path, 'wb').write(s.getvalue().replace('\n', e).encode('utf-8'))

if __name__ == '__main__':
    R = rows()
    with open(os.path.join(HERE, 'out', 'r1c_pending_rows.csv'), 'w', newline='') as fh:
        w = csv.writer(fh); w.writerow(['item', 'key', 'value', 'source_file', 'date']); w.writerows(R)
    print(f'{len(R)} R1C rows')
    if '--apply' in sys.argv:
        rewrite(os.path.join(MS, 'pending_values.csv'), lambda r: r[0] != 'R1C', R, None)
        rewrite(os.path.join(MS, 'pending_status.csv'), lambda r: r[0] != 'R1C', [['R1C', 'run']], None)
        print('applied to pending_values.csv and pending_status.csv')
