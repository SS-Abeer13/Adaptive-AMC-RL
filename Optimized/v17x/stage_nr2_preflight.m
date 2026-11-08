function pf = stage_nr2_preflight(ctx)
% stage_nr2_preflight  20-episode / 20-trace preflight for NR2 (basis 0.64 s/ep).
% Preflight trace range: 1030001--1030020 (separate from evaluation range 1000001--1000500).
    addpath(ctx.v17);
    addpath(fullfile(fileparts(mfilename('fullpath')), 'nr1'));
    addpath(fullfile(fileparts(mfilename('fullpath')), 'g6'));
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
    DeepA2C_Shared_v17(o.simTime, n_ep, 25042 + 201, env);
    sec = toc(t0) / n_ep;
    
    % Verify 20 preflight traces can be generated from range 1030001..1030020
    for j = 1:20
        rng(1030000 + j);
        [~, ~, ~] = generateChannel_v17(o.simTime, env);
    end
    
    % NR2 totals: 30,000 training episodes + 14,500 evaluations
    % (10 NR2 + 1 ens + 10 M1 + 8 comparators) x 500 = 14,500 evals
    % At basis ratio (0.095 / 0.140): 14,500 x 0.6786 = 9,839
    % Total units = 30,000 + 9,839 = 39,839 episode-equivalents
    n_ep_total = ternary(ctx.smoke, 4, 39839);
    pf = struct('unit', 'episode', ...
                'sec_per_unit', sec, ...
                'basis', 0.64, ...
                'n_units_total', n_ep_total, ...
                'note', sprintf('NR2 confirmatory replication (30k ep training + 14.5k evals; %d ep benchmarked; basis 0.64 s/ep)', n_ep));
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
