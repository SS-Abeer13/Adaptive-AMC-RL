"""check_disjointness_ft.py -- Widened disjointness check (Amendment 14 Section 4).
Scans all .m and .py files under Optimized/ and Optimized/case_registry.csv
for rng(, randi, RandStream, and seed_base constants, verifies zero overlap
with FT ranges:
  - Evaluation traces: 7,000,001 .. 7,000,500 (7000000 + j)
  - CRN:               7,100,001 .. 7,100,500 (7100000 + j)
  - Decision draws:    7,200,101 .. 7,250,099 (7200000 + 100*j + s, s <= 99)
"""
import os
import re
import csv

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OPT_DIR = os.path.join(REPO_ROOT, "Optimized")
OUT_TXT = os.path.join(OPT_DIR, "v17x", "Dataset", "ft", "ft_disjointness.txt")
os.makedirs(os.path.dirname(OUT_TXT), exist_ok=True)

FT_TRACES = (7000001, 7000500)
FT_CRN    = (7100001, 7100500)
FT_DEC    = (7200101, 7250099)


def main():
    seed_hits = {}  # base_val -> set of files

    # 1. Scan all .m and .py under Optimized/ (excluding v17x/ft/ itself)
    for root, _, files in os.walk(OPT_DIR):
        norm_root = root.replace("\\", "/")
        if norm_root.endswith("/v17x/ft"):
            continue
        for fn in files:
            if not fn.endswith((".m", ".py")):
                continue
            p = os.path.join(root, fn)
            rel = os.path.relpath(p, REPO_ROOT).replace("\\", "/")
            try:
                txt = open(p, "r", encoding="utf-8", errors="ignore").read()
            except Exception:
                continue
            for line in txt.splitlines():
                low = line.lower()
                if any(tok in low for tok in ["rng(", "randi", "randstream", "seed_base", "tr_b", "crn_b", "exp_b"]):
                    for m in re.finditer(r"\b(\d{4,9})\b", line):
                        val = int(m.group(1))
                        # Ignore date-like constants 2026xxxx
                        if 20260000 <= val <= 20269999:
                            continue
                        seed_hits.setdefault(val, set()).add(rel)

    # 2. Scan case_registry.csv
    reg_path = os.path.join(OPT_DIR, "case_registry.csv")
    if os.path.exists(reg_path):
        with open(reg_path, "r", encoding="utf-8", errors="ignore") as f:
            for row in csv.reader(f):
                for cell in row:
                    for m in re.finditer(r"\b(\d{4,9})\b", cell):
                        val = int(m.group(1))
                        if 20260000 <= val <= 20269999:
                            continue
                        seed_hits.setdefault(val, set()).add("Optimized/case_registry.csv")

    # Check overlaps with FT ranges (conservative +/- 50,000 span around any base >= 1,000,000)
    collisions = []
    for val, files in sorted(seed_hits.items()):
        span_hi = val + 50000
        for name, (lo, hi) in [("FT_TRACES", FT_TRACES), ("FT_CRN", FT_CRN), ("FT_DEC", FT_DEC)]:
            if not (span_hi < lo or val > hi):
                collisions.append((name, val, sorted(files)))

    lines = []
    lines.append("=" * 88)
    lines.append("AMENDMENT 14 WIDENED DISJOINTNESS CHECK (all Optimized/ .m/.py + case_registry.csv)")
    lines.append("=" * 88)
    lines.append(f"FT Evaluation Traces : {FT_TRACES[0]:,} .. {FT_TRACES[1]:,}")
    lines.append(f"FT CRN               : {FT_CRN[0]:,} .. {FT_CRN[1]:,}")
    lines.append(f"FT Decision Draws    : {FT_DEC[0]:,} .. {FT_DEC[1]:,}")
    lines.append("")
    lines.append(f"Occupied seed bases >= 1,000 found ({len(seed_hits)} distinct values):")
    for val in sorted(seed_hits.keys()):
        if val >= 1000:
            flist = ", ".join(sorted(seed_hits[val])[:4])
            if len(seed_hits[val]) > 4:
                flist += f" (+{len(seed_hits[val]) - 4} more)"
            lines.append(f"  {val:>10d}  | {flist}")

    lines.append("")
    if collisions:
        lines.append("DISJOINTNESS RESULT: FAILED")
        for c in collisions:
            lines.append(f"  COLLISION: {c}")
    else:
        lines.append("DISJOINTNESS RESULT: PASS (0 collisions with FT ranges)")

    with open(OUT_TXT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print("\n".join(lines))
    assert not collisions, f"Disjointness failed: {collisions}"


if __name__ == "__main__":
    main()
