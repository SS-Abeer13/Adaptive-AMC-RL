#!/usr/bin/env python3
"""Generate ft_numbers.tex from the stored S-EOT, D-PF, D-RS, S-SYM, FT and T-GBT outputs.

Usage (from paper/manuscript):
    python build_ft_numbers.py ../../Optimized/v17x/Dataset ft_numbers.tex

Every macro is read from a result file; nothing is typed by hand.
"""
import csv, re, sys, os, hashlib

root = sys.argv[1] if len(sys.argv) > 1 else '../../Optimized/v17x/Dataset'
P = lambda *a: os.path.join(root, *a)
SRC = {}

def read(path, enc='utf-8'):
    raw = open(path, 'rb').read()
    SRC[os.path.relpath(path, root)] = hashlib.sha256(raw).hexdigest()
    if raw[:2] in (b'\xff\xfe', b'\xfe\xff'):
        return raw.decode('utf-16')
    return raw.decode(enc)

def num(x, dp=2, sign=False):
    v = float(x)
    s = f'{abs(v):.{dp}f}'
    if v < 0:
        return r'\ensuremath{-}' + s
    return ('+' if sign else '') + s

def intsep(x):
    s = f'{int(round(float(x))):d}'
    return s if len(s) < 4 else s[:-3] + r'\,' + s[-3:]

M = {}

# ---------- FT (as run = primary; resolved = secondary) ----------
def rows(path):
    return list(csv.DictReader(read(path).splitlines()))
prim = rows(P('ft', 'ft_primary.csv'))
res = rows(P('ft', 'out_resolved', 'ft_primary.csv'))
h1 = [r for r in prim if r['family'] == 'FT-H1']
h2 = [r for r in prim if r['family'] == 'FT-H2']
h3 = [r for r in prim if r['family'] == 'FT-H3'][0]
assert len(h1) == 4 and len(h2) == 4
assert all(r['verdict'] == 'SUP-BEATS' for r in h1 + h2)
loss = lambda rs: sorted(-float(r['margin_pct']) for r in rs)
M['NFtResLossMin'], M['NFtResLossMax'] = num(loss(h1)[0]), num(loss(h1)[-1])
M['NFtFullLossMin'], M['NFtFullLossMax'] = num(loss(h2)[0]), num(loss(h2)[-1])
M['NFtHierUpperMax'] = num(max(float(r['hier95_hi']) for r in h1 + h2))
M['NFtSeedsAheadMax'] = str(max(int(r['seeds_ahead']) for r in h1 + h2))
M['NFtCtxJMar'] = num(h3['margin_pct'])
M['NFtCtxJHierLo'], M['NFtCtxJHierHi'] = num(h3['hier95_lo']), num(h3['hier95_hi'])
M['NFtCtxJSeeds'] = h3['seeds_ahead']
assert h3['verdict'] == 'CONFIRM'
r3 = [r for r in res if r['family'] == 'FT-H3'][0]
M['NFtResolvedCtxJMar'] = num(r3['margin_pct'])
assert all(a['verdict'] == b['verdict'] for a, b in zip(prim, res))
sch = {r['scheme']: r for r in rows(P('ft', 'ft_schemes.csv'))}
M['NFtOntNRtwo'] = f"{float(sch['NR2']['ft_ontime']):.4f}"
M['NFtOntRLfull'] = f"{float(sch['RL-full']['ft_ontime']):.4f}"
for kind, tag in (('res', 'Res'), ('full', 'Full')):
    v = [float(sch[f'GBT-{kind}-ACK-M1fit{k}']['ft_ontime']) for k in range(1, 5)]
    M[f'NFtOnt{tag}Mean'] = f'{sum(v)/4:.4f}'
    M[f'NFtOnt{tag}Min'], M[f'NFtOnt{tag}Max'] = f'{min(v):.4f}', f'{max(v):.4f}'
m = re.search(r'exposed_pct=([\d.]+)%', read(P('ft', 'ft_exposure.txt')))
M['NFtExposed'] = num(m.group(1))

# ---------- S-EOT ----------
eot = read(P('eot', 'eot_summary.txt'))
shifts = [abs(float(x)) for x in re.findall(r'\|\s*([+-]?[\d.]+) pp\s*\|', eot)]
assert shifts and all(l.strip().endswith('| no') for l in eot.splitlines() if l.count('|') >= 6 and not l.startswith('Format'))
M['NEotMaxShift'] = num(max(shifts))
g = re.search(r'R1b GBT-res-ACK fit 1 vs NR2\s*\|\s*([+-][\d.]+)%\s*\|\s*([+-][\d.]+)%', eot)
M['NEotResFitOneAsrun'], M['NEotResFitOneResolved'] = num(g.group(1)), num(g.group(2))
exp = [float(x) for x in re.findall(r'\|\s*([\d.]+)%\s*$', read(P('eot', 'exposure_table.txt')), re.M)]
M['NEotExpMin'], M['NEotExpMax'] = num(min(exp)), num(max(exp))

# ---------- D-RS ----------
drs = read(P('eot', 'diag_rsched_retx.txt'))
M['NDrsShare'] = num(100*float(re.search(r'share_diff_rsched=([\d.]+)', drs).group(1)))
M['NDrsUserChange'] = num(100*float(re.search(r'share_pf_user_change=([\d.]+)', drs).group(1)))

# ---------- D-PF ----------
dpf = read(P('eot', 'pf_diag_M4_detail.txt'))
def dpf_row(case, mode, comp):
    block = dpf.split(case)[1]
    if 'M 2' in case or case.startswith('M4'):
        pass
    sec = block.split('Mode: ' + mode)[1]
    line = [l for l in sec.splitlines() if l.strip().startswith(comp + ' ') or l.strip().startswith(comp + '\t')][0]
    mm = re.search(r'margin=\s*([+-][\d.]+)%.*\[\s*([+-][\d.]+),\s*([+-][\d.]+)\].*Holm p=([\d.e+-]+)\s*\|\s*(.+)$', line)
    return mm.groups()
m4 = dpf.split('M2 (DL RTT 0)')[0]; m2 = dpf.split('M2 (DL RTT 0)')[1]
def row(text, mode, comp):
    sec = text.split('Mode: ' + mode)[1].split('Mode:')[0]
    line = [l for l in sec.splitlines() if re.match(r'\s*' + re.escape(comp) + r'\s*\|', l)][0]
    return re.search(r'margin=\s*([+-][\d.]+)%.*\[\s*([+-][\d.]+),\s*([+-][\d.]+)\].*Holm p=([\d.e+-]+)\s*\|\s*(.+)$', line).groups()
a = row(m4, 'acked', 'Fixed'); s = row(m4, 'scheduled', 'Fixed'); o = row(m4, 'acked', 'OLLA')
M['NDpfMfourSchedFixedMar'] = num(s[0], sign=True)
M['NDpfMfourAckFixedMar'], M['NDpfMfourAckFixedLo'], M['NDpfMfourAckFixedHi'] = num(a[0], sign=True), num(a[1], sign=True), num(a[2], sign=True)
M['NDpfMfourAckOllaMar'] = num(o[0], sign=True)
c = row(m2, 'acked', 'Context')
M['NDpfMtwoAckCtxMar'], M['NDpfMtwoAckCtxHolm'] = num(c[0], sign=True), f'{float(c[3]):.2f}'
assert a[4].strip() == 'BEATS' and o[4].strip() == 'LOSES' and c[4].strip().startswith('TIE')

# ---------- S-SYM ----------
ss = read(P('ft', 'ssym_summary.txt'))
t = re.search(r'Total comparisons checked:\s*(\d+)\s*\|\s*Directional verdict changes under symmetric rule:\s*(\d+)', ss)
M['NSsymN'], M['NSsymChanged'] = t.group(1), t.group(2)

# ---------- T-GBT (scikit-learn) and T-GBT-b (compiled) ----------
tg = read(P('ft', 'tgbt_timing.txt'))
part_a, part_b = tg.split('T-GBT-b (descriptive')[0], tg.split('T-GBT-b (descriptive')[1]
def trow(text, n, label):
    sec = text.split(f'N = {n} Users')[1].split('--- N =')[0]
    line = [l for l in sec.splitlines() if l.startswith(label)][0]
    f = [x.strip() for x in line.split('|')]
    return f
r = trow(part_a, 10, 'GBT-res-ACK (fit 1)'); M['NTgbtSkResMed'] = intsep(r[1])
r = trow(part_a, 10, 'NR2 A2C (A3c NumPy)'); M['NTgbtRlMed'] = intsep(r[1]); M['NTgbtRlPnine'] = intsep(r[2])
r = trow(part_b, 10, 'GBT-res-ACK (ONNX Runtime)')
M['NTgbtOnnxResMed'], M['NTgbtOnnxResPnine'] = intsep(r[1]), intsep(r[2]); M['NTgbtOnnxResSlot'] = num(r[3].rstrip('%'), 1)
r = trow(part_b, 10, 'GBT-full-ACK (ONNX Runtime)')
M['NTgbtOnnxFullMed'] = intsep(r[1]); M['NTgbtOnnxFullSlot'] = num(r[3].rstrip('%'), 1)
r = trow(part_b, 50, 'GBT-res-ACK (ONNX Runtime)'); M['NTgbtOnnxResMedFifty'] = intsep(r[1])
assert 'MCS match = 100.00%' in part_b

out = ['% generated by build_ft_numbers.py -- do not edit']
for k, v in sorted(SRC.items()):
    out.append(f'% source {k} sha256 {v}')
for k in sorted(M):
    assert re.fullmatch(r'N[A-Za-z]+', k), k
    out.append(f'\\newcommand{{\\{k}}}{{{M[k]}}}')
text = '\n'.join(out) + '\n'
if len(sys.argv) > 2:
    with open(sys.argv[2], 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(text)
else:
    sys.stdout.write(text)
