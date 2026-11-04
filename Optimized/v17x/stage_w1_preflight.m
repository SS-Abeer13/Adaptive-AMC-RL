function pf = stage_w1_preflight(ctx)
% stage_w1_preflight  20-trace preflight with warm-up (olla_warm_ttis = 200).
    addpath(ctx.v17);
    v17_setup;
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R = data.results; env = R.env; envE = env; envE.scheduler = 'pf';
    envE.olla_warm_ttis = 200;
    kA2C = find(strcmp(R.schemes, 'Deep A2C v17'));
    pol = R.policies.A2C{1};
    nT = 20;
    if (isfield(ctx, 'smoke') && ctx.smoke) || (isfield(ctx, 'cfg') && isfield(ctx.cfg, 'smoke') && ctx.cfg.smoke)
        nT = 2;
    end
    T = o.simTime;
    t0 = tic;
    for j = 1:nT
        rng(o.trace_seed_base + j);
        [Strue, ~, meta] = generateChannel_v17(T, env);
        obsS = cqiFeedback_v17(Strue, env, meta.delays);
        meta.trace_id = j;
        rng(o.crn_seed_base + j); U = rand(T, env.N);
        rng(77000 + 100*j + 10*kA2C + 1);
        evalPolicy_v17('a2c_v17', pol, Strue, obsS, envE, meta, U);
    end
    sec = toc(t0) / nT;
    n_eval_full = ternary(ctx.smoke, 2, 500);
    pf = struct('unit', 'eval', 'sec_per_unit', sec, ...
                'n_units_total', 38 * n_eval_full, ...
                'note', sprintf('W1 warm-up 200 TTIs, %d traces, M1 seed-1 policy', nT));
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
