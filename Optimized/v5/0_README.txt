==============================================================================
  v5 -- RL-AMC STACK (CURRENT BEST)
==============================================================================


If you only want to reproduce results, jump to "HOW TO RUN" below.


==============================================================================
  WHAT'S IN THIS FOLDER
==============================================================================

------------------------------------------------------------------------------
  ENTRY POINTS (run these)
------------------------------------------------------------------------------

  runCase23_v5.m
      MAIN HARNESS. Multi-user (N in {5, 10, 20, 50}) with PF / RR / EQ
      schedulers, trains all three RL algorithms, runs multi-seed statistical
      evaluation, writes .mat + .txt, plots figures.

  runCase1_v5.m
      Single-user radial variant. Use for the smallest sanity check.

  runComparison_v5.m
      Cross-algorithm comparison + plot generation (called internally by the
      harnesses; can also be run standalone).

  sweepDelay_v5.m
      Sweep CQI feedback delay in {0, 2, 4, 6, 8} TTI. Headline figure: RL
      margin vs delay.

  sweepN_v5.m
      Sweep cell size N in {5, 10, 20, 50}. Scaling study.

  replotFromResults_v5.m
      Re-render figures from an existing results_v5_case23_N*.mat without
      re-training.

  plotPolicyHeatmap_v5.m
      Explainability plot: learned offset vs baseline, split by rising / flat
      / falling SINR trend.

------------------------------------------------------------------------------
  ENVIRONMENT AND HELPERS
------------------------------------------------------------------------------

  defaultEnv_v5.m
      Central config: MDP shape, channel params, CQI feedback, reward
      normaliser rho, action set, scheduler mix. Take-once, override-via-
      struct pattern.

  generateChannel_v5.m
      TR 38.901 urban-macro channel generation for arbitrary N users.

  cqiFeedback_v5.m
      Delayed (5 TTI) + log-Normal-noisy (sigma = 1.5 dB) + 4-bit-quantized
      CQI observation.

  baseCQI_v5.m
      Observed SINR -> baseline CQI via 3GPP threshold table.

  estimateBLER_v5.m
      Sigmoid link-abstraction BLER model, calibrated per MCS.

  computeReward_v5.m
      (1 - BLER) * TBS * 1e-3 / rho, with rho = 30 Mbps.

  schedule_users_v5.m
      Dispatcher for PF / RR / EQ scheduling.

  schedContext_v5.m
      Maps active scheduler -> one-hot for the state vector.

  sampleSched_v5.m
      Weighted sampler for the training scheduler mix.

  trendBin_v5.m
      3-bin SINR trend feature: {-1, 0, +1}.

  argmaxNoOp_v5.m
      argmax with random tie-break (avoids the zero-init argmax bias).

------------------------------------------------------------------------------
  ALGORITHMS (three shared-parameter learners)
------------------------------------------------------------------------------

  QL_Shared_v5.m
      Shared Q-Learning. One Q-table of shape 15 x 11 x 20 x 3 x 5 trained by
      every user's transitions. Epsilon-greedy, alpha = 0.10, gamma = 0.95.

  AC_Shared_v5.m
      Shared tabular Actor-Critic. theta in R^(15x11x20x3x5), V in
      R^(15x11x20x3). alpha_theta = 0.05, alpha_v = 0.10, gamma = 0.95.
      Numerically-stable softmax (max-subtract).

  DeepA2C_Shared_v5.m
      Shared-network Deep A2C. Actor 4->64->64->5, critic 4->64->64->1,
      both Adam (5e-4 / 1e-3), n_step = 10, advantage standardised, entropy
      annealed 0.05 -> 0.001, global gradient clip 5.0. GPU-aware.

------------------------------------------------------------------------------
  EVALUATION
------------------------------------------------------------------------------

  evalPolicy_v5.m
      Frozen-policy evaluation for any trained learner, plus Baseline and
      OLLA for reference. Returns cell Tp, edge Tp, BLER, Jain, CQI-error.

------------------------------------------------------------------------------
  RESULT FILES (already produced)
------------------------------------------------------------------------------

  results_v5_case23_N5.mat / .txt   -- N = 5, 3 seeds, 20 eval traces,
                                       400 episodes per algo, PF/RR/EQ
  results_v5_case23_N10.mat / .txt  -- N = 10
  results_v5_case23_N20.mat / .txt  -- N = 20
  results_v5_case23_N50.mat / .txt  -- N = 50
  sweepN_v5_case23.mat              -- cell-size sweep aggregate
  1.jpg .. 4.jpg                    -- snapshot figures from earlier run

The .txt files are human-readable and self-contained -- open one for a fully
annotated results table with per-scheduler breakdown and Wilcoxon p-values.


==============================================================================
  HOW TO RUN
==============================================================================

Cold start:

    cd 'G:\8th Semester\Case 1\Case 1\optimized\v5'
    results = runCase23_v5();                   % N = 5, defaults

Common variations:

    results = runCase23_v5('N', 10);            % N = 10 users
    results = runCase23_v5('N', 50);            % N = 50 users (scale study)
    results = runCase23_v5('n_seeds', 5);       % more seeds for tighter CIs
    results = runCase23_v5('ep_deep', 600);     % longer Deep A2C training

    % camera-ready
    results = runCase23_v5('N', 50, 'n_seeds', 5, 'n_eval', 30, 'ep_deep', 300);

Focus on one evaluation scheduler:

    results = runCase23_v5('eval_schedulers', {'pf'});           % PF only
    results = runCase23_v5('eval_schedulers', {'rr'});           % RR only
    results = runCase23_v5('eval_schedulers', {'pf','rr','eq'}); % default

Sensitivity studies:

    S = sweepDelay_v5([0 2 4 6 8]);             % delay sensitivity (headline)
    S = sweepDelay_v5([0 2 4 6 8], 23, struct('N', 10, 'n_seeds', 3));
    S = sweepN_v5([5 10 20 50]);                % cell-size sweep

Re-plot without re-training:

    replotFromResults_v5('results_v5_case23_N10.mat');

Explainability heatmap for a single trained policy:

    plotPolicyHeatmap_v5(results.policies.AC{1});


==============================================================================
  WHAT EACH RUN PRODUCES
==============================================================================

A runCase23_v5 call writes:

  * results_v5_case23_N<N>.mat -- all metrics, learning curves, trained
                                  policies.
  * results_v5_case23_N<N>.txt -- human-readable results table (one section
                                  per evaluation scheduler + robustness
                                  summary).
  * MATLAB figures            -- KPI bars with CIs, learning curves + Deep
                                  A2C entropy, throughput vs distance, policy
                                  heatmap.

For paper-ready Python-generated figures over the .mat outputs, see
../../docs/figures_v5/.


==============================================================================
  COMPUTE BUDGET
==============================================================================

On Ryzen 7 7700X + RTX 5060 Ti 16 GB:

  runCase23_v5() at N = 5, defaults ................ ~30 min
  runCase23_v5('N', 10) ............................ ~35 min
  runCase23_v5('N', 20) ............................ ~45 min
  runCase23_v5('N', 50) ............................ ~55 min
  Full sweep {5, 10, 20, 50} ....................... ~2 h 45 min

The Deep A2C training is the dominant cost; on CPU it's roughly 3x slower.


==============================================================================
  DEPENDENCIES
==============================================================================

  * MATLAB R2024a+.
  * Deep Learning Toolbox (for dlnetwork / dlgradient).
  * Parallel Computing Toolbox (optional, for GPU).
  * Statistics and Machine Learning Toolbox (optional, for Wilcoxon signrank).
  * ../case2_3/createTBS_Table.m and tbsFromMCSandRB.m -- added to the path
    automatically by the harness.

For RTX 50-series (Blackwell, sm_120) the harness calls

    parallel.gpu.enableCUDAForwardCompatibility(true)

before touching the GPU. This is wrapped in try/catch for backward
compatibility with pre-R2023b MATLAB.


==============================================================================
  VERSION POSITION
==============================================================================

v5 supersedes v1-v4. Cite v5 numbers in the paper. The defensible headline
claim: under realistic imperfect CQI, a shared-network A2C learning
baseline-relative CQI offsets outperforms fixed-mapping and OLLA link
adaptation and tabular RL, with statistically significant margins, and
degrades least under scheduler shift.

Details of what changed between versions are in ../../README.md and
../../docs/Case1_Parameter_Audit.pdf.
