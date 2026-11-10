# Diagram sources (Mermaid)

| File | Used in | Config |
|---|---|---|
| `f9_protocol.mmd` | `manuscript/figs/f9_protocol.pdf` (Fig. 2, `fig:protocol`) | `mermaid_cfg_paper.json` |
| `f10_nr2.mmd` | `manuscript/figs/f10_nr2.pdf` (appendix, `fig:nr2`) | `mermaid_cfg_tree.json` |
| `roadmap.mmd` | `proposals/figs/roadmap.png`, roadmap doc | `mermaid_cfg.json` |
| `nr2_verdicts.mmd` | `proposals/figs/nr2_verdicts.png`, roadmap doc | `mermaid_cfg.json` |

Render with mermaid-cli:

    npx -p @mermaid-js/mermaid-cli mmdc -c mermaid_cfg_paper.json -i f9_protocol.mmd -o ../manuscript/figs/f9_protocol.pdf

No numbers from results appear in these diagrams; only pre-registered design constants (test levels).

Matplotlib figures (`f1`–`f8`): `common.save()` exports each figure at its exact print width (3.5 in column, 7.16 in full width), so LaTeX includes it at scale 1; fonts are 7.5–8 pt, minimum 7 pt. Run `python f<n>_<name>.py` from this folder.
