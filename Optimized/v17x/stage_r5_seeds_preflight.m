function pf = stage_r5_seeds_preflight(ctx)
% stage_r5_seeds_preflight  Preflight timing for stage r5_seeds.
% Times 2 training episodes on NR2 configuration.

    addpath(ctx.v17);
    addpath(fullfile(ctx.root, 'nr1'));
    v17_setup;

    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(ctx.v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data.results; envFixed = R_M1.env;
    envFixed.base_rule_force = 'fixed';
    envFixed.fixed_offset = -2;
    envFixed = selectBaseRule_v17n(envFixed, 2, o.simTime);
    envFixed.scheme_name = 'Deep A2C v17 (non-oracle base)';

    n_ep_pf = 2;
    pf_seed = 25999;
    t0 = tic;
    DeepA2C_Shared_v17(o.simTime, n_ep_pf, pf_seed, envFixed);
    elapsed = toc(t0);

    sec_per_ep = elapsed / n_ep_pf;
    basis_ep = 0.140;

    n_ep_full = 20 * 3000;
    n_units = ternary(ctx.smoke, 6 * 2, n_ep_full);

    pf = struct( ...
        'unit', 'episode', ...
        'sec_per_unit', sec_per_ep, ...
        'basis', basis_ep, ...
        'n_units_total', n_units, ...
        'proj_hours', (sec_per_ep * n_units) / 3600, ...
        'note', sprintf('r5_seeds preflight: %.4f s/episode (basis %.4f s), projected %.2f h for %d units', ...
                        sec_per_ep, basis_ep, (sec_per_ep * n_units) / 3600, n_units) ...
    );
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
