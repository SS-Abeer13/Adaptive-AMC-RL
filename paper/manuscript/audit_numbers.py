"""Audit every number printed in the manuscript PDF against its generated source.

For each numeric token in the main text, captions and tables of main.pdf (references excluded),
the audit records where it came from:
  macro      equals the value of a numbers.tex macro (ledger ID and source file from numbers_audit.csv)
  pending    equals a value of pending_values.tex (item:key, source file from pending_values.csv)
  table      appears in a generated table (gen/*.tex, written by build_tables.py)
  lit        an intended literal wrapped in \\lit{} or a reported literal of a non-gated section
  structural section, figure, table, equation, page or citation number, or part of an identifier
  UNMATCHED  none of the above: must be checked by hand
Run from paper/manuscript after a build:  python3 -I audit_numbers.py [main.pdf]
Writes paper/manuscript/audit_numbers.csv and prints a summary.
"""
import csv, glob, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
PDF = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'main.pdf')

def norm(s):
    s = s.replace('\\ensuremath{-}', '-').replace('−', '-').replace('\\,', '').replace('\u2009', '').replace(',', '')
    s = s.replace('$', '').replace('{', '').replace('}', '').strip()
    s = s.lstrip('+')
    m = re.fullmatch(r'(-?[0-9.]+)\\times10\^(-?\d+)', s)
    if m: return f'{m.group(1)}e{int(m.group(2))}'
    return s

# ---- sources
audit = {r['macro']: r for r in csv.DictReader(open(os.path.join(HERE, 'numbers_audit.csv'), encoding='utf-8'))}
vals = {}
for line in open(os.path.join(HERE, 'numbers.tex'), encoding='utf-8'):
    m = re.match(r'\\newcommand\{\\(\w+)\}\{(.*)\}%', line)
    if m:
        for part in re.findall(r'[-0-9.,\\{}a-z]+', norm(m.group(2))):
            pass
        v = norm(m.group(2))
        for tok in re.findall(r'-?\d[\d.]*(?:e-?\d+)?', v):
            vals.setdefault(tok, []).append(('macro', m.group(1)))
pv = {(r['item'], r['key']): r for r in csv.DictReader(open(os.path.join(HERE, 'pending_values.csv'), encoding='utf-8'))}
for line in open(os.path.join(HERE, 'pending_values.tex'), encoding='utf-8'):
    m = re.match(r'\\pendingdef\{(\w+)\}\{(\w+)\}\{(.*)\}', line)
    if m:
        for tok in re.findall(r'-?\d[\d.]*(?:e-?\d+)?', norm(m.group(3))):
            vals.setdefault(tok, []).append(('pending', f'{m.group(1)}:{m.group(2)}'))
tabtok = set()
for f in glob.glob(os.path.join(HERE, 'gen', '*.tex')):
    t = norm(open(f, encoding='utf-8').read())
    for m in re.finditer(r'(\d+(?:\.\d+)?)\\times10\^(-?)(\d+)', t): tabtok.add(f"{m.group(1)}e{m.group(2)}{int(m.group(3))}")
    for tok in re.findall(r'-?\d[\d.]*', t): tabtok.add(tok)
littok = set()
for f in glob.glob(os.path.join(HERE, 'sec_*.tex')) + [os.path.join(HERE, 'main.tex')]:
    t = open(f, encoding='utf-8').read()
    for m in re.finditer(r'\\lit\{([^}]*)\}', t):
        for tok in re.findall(r'-?\d[\d.]*', norm(m.group(1))): littok.add(tok)
    if os.path.basename(f) not in ('main.tex', 'sec_intro.tex', 'sec_results.tex', 'sec_discussion.tex'):
        body = re.sub(r'\\(cite|ref|label)\{[^}]*\}', '', t)
        body = re.sub(r'\\[A-Za-z]+', ' ', body)
        for tok in re.findall(r'-?\d[\d.]*', norm(body)): littok.add(tok)
for f in ['wording.tex']:
    t = re.sub(r'\\[A-Za-z]+', ' ', open(os.path.join(HERE, f), encoding='utf-8').read())
    for tok in re.findall(r'-?\d[\d.]*', norm(t)): littok.add(tok)

# ---- PDF text (reading order, references excluded)
n = int(re.search(r'Pages:\s+(\d+)', subprocess.run(['pdfinfo', PDF], capture_output=True, text=True).stdout).group(1))
rows = []
STRUCT = re.compile(r'(Fig\.|Figs\.|Table|Tables|Section|Sections|Appendix|Eq\.|Step|Claim|Rule|item|C|M|NR|NR-G|G|W|A|H|P|R|v|S|TS|TR|E|X|Y|K|Q|ID|SHA-|arXiv:)\s?$')
SCI = re.compile(r'(\d+(?:\.\d+)?)\s*×\s*10\s*([−-]?)\s*(\d+)')
NUM = re.compile(r'(?<![\w.])[+−-]?\d{1,3}(?:[  ]\d{3})+(?:\.\d+)?(?![\w])|(?<![\w.])[+−-]?\d+(?:\.\d+)?(?![\w])')
p = 0
for p in range(1, n + 1):
    txt = subprocess.run(['pdftotext', '-f', str(p), '-l', str(p), PDF, '-'], capture_output=True, text=True).stdout
    mref = re.search(r'R\s?EFERENCES', txt)
    stop = bool(mref)
    if mref: txt = txt[:mref.start()]
    for line in txt.split('\n'):
        if re.fullmatch(r'[\s\d.,−+%<>=-]*', line):            # axis ticks, page numbers, bare numeric rows of figures
            if re.search(r'\d', line): rows.append(dict(page=p, token=line.strip(), status='figure-axis', source='figure text', context=line.strip()))
            continue
        spans = []
        for m in SCI.finditer(line):
            spans.append((m.start(), m.end(), f"{m.group(1)}e{'-' if m.group(2) else ''}{int(m.group(3))}", m.group(0)))
        taken = [(a, b) for a, b, _, _ in spans]
        for m in NUM.finditer(line):
            if any(a <= m.start() < b for a, b in taken): continue
            spans.append((m.start(), m.end(), norm(m.group(0).replace(' ', '').replace(' ', '')), m.group(0)))
        for a, b, tok, raw in sorted(spans):
            pre = line[max(0, a - 12):a]; post = line[b:b + 3]
            ctx = line[max(0, a - 40):b + 40].strip()
            if re.search(r'\[\s*$', pre) and re.match(r'\s*[\],–-]', post) and '.' not in tok:
                st, src = 'structural', 'citation'
            elif STRUCT.search(pre.rstrip('~( ')) or re.match(r'[A-Za-z]', post or ' '):
                st, src = 'structural', 'label/identifier/unit-free code'
            elif tok in vals or tok.lstrip('-') in vals:
                hit = vals.get(tok) or vals.get(tok.lstrip('-'))
                st = hit[0][0]
                src = '; '.join(f"{h[1]}" + (f" [{audit[h[1]]['ledger_id']}]" if h[0] == 'macro' and h[1] in audit else '') for h in hit[:3])
            elif tok in tabtok or tok.lstrip('-') in tabtok:
                st, src = 'table', 'gen/*.tex'
            elif tok in littok or tok.lstrip('-') in littok:
                st, src = 'lit', 'literal in source'
            else:
                st, src = 'UNMATCHED', ''
            rows.append(dict(page=p, token=raw, status=st, source=src, context=ctx))
    if stop: break
out = os.path.join(HERE, 'audit_numbers.csv')
with open(out, 'w', newline='', encoding='utf-8') as fh:
    w = csv.DictWriter(fh, fieldnames=['page', 'token', 'status', 'source', 'context']); w.writeheader(); w.writerows(rows)
from collections import Counter
c = Counter(r['status'] for r in rows)
print(f'{len(rows)} numeric tokens on pages 1-{p}: ' + ', '.join(f'{k} {v}' for k, v in sorted(c.items())))
for r in rows:
    if r['status'] == 'UNMATCHED': print(f"  p{r['page']}: {r['token']!r:12} | {r['context']}")
