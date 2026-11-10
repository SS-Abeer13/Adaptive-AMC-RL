# Diagram sources (Mermaid)

| File | Used in | Config |
|---|---|---|
| `f9_protocol.mmd` | `manuscript/figs/f9_protocol.pdf` (Fig. 2, `fig:protocol`) | `mermaid_cfg_paper.json` |
| `roadmap.mmd` | `proposals/figs/roadmap.png`, roadmap doc | `mermaid_cfg.json` |
| `nr2_verdicts.mmd` | `proposals/figs/nr2_verdicts.png`, roadmap doc | `mermaid_cfg.json` |

Render with mermaid-cli:

    npx -p @mermaid-js/mermaid-cli mmdc -c mermaid_cfg_paper.json -i f9_protocol.mmd -o ../manuscript/figs/f9_protocol.pdf

No numbers from results appear in these diagrams; only pre-registered design constants (test levels).
