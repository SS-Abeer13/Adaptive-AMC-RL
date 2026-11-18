function pf = stage_r6_fullaction_preflight(ctx)
% stage_r6_fullaction_preflight  20-episode preflight for R6a (Amendment 11).
% Same basis as NR2 (0.64 s/ep): same env, same network depth, only the
% actor's output layer widens from 3 to 7 (R6_fullaction_prereg.md Section 8).
% Preflight trace range: 1030001-1030020 (shared v17x convention, disjoint
% from every evaluation range).
    addpath(ctx.v17);
    addpath(fullfile(ctx.v17, 'headroom'));
    addpath(fullfile(ctx.root, 'g6'));
    addpath(fullfile(ctx.root, 'nr1'));
    addpath(ctx.root);
    v17_setup;

    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(ctx.v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data.results; env = R_M1.env;
    env.base_rule_force = 'fixed';
    env.fixed_offset = -2;
    env = selectBaseRule_v17n(env, 2, o.simTime);
    env.resid_actions = -2:4;   % R6a: the only change from NR2

    n_ep = ternary(ctx.smoke, 2, 20);
    t0 = tic;
    DeepA2C_Shared_v17(o.simTime, n_ep, 1030001, env);
    sec = toc(t0) / n_ep;

    % Verify 20 preflight traces can be generated from range 1030001..1030020
    for j = 1:20
        rng(1030000 + j);
        [~, ~, ~] = generateChannel_v17(o.simTime, env);
    end

    % R6a totals: 10 seeds x 3000 episodes = 30,000 training episodes.
    % Evaluation (500 traces x 10 seeds, ~30 min per Section 8's estimate) and
    % R6b (optional, ~25 min logging/fit/gate + ~1.6 h evaluation) are the
    % smaller parts of the ~7.5-8.5 h total and are not folded into this
    % episode-equivalent count; this preflight exists for the 1.5x pause rule
    % on the dominant training cost, as for NR2.
    n_ep_total = ternary(ctx.smoke, 4, 30000);
    pf = struct('unit', 'episode', ...
                'sec_per_unit', sec, ...
                'basis', 0.64, ...
                'n_units_total', n_ep_total, ...
                'note', sprintf('R6a full-action-set training (10 seeds x 3000 ep; %d ep benchmarked; basis 0.64 s/ep, as NR2)', n_ep));
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
