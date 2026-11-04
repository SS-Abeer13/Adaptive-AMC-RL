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
    
    n_ep_total = ternary(ctx.smoke, 2 * 2, 10 * 3000);
    pf = struct('unit', 'episode', 'sec_per_unit', sec, ...
                'n_units_total', n_ep_total, ...
                'note', sprintf('NR1 non-oracle residual A2C training (%d episodes)', n_ep));
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
