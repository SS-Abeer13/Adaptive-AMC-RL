#!/bin/bash
# Repeatable test of the pending-number macros. Run from paper/manuscript:  bash tests/test_pending.sh
# Needs pdflatex and pdftotext. Works in a temp directory; the repository files are not modified.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); fail=0
cp "$HERE"/pending.tex "$HERE"/wording.tex "$HERE"/pending_manifest.csv "$HERE"/build_pending.py "$HERE"/check_pending.py "$HERE"/numbers.tex "$HERE"/tests/pending_test.tex "$T"/
cd "$T"
ok(){ if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }
# --- A: nothing run (G10 not_run)
printf 'item,key,value,source_file,date\n' > pending_values.csv
printf 'item,status\nG1,pending\nW1,pending\nG6,pending\nNR,pending\nG10,not_run\nA1,pending\nA3,pending\nA6,pending\n' > pending_status.csv
python3 -I build_pending.py > /dev/null
pdflatex -interaction=nonstopmode -halt-on-error pending_test.tex > A.log 2>&1
ok "A: compiles without LaTeX errors" "! grep -q '^!' A.log"
ok "A: unresolved numbers are listed in pending_report.txt" "grep -q 'G6:margin_ctxj' pending_report.txt"
ok "A: wording falls back to the conservative default" "pdftotext pending_test.pdf - | tr -d '\n ' | grep -q 'beatstheOLLAfamilyandthesingle-cuecalibratedrules'"
ok "A: 'same-information' is NOT produced before G6" "! pdftotext pending_test.pdf - | tr -d '\n ' | grep -qi 'same-information'"
ok "A: not-run G10 shows the pre-registered default, not numbers" "pdftotext pending_test.pdf - | tr -d '\n ' | grep -q 'oneoperatingpoint'"
ok "A: --final gate FAILS (pending items, unresolved)" "! python3 -I check_pending.py --final > /dev/null"
# --- B: G6, W1, G10 run
printf 'item,key,value,source_file,date\nW1,abstract_gain,9.84,w,d\nW1,abstract_cond,warm,w,d\nG6,verdict,ABJ,w,d\nG6,margin_ctxj,0.87,w,d\nG6,ci_lo_ctxj,0.21,w,d\nG6,holm_ctxj,9.06e-13,w,d\nG10,n_win,3,w,d\nG10,n_tested,4,w,d\nG10,verdict,MIXED,w,d\n' > pending_values.csv
printf 'item,status\nG1,not_run\nW1,run\nG6,run\nNR,not_run\nG10,run\nA1,not_run\nA3,not_run\nA6,not_run\n' > pending_status.csv
python3 -I build_pending.py > /dev/null
pdflatex -interaction=nonstopmode -halt-on-error pending_test.tex > B.log 2>&1
ok "B: compiles without LaTeX errors" "! grep -q '^!' B.log"
ok "B: values appear" "pdftotext pending_test.pdf - | tr -d '\n ' | grep -q '9.84%(afteraWarm\|9.84%(after'"
ok "B: ABJ verdict allows the full C2 wording and 'same-information'" "pdftotext pending_test.pdf - | tr -d '\n ' | grep -q 'beatsallcalibratedcomparators' && pdftotext pending_test.pdf - | tr -d '\n ' | grep -q 'same-information'"
ok "B: run G10 shows its numbers" "pdftotext pending_test.pdf - | tr -d '\n ' | grep -q 'Grid:3of4cells'"
ok "B: no unresolved placeholders in the report" "[ -z \"\$(tr -d ' \n' < pending_report.txt)\" ]"
ok "B: --final gate passes" "python3 -I check_pending.py --final > /dev/null"
# --- C: G6 verdict ABJ-seed (R2 fails for the best comparator): qualifier present, "same-information" only qualified
printf 'item,key,value,source_file,date\nW1,abstract_gain,9.84,w,d\nW1,abstract_cond,warm,w,d\nG6,verdict,ABJ-seed,w,d\nG6,margin_ctxj,0.66,w,d\nG6,ci_lo_ctxj,0.29,w,d\nG6,holm_ctxj,1.05e-3,w,d\nG10,verdict,MIXED,w,d\nG10,n_win,1,w,d\nG10,n_tested,2,w,d\n' > pending_values.csv
python3 -I build_pending.py > /dev/null
pdflatex -interaction=nonstopmode -halt-on-error pending_test.tex > C.log 2>&1
ok "C: compiles" "! grep -q '^!' C.log"
ok "C: ABJ-seed carries the R2 qualifier" "pdftotext pending_test.pdf - | tr -d '\n ' | grep -q 'notrobusttoseedresampling'"
ok "C: same-information appears only with 'not robustly across training seeds'" "pdftotext pending_test.pdf - | tr -d '\n ' | grep -q 'same-informationcomparison,whichthelearnerwinsonevaluationtracesbutnotrobustlyacrosstrainingseeds'"
# --- D: literal-number gate
printf 'The margin is 0.66 %%.\n' > sec_results.tex
ok "D: --final fails on a literal number in a gated file" "! python3 -I check_pending.py --final > /dev/null && python3 -I check_pending.py --final | grep -q 'literal number'"
printf 'The action is $\\delta=\\lit{0}$, case M1, Context-500, ns-3.\n' > sec_results.tex
ok "D: \\lit{}, identifiers and names pass the literal gate" "python3 -I check_pending.py --final > /dev/null"
rm -f sec_results.tex
# --- E: G6 verdict vs Rule R2 for the best comparator
printf 'comparator,margin_pct,seed_robust_R2,hier_boot_ci95_lo,hier_boot_ci95_hi\nContext-joint-500,0.66,0,-0.30,1.70\nContext-500,1.43,1,0.47,2.46\n' > g6s.csv
ok "E: ABJ-seed agrees with R2 (gate passes)" "G6_SEED_STATS=g6s.csv python3 -I check_pending.py --final > /dev/null"
sed -i 's/G6,verdict,ABJ-seed/G6,verdict,ABJ/' pending_values.csv
ok "E: ABJ with a non-robust best comparator FAILS the gate" "! G6_SEED_STATS=g6s.csv python3 -I check_pending.py --final > /dev/null"
rm -rf "$T"; [ $fail -eq 0 ] && echo "ALL PENDING-MACRO TESTS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
