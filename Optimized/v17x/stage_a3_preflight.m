function pf = stage_a3_preflight(ctx)
% stage_a3_preflight  Preflight rate benchmark for A3 (inference timing microbenchmark).

    addpath(ctx.v17);
    v17_setup;
    r_file = fullfile(ctx.v17, 'Dataset', 'results_v17_M1_dl_rtt8.mat');
    if ~exist(r_file, 'file')
        error('v17x:a3:noM1', 'Cannot find M1 results at %s', r_file);
    end
    S = load(r_file);
    env = S.results.env;
    
    t0 = tic;
    rng(500001);
    [Strue, ~, meta] = generateChannel_v17(200, env);
    obsS = cqiFeedback_v17(Strue, env, meta.delays);
    meta.trace_id = 1;
    rng(510001); U = rand(200, env.N);
    
    evalPolicy_v17('fixed_class', [], Strue, obsS, env, meta, U);
    sec_per_unit = toc(t0);
    
    pf = struct('unit', 'eval', ...
                'sec_per_unit', sec_per_unit, ...
                'n_units_total', 2, ...
                'note', sprintf('a3: benchmark: %.4f s/eval (basis 0.095 s)', sec_per_unit));
end
