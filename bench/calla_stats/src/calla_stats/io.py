"""I/O routines for CSV and JSON formats and reporting card generation."""

from __future__ import annotations
import csv
import json
import os
from typing import Any, Dict, List, Optional, Union
import numpy as np


def load_csv(path: str) -> List[Dict[str, str]]:
    """Read a CSV file into a list of row dictionaries."""
    with open(path, mode="r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        return list(reader)


def save_csv(
    rows: List[Dict[str, Any]],
    path: str,
    fieldnames: Optional[List[str]] = None,
) -> None:
    """Write a list of row dictionaries to a CSV file."""
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    if not rows and not fieldnames:
        raise ValueError("Cannot write empty CSV without fieldnames")

    if fieldnames is None:
        fieldnames = list(rows[0].keys())

    with open(path, mode="w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in rows:
            formatted_row = {}
            for k in fieldnames:
                v = r.get(k, "")
                if isinstance(v, float):
                    if abs(v) < 1e-4 and v != 0.0:
                        formatted_row[k] = f"{v:.3e}"
                    else:
                        formatted_row[k] = f"{v:.4f}"
                else:
                    formatted_row[k] = v
            writer.writerow(formatted_row)


def load_json(path: str) -> Dict[str, Any]:
    """Read a JSON file into a Python dictionary."""
    with open(path, mode="r", encoding="utf-8") as f:
        return json.load(f)


def save_json(data: Any, path: str, indent: int = 2) -> None:
    """Save serializable data or numpy structures to a JSON file."""
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)

    class NumpyEncoder(json.JSONEncoder):
        def default(self, obj):
            if isinstance(obj, (np.integer, np.int64, np.int32)):
                return int(obj)
            if isinstance(obj, (np.floating, np.float64, np.float32)):
                return float(obj)
            if isinstance(obj, np.ndarray):
                return obj.tolist()
            if isinstance(obj, (np.bool_, bool)):
                return bool(obj)
            return super().default(obj)

    with open(path, mode="w", encoding="utf-8") as f:
        json.dump(data, f, cls=NumpyEncoder, indent=indent)


def load_mat_eval(path: str) -> Dict[str, Any]:
    """Load evaluation data from a MATLAB v7.3 / HDF5 file (no MATLAB runtime required)."""
    import h5py

    def _decode_str(f, ref):
        data = np.array(f[ref]).flatten()
        return "".join(chr(c) for c in data)

    with h5py.File(path, "r") as f:
        if "out" in f:
            o = f["out"]
            res = {}
            if "nr2_seeds" in o:
                res["nr2_seeds"] = np.array(o["nr2_seeds"])
            if "m1_seeds" in o:
                res["m1_seeds"] = np.array(o["m1_seeds"])
            if "nr2_ens" in o:
                res["nr2_ens"] = np.array(o["nr2_ens"]).flatten()
            if "cmp" in o:
                cmp_grp = o["cmp"]
                res["cmp"] = {k: np.array(cmp_grp[k]).flatten() for k in cmp_grp.keys()}
            if "cmpNames" in o and "cmp_vals" in o:
                names = [_decode_str(f, r) for r in np.array(o["cmpNames"]).flatten()]
                vals = [np.array(f[r]).flatten() for r in np.array(o["cmp_vals"]).flatten()]
                res["comparators"] = dict(zip(names, vals))
            if "rl_prim" in o:
                res["primary"] = np.array(o["rl_prim"]).flatten()
            if "rl_seeds" in o:
                res["seeds"] = np.array(o["rl_seeds"])
            if "r2_ci" in o:
                res["r2_ci"] = np.array(o["r2_ci"]).flatten()
            return res
        elif "results" in f:
            r = f["results"]
            schemes = [_decode_str(f, x) for x in np.array(r["schemes"]).flatten()]
            M = r["metrics"]
            out_metrics = {}
            for key in ["primary", "cell_tp", "ontime", "jain", "edge_tp"]:
                if key in M:
                    refs = np.array(M[key]).flatten()
                    out_metrics[key] = {}
                    for s, ref in zip(schemes, refs):
                        a = np.array(f[ref])
                        out_metrics[key][s] = a.T if a.shape[0] > a.shape[1] else a
            return {"schemes": schemes, "metrics": out_metrics}
        else:
            raise ValueError(f"Unrecognized HDF5/mat layout in {path}")


def generate_reporting_card(
    protocol_version: str = "v17x / Amendment 5",
    study_id: str = "M1_dl_rtt8",
    treatment_name: str = "Deep A2C (NR recipe)",
    comparator_name: str = "Context-joint-500",
    traffic_profile: str = "Deadline (RTT = 8 TTIs)",
    scheduler: str = "Proportional Fair (scheduled rate average)",
    harq_rtt: int = 8,
    target_bler: float = 0.10,
    achieved_bler: float = 0.089,
    calibration_budget: str = "20 traces x 5 schemes (seeds 60001+)",
    evaluation_budget: str = "500 traces x 10 seeds (seeds 70001+)",
    split_disjointness: str = "Verified disjoint: calibration seeds != eval seeds != CRN",
    pf_avg_definition: str = "R_ema = (1 - 0.05)*R_ema + 0.05*r_sched",
    rule_r1_result: str = "PASS (+3.35%, 90% CI [+2.93, +3.76], Holm p = 3.68e-30)",
    rule_r2_result: str = "PASS (hierarchical 95% CI [+2.22, +4.40], 9/10 seeds > 0)",
    final_verdict: str = "CONFIRM / WIN (reframing gate OPEN)",
) -> str:
    """Generate a formatted markdown evaluation reporting card."""
    card = f"""# Wireless Link Adaptation Evaluation Reporting Card

## 1. Study Information & Protocol Identification
| Parameter | Value |
|:---|:---|
| Protocol Specification | {protocol_version} |
| Evaluation Case / Study ID | {study_id} |
| Treatment Scheme | {treatment_name} |
| Primary Comparator | {comparator_name} |
| Traffic Model | {traffic_profile} |
| Multi-user Scheduler | {scheduler} |
| HARQ Feedback Delay | {harq_rtt} TTIs |
| Target First-Tx BLER | {target_bler:.2f} |
| Achieved First-Tx BLER | {achieved_bler:.3f} |

## 2. Experimental Rigor & Calibration Budgets
| Rigor Dimension | Specification |
|:---|:---|
| Calibration Traces & Seeds | {calibration_budget} |
| Evaluation Traces & Seeds | {evaluation_budget} |
| Data Split & Seed Disjointness | {split_disjointness} |
| PF Average Definition | `{pf_avg_definition}` |
| HARQ State Timing | RTT-delayed ACK/NACK credit allocation |

## 3. Decision Rules & Pre-registered Verdict
| Criterion | Metric & Threshold | Outcome |
|:---|:---|:---|
| Rule R1 (Trace-Level Superiority) | Holm p < 0.05 AND 90% CI lower bound > 0 | **{rule_r1_result}** |
| Rule R2 (Seed-Level Generalizability)| Hierarchical 95% CI lower bound > 0 vs Primary | **{rule_r2_result}** |
| Pre-registered Verdict | CONFIRM / TRACE / REVERSE / NULL | **{final_verdict}** |
"""
    return card
