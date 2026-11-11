"""calla_stats: Confirmatory statistical inference protocol for link adaptation evaluation.

Provides:
- Paired per-trace margins and 90% Student-t confidence intervals
- Two-sided Wilcoxon signed-rank tests
- Holm-Bonferroni family-wise error rate adjustment
- Hierarchical seed x trace bootstrap (preserving Common Random Numbers / pairing)
- Seed-mean bootstrap and one-sided sign tests across training seeds
- Decision rules R1 and R2, and formal pre-registration verdicts (CONFIRM, TRACE, REVERSE, NULL, WIN)
"""

from .core import paired_margin, wilcoxon_test, holm_adjust
from .bootstrap import (
    ensure_seeds_by_traces,
    compute_seed_margins,
    seed_sign_test,
    hierarchical_bootstrap,
    seedmean_bootstrap,
    trace_bootstrap,
)
from .protocol import (
    evaluate_rule_r1,
    evaluate_rule_r2,
    evaluate_verdict,
    evaluate_study,
)
from .io import (
    load_csv,
    save_csv,
    load_json,
    save_json,
    load_mat_eval,
    generate_reporting_card,
)

__version__ = "0.1.0"

__all__ = [
    "paired_margin",
    "wilcoxon_test",
    "holm_adjust",
    "ensure_seeds_by_traces",
    "compute_seed_margins",
    "seed_sign_test",
    "hierarchical_bootstrap",
    "seedmean_bootstrap",
    "trace_bootstrap",
    "evaluate_rule_r1",
    "evaluate_rule_r2",
    "evaluate_verdict",
    "evaluate_study",
    "load_csv",
    "save_csv",
    "load_json",
    "save_json",
    "load_mat_eval",
    "generate_reporting_card",
]
