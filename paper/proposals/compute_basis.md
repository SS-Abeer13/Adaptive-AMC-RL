# Compute basis for all Checkpoint-5 estimates

Measured on the author's PC: MATLAB R2023a, 16 GB RAM, `n_workers = 2`. Times are the `STEP|…|done|elapsed_min` lines in `Optimized/v17/Dataset/fill_summary_v17.txt`.

| Case | Wall time (min) | Training episodes | 200-TTI trace evaluations |
|---|---|---|---|
| M1_dl_rtt8 | 160.8 (includes one interrupted launch) | 10×3000 + 10×800 + 10×800 = 46,000 | (7 det. + 10 A2C + 10 best-on-val + 1 ens. + 10 offset + 10 resid-800 + 20 bandit) × 500 = 34,000 |
| M3_gp_rtt8 | 70.0 | 10×800 + 5×800 = 12,000 | (7 + 10 + 10 + 1 + 5 + 20) × 500 = 26,500 |

Solving the two linear equations gives, for RTT 8 on 2 workers:
- **≈ 0.14 s wall per training episode** (200 TTI, including A2C updates and bandit training);
- **≈ 0.095 s wall per 200-TTI trace evaluation** (any scheme, including calibration runs).

These are **upper-bound** rates, because M1 includes an interrupted launch. A 400-TTI trace (200 warm-up + 200) counts as about 2 evaluations. RTT-0 cases run faster (M4: 56 min for fewer evaluations). Every proposal includes a 20-trace preflight that measures the true rate before the main run. If the preflight rate is more than 1.5× the basis, the run pauses for the author.
