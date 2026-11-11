"""Command line interface for calla-stats."""

from __future__ import annotations
import argparse
import sys
import numpy as np

from .core import paired_margin, wilcoxon_test, holm_adjust
from .bootstrap import hierarchical_bootstrap, seedmean_bootstrap, seed_sign_test
from .protocol import evaluate_study, evaluate_rule_r1, evaluate_rule_r2
from .io import load_csv, load_json, save_csv, save_json, generate_reporting_card


def main():
    parser = argparse.ArgumentParser(
        prog="calla-stats",
        description="Confirmatory statistical inference protocol for wireless link adaptation",
    )
    subparsers = parser.add_subparsers(dest="command", help="Sub-commands")

    # Command: card
    parser_card = subparsers.add_parser("card", help="Generate a markdown reporting card template")
    parser_card.add_argument("--output", "-o", default=None, help="Output file path (default: stdout)")

    # Command: eval-json
    parser_eval = subparsers.add_parser("eval", help="Evaluate treatment against family of comparators from JSON")
    parser_eval.add_argument("--input", "-i", required=True, help="Path to input JSON file")
    parser_eval.add_argument("--primary", "-p", required=True, help="Name of primary comparator")
    parser_eval.add_argument("--out-csv", help="Path to save family results CSV")
    parser_eval.add_argument("--out-json", help="Path to save full results JSON")
    parser_eval.add_argument("--B", type=int, default=20000, help="Bootstrap iterations (default 20000)")
    parser_eval.add_argument("--seed", type=int, default=20261104, help="RNG seed for hierarchical bootstrap")

    args = parser.parse_args()

    if args.command == "card":
        card = generate_reporting_card()
        if args.output:
            with open(args.output, "w", encoding="utf-8") as f:
                f.write(card)
            print(f"Reporting card written to {args.output}")
        else:
            print(card)
        return

    if args.command == "eval":
        data = load_json(args.input)
        treatment = np.asarray(data["treatment"], dtype=float)
        comparators = {k: np.asarray(v, dtype=float) for k, v in data["comparators"].items()}

        res = evaluate_study(
            treatment_seeds=treatment,
            comparators=comparators,
            primary_comparator=args.primary,
            B=args.B,
            rng_hier=args.seed,
            rng_seed=args.seed + 1,
        )

        print(f"Verdict: {res['verdict']['verdict']} | WIN: {'yes' if res['verdict']['win'] else 'no'} | Gate: {res['verdict']['reframing_gate']}")
        prim = res["primary_stats"]
        print(f"vs {args.primary}:")
        print(f"  Hierarchical 95% CI: [{prim['hier95_lo']:.2f}%, {prim['hier95_hi']:.2f}%]")
        print(f"  Seeds > 0: {prim['seeds_above']}/{prim['n_seeds']} (sign test p = {prim['sign_p']:.4g})")

        if args.out_csv:
            save_csv(res["family_results"], args.out_csv)
            print(f"Family table saved to {args.out_csv}")
        if args.out_json:
            save_json(res, args.out_json)
            print(f"Full results saved to {args.out_json}")
        return

    parser.print_help()


if __name__ == "__main__":
    main()
