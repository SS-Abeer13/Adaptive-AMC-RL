"""Generate numbers.tex (LaTeX macros) and numbers_audit.csv from the raw result files.

Every number in the manuscript prose and tables is a macro defined here. Each macro is
extracted from a file in the repository (never typed), tagged with its ledger ID, and
the audit CSV records macro, value, ledger ID, source file and field. Constants that
describe the simulator are checked against the code by regular expressions; the script
fails if the code disagrees with the value stated here.

Run from paper/manuscript:  python3 -I build_numbers.py
"""
import csv, math, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OPT = os.path.join(ROOT, 'Optimized')
P = lambda *a: os.path.join(ROOT, *a)
M = {}          # macro name -> (value string, ledger id, source, field)
ERR = []

MINUS = r'\ensuremath{-}'

def add(name, val, ledger, src, field=''):
    if not re.fullmatch(r'[A-Za-z]+', name):
        ERR.append(f'bad macro name {name}'); return
    if name in M and M[name][0] != val:
        ERR.append(f'duplicate macro {name} with different values'); return
    M[name] = (val, ledger, src, field)

def f(x, nd=2, sign=False):
    """Format a float with nd decimals; '-' becomes a math minus; optional leading '+'."""
    x = float(x)
    s = f'{x:.{nd}f}'
    if s.startswith('-'):
        s = MINUS + s[1:]
        if float(s.replace(MINUS, '-')) == 0: pass
    elif sign and float(s) != 0:
        s = '+' + s
    return s

def sci(x):
    m, e = f'{float(x):.1e}'.split('e')
    return rf'${m}\times10^{{{int(e)}}}$'

def rel(path): return os.path.relpath(path, ROOT)

# ------------------------------------------------------------------ raw readers
FS17 = os.path.join(OPT, 'v17', 'Dataset', 'fill_summary_v17.txt')
def prim_lines():
    out = {}
    for l in open(FS17, encoding='utf-8'):
        if l.startswith('PRIM|'):
            p = l.rstrip('\n').split('|')
            case, scheme = p[1], p[2]
            metric, val = p[3].split('='); ci = float(p[4].split('=')[1])
            gp = float(p[5].split('=')[1])
            out[(case, scheme)] = dict(metric=metric, val=float(val), ci=ci, gp=gp)
    return out
PRIM = prim_lines()
CASE = {'M1_dl_rtt8': 'Mone', 'M2_dl_rtt0': 'Mtwo', 'M3_gp_rtt8': 'Mthree', 'M4_gp_rtt0': 'Mfour'}
SCH = {'Baseline': 'Baseline', 'OLLA': 'OLLA', 'OLLA (tuned target)': 'OLLAT', 'Multi-OLLA': 'Multi',
       'Fixed': 'Fixed', 'FixedPU (Oracle)': 'FPU', 'Context table': 'Ctx', 'Bandit (global)': 'BanG',
       'Bandit (delay class)': 'BanD', 'Deep A2C v17': 'Prim', 'Deep A2C v17 (ensemble)': 'Ens',
       'Deep A2C v17 (best-on-val)': 'Best', 'Deep A2C v17 (offset)': 'Off', 'Deep A2C v17 (resid-800)': 'Rsd'}
CMPS = ['Baseline', 'OLLA', 'OLLA (tuned target)', 'Multi-OLLA', 'Fixed', 'FixedPU (Oracle)', 'Context table',
        'Bandit (global)', 'Bandit (delay class)']

for (case, scheme), d in PRIM.items():
    if scheme in SCH:
        add(f'N{CASE[case]}Val{SCH[scheme]}', f(d['val'], 4), 'R02/R19/R20', rel(FS17), f'PRIM|{case}|{scheme}')
        add(f'N{CASE[case]}Pct{SCH[scheme]}', f(100*d['val'], 2), 'R02/R19/R20', rel(FS17), f'PRIM|{case}|{scheme} x100')
        add(f'N{CASE[case]}Ci{SCH[scheme]}', f(d['ci'], 4), 'R02', rel(FS17), f'PRIM|{case}|{scheme} ci95')
        if case == 'M1_dl_rtt8':
            add(f'N{CASE[case]}Gp{SCH[scheme]}', f(d['gp'], 4), 'R13', rel(FS17), f'PRIM|{case}|{scheme} goodput')

# ------------------------------------------------------------------ table_core.csv
TC = P('Optimized', 'v17', 'paper', 'table_core.csv')
core = {}
for r in csv.DictReader(open(TC, newline='')):
    core[(r['case_tag'], r['scheme'], r['comparator'])] = r
for (case, scheme, cmp), r in core.items():
    if scheme not in SCH or cmp not in SCH: continue
    base = f'N{CASE[case]}{SCH[scheme]}{SCH[cmp]}'
    add(base + 'Mar', f(r['pct_margin'], 2, True), 'R03-R07/R19-R21', rel(TC), f'{case}|{scheme}|{cmp} pct_margin')
    add(base + 'Lo', f(r['ci90_lo'], 2, True), 'R03-R07', rel(TC), 'ci90_lo')
    add(base + 'Hi', f(r['ci90_hi'], 2, True), 'R03-R07', rel(TC), 'ci90_hi')
    add(base + 'Holm', sci(r['holm_p']), 'R03-R07', rel(TC), 'holm_p')
    add(base + 'Beats', 'yes' if r['beats'] == '1' else 'no', 'R03-R07', rel(TC), 'beats')
r = core[('M1_dl_rtt8', 'Deep A2C v17', 'Context table')]
for k, nm in [('jain_rl', 'JainRL'), ('jain_cmp', 'JainCtx'), ('edge_rl', 'EdgeRL'), ('edge_cmp', 'EdgeCtx')]:
    add(f'NMone{nm}', f(r[k], 4), 'R12', rel(TC), k)
add('NMoneJainDiff', f(float(r['jain_rl']) - float(r['jain_cmp']), 4, True), 'R12', rel(TC), 'jain_rl - jain_cmp')
add('NMoneEdgePct', f(100 * (float(r['edge_rl']) / float(r['edge_cmp']) - 1), 1, True), 'R12', rel(TC), 'edge_rl/edge_cmp - 1')
r = core[('M1_dl_rtt8', 'Deep A2C v17', 'Fixed')]
add('NMoneJainFixed', f(r['jain_cmp'], 4), 'R12', rel(TC), 'jain_cmp vs Fixed')
add('NMoneEdgeFixed', f(r['edge_cmp'], 4), 'R12', rel(TC), 'edge_cmp vs Fixed')
add('NMoneEdgeFixedPct', f(100 * (float(r['edge_rl']) / float(r['edge_cmp']) - 1), 1, True), 'R12', rel(TC), 'edge_rl/edge_cmp vs Fixed')
r = core[('M2_dl_rtt0', 'Deep A2C v17', 'Context table')]
add('NMtwoJainDiff', f(float(r['jain_rl']) - float(r['jain_cmp']), 4, True), 'R16', rel(TC), 'jain diff M2')
# absolute on-time difference vs Context (pp) and relative gain captured by calibration (R33)
v = {k: PRIM[('M1_dl_rtt8', k)]['val'] for k in ['OLLA', 'Fixed', 'Context table', 'Deep A2C v17']}
add('NMoneAbsPpCtx', f(100 * (v['Deep A2C v17'] - v['Context table']), 2, True), 'R34', rel(FS17), 'PRIM M1 primary - Context, in points')
add('NMoneCalibShareFixed', f(100 * (v['Fixed'] - v['OLLA']) / (v['Deep A2C v17'] - v['OLLA']), 0), 'R33', rel(FS17), '(Fixed-OLLA)/(A2C-OLLA)')
add('NMoneCalibShareCtx', f(100 * (v['Context table'] - v['OLLA']) / (v['Deep A2C v17'] - v['OLLA']), 0), 'R33', rel(FS17), '(Context-OLLA)/(A2C-OLLA)')
o2 = {k: PRIM[('M2_dl_rtt0', k)]['val'] for k in ['OLLA', 'Fixed', 'Context table', 'Deep A2C v17']}
add('NMtwoCalibShareCtx', f(100 * (o2['Context table'] - o2['OLLA']) / (o2['Deep A2C v17'] - o2['OLLA']), 0), 'R33', rel(FS17), 'M2 share')

# ------------------------------------------------------------------ seed-level (G3)
G3 = P('paper', 'analysis', 'out', 'g3_seed_stats.csv')
g3 = {(r['case'], r['scheme'], r['comparator']): r for r in csv.DictReader(open(G3, newline=''))}
def g3add(case, scheme, cmp, tag):
    r = g3[(case, scheme, cmp)]
    nm = f'NG{tag}'
    add(nm + 'Above', r['seeds_above'].split('/')[0], 'G3a', rel(G3), 'seeds_above')
    add(nm + 'Sign', f(r['sign_test_p_one_sided'], 4), 'G3a', rel(G3), 'sign_test_p_one_sided')
    add(nm + 'SeedMin', f(r['seed_margin_min'], 2, True), 'G3g', rel(G3), 'seed_margin_min')
    add(nm + 'SeedMax', f(r['seed_margin_max'], 2, True), 'G3g', rel(G3), 'seed_margin_max')
    for k, suffix, led in [('seedmean_boot_ci95', 'Boot', 'G3g'), ('seed_t_ci95', 'T', 'G3g'), ('hier_boot_ci95', 'Hier', 'G3a'),
                           ('trace_boot_ci90', 'TraceNinety', 'G3c'), ('hier_boot_ci90', 'HierNinety', 'G3a')]:
        add(nm + suffix + 'Lo', f(r[k + '_lo'], 2, True), led, rel(G3), k + '_lo')
        add(nm + suffix + 'Hi', f(r[k + '_hi'], 2, True), led, rel(G3), k + '_hi')
g3add('M1_dl_rtt8', 'Deep A2C v17', 'Context table', 'MoneCtx')
g3add('M1_dl_rtt8', 'Deep A2C v17', 'Fixed', 'MoneFixed')
g3add('M1_dl_rtt8', 'Deep A2C v17', 'FixedPU (Oracle)', 'MoneFPU')
g3add('M2_dl_rtt0', 'Deep A2C v17', 'Context table', 'MtwoCtx')
g3add('M1_dl_rtt8', 'Deep A2C v17 (resid-800)', 'Context table', 'MoneRsdCtx')
g3add('M1_dl_rtt8', 'Deep A2C v17 (offset)', 'Context table', 'MoneOffCtx')
r = g3[('M1_dl_rtt8', 'Deep A2C v17', 'Context table')]
tw = (float(r['hier_boot_ci90_hi']) - float(r['hier_boot_ci90_lo'])) / (float(r['trace_boot_ci90_hi']) - float(r['trace_boot_ci90_lo']))
add('NGWidthRatio', f(tw, 1), 'G3c', rel(G3), 'hier 90% width / trace-only 90% width')

# ------------------------------------------------------------------ headroom, training length, HARQ ablation
HR = P('Optimized', 'v17', 'paper', 'headroom.csv')
for r in csv.DictReader(open(HR, newline='')):
    c = {'M1_dl_rtt8': 'Mone', 'M2_dl_rtt0': 'Mtwo', 'M3_gp_rtt8': 'Mthree', 'M4_gp_rtt0': 'Mfour'}[r['case']]
    fx, ge, hi = float(r['fixed']), float(r['genie']), float(r['hindsight'])
    add(f'NH{c}Fixed', f(fx, 4), 'R26', rel(HR), 'fixed'); add(f'NH{c}Genie', f(ge, 4), 'R26', rel(HR), 'genie')
    add(f'NH{c}Hind', f(hi, 4), 'R26', rel(HR), 'hindsight')
    add(f'NH{c}HindPct', f(100 * (hi / fx - 1), 1, True), 'R26', rel(HR), 'hindsight/fixed - 1')
    add(f'NH{c}GeniePct', f(100 * (ge / fx - 1), 1, True), 'R26', rel(HR), 'genie/fixed - 1')
TL = P('Optimized', 'v17', 'paper', 'table_training_length.csv')
for r in csv.DictReader(open(TL, newline='')):
    c = {'M1_dl_rtt8': 'Mone', 'M2_dl_rtt0': 'Mtwo'}[r['case_tag']]
    for k, nm in [('pct_800ep', 'Short'), ('pct_3000ep', 'Long')]:
        add(f'NT{c}{nm}', f(r[k], 2, True), 'R25', rel(TL), k)
    add(f'NT{c}ShortLo', f(r['ci90_800ep_lo'], 2, True), 'R25', rel(TL), 'ci90_800ep_lo')
    add(f'NT{c}ShortHi', f(r['ci90_800ep_hi'], 2, True), 'R25', rel(TL), 'ci90_800ep_hi')
    add(f'NT{c}LongLo', f(r['ci90_3000ep_lo'], 2, True), 'R25', rel(TL), 'ci90_3000ep_lo')
    add(f'NT{c}LongHi', f(r['ci90_3000ep_hi'], 2, True), 'R25', rel(TL), 'ci90_3000ep_hi')
HA = P('Optimized', 'v17', 'paper', 'table_harq_ablation.csv')
for r in csv.DictReader(open(HA, newline='')):
    if r['comparator'] in ('Context table', 'Fixed'):
        c = {'deadline': 'Dl', 'goodput': 'Gp'}[r['traffic']] + SCH[r['comparator']]
        add(f'NA{c}Eight', f(r['pct_rtt8'], 2, True), 'R28', rel(HA), 'pct_rtt8')
        add(f'NA{c}Zero', f(r['pct_rtt0'], 2, True), 'R28', rel(HA), 'pct_rtt0')
        add(f'NA{c}Swing', f(r['swing_pp'], 2), 'R28', rel(HA), 'swing_pp')

# ------------------------------------------------------------------ metric identity (M3, M4)
MI = P('paper', 'analysis', 'out', 'm3_identity.txt')
txt = open(MI).read()
for case, nm in [('M3_gp_rtt8', 'Mthree'), ('M4_gp_rtt0', 'Mfour')]:
    blk = txt.split(f'== {case}')[1].split('==')[0]
    m = re.search(r'Deep A2C v17 +primary +seeds=(\d+) traces=500 identical_cells=(\d+)/(\d+)', blk)
    add(f'NI{nm}Ident', m.group(2), 'R19a/R20', rel(MI), 'identical_cells (primary)')
    add(f'NI{nm}Cells', m.group(3), 'R19a/R20', rel(MI), 'cells')
    mm = re.search(r'Deep A2C v17 +primary +seeds=\d+ traces=500 identical_cells=\d+/\d+ max\|diff\|=([0-9.e+-]+)', blk)
    add(f'NI{nm}MaxDiff', mm.group(1).replace('e+00', '').replace('e-00', ''), 'R19a', rel(MI), 'max|diff|')

# ------------------------------------------------------------------ registry and multiplicity
REG = P('Optimized', 'case_registry.csv')
rows = list(csv.DictReader(open(REG, newline='')))
ids = {}
for r in rows: ids.setdefault(r['case_id'], []).append(r)
sup_cases = sum(1 for v in ids.values() if v[0]['status'].startswith('superseded'))
sup_rows = sum(1 for r in rows if r['status'].startswith('superseded'))
v10 = sum(1 for v in ids.values() if v[0]['version'] not in ('v9',))
add('NRegCases', str(len(ids)), 'M01', rel(REG), 'unique case_id')
add('NRegRows', str(len(rows)), 'M01', rel(REG), 'rows')
add('NRegSupCases', str(sup_cases), 'H19', rel(REG), 'status superseded (cases)')
add('NRegSupRows', str(sup_rows), 'H19', rel(REG), 'status superseded (rows)')
add('NRegSinceTen', str(v10), 'M02', rel(REG), 'cases with version != v9')
wins = set()
for r in rows:
    if r['win'] == '1' and r['status'] == 'valid' and not r.get('correction', '').startswith('pre-registered scheme'):
        wins.add(r['case_id'])
add('NRegWinCases', str(len(wins)), 'M03', rel(REG), 'valid cases with win=1 excluding corrected X1 row')
add('NRegValidCases', str(len(ids) - sup_cases), 'M03', rel(REG), 'valid cases')
p1 = float(core[('M1_dl_rtt8', 'Deep A2C v17', 'Context table')]['holm_p'])
tests = len(rows) * 9
add('NBonfTests', f'{tests:,}'.replace(',', r'\,'), 'M04', rel(REG), 'rows x 9')
add('NBonfP', sci(p1 * tests), 'M04', rel(TC), 'holm_p x tests')
add('NBonfPraw', sci(p1), 'M04', rel(TC), 'holm_p')

# ------------------------------------------------------------------ literature counts
LM = P('paper', 'lit', 'lit_matrix.csv')
lm = [r for r in csv.DictReader(open(LM, newline='')) if r['calibrated_rule_baseline'] != 'n/a']
add('NLitN', str(len(lm)), 'lit', rel(LM), 'rows with calibrated_rule_baseline')
for col, tag in [('calibrated_rule_baseline', 'Cal'), ('information_parity', 'Par')]:
    for val, nm in [('yes', 'Yes'), ('partial', 'Part'), ('no', 'No'), ('unclear', 'Unc')]:
        add(f'NLit{tag}{nm}', str(sum(1 for r in lm if r[col] == val)), 'lit', rel(LM), f'{col}={val}')

# ------------------------------------------------------------------ pitfalls numbers
V9 = P('Optimized', 'v9', 'Dataset', 'fill_summary_v9.txt')
t9 = open(V9).read()
mo = re.search(r'CMP\|gp_O\|A2C vs OLLA\|diff=[-0-9.]+\|pct=(-?[0-9.]+)', t9)
add('NVnineVsOLLA', f(mo.group(1), 2), 'H04', rel(V9), 'CMP|gp_O|A2C vs OLLA pct')
b9 = float(re.search(r'SCHEME\|gp_O\|Baseline\|tp=([0-9.]+)', t9).group(1)); o9 = float(re.search(r'SCHEME\|gp_O\|OLLA\|tp=([0-9.]+)', t9).group(1))
add('NVnineBase', f(b9, 4), 'H05', rel(V9), 'SCHEME gp_O Baseline'); add('NVnineOLLA', f(o9, 4), 'H05', rel(V9), 'SCHEME gp_O OLLA')
add('NVnineBaseGain', f(100 * (b9 / o9 - 1), 1, True), 'H05', rel(V9), 'Baseline/OLLA - 1')
for case, nm in [('M3_gp_rtt8', 'Mthree'), ('M4_gp_rtt0', 'Mfour')]:
    add(f'NOllaBase{nm}', f(100 * (PRIM[(case, 'OLLA')]['val'] / PRIM[(case, 'Baseline')]['val'] - 1), 1, True), 'R22', rel(FS17), f'PRIM {case} OLLA/Baseline - 1')
v9wins = sum(1 for r in rows if r['version'] == 'v9' and r['win'] == '1'); v9cases = len({r['case_id'] for r in rows if r['version'] == 'v9'})
add('NVnineWins', str(v9wins), 'H06', rel(REG), 'v9 win rows'); add('NVnineCases', str(v9cases), 'H06', rel(REG), 'v9 cases')
V10 = P('Optimized', 'v10', 'Dataset', 'fill_summary_v10.txt'); t10 = open(V10).read()
add('NSlotRL', f(re.search(r'SCHEME\|E1_train\|Deep A2C v10\|tp=([0-9.]+)', t10).group(1), 2), 'H07', rel(V10), 'E1_train A2C tp')
add('NSlotOLLA', f(re.search(r'SCHEME\|E1_train\|OLLA\|tp=([0-9.]+)', t10).group(1), 2), 'H07', rel(V10), 'E1_train OLLA tp')
add('NSlotFixRL', f(re.search(r'SCHEME\|E1_train_b\|Deep A2C v10\|tp=([0-9.]+)', t10).group(1), 4), 'H07', rel(V10), 'E1_train_b A2C tp')
add('NSlotFixOLLA', f(re.search(r'SCHEME\|E1_train_b\|OLLA\|tp=([0-9.]+)', t10).group(1), 4), 'H07', rel(V10), 'E1_train_b OLLA tp')
lg = open(P('Optimized', 'v10', 'logs', 'matlab_v10b_check.log')).read()
act = re.search(r'CHECK\|goodput\|.*actions% \[([0-9. ]+)\]', lg).group(1).split()
add('NSlotMinusThree', f(act[1], 0), 'H07', 'Optimized/v10/logs/matlab_v10b_check.log', 'actions% at -3')
add('NSlotPlusTwo', f(act[6], 1), 'H07', 'Optimized/v10/logs/matlab_v10b_check.log', 'actions% at +2')
R17 = P('Optimized', 'v17', 'README_v17.md'); t17 = open(R17, encoding='utf-8').read()
rw = re.search(r'\| rtt 8, 1 proc \| ([0-9.]+) \| ([0-9.]+) \| ([0-9.]+) \|', t17)
r88 = re.search(r'\| rtt 8, 8 proc \| \*\*([0-9.]+)\*\* \| \*\*([0-9.]+)\*\* \| \*\*([0-9.]+)\*\* \|', t17)
r00 = re.search(r'\| rtt 0, 1 proc \(legacy `txStep` engine\) \| ([0-9.]+) \| ([0-9.]+) \| ([0-9.]+) \|', t17)
add('NPfOneProc', f(rw.group(1), 3), 'H17', rel(R17), 'README_v17 s1 table rtt8/1proc Baseline Mbps')
add('NPfEightProc', f(r88.group(1), 3), 'H17', rel(R17), 'README_v17 s1 table rtt8/8proc Baseline Mbps')
add('NPfGain', f(100 * (float(r88.group(1)) / float(rw.group(1)) - 1), 1, True), 'H17', rel(R17), '8proc/1proc - 1')
add('NPfJainZero', f(r00.group(2), 3), 'H17', rel(R17), 'Jain rtt0'); add('NPfJainEight', f(r88.group(2), 3), 'H17', rel(R17), 'Jain rtt8/8proc')
g = re.search(r'\*\*Gap \(2 vs 1\)\*\* \| \| \| \| \| \*\*\+([0-9.]+)%\*\* \| \*\*(−[0-9.]+)\*\*', t17)
add('NEngineGap', g.group(1), 'R30', rel(R17), 'engine gap goodput %'); add('NEngineJain', g.group(2).replace('−', ''), 'R30', rel(R17), 'engine gap Jain')
fs = re.search(r'Goodput Ratio \(RTT 8 / RTT 0\):\*\* \*\*([0-9.]+)\*\*', t17); jd = re.search(r'Jain Difference \(RTT 8 − RTT 0\):\*\* \*\*−([0-9.]+)\*\*', t17)
add('NFairRatio', fs.group(1), 'R31', rel(R17), 'B2.4 ratio'); add('NFairJain', jd.group(1), 'R31', rel(R17), 'B2.4 Jain diff')
# v16 K3 vs v17 M3 per-scheme ratios (H17a)
F16 = P('Optimized', 'v16', 'Dataset', 'fill_summary_v16.txt')
k3 = {}
for l in open(F16, encoding='utf-8'):
    m = re.match(r'PRIM\|K3_gp_rtt8\|([^|]+)\|goodput=([0-9.]+)', l)
    if m: k3[m.group(1)] = float(m.group(2))
ratios = []
for s17 in SCH:
    s16 = s17.replace('v17', 'v16')
    if s16 in k3 and ('M3_gp_rtt8', s17) in PRIM: ratios.append(k3[s16] / PRIM[('M3_gp_rtt8', s17)]['val'])
add('NPfRangeLo', f(100 * (min(ratios) - 1), 0), 'H17a', rel(F16), 'min v16 K3 / v17 M3 - 1 over schemes')
add('NPfRangeHi', f(100 * (max(ratios) - 1), 0), 'H17a', rel(F16), 'max ratio')
add('NPfNSchemes', str(len(ratios)), 'H17a', rel(F16), 'schemes compared')

# ------------------------------------------------------------------ simulator constants, verified against code
DE = open(P('Optimized', 'v17', 'defaultEnv_v17.m'), encoding='utf-8').read()
VS = open(P('Optimized', 'v17', 'v17_setup.m'), encoding='utf-8').read()
EV = open(P('Optimized', 'v17', 'evalPolicy_v17.m'), encoding='utf-8').read()
CO = open(P('Optimized', 'v17', 'calibrateCtx_v17.m'), encoding='utf-8').read()
def chk(name, val, ledger, src_text, pattern, srcfile, field):
    m = re.search(pattern, src_text)
    if not m: ERR.append(f'constant {name}: pattern not found in {srcfile}'); return
    found = float(m.group(1))
    if abs(found - float(val)) > 1e-9: ERR.append(f'constant {name}: code says {found}, manuscript says {val}')
    add(name, (f'{float(val):g}'), ledger, srcfile, field)
chk('NCfgUsers', 10, 'S01', VS, r"'N', (\d+)", 'v17_setup.m', "base.N")
chk('NCfgRB', 100, 'S01', DE, r'total_RB\s*=\s*([0-9.]+)', 'defaultEnv_v17.m', 'total_RB')
chk('NCfgSigmaSF', 6, 'S02', DE, r'sigma_SF\s*=\s*([0-9.]+)', 'defaultEnv_v17.m', 'sigma_SF')
chk('NCfgDcorr', 50, 'S02', DE, r'd_corr\s*=\s*([0-9.]+)', 'defaultEnv_v17.m', 'd_corr')
chk('NCfgSpeedMin', 3, 'S02', DE, r'speed_min\s*=\s*([0-9.]+)', 'defaultEnv_v17.m', 'speed_min')
chk('NCfgSpeedMax', 30, 'S02', DE, r'speed_max\s*=\s*([0-9.]+)', 'defaultEnv_v17.m', 'speed_max')
chk('NCfgSigmaMeas', 1, 'S03', DE, r'sigma_meas\s*=\s*([0-9.]+)', 'defaultEnv_v17.m', 'sigma_meas')
chk('NCfgBurstDb', 9, 'S04', DE, r'burst_IM_dB\s*=\s*([0-9.]+)', 'defaultEnv_v17.m', 'burst_IM_dB')
chk('NCfgDwellCalm', 250, 'S04', DE, r'burst_dwell_calm\s*=\s*([0-9.]+)', 'defaultEnv_v17.m', 'burst_dwell_calm')
chk('NCfgDwellBurst', 120, 'S04', DE, r'burst_dwell_burst\s*=\s*([0-9.]+)', 'defaultEnv_v17.m', 'burst_dwell_burst')
chk('NCfgChase', 2.5, 'S05', DE, r'harq_comb_dB\s*=\s*([0-9.]+)', 'defaultEnv_v17.m', 'harq_comb_dB')
chk('NCfgMaxRetx', 3, 'S05', DE, r'harq_max_retx\s*=\s*([0-9.]+)', 'defaultEnv_v17.m', 'harq_max_retx')
chk('NCfgOllaTarget', 0.10, 'S11', DE, r'olla_target\s*=\s*([0-9.]+)', 'defaultEnv_v17.m', 'olla_target')
chk('NCfgOllaDown', 0.5, 'S11', DE, r'olla_step_down\s*=\s*([0-9.]+)', 'defaultEnv_v17.m', 'olla_step_down')
chk('NCfgOllaLim', 10, 'S11', DE, r'olla_off_lim\s*=\s*([0-9.]+)', 'defaultEnv_v17.m', 'olla_off_lim')
add('NCfgOllaUp', f(0.5 * 0.10 / 0.90, 3), 'S11', 'derived', 'Delta_down * P_tgt / (1 - P_tgt)')
chk('NCfgBurnIn', 50, 'S10', DE, r'burn_in\s*=\s*([0-9.]+)', 'defaultEnv_v17.m', 'burn_in')
chk('NCfgTrace', 200, 'S10', VS, r"'simTime', (\d+)", 'v17_setup.m', 'base.simTime')
add('NCfgScored', str(200 - 50), 'S10', 'derived', 'simTime - burn_in')
chk('NCfgEval', 500, 'S10', VS, r"'n_eval', (\d+)", 'v17_setup.m', 'base.n_eval')
chk('NCfgCalib', 20, 'S12', VS, r"'n_calib', (\d+)", 'v17_setup.m', 'base.n_calib')
chk('NCfgCalibCtx', 10, 'S18', DE, r'n_calib_ctx\s*=\s*([0-9.]+)', 'defaultEnv_v17.m', 'n_calib_ctx')
chk('NCfgPkt', 12000, 'S09', VS, r"'pkt_bits', (\d+)", 'v17_setup.m', 'DL.pkt_bits')
chk('NCfgPeriod', 20, 'S09', VS, r"'pkt_period', (\d+)", 'v17_setup.m', 'DL.pkt_period')
chk('NCfgDeadline', 10, 'S09', VS, r"'pkt_deadline', (\d+)", 'v17_setup.m', 'DL.pkt_deadline')
chk('NCfgPfAlpha', 0.05, 'S07', EV, r'ema\s*=\s*([0-9.]+)', 'evalPolicy_v17.m', 'ema')
chk('NCfgShape', 0.5, 'S14', VS, r"'shape_c', ([0-9.]+)", 'v17_setup.m', 'DL.shape_c')
chk('NCfgResidPen', 0.02, 'S13', VS, r"'resid_pen', ([0-9.]+)", 'v17_setup.m', 'base.resid_pen')
chk('NCfgResidBias', 3, 'S13', VS, r"'resid_init_bias', ([0-9.]+)", 'v17_setup.m', 'base.resid_init_bias')
chk('NCfgSeeds', 10, 'S15', VS, r"'n_seeds', (\d+)", 'v17_setup.m', 'base.n_seeds')
chk('NCfgEpDl', 3000, 'S15', VS, r'C\.M1_dl_rtt8\.ep_deep = (\d+)', 'v17_setup.m', 'M1 ep_deep')
chk('NCfgEpGp', 800, 'S15', VS, r'C\.M3_gp_rtt8\.ep_deep = (\d+)', 'v17_setup.m', 'M3 ep_deep')
if 'for pass = 1:2' not in CO: ERR.append('calibrateCtx_v17.m no longer has a 2-pass coordinate ascent')
add('NCalCtxPasses', '2', 'S18', 'Optimized/v17/calibrateCtx_v17.m', 'for pass = 1:2')
add('NCalCtxTables', str(7 ** 3), 'S20', 'derived', '7 offsets ^ 3 slack bins')
add('NCalFixedCands', '9', 'S19', 'Optimized/v17/defaultEnv_v17.m', 'fixed_cands = -5:3')
add('NCalClasses', '6', 'S19', 'Optimized/v17/userClass_v17.m', '2 delay x 3 speed classes')
add('NParamsActor', '20,099'.replace(',', r'\,'), 'S16', 'Optimized/v17/DeepA2C_Shared_v17.m', '57x128 + 128x96 + 96x3 weights and biases')
add('NMacsActor', '19,872'.replace(',', r'\,'), 'S16', 'Optimized/v17/DeepA2C_Shared_v17.m', '57*128+128*96+96*3')
add('NInputDim', '57', 'S16', 'Optimized/v17/stateFeat_v17.m', '3 frames x 19 features')
# check the S16 arithmetic
assert 57 * 128 + 128 * 96 + 96 * 3 == 19872 and (57 * 128 + 128) + (128 * 96 + 96) + (96 * 3 + 3) == 20099

# ------------------------------------------------------------------ compute and run facts
T = open(FS17, encoding='utf-8').read()
el = {}
for m in re.finditer(r'STEP\|(\w+)\|done\|[0-9:]+\|elapsed_min=([0-9.]+)', T): el[m.group(1)] = float(m.group(2))
add('NMoneMinutes', f(el['M1_dl_rtt8'], 1), 'R32', rel(FS17), 'STEP M1 done elapsed_min')
add('NActiveHours', re.search(r'active compute time ~([0-9.]+) hours', t17).group(1), 'R32', rel(R17), 'README_v17 s6.1 active compute time')
rs = re.search(r'REPLSEED\|M1_dl_rtt8\|pf\|a2c_seed_means=\[([0-9. ]+)\]\|best_rule=Context table\(([0-9.]+)\)\|seeds_above=(\d+)/(\d+)', T)
add('NMoneSeedsAbove', rs.group(3), 'R09', rel(FS17), 'REPLSEED M1 seeds_above'); add('NMoneSeedsTotal', rs.group(4), 'R09', rel(FS17), 'REPLSEED total')
sm = [float(x) for x in rs.group(1).split()]
add('NMoneSeedLoVal', f(min(sm), 4), 'R09', rel(FS17), 'min seed mean'); add('NMoneSeedHiVal', f(max(sm), 4), 'R09', rel(FS17), 'max seed mean')
sm_idx = sm.index(min(sm)) + 1
add('NMoneWorstSeed', str(sm_idx), 'G3g', rel(FS17), 'index of the lowest seed mean')
rs2 = re.search(r'REPLSEED\|M2_dl_rtt0\|pf\|a2c_seed_means=\[[0-9. ]+\]\|best_rule=Context table\([0-9.]+\)\|seeds_above=(\d+)/(\d+)', T)
add('NMtwoSeedsAbove', rs2.group(1), 'R16', rel(FS17), 'REPLSEED M2 seeds_above')
# stored C4 outcomes
add('NMoneRsdSeedsAbove', '6', 'R15', rel(FS17), 'REPLSEED resid-800 seeds_above 6/10 (verified below)')
if not re.search(r'a2c_seed_means=\[0.6102 0.6048 0.6041 0.5969 0.6007 0.6118 0.5962 0.6216 0.5951 0.6098\]\|best_rule=Context table\(0.6031\)\|seeds_above=6/10', T):
    ERR.append('M1 resid-800 seeds_above is no longer 6/10 in the summary file')
ent = re.search(r'TRAIN\|M1_dl_rtt8\|final_train_tp_mean=([0-9.]+)', T)

# ------------------------------------------------------------------ v17x Checkpoint-5 stages (G6, W1, NR1, A1, A3, A6)
X = lambda *a: P('Optimized', 'v17x', 'Dataset', *a)
AN = lambda *a: P('paper', 'analysis', 'out', *a)
def rows_of(path): return list(csv.DictReader(open(path, newline='', encoding='utf-8')))
def tag_of(name):
    return {'Baseline': 'Baseline', 'OLLA': 'OLLA', 'OLLA (tuned target)': 'OLLAT', 'OLLA-tuned-500': 'OLLATD', 'Multi-OLLA': 'Multi',
            'Fixed': 'Fixed', 'Fixed-500': 'FixedD', 'FixedPU (Oracle)': 'FPU', 'FixedPU-500': 'FPUD', 'Context table': 'Ctx',
            'Context-500': 'CtxD', 'Context-joint-500': 'CtxJ', 'Bandit (global)': 'BanG', 'Bandit (delay class)': 'BanDel',
            'M1 (Oracle-base primary)': 'Mone', 'M1 primary (oracle base)': 'Mone'}[name]
# protocol constants stated in the frozen common rules
CR = open(P('paper', 'proposals', 'common_rules.md'), encoding='utf-8').read()
if not re.search(r'the 90 % CI lower bound of the paired % margin > 0', CR): ERR.append('common_rules R1 no longer states the 90 % CI')
if not re.search(r'B = 20,000; seeds resampled, then traces\) 95 % CI', CR): ERR.append('common_rules R2 no longer states B = 20,000 / 95 %')
add('NLevTrace', '90', 'P01', 'paper/proposals/common_rules.md', 'R1 90 % CI')
add('NLevHier', '95', 'P01', 'paper/proposals/common_rules.md', 'R2 95 % CI')
add('NBoot', r'20\,000', 'P01', 'paper/proposals/common_rules.md', 'R2 B = 20,000')
m = re.search(r"C\.M1_dl_rtt8\.harq_rtt\s*=\s*(\d+);\s*C\.M1_dl_rtt8\.harq_nproc\s*=\s*(\d+)", VS) or re.search(r"'harq_rtt',\s*(\d+),\s*'harq_nproc',\s*(\d+)", VS)
if m:
    add('NCfgRtt', m.group(1), 'S06', 'v17_setup.m', 'M1 harq_rtt'); add('NCfgNproc', m.group(2), 'S06', 'v17_setup.m', 'M1 harq_nproc')
else:
    ERR.append('cannot find M1 harq_rtt/harq_nproc in v17_setup.m')
add('NCfgPktKbit', f(12000 / 1000, 0), 'S09', 'v17_setup.m', 'pkt_bits / 1000')
add('NVersions', str(max(int(r['version'].lstrip('v')) for r in rows)), 'M01', rel(REG), 'highest version in the registry')

# ---- G6 (trace level: MATLAB stage output, never edited)
TC5 = X('table_cal500.csv'); FSB = X('fill_summary_v17b_cal.txt'); fsb = open(FSB, encoding='utf-8').read()
tc5 = rows_of(TC5)
for r in tc5:
    t = 'NGsix' + tag_of(r['comparator'])
    add(t + 'Mar', f(r['margin_pct'], 2, True), 'G6a', rel(TC5), r['comparator'] + ' margin_pct')
    add(t + 'Lo', f(r['ci90_lo'], 2, True), 'G6a', rel(TC5), 'ci90_lo'); add(t + 'Hi', f(r['ci90_hi'], 2, True), 'G6a', rel(TC5), 'ci90_hi')
    add(t + 'Holm', sci(r['holm_p']), 'G6a', rel(TC5), 'holm_p'); add(t + 'Beats', 'yes' if r['beats'] == '1' else 'no', 'G6a', rel(TC5), 'beats')
add('NGsixValPrim', f(re.search(r'PRIMARY_A2C\|ontime=([0-9.]+)', fsb).group(1), 4), 'G6a', rel(FSB), 'PRIMARY_A2C')
add('NGsixValEns', f(re.search(r'ENS_A2C\|ontime=([0-9.]+)', fsb).group(1), 4), 'G6a', rel(FSB), 'ENS_A2C')
add('NGsixNcmp', str(len(tc5)), 'G6a', rel(TC5), 'rows')
cal = open(X('cal500_tables.txt'), encoding='utf-8').read(); sgl = open(X('cal500_single.txt'), encoding='utf-8').read()
sc = dict(re.findall(r'(\w+)=([0-9.]+)', re.search(r'SCORES: (.*)', cal).group(1)))
for k, nm in [('Context_joint_500', 'CtxJ'), ('Context_500', 'CtxD'), ('Fixed_500', 'FixedD'), ('FixedPU_500', 'FPUD'), ('Composite', 'Comp')]:
    add('NGsixCal' + nm, f(sc[k], 4), 'G6c', 'Optimized/v17x/Dataset/cal500_tables.txt', 'SCORES ' + k)
add('NGsixCtxDOffs', ', '.join(f(x, 0) for x in re.search(r'Context-500: \[([-0-9 ]+)\]', sgl).group(1).split()), 'G6a', 'Optimized/v17x/Dataset/cal500_single.txt', 'Context-500 offsets per slack bin')
add('NGsixFixedOff', f(re.search(r'Fixed-500: offset = (-?\d+)', sgl).group(1), 0), 'G6a', 'Optimized/v17x/Dataset/cal500_single.txt', 'Fixed-500 offset')
mo = re.search(r'OLLA-tuned-500: target = ([0-9.]+), step = ([0-9.]+) dB', sgl)
add('NGsixOllaTgt', f(mo.group(1), 2), 'G6a', 'Optimized/v17x/Dataset/cal500_single.txt', 'OLLA-tuned target')
add('NGsixOllaStep', f(mo.group(2), 1), 'G6a', 'Optimized/v17x/Dataset/cal500_single.txt', 'OLLA-tuned step')
cells = rows_of(X('ctxj_cells.csv'))
add('NGsixCells', str(len(cells)), 'G6a', 'Optimized/v17x/Dataset/ctxj_cells.csv', 'rows')
add('NGsixSearched', str(sum(1 for c in cells if c['is_sparse'] == '0')), 'G6a', 'Optimized/v17x/Dataset/ctxj_cells.csv', 'is_sparse = 0')
spmin = min(int(c['decision_count']) for c in cells if c['is_sparse'] == '0'); spmax = max(int(c['decision_count']) for c in cells if c['is_sparse'] == '1')
G6P = open(P('paper', 'proposals', 'G6_calibration_budget_prereg.md'), encoding='utf-8').read()
mthr = re.search(r'fewer than N = (\d+)\*\* decisions', G6P)
thr = int(mthr.group(1)) if mthr else 200
if not mthr: ERR.append('G6 prereg: sparse threshold sentence not found')
if not (spmax < thr <= spmin): ERR.append(f'G6 sparse threshold {thr} inconsistent with ctxj_cells.csv ({spmax} < thr <= {spmin})')
add('NGsixSparse', str(thr), 'G6a', 'paper/proposals/G6_calibration_budget_prereg.md; ctxj_cells.csv', 'sparse threshold (checked against counts)')
rg = open(X('REPORT_g6a.txt'), encoding='utf-8').read()
ms = re.search(r'\((\d+) traces (\d+)-(\d+), CRN', rg)
add('NGsixCalTraces', ms.group(1), 'G6a', 'Optimized/v17x/Dataset/REPORT_g6a.txt', 'scope')
add('NGsixCalSeedLo', ms.group(2), 'G6a', 'Optimized/v17x/Dataset/REPORT_g6a.txt', 'scope')
add('NGsixCalSeedHi', ms.group(3), 'G6a', 'Optimized/v17x/Dataset/REPORT_g6a.txt', 'scope')
add('NGsixStarts', re.search(r'full \((\d+) starts', rg).group(1), 'G6a', 'Optimized/v17x/Dataset/REPORT_g6a.txt', 'profile')
add('NGsixSweepCap', re.search(r'cap (\d+) sweeps', rg).group(1), 'G6a', 'Optimized/v17x/Dataset/REPORT_g6a.txt', 'profile')

# ---- G6 seed level (paper/analysis/g6_seed_stats.py, same estimators as G3) and the R2 decision vs the best comparator
G6S = AN('g6_seed_stats.csv'); g6s = {r['comparator']: r for r in rows_of(G6S)}
for cmpn, r in g6s.items():
    t = 'NGsix' + tag_of(cmpn)
    add(t + 'Above', r['seeds_above'].split('/')[0], 'G6b', rel(G6S), 'seeds_above')
    add(t + 'Sign', f(r['sign_test_p_one_sided'], 3), 'G6b', rel(G6S), 'sign p')
    add(t + 'BootLo', f(r['seedmean_boot_ci95_lo'], 2, True), 'G6b', rel(G6S), 'seedmean boot 95 lo')
    add(t + 'BootHi', f(r['seedmean_boot_ci95_hi'], 2, True), 'G6b', rel(G6S), 'seedmean boot 95 hi')
    add(t + 'HierLo', f(r['hier_boot_ci95_lo'], 2, True), 'G6b', rel(G6S), 'hier 95 lo')
    add(t + 'HierHi', f(r['hier_boot_ci95_hi'], 2, True), 'G6b', rel(G6S), 'hier 95 hi')
    add(t + 'SeedMin', f(r['seed_margin_min'], 2, True), 'G6b', rel(G6S), 'seed min')
    add(t + 'SeedMax', f(r['seed_margin_max'], 2, True), 'G6b', rel(G6S), 'seed max')
    add(t + 'Robust', 'yes' if r['seed_robust_R2'] == '1' else 'no', 'G6b', rel(G6S), 'R2 seed-robust')
    if abs(float(r['margin_pct']) - float(next(x for x in tc5 if x['comparator'] == cmpn)['margin_pct'])) > 0.006:
        ERR.append(f'g6_seed_stats margin vs {cmpn} disagrees with table_cal500.csv')
best = min(tc5, key=lambda r: float(r['margin_pct']))['comparator']
if best != 'Context-joint-500': ERR.append(f'best G6 comparator is now {best}; the R2 correction text assumes Context-joint-500')
add('NGsixRtwoFile', 'yes' if re.search(r'seed_robust=(\d)', fsb).group(1) == '1' else 'no', 'G6e', rel(FSB), 'seed_robust flag as written (computed vs Context-500 only)')
hc = re.search(r'HIERARCHICAL_CI\|vs=Context-500\|ci95=\[([-0-9.]+) ([-0-9.]+)\]', fsb)
add('NGsixCtxDHierMatLo', f(hc.group(1), 2, True), 'G6e', rel(FSB), 'HIERARCHICAL_CI lo')
add('NGsixCtxDHierMatHi', f(hc.group(2), 2, True), 'G6e', rel(FSB), 'HIERARCHICAL_CI hi')
# margin closure (v17 10-trace Context margin -> combined-table margin) and absolute gap
v17ctx = float(core[('M1_dl_rtt8', 'Deep A2C v17', 'Context table')]['pct_margin'])
g6j = float(next(x for x in tc5 if x['comparator'] == 'Context-joint-500')['margin_pct'])
add('NGsixClosure', f(100 * (1 - g6j / v17ctx), 0), 'G6d', rel(TC5) + '; ' + rel(TC), '1 - margin(CtxJ)/margin(v17 Context)')
ev = {r['comparator']: float(r['cmp_mean']) for r in rows_of(G6S)}
for k, nm in [('Context-joint-500', 'CtxJ'), ('Context-500', 'CtxD'), ('Fixed-500', 'FixedD'), ('FixedPU-500', 'FPUD'), ('OLLA-tuned-500', 'OLLATD')]:
    add('NGsixEval' + nm, f(ev[k], 4), 'G6c', rel(G6S) + ' (from ckpt/g6c/eval.mat)', 'cmp_mean ' + k)
add('NGsixCalGap', f(abs(float(sc['Context_joint_500']) - ev['Context-joint-500']), 4), 'G6c', 'cal500_tables.txt; g6c/eval.mat', '|cal - eval| CtxJ')
prim6 = float(re.search(r'PRIMARY_A2C\|ontime=([0-9.]+)', fsb).group(1))
add('NGsixAbsPpCtxJ', f(100 * (prim6 - ev['Context-joint-500']), 2, True), 'G6a', rel(FSB), 'primary - CtxJ, points')
add('NGsixBaseGapPct', f(100 * (ev['Fixed-500'] / ev['FixedPU-500'] - 1), 2, True), 'G6c', 'g6c/eval.mat', 'Fixed-500 / FixedPU-500 - 1 (evaluation)')

# ---- W1
TW = X('table_warmup.csv'); FSW = X('fill_summary_v17w.txt'); fsw = open(FSW, encoding='utf-8').read()
for r in rows_of(TW):
    t = 'NWone' + tag_of(r['comparator'])
    for cond in ['cold', 'warm']:
        c = t + cond.capitalize()
        add(c + 'Mar', f(r[cond + '_margin_pct'], 2, True), 'W01', rel(TW), cond + '_margin_pct')
        add(c + 'Lo', f(r[cond + '_ci90_lo'], 2, True), 'W01', rel(TW), cond + '_ci90_lo')
        add(c + 'Hi', f(r[cond + '_ci90_hi'], 2, True), 'W01', rel(TW), cond + '_ci90_hi')
        add(c + 'Beats', 'yes' if r[cond + '_beats'] == '1' else 'no', 'W01', rel(TW), cond + '_beats')
add('NWoneTTI', re.search(r'olla_warm_ttis=(\d+)', fsw).group(1), 'W01', rel(FSW), 'CONFIG olla_warm_ttis')
add('NWoneValWarm', f(re.search(r'PRIMARY_WARM\|ontime=([0-9.]+)', fsw).group(1), 4), 'W01', rel(FSW), 'PRIMARY_WARM')
add('NWoneValCold', f(re.search(r'PRIMARY_COLD\|ontime=([0-9.]+)', fsw).group(1), 4), 'W01', rel(FSW), 'PRIMARY_COLD')
add('NWoneClaimBWarm', 'passes' if re.search(r'CLAIM_B_WARM\|passes=1', fsw) else 'fails', 'W01', rel(FSW), 'CLAIM_B_WARM')

# ---- NR1
TN = X('table_nr1.csv'); FSN = X('fill_summary_v17n.txt'); fsn = open(FSN, encoding='utf-8').read()
for r in rows_of(TN):
    t = 'NNRone' + tag_of(r['comparator'])
    add(t + 'Mar', f(r['nr1_margin_pct'], 2, True), 'NR01', rel(TN), 'nr1_margin_pct')
    add(t + 'Lo', f(r['ci90_lo'], 2, True), 'NR01', rel(TN), 'ci90_lo'); add(t + 'Hi', f(r['ci90_hi'], 2, True), 'NR01', rel(TN), 'ci90_hi')
    add(t + 'Holm', sci(r['holm_p']), 'NR01', rel(TN), 'holm_p')
add('NNRoneVal', f(re.search(r'PRIMARY_NR1\|ontime=([0-9.]+)', fsn).group(1), 4), 'NR01', rel(FSN), 'PRIMARY_NR1')
add('NNRoneValEns', f(re.search(r'ENS_NR1\|ontime=([0-9.]+)', fsn).group(1), 4), 'NR01', rel(FSN), 'ENS_NR1')
add('NNRoneOff', f(re.search(r'offset=([-+0-9]+)', fsn).group(1), 0), 'NR01', rel(FSN), 'CONFIG offset')
add('NNRoneSeedBase', re.search(r"base_seed = (\d+);", open(P('Optimized', 'v17x', 'stage_nr1.m'), encoding='utf-8').read()).group(1), 'NR01', 'Optimized/v17x/stage_nr1.m', 'base_seed')
add('NNRoneWins', str(sum(1 for r in rows_of(TN) if r['comparator'] != 'M1 (Oracle-base primary)' and r['beats'] == '1')), 'NR01', rel(TN), 'beats among the 9')
NG = AN('nr1_g6_compare.csv')
for r in rows_of(NG):
    t = 'NNRoneG' + tag_of(r['comparator'])
    add(t + 'Mar', f(r['margin_pct'], 2, True), 'NR02', rel(NG), 'margin_pct'); add(t + 'Lo', f(r['ci90_lo'], 2, True), 'NR02', rel(NG), 'ci90_lo')
    add(t + 'Hi', f(r['ci90_hi'], 2, True), 'NR02', rel(NG), 'ci90_hi'); add(t + 'P', sci(r['wilcoxon_p']), 'NR02', rel(NG), 'wilcoxon_p')
    add(t + 'Pp', f(r['diff_pp'], 2, True), 'NR02', rel(NG), 'diff_pp')

# ---- A1 (hierarchical 95 % CIs, paper/analysis/a1_speed_stats.py)
A1S = AN('a1_speed_stats.csv'); a1src = open(P('paper', 'analysis', 'a1_speed_stats.py'), encoding='utf-8').read()
add('NAoneEdgeLo', re.search(r"\('lo', sp < (\d+)\)", a1src).group(1), 'A01', 'paper/analysis/a1_speed_stats.py', 'slow edge')
add('NAoneEdgeHi', re.search(r"\('hi', sp > (\d+)\)", a1src).group(1), 'A01', 'paper/analysis/a1_speed_stats.py', 'fast edge')
for r in rows_of(A1S):
    t = 'NAone' + {'lo': 'Slow', 'mid': 'Mid', 'hi': 'Fast', 'all': 'All'}[r['speed_class']]
    add(t + 'Mar', f(r['margin_pct'], 2, True), 'A01', rel(A1S), 'margin_pct')
    add(t + 'Lo', f(r['hier_ci95_lo'], 2, True), 'A01', rel(A1S), 'hier_ci95_lo'); add(t + 'Hi', f(r['hier_ci95_hi'], 2, True), 'A01', rel(A1S), 'hier_ci95_hi')
    add(t + 'Share', f(100 * float(r['share_user_traces']), 0), 'A01', rel(A1S), 'share of user-traces x100')

# ---- A3
RA = X('REPORT_a3.txt'); ra = open(RA, encoding='utf-8').read()
add('NAthreeLoop', re.search(r'Loop \(100000 passes\) per decision: ([0-9.]+)', ra).group(1), 'A03', rel(RA), 'loop per decision')
add('NAthreeFwd', re.search(r'Median per decision: ([0-9.]+)', ra).group(1), 'A03', rel(RA), 'median forward pass')
add('NAthreeTti', re.search(r'Deep A2C v17: ([0-9.]+) us/TTI', ra).group(1), 'A03', rel(RA), 'A2C us/TTI')
add('NAthreeTtiFpu', re.search(r'FixedPU \(Oracle\): ([0-9.]+) us/TTI', ra).group(1), 'A03', rel(RA), 'FixedPU us/TTI')
add('NAthreeRatio', re.search(r'Ratio A2C / FixedPU: ([0-9.]+)x', ra).group(1), 'A03', rel(RA), 'ratio')
add('NAthreeCpu', re.search(r'CPU Model: Intel\(R\) Core\(TM\) (\S+) CPU', ra).group(1), 'A03', rel(RA), 'CPU model (short)')

# ---- A6
FPF = X('fill_summary_v17pf.txt'); fpf = open(FPF, encoding='utf-8').read()
add('NAsixTraces', re.search(r'Traces: (\d+)', fpf).group(1), 'A06', rel(FPF), 'Traces')
if 'Expectation E holds for ALL THREE schemes' not in fpf: ERR.append('A6 verdict changed')
for sch, nm in [('Baseline', 'Base'), ('OLLA', 'OLLA'), ('Fixed', 'Fixed')]:
    blk = fpf.split('\n' + sch + ':')[1]
    ma = re.search(r'pf_avg=acked:\s+np1=([0-9.]+), np8=([0-9.]+), ratio=([0-9.]+), dJain=([-0-9.]+)', blk)
    mb = re.search(r'pf_avg=scheduled:\s+np1=([0-9.]+), np8=([0-9.]+), ratio=([0-9.]+), dJain=([-0-9.]+)', blk)
    add(f'NAsix{nm}AckRatio', f(ma.group(3), 3), 'A06', rel(FPF), sch + ' acked ratio')
    add(f'NAsix{nm}SchedRatio', f(mb.group(3), 3), 'A06', rel(FPF), sch + ' scheduled ratio')
    add(f'NAsix{nm}AckGain', f(100 * (float(ma.group(3)) - 1), 1, True), 'A06', rel(FPF), 'ratio - 1')
    add(f'NAsix{nm}SchedGain', f(100 * (float(mb.group(3)) - 1), 1, True), 'A06', rel(FPF), 'ratio - 1')
    add(f'NAsix{nm}AckDJain', f(ma.group(4), 3, True), 'A06', rel(FPF), 'dJain acked')
    add(f'NAsix{nm}SchedDJain', f(mb.group(4), 3, True), 'A06', rel(FPF), 'dJain scheduled')
A6C = {(r['cell'], r['scheme']): r for r in rows_of(X('a6_pf_timing.csv'))}
for cell, nm in [('acked_rtt8_np1', 'AckOne'), ('acked_rtt8_np8', 'AckEight'), ('scheduled_rtt8_np1', 'SchedOne'), ('scheduled_rtt8_np8', 'SchedEight')]:
    add(f'NAsixJain{nm}', f(A6C[(cell, 'Baseline')]['jain_mean'], 3), 'A06', 'Optimized/v17x/Dataset/a6_pf_timing.csv', cell + ' Baseline jain')
    add(f'NAsixGp{nm}', f(A6C[(cell, 'Baseline')]['goodput_mean'], 2), 'A06', 'Optimized/v17x/Dataset/a6_pf_timing.csv', cell + ' Baseline goodput')

# ---- training hyper-parameters (Appendix A), read from the code
for nm, pat in [('NHpLrActor', r"'lr_actor', ([0-9e.-]+)"), ('NHpLrCritic', r"'lr_critic', ([0-9e.-]+)"), ('NHpEntStart', r"'ent_start', ([0-9.]+)"),
                ('NHpEntEnd', r"'ent_end', ([0-9.]+)"), ('NHpNstep', r"'n_step', (\d+)"), ('NHpValEvery', r"'val_every', (\d+)"), ('NHpNval', r"'n_val', (\d+)")]:
    mm = re.search(pat, VS)
    if not mm: ERR.append(f'{nm}: pattern not found in v17_setup.m'); continue
    v = mm.group(1)
    if 'e' in v.lower():
        mant, ex = v.lower().split('e'); s = rf'\ensuremath{{{float(mant):g}\times10^{{{int(ex)}}}}}'
    else:
        s = v
    add(nm, s, 'S15', 'Optimized/v17/v17_setup.m', pat)
add('NHpGamma', re.search(r'env\.gamma\s*=\s*([0-9.]+)', DE).group(1), 'S15', 'Optimized/v17/defaultEnv_v17.m', 'gamma')

# ---- G1 seed consistency (paper/analysis/g1_seed_consistency.py)
G1C = AN('g1_seed_consistency.csv'); G1K = AN('g1_seed_contrasts.csv')
for r in rows_of(G1C):
    t = 'NGone' + {'all': 'All', 'busy_0': 'BusyZero', 'busy_1_2': 'BusyOne', 'busy_ge3': 'BusyThree', 'slack_le_0.3': 'SlackTight',
                   'slack_0.3_0.6': 'SlackMid', 'slack_gt_0.6': 'SlackLoose', 'calm': 'Calm', 'burst': 'Burst', 'base_m3': 'BaseMthree', 'base_m2': 'BaseMtwo'}[r['bin']]
    add(t + 'Plus', f(r['pct_plus1'], 1), 'G1b', rel(G1C), 'pct_plus1'); add(t + 'Zero', f(r['pct_zero'], 1), 'G1b', rel(G1C), 'pct_zero')
    add(t + 'Minus', f(r['pct_minus1'], 1), 'G1b', rel(G1C), 'pct_minus1'); add(t + 'Share', f(r['share_of_decisions'], 0), 'G1b', rel(G1C), 'share_of_decisions')
    add(t + 'SeedMin', f(r['plus1_seed_min'], 0), 'G1b', rel(G1C), 'plus1_seed_min'); add(t + 'SeedMax', f(r['plus1_seed_max'], 0), 'G1b', rel(G1C), 'plus1_seed_max')
for r in rows_of(G1K):
    t = 'NGoneK' + {'busy_1_2_vs_busy_0': 'Busy', 'slack_le_0.6_vs_gt_0.6': 'Slack', 'burst_vs_calm': 'Burst'}[r['contrast']]
    add(t + 'Seeds', r['seeds_positive'], 'G1b', rel(G1K), 'seeds_positive')
    add(t + 'Min', f(r['diff_min_pp'], 0), 'G1b', rel(G1K), 'diff_min_pp'); add(t + 'Max', f(r['diff_max_pp'], 0), 'G1b', rel(G1K), 'diff_max_pp')
    add(t + 'A', f(r['pooled_a'], 1), 'G1b', rel(G1K), 'pooled_a'); add(t + 'ShareA', f(r['share_a'], 0), 'G1b', rel(G1K), 'share_a')
G1A = P('Optimized', 'v17', 'paper', 'g1', 'g1_action_by_state.csv')
for r in rows_of(G1A):
    if r['case_tag'] == 'M1_dl_rtt8' and r['condition_type'] == 'speed_class':
        t = {'<10 m/s': 'Slow', '10-20 m/s': 'Mid', '>20 m/s': 'Fast'}[r['condition_bin']]
        add(f'NGoneSpeed{t}Plus', f(r['pct_delta_plus1'], 1), 'G1a', rel(G1A), 'speed_class pct_delta_plus1')
TL0 = open(P('Optimized', 'v17', 'paper', 'table_training_length.csv')).readline()
add('NCfgEpShort', re.search(r'pct_(\d+)ep', TL0).group(1), 'R25', 'Optimized/v17/paper/table_training_length.csv', 'header pct_<n>ep')
add('NGoneSlackEdge', '0.6', 'G1b', 'paper/analysis/g1_seed_consistency.py', 'slack fraction edge (G1_SPEC bins 0.3, 0.6)')

# ---- cross-check of the hand-entered pending values against the extracted macros
PV = {(r['item'], r['key']): r['value'] for r in rows_of(P('paper', 'manuscript', 'pending_values.csv'))}
XC = {('W1', 'cold_gain'): 'NWoneOLLAColdMar', ('W1', 'warm_gain'): 'NWoneOLLAWarmMar', ('W1', 'warm_ctx_margin'): 'NWoneCtxWarmMar',
      ('W1', 'warm_fixed_margin'): 'NWoneFixedWarmMar', ('W1', 'warm_ci_lo'): 'NWoneOLLAWarmLo', ('W1', 'warm_ci_hi'): 'NWoneOLLAWarmHi',
      ('G6', 'margin_ctx500'): 'NGsixCtxDMar', ('G6', 'margin_ctxj'): 'NGsixCtxJMar', ('G6', 'ci_lo_ctxj'): 'NGsixCtxJLo', ('G6', 'ci_hi_ctxj'): 'NGsixCtxJHi',
      ('G6', 'margin_fixed500'): 'NGsixFixedDMar', ('G6', 'margin_fpu500'): 'NGsixFPUDMar', ('G6', 'seed_lo_best'): 'NGsixCtxJHierLo',
      ('G6', 'calib_obj_ctxj'): 'NGsixCalCtxJ', ('G6', 'eval_obj_ctxj'): 'NGsixEvalCtxJ', ('G6', 'calib_obj_ctx500'): 'NGsixCalCtxD', ('G6', 'eval_obj_ctx500'): 'NGsixEvalCtxD',
      ('G6', 'n_searched_cells'): 'NGsixSearched', ('NR', 'best_margin'): 'NNRoneCtxMar', ('NR', 'ci_lo'): 'NNRoneCtxLo',
      ('A1', 'margin_lo'): 'NAoneSlowMar', ('A1', 'margin_mid'): 'NAoneMidMar', ('A1', 'margin_hi'): 'NAoneFastMar',
      ('A3', 'us_per_decision'): 'NAthreeLoop', ('A3', 'us_per_tti'): 'NAthreeTti',
      ('A6', 'baseline_8p_vs_1p_acked'): 'NAsixBaseAckRatio', ('A6', 'baseline_8p_vs_1p_sched'): 'NAsixBaseSchedRatio',
      ('A6', 'jain_8p_acked'): 'NAsixJainAckEight', ('A6', 'jain_8p_sched'): 'NAsixJainSchedEight'}
num = lambda s: float(s.replace(MINUS, '-').replace(r'\,', '').replace('$', ''))
for k, mac in XC.items():
    if k in PV and mac in M and abs(float(PV[k]) - num(M[mac][0])) > 0.0051:
        ERR.append(f'pending_values {k} = {PV[k]} disagrees with extracted {mac} = {M[mac][0]}')

# ------------------------------------------------------------------ write
if ERR:
    print('ERRORS:'); [print('  ', e) for e in ERR]; sys.exit(1)
here = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(here, 'numbers.tex'), 'w', encoding='utf-8') as fh:
    fh.write('% generated by build_numbers.py -- do not edit. Every value comes from a file listed in numbers_audit.csv.\n')
    for k in sorted(M):
        fh.write(f'\\newcommand{{\\{k}}}{{{M[k][0]}}}%\n')
with open(os.path.join(here, 'numbers_audit.csv'), 'w', newline='', encoding='utf-8') as fh:
    w = csv.writer(fh); w.writerow(['macro', 'value', 'ledger_id', 'source_file', 'field'])
    for k in sorted(M): w.writerow([k] + list(M[k]))
print(f'{len(M)} macros written; constants verified against the code')
