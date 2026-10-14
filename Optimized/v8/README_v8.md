# RL-AMC v8 — Autonomous Link Adaptation in 5G/6G Macrocells

**Design rationale:** [`V8_DESIGN_PLAN.md`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/V8_DESIGN_PLAN.md).  
**Review response:** [`RESPONSE_TO_REVIEWERS.md`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/RESPONSE_TO_REVIEWERS.md).  
**Technical report:** [`v8_technical_process_report.md`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/v8_technical_process_report.md).

RL-AMC v8 is the comprehensive, post-peer-review architectural overhaul that resolves all 10 major and minor vulnerabilities identified in the v7 report. It introduces strictly autonomous learning (Zero Behavior Cloning), per-user scheduled credit assignment, modern multi-loop link adaptation (`MultiOLLA`), dual evaluation horizons (transient vs. steady-state), and formal Two One-Sided Tests (TOST) for statistical equivalence.

---

## Core File Manifest

| File | Role |
|---|---|
| [`defaultEnv_v8.m`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/defaultEnv_v8.m) | 3GPP macrocell physical parameters, -92.0 dBm noise floor, actions [-6, +4], bc_warm_eps = 0 |
| [`txStep_v8.m`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/txStep_v8.m) | Physical transmission step: Chase combining, accumulated SINR tracking, scaled retx penalties |
| [`estimateBLER_v8.m`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/estimateBLER_v8.m) | 15-CQI 3GPP AWGN sigmoidal BLER waterfall curves anchored at 10% target BLER |
| [`cqiFeedback_v8.m`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/cqiFeedback_v8.m) | Per-user feedback reporting with delay and 1.0 dB measurement noise |
| [`harqInit_v8.m`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/harqInit_v8.m) | HARQ state container for pending retx, attempt counters, and soft-combined SINR |
| [`userClass_v8.m`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/userClass_v8.m) | 2×3 velocity and delay partitioner for class-based link adaptation |
| [`calibrateFixedClass_v8.m`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/calibrateFixedClass_v8.m) | Disjoint trace calibration harness for Fixed, Fixed-Online, and FixedPU |
| [`MultiOLLA_v8.m`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/MultiOLLA_v8.m) | Modern dual-loop link adaptation (Ahsen et al. [arXiv:2604.20459]) |
| [`stateFeat_v8.m`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/stateFeat_v8.m) | 17-dimensional continuous state vector with speed, burst, HARQ, and scheduler context |
| [`DeepA2C_Shared_v8.m`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/DeepA2C_Shared_v8.m) | Autonomous n-step A2C trainer with scheduled credit assignment and 86.9x BLAS acceleration |
| [`evalPolicy_v8.m`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/evalPolicy_v8.m) | Unified evaluator across all 8 comparator schemes |
| [`runComparison_v8.m`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/runComparison_v8.m) | Master evaluation harness with Wilcoxon signed-rank and TOST equivalence tests |
| [`test_v8_smoke.m`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/test_v8_smoke.m) | 6-point architectural verification smoke test |
| [`generate_figures_v8.m`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/generate_figures_v8.m) | Publication-quality figure generator (PNG + FIG) |
| [`run_v8_campaign.m`](file:///d:/Adaptive%20AMC%20A2C+QL/Optimized/v8/run_v8_campaign.m) | Full multi-condition headless campaign runner |

---

## 8 Comparator Schemes Evaluated

1. **Baseline**: Uncorrected inner-loop CQI mapping.
2. **OLLA**: Standard single-loop Outer Loop Link Adaptation ($\delta_{down} = 0.5$ dB).
3. **Warm-OLLA**: Pre-converged OLLA over 1000 TTIs.
4. **Multi-OLLA**: Modern dual fast/slow loop adaptation (Ahsen et al. [arXiv:2604.20459]).
5. **Fixed**: Best global scalar offset.
6. **Fixed-Online**: Realistic online Doppler and delay class estimator.
7. **FixedPU (Oracle)**: Idealized upper-bound oracle with zero-overhead class knowledge.
8. **Deep A2C v8**: Autonomous actor-critic network with temporal sequence memory ($L=3$) and scheduled credit assignment.

---

## How to Run

From MATLAB or PowerShell in the repository root:

```bash
# 1. Run architectural smoke test (takes ~8 seconds)
matlab -batch "addpath('Optimized/v8'); test_v8_smoke"

# 2. Run full multi-condition campaign (Headline, Calm, Severe Burst, Tier-A, Steady-State)
matlab -batch "addpath('Optimized/v8'); run_v8_campaign"

# 3. Generate publication figures
matlab -batch "addpath('Optimized/v8'); generate_figures_v8"

# 4. Compile Comprehensive Evaluation Report PDF
python Docs/v8/generate_report_pdf.py
```

Results are saved to `Optimized/v8/Dataset/` and figures are saved to `Docs/figures/v8/` and `Optimized/v8/figures/`.
