function pf = stage_nr1_preflight(ctx)
% stage_nr1_preflight  Preflight: measure A2C training time on 20 episodes.
    addpath(ctx.v17);
    addpath(fullfile(fileparts(mfilename('fullpath')), 'nr1'));
    v17_setup;
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R = data.results; env = R.env;
    env.base_rule_force = 'fixed';
    env = selectBaseRule_v17n(env, 2, o.simTime);
    
    n_ep = 20;
    if (isfield(ctx, 'smoke') && ctx.smoke) || (isfield(ctx, 'cfg') && isfield(ctx.cfg, 'smoke') && ctx.cfg.smoke)
        n_ep = 2;
    end
    t0 = tic;
    DeepA2C_Shared_v17(o.simTime, n_ep, 24042 + 201, env);
    sec = toc(t0) / n_ep;
    
    % NR1 true totals: 30,000 training episodes + 10,500 evaluation runs
    % (10 A2C + 10 best-on-val + 1 ensemble) x 500 = 10,500 evals
    % In episode units at basis ratio (0.095 / 0.140): 10,500 x 0.6786 = 7,125
    % Total units = 30,000 + 7,125 = 37,125 episode-equivalents
    n_ep_total = ternary(ctx.smoke, 4, 37125);
    pf = struct('unit', 'episode', 'sec_per_unit', sec, ...
                'n_units_total', n_ep_total, ...
                'note', sprintf('NR1 non-oracle residual (30k ep training + 10.5k evals; %d ep benchmarked)', n_ep));
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
