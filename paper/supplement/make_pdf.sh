#!/bin/bash
# Build supplement.pdf: pandoc converts each frozen Markdown text (unchanged; only line-break
# points are added inside \texttt paths), XeLaTeX typesets. Run from paper/supplement.
set -e
cd "$(dirname "$0")"
for f in files/S3_preregistration/*.md; do
  b=$(basename "$f"); n=$(echo "$b" | sed 's/[^A-Za-z0-9]/_/g')
  pandoc "$f" -f markdown-yaml_metadata_block -t latex --columns=60 --wrap=preserve --shift-heading-level-by=2 -o "md_${n}.tex"
  python3 - "md_${n}.tex" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
brk = lambda m: r'\texttt{' + m.group(1).replace('/', r'/\allowbreak{}').replace(r'\_', r'\_\allowbreak{}').replace('.', r'.\allowbreak{}') + '}'
open(p, 'w', encoding='utf-8').write(re.sub(r'\\texttt\{([^{}]*)\}', brk, s))
PY
done
latexmk -xelatex -interaction=nonstopmode -halt-on-error supplement.tex > /dev/null
echo "pages: $(pdfinfo supplement.pdf | awk '/Pages/{print $2}')"
