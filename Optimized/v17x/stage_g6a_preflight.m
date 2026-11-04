function pf = stage_g6a_preflight(ctx)
% stage_g6a_preflight  20-trace preflight for deterministic rule evaluation.
    addpath(ctx.v17);
    addpath(fullfile(fileparts(mfilename('fullpath')), 'g6'));
    v17_setup;
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R = data.results; env = R.env; envE = env; envE.scheduler = 'pf';
    
    nT = 20;
    if (isfield(ctx, 'smoke') && ctx.smoke) || (isfield(ctx, 'cfg') && isfield(ctx.cfg, 'smoke') && ctx.cfg.smoke)
        nT = 2;
    end
    T = o.simTime;
    t0 = tic;
    for j = 1:nT
        rng(600000 + j);
        [Strue, ~, meta] = generateChannel_v17(T, envE);
        obsS = cqiFeedback_v17(Strue, envE, meta.delays);
        meta.trace_id = j;
        rng(610000 + j); U = rand(T, envE.N);
        rng(61500 + j);
        evalPolicy_v17_g6('fixed', [], Strue, obsS, envE, meta, U);
    end
    sec = toc(t0) / nT;
    
    n_units = ternary(ctx.smoke, 20, 263000);
    pf = struct('unit', 'eval', 'sec_per_unit', sec, ...
                'n_units_total', n_units, ...
                'note', sprintf('G6a deterministic calibration evaluation (%d traces)', nT));
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
