function pf = stage_g6c_preflight(ctx)
% stage_g6c_preflight  20-trace preflight for G6c evaluation.
    addpath(ctx.v17);
    addpath(fullfile(fileparts(mfilename('fullpath')), 'g6'));
    v17_setup;
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R = data.results; env = R.env; envE = env; envE.scheduler = 'pf';
    envE.ctxj_tab = zeros(3, 2, 3, 2);
    
    nT = 20;
    if (isfield(ctx, 'smoke') && ctx.smoke) || (isfield(ctx, 'cfg') && isfield(ctx.cfg, 'smoke') && ctx.cfg.smoke)
        nT = 2;
    end
    T = o.simTime;
    t0 = tic;
    for j = 1:nT
        rng(o.trace_seed_base + j);
        [Strue, ~, meta] = generateChannel_v17(T, envE);
        obsS = cqiFeedback_v17(Strue, envE, meta.delays);
        meta.trace_id = j;
        rng(o.crn_seed_base + j); U = rand(T, envE.N);
        rng(61500 + j);
        evalPolicy_v17_g6('ctxj', [], Strue, obsS, envE, meta, U);
    end
    sec = toc(t0) / nT;
    
    n_units = ternary(ctx.smoke, 20, 8000);
    pf = struct('unit', 'eval', 'sec_per_unit', sec, ...
                'n_units_total', n_units, ...
                'note', sprintf('G6c evaluation traces (%d traces)', nT));
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
