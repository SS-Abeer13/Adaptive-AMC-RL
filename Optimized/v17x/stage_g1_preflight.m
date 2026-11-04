function pf = stage_g1_preflight(ctx)
% 20-trace preflight: frozen-copy evaluator, M1 seed-1 policy, including trace generation.
    v17_setup;                                   % defines C, base, v17 (and cd's to the project root)
    addpath(fullfile(v17, 'g1'));
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R = data.results; env = R.env; envE = env; envE.scheduler = 'pf';
    kA2C = find(strcmp(R.schemes, 'Deep A2C v17'));
    pol = R.policies.A2C{1};
    nT = 20; T = o.simTime;
    t0 = tic;
    for j = 1:nT
        rng(o.trace_seed_base + j);
        [Strue, ~, meta] = generateChannel_v17(T, env);
        obsS = cqiFeedback_v17(Strue, env, meta.delays);
        meta.trace_id = j;
        rng(o.crn_seed_base + j); U = rand(T, env.N);
        rng(77000 + 100*j + 10*kA2C + 1);
        evalPolicy_v17_g1('a2c_v17', pol, Strue, obsS, envE, meta, U);
    end
    sec = toc(t0) / nT;
    pf = struct('unit', 'eval', 'sec_per_unit', sec, ...
                'n_units_total', 2 * (10 * 500 + 500), ...      % two cases x (10 A2C seeds + FixedPU) x 500 traces
                'note', 'M1 seed-1 policy, 20 traces, trace generation included');
end
