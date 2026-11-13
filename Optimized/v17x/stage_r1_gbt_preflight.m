function pf = stage_r1_gbt_preflight(ctx)
% stage_r1_gbt_preflight  Preflight timing for stage r1_gbt.
% Uses only preflight range 1050001-1050020, asserted disjoint from evaluation ranges.

    addpath(ctx.v17);
    addpath(fullfile(ctx.v17, 'headroom'));
    addpath(fullfile(ctx.root, 'g6'));
    addpath(fullfile(ctx.root, 'nr1'));
    v17_setup;

    pf_base = 1050000;
    crn_base = 1060000;
    assert(pf_base >= 1050000 && pf_base + 20 <= 1070000, 'Preflight trace range assertion');

    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(ctx.v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data.results; envE = R_M1.env;
    envE.base_rule_force = 'fixed';
    envE.fixed_offset = -2;
    envE = selectBaseRule_v17n(envE, 2, o.simTime);

    nT = 2;
    t0 = tic;
    for j = 1:nT
        rng(pf_base + j);
        [Strue, ~, meta] = generateChannel_v17(o.simTime, envE);
        obsS = cqiFeedback_v17(Strue, envE, meta.delays);
        meta.trace_id = pf_base + j;
        rng(crn_base + j);
        U = rand(o.simTime, envE.N);
        rng(77000 + 100*j + 10*5 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_hr('fixed', [], Strue, obsS, envE, meta, U);
        b0 = min(envE.burn_in, size(Strue, 1) - 1);
        [~, ~, ~] = userMetric_v17(envE, tp, inf, b0);
    end
    elapsed = toc(t0);

    sec_per_eval = elapsed / nT;
    basis_eval = 0.5403; % Basis s/eval from HR1

    n_eval_full = 500 + 1000 + 1000 + 5000; % calib logging + 2x500 NR2 + 2x500 M1 + 10x500 NR2 on M1
    n_units = ternary(ctx.smoke, 20, n_eval_full);

    pf = struct( ...
        'unit', 'eval', ...
        'sec_per_unit', sec_per_eval, ...
        'basis', basis_eval, ...
        'n_units_total', n_units, ...
        'proj_hours', (sec_per_eval * n_units) / 3600, ...
        'note', sprintf('r1_gbt preflight: %.4f s/eval (basis %.4f s), projected %.2f h for %d units', ...
                        sec_per_eval, basis_eval, (sec_per_eval * n_units) / 3600, n_units) ...
    );
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
