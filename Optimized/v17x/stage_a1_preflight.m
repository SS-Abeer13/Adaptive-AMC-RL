function pf = stage_a1_preflight(ctx)
% stage_a1_preflight  Preflight rate benchmark for A1 (re-evaluation by speed class).
% Measures seconds per evaluation on 20 traces and checks against basis (0.095 s).

    addpath(ctx.v17);
    v17_setup;
    r_file = fullfile(ctx.v17, 'Dataset', 'results_v17_M1_dl_rtt8.mat');
    if ~exist(r_file, 'file')
        error('v17x:a1:noM1', 'Cannot find M1 results at %s', r_file);
    end
    S = load(r_file);
    r = S.results;
    env = r.env;
    
    n_pf = 20;
    if isfield(ctx.cfg, 'smoke') && ctx.cfg.smoke
        n_pf = 2;
    end
    
    t0 = tic;
    b0 = min(env.burn_in, 199);
    for j = 1:n_pf
        rng(500000 + j);
        [Strue, ~, meta] = generateChannel_v17(200, env);
        obsS = cqiFeedback_v17(Strue, env, meta.delays);
        meta.trace_id = j;
        rng(510000 + j); U = rand(200, env.N);
        
        rng(77000 + 100*j + 10*5 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17('fixed', [], Strue, obsS, env, meta, U);
        userMetric_v17(env, tp, inf, b0);
    end
    dt = toc(t0);
    sec_per_eval = dt / n_pf;
    
    % Total evaluations in full run: 500 traces * (3 det + 10 seeds A2C) = 6500 evals
    n_eval_total = 500;
    if isfield(ctx.cfg, 'smoke') && ctx.cfg.smoke
        n_eval_total = 2;
    end
    n_units_total = n_eval_total * 13;
    
    pf = struct('unit', 'eval', ...
                'sec_per_unit', sec_per_eval, ...
                'n_units_total', n_units_total, ...
                'note', sprintf('a1: 20-trace benchmark: %.4f s/eval (basis 0.095 s)', sec_per_eval));
end
