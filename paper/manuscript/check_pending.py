"""Scan the manuscript for pending-number macros, wording switches and literal numbers.
  python3 -I check_pending.py            report only (exit 0 unless a typo/unknown key is found)
  python3 -I check_pending.py --final    submission gate: also fail on unresolved placeholders,
                                         items still 'pending', numbers of 'not_run' items,
                                         literal numbers in the gated files, and a G6 verdict
                                         that disagrees with Rule R2 for the best comparator
Dead branches of \\ifitemrun{ITEM}{run text}{default text} are ignored, so numbers inside the
run branch of an item that was not run do not count.

Literal-number rule: in the body of LITERAL_GATED every number must come from a macro
(numbers.tex, pending values).  Identifiers such as M1, C2, A2C, v17, 5G, 3GPP, Context-500 or
ns-3 are not numbers.  A literal that is intended (for example the action value 0 in
"$\\delta=\\lit{0}$") is wrapped in \\lit{...}; such literals are counted and listed, never silent.
"""
import csv, glob, re, sys, os

MACRO = {'Gone': 'G1', 'Wone': 'W1', 'Gsix': 'G6', 'NR': 'NR', 'Gten': 'G10', 'NRtwo': 'NR2', 'Aone': 'A1', 'Athree': 'A3', 'Asix': 'A6'}
SKIP = {'pending.tex', 'wording.tex', 'pending_values.tex', 'pending_status.tex', 'numbers.tex'}
LITERAL_GATED = ['main.tex', 'sec_intro.tex', 'sec_results.tex', 'sec_discussion.tex']
LITERAL_REPORTED = ['sec_related.tex', 'sec_system.tex', 'sec_method.tex', 'sec_protocol.tex', 'sec_pitfalls.tex',
                    'sec_conclusion.tex', 'sec_appendix.tex']

def group(s, i):
    """Return (content, index after) of the {...} group starting at s[i] (after optional spaces)."""
    while i < len(s) and s[i] in ' \t\n': i += 1
    if i >= len(s) or s[i] != '{': return None, i
    d = 0; j = i
    while j < len(s):
        if s[j] == '\\': j += 2; continue
        if s[j] == '{': d += 1
        elif s[j] == '}':
            d -= 1
            if d == 0: return s[i + 1:j], j + 1
        j += 1
    return None, i

def resolve_ifitemrun(s, status):
    out = []; i = 0
    tag = '\\ifitemrun'
    while True:
        k = s.find(tag, i)
        if k < 0: out.append(s[i:]); break
        out.append(s[i:k])
        item, j = group(s, k + len(tag)); a, j = group(s, j); b, j = group(s, j)
        if item is None or a is None or b is None:
            out.append(tag); i = k + len(tag); continue
        keep = a if status.get(item.strip(), 'pending') == 'run' else b
        out.append(resolve_ifitemrun(keep, status)); i = j
    return ''.join(out)

def drop_cmd_args(s, cmd, nargs):
    """Remove \\cmd[opt]{a1}...{an} (n groups)."""
    out = []; i = 0; tag = '\\' + cmd
    while True:
        k = s.find(tag, i)
        if k < 0: out.append(s[i:]); break
        e = k + len(tag)
        if e < len(s) and s[e].isalpha(): out.append(s[i:e]); i = e; continue   # longer command name
        out.append(s[i:k]); j = e
        while j < len(s) and s[j] in ' \t\n': j += 1
        if j < len(s) and s[j] == '[':
            j = s.find(']', j) + 1
        for _ in range(nargs):
            g, j2 = group(s, j)
            if g is None: break
            j = j2
        out.append(' '); i = j
    return ''.join(out)

NUM = re.compile(r'(?<![A-Za-z0-9_@\\.])[+-]?\d+(?:[.,]\d+)*(?![A-Za-z0-9_])')

def literal_numbers(text):
    """Return (list of literal numbers, list of \\lit{} contents) in a LaTeX body."""
    s = text
    if '\\begin{document}' in s: s = s.split('\\begin{document}', 1)[1]
    s = s.split('\\end{document}', 1)[0]
    lits = []
    s = re.sub(r'\\cmidrule(\([^)]*\))?\{[^}]*\}', ' ', s)
    def keep_lit(m): lits.append(m.group(1)); return ' '
    s = re.sub(r'\\lit\{([^{}]*)\}', keep_lit, s)
    for cmd, n in [('label', 1), ('ref', 1), ('eqref', 1), ('cite', 1), ('input', 1), ('includegraphics', 1), ('bibliography', 1),
                   ('bibliographystyle', 1), ('setlength', 2), ('hspace', 1), ('vspace', 1), ('begin', 1), ('end', 1),
                   ('subfloat', 0), ('resizebox', 2), ('multicolumn', 2), ('multirow', 2), ('cmidrule', 1), ('url', 1)]:
        s = drop_cmd_args(s, cmd, n)
    s = re.sub(r'\{@\{\}[^{}]*@\{\}\}', ' ', s)                   # tabular column specs
    s = re.sub(r'\[[^\]\n]*\]', lambda m: ' ' if re.search(r'width|height|[0-9.]+(pt|mm|cm|em|ex|in)|^\[[htbp!H]+\]$', m.group(0)) else m.group(0), s)
    s = re.sub(r'[0-9.]+\s*(pt|mm|cm|em|ex|in)\b', ' ', s)
    s = re.sub(r'\\\\\[[^\]]*\]', ' ', s)
    s = re.sub(r'[A-Za-z][A-Za-z]*(?:-[A-Za-z]+)*-\d+', ' ', s)   # identifiers: Context-500, ns-3, resid-800
    s = re.sub(r'\\[A-Za-z@]+', ' ', s)                            # control words (macro names hold letters only)
    return NUM.findall(s), lits

def g6_r2_check(values_rows):
    """G6 verdict must agree with R2 evaluated against the best (smallest-margin) comparator."""
    errs = []
    v = {(r['item'], r['key']): r['value'] for r in values_rows}
    verdict = v.get(('G6', 'verdict'))
    path = os.environ.get('G6_SEED_STATS') or os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'analysis', 'out', 'g6_seed_stats.csv')
    if verdict is None or not os.path.exists(path): return errs
    rows = list(csv.DictReader(open(path, newline='')))
    best = min(rows, key=lambda r: float(r['margin_pct']))
    robust = best['seed_robust_R2'] == '1'
    if verdict == 'ABJ' and not robust:
        errs.append(f'G6 verdict is ABJ but the margin over the best comparator ({best["comparator"]}) is not seed-robust under R2 '
                    f'(hierarchical 95% CI [{best["hier_boot_ci95_lo"]}, {best["hier_boot_ci95_hi"]}]); use ABJ-seed')
    if verdict == 'ABJ-seed' and robust:
        errs.append(f'G6 verdict is ABJ-seed but the margin over {best["comparator"]} is seed-robust; use ABJ')
    return errs

def main():
    final = '--final' in sys.argv
    man = {(r['item'], r['key']) for r in csv.DictReader(open('pending_manifest.csv', newline=''))}
    items = {i for i, _ in man}
    status = {r['item']: r['status'] for r in csv.DictReader(open('pending_status.csv', newline=''))}
    vrows = list(csv.DictReader(open('pending_values.csv', newline='')))
    values = {(r['item'], r['key']) for r in vrows}
    errs, warns, used, used_word = [], [], set(), set()
    lit_report = []
    for f in sorted(glob.glob('*.tex') + glob.glob('sections/*.tex')):
        if os.path.basename(f) in SKIP: continue
        raw = open(f, encoding='utf-8').read()
        s = resolve_ifitemrun(raw, status)
        s = re.sub(r'(?<!\\)%.*', '', s)
        for m, key in re.findall(r'\\(Gone|Wone|Gsix|NRtwo|NR|Gten|Aone|Athree|Asix)\s*\{([^}]*)\}', s):
            it = MACRO[m]
            if (it, key) not in man: errs.append(f'{f}: \\{m}{{{key}}} is not in pending_manifest.csv (typo?)')
            used.add((it, key))
        for slot, it, key, dflt in re.findall(r'\\wordingsel\s*\{([^}]*)\}\s*\{([^}]*)\}\s*\{([^}]*)\}\s*\{([^}]*)\}', s):
            if (it, key) not in man: errs.append(f'{f}: \\wordingsel uses unknown ({it},{key})')
            used_word.add((it, key))
        for it in re.findall(r'\\ifitemrun\s*\{([^}]*)\}', s):
            if it not in items: errs.append(f'{f}: \\ifitemrun with unknown item {it}')
        base = os.path.basename(f)
        if base in LITERAL_GATED or base in LITERAL_REPORTED:
            nums, lits = literal_numbers(s)
            lit_report.append((base, nums, lits))
            if nums and base in LITERAL_GATED:
                msg = f'{base}: {len(nums)} literal number(s) in text: {", ".join(nums[:12])}{" ..." if len(nums) > 12 else ""}'
                (errs if final else warns).append(msg)
    # a wording switch on an item that was not run resolves to its pre-registered default by design
    need = set(used) | {k for k in used_word if status.get(k[0], 'pending') != 'not_run'}
    unresolved = sorted(k for k in need if k not in values)
    for it in sorted({i for i, _ in used | used_word}):
        stt = status.get(it, 'pending')
        if stt == 'not_run':
            leaked = sorted(k for i, k in used if i == it)
            if leaked: (errs if final else warns).append(f'item {it} is not_run but its numbers are used outside \\ifitemrun: {leaked}')
        if final and stt == 'pending':
            errs.append(f'item {it} is still "pending" (set run or not_run in pending_status.csv)')
    if final and unresolved:
        errs.append('unresolved placeholders: ' + ', '.join(f'{i}:{k}' for i, k in unresolved))
    errs += g6_r2_check(vrows)
    print(f'{len(used | used_word)} pending references in use; {len(unresolved)} unresolved')
    for u in unresolved: print('  waiting:', f'{u[0]}:{u[1]}')
    for base, nums, lits in lit_report:
        gate = 'gated' if base in LITERAL_GATED else 'reported'
        print(f'literals [{gate}] {base}: {len(nums)} bare, {len(lits)} in \\lit{{}}' + (f' ({", ".join(nums[:8])}{" ..." if len(nums) > 8 else ""})' if nums and gate == 'reported' else ''))
    for w in warns: print('warning:', w)
    if errs:
        print('ERRORS:'); [print('  ', e) for e in errs]; sys.exit(1)
    print('OK' + (' (final gate passed)' if final else ''))

if __name__ == '__main__':
    main()
