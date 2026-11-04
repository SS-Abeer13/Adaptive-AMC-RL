"""Scan the manuscript for pending-number macros and wording switches.
  python3 -I check_pending.py            report only (exit 0 unless a typo/unknown key is found)
  python3 -I check_pending.py --final    submission gate: also fail on unresolved placeholders,
                                         items still 'pending', and numbers of 'not_run' items
Dead branches of \\ifitemrun{ITEM}{run text}{default text} are ignored, so numbers inside the
run branch of an item that was not run do not count.
"""
import csv, glob, re, sys, os

MACRO = {'Gone': 'G1', 'Wone': 'W1', 'Gsix': 'G6', 'NR': 'NR', 'Gten': 'G10', 'Aone': 'A1', 'Athree': 'A3', 'Asix': 'A6'}
SKIP = {'pending.tex', 'wording.tex', 'pending_values.tex', 'pending_status.tex'}

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

def main():
    final = '--final' in sys.argv
    man = {(r['item'], r['key']) for r in csv.DictReader(open('pending_manifest.csv', newline=''))}
    items = {i for i, _ in man}
    status = {r['item']: r['status'] for r in csv.DictReader(open('pending_status.csv', newline=''))}
    values = {(r['item'], r['key']) for r in csv.DictReader(open('pending_values.csv', newline=''))}
    errs, warns, used, used_word = [], [], set(), set()
    for f in sorted(glob.glob('*.tex') + glob.glob('sections/*.tex')):
        if os.path.basename(f) in SKIP: continue
        s = resolve_ifitemrun(open(f, encoding='utf-8').read(), status)
        s = re.sub(r'(?<!\\)%.*', '', s)
        for m, key in re.findall(r'\\(Gone|Wone|Gsix|NR|Gten|Aone|Athree|Asix)\s*\{([^}]*)\}', s):
            it = MACRO[m]
            if (it, key) not in man: errs.append(f'{f}: \\{m}{{{key}}} is not in pending_manifest.csv (typo?)')
            used.add((it, key))
        for slot, it, key, dflt in re.findall(r'\\wordingsel\s*\{([^}]*)\}\s*\{([^}]*)\}\s*\{([^}]*)\}\s*\{([^}]*)\}', s):
            if (it, key) not in man: errs.append(f'{f}: \\wordingsel uses unknown ({it},{key})')
            used_word.add((it, key))
        for it in re.findall(r'\\ifitemrun\s*\{([^}]*)\}', s):
            if it not in items: errs.append(f'{f}: \\ifitemrun with unknown item {it}')
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
    print(f'{len(used | used_word)} pending references in use; {len(unresolved)} unresolved')
    for u in unresolved: print('  waiting:', f'{u[0]}:{u[1]}')
    for w in warns: print('warning:', w)
    if errs:
        print('ERRORS:'); [print('  ', e) for e in errs]; sys.exit(1)
    print('OK' + (' (final gate passed)' if final else ''))

if __name__ == '__main__':
    main()
