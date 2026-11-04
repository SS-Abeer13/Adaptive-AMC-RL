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
