function pf = stage_r2_rule_preflight(ctx)
% stage_r2_rule_preflight  Preflight timing for stage r2_rule.
% Uses only preflight range 1050001-1050020, asserted disjoint from evaluation ranges.

    addpath(ctx.v17);
    addpath(fullfile(ctx.root, 'g6'));
    addpath(ctx.root);
    v17_setup;

    pf_base = 1050000;
    crn_base = 1060000;
    assert(pf_base >= 1050000 && pf_base + 20 <= 1070000, 'Preflight trace range assertion');

    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(ctx.v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data.results; envFixed = R_M1.env;
    envFixed.base_rule_force = 'fixed';
    envFixed.fixed_offset = -2;
    envFixed = selectBaseRule_v17n(envFixed, 2, o.simTime);

    nT = 2;
    t0 = tic;
    for j = 1:nT
        rng(pf_base + j);
        [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
        obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
        meta.trace_id = pf_base + j;
        rng(crn_base + j);
        U = rand(o.simTime, envFixed.N);
        rng(77000 + 100*j + 10*5 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('rule', [], Strue, obsS, envFixed, meta, U);
        b0 = min(envFixed.burn_in, size(Strue, 1) - 1);
        [~, ~, ~] = userMetric_v17(envFixed, tp, inf, b0);
    end
    elapsed = toc(t0);

    sec_per_eval = elapsed / nT;
    basis_eval = 0.095; % 0.095 s per trace evaluation

    n_eval_full = 160 * 500 + 2000; % 160 grid points x 500 calib + 4 x 500 evals
    n_units = ternary(ctx.smoke, 20, n_eval_full);

    pf = struct( ...
        'unit', 'eval', ...
        'sec_per_unit', sec_per_eval, ...
        'basis', basis_eval, ...
        'n_units_total', n_units, ...
        'proj_hours', (sec_per_eval * n_units) / 3600, ...
        'note', sprintf('r2_rule preflight: %.4f s/eval (basis %.4f s), projected %.2f h for %d units', ...
                        sec_per_eval, basis_eval, (sec_per_eval * n_units) / 3600, n_units) ...
    );
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
