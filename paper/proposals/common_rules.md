# Common rules for the Checkpoint-5 runs (G1, W1, G6, NR1, G10, A1, A3)

**STATUS: FROZEN (Checkpoint 5, 4 Nov 2026)** together with the pre-registrations that cite it (G6, W1, NR1, G10).

**R1. "Beats X"** = two-sided Wilcoxon signed-rank on paired per-trace values, Holm-adjusted over the case's comparator family (p < 0.05), **and** the 90 % CI lower bound of the paired % margin > 0. Identical to `analyze_v17_replication.m`. Claim A, Claim B and WIN are defined as in `README_v17.md` §3.3, with the family size stated in each pre-registration.

**R2. Seed-level rule.** For every claim "beats the best comparator", the hierarchical seed × trace bootstrap (B = 20,000; seeds resampled, then traces) 95 % CI of the margin is reported, together with the sign test over the per-seed margins and the bootstrap over the seed margins (as in `paper/analysis/g3_seed_stats.py`). If a claim passes R1 but the hierarchical 95 % lower bound is ≤ 0, every statement of that claim in the paper adds "not robust to seed resampling" and the interval. For M1 vs Context and vs Fixed all seed-level lower bounds are > 0 (ledger G3a, G3g, G3h), so no such qualifier applies to M1 as it stands.

**R3. No selection on evaluation traces.** Calibration, base-rule choice, table search and every hyper-parameter use only calibration/validation traces. Calibrated tables are written to a file and hashed (SHA-256, logged) before any evaluation-trace run. A stage that needs the hash refuses to run without it.

**R4. Determinism and pairing.** Evaluation uses the traces and CRN draws given in each pre-registration. Frozen v17 evaluators are used unchanged, or an instrumented copy that passes a bit-identity test against the frozen one before use. Training seeds and trace ranges are disjoint from all earlier rounds (the code asserts it).

**R5. Preflight and pause rule.** Every stage runs a 20-trace preflight and measures seconds per unit (one 200-TTI trace evaluation, or one training episode). Basis (`compute_basis.md`): 0.095 s per evaluation, 0.14 s per training episode, 2 workers, RTT 8. The runner prints the projected stage time. If the measured rate exceeds **1.5×** the basis, the stage **pauses**: it writes `PAUSED_<stage>.txt` and exits without starting. The author resumes by creating `APPROVE_<stage>.txt`. A measured rate below the basis never pauses and only scales the projection down.

**R6. Failure handling.** A stage that errors writes `ERROR_<stage>.txt` (message and stack) and **no** "done" marker. It is retried at most once after a restart; if the second attempt also errors, the pipeline halts (default) and the status file reads `HALTED`. A native crash (no marker written) triggers a restart of the whole runner from the checkpoints. "FINISHED" is written only when every requested stage has a done marker.

**R7. Multiplicity bookkeeping.** Each stage's new registry rows are listed in its pre-registration. All of them are robustness checks or design ablations of M1, never new claims.

**R8. Parallelism.** 2 parfor workers (`n_workers = 2`). A larger pool only by explicit author decision (4 workers ran out of memory in v17 M1).
