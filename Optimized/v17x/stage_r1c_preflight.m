function pf = stage_r1c_preflight(ctx)
% stage_r1c_preflight  Preflight timing for stage r1c (Amendment 10).
% Uses preflight range 1050001-1050020, asserted disjoint from evaluation ranges.

    addpath(ctx.v17);
    addpath(fullfile(ctx.v17, 'headroom'));
    addpath(fullfile(ctx.root, 'g6'));
    addpath(fullfile(ctx.root, 'nr1'));
    addpath(ctx.root);
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
        pol.s_exp = RandStream('twister', 'Seed', 3060000 + j);
        pol.trace_id = pf_base + j;
        pol.base_offset = -2;
        [tp, ~, ~, ~, inf] = evalPolicy_presub('log_explore', pol, Strue, obsS, envE, meta, U);
        b0 = min(envE.burn_in, size(Strue, 1) - 1);
        [~, ~, ~] = userMetric_v17(envE, tp, inf, b0);
    end
    elapsed = toc(t0);

    sec_per_eval = elapsed / nT;
    basis_eval = 0.5403; % Basis s/eval from HR1/R1/R1b

    % 11 calib draws (500 traces each) = 5500
    % NR2 eval: 3 fits * 2 schemes * 500 = 3000
    % G2 cell fits: 4 fits * 2 schemes * 300 = 2400
    % G3 cell fits: 4 fits * 2 schemes * 300 = 2400
    % G2 transfer: 4 fits * 2 schemes * 300 = 2400
    % G3 transfer: 4 fits * 2 schemes * 300 = 2400
    % Total full eval units = 5500 + 3000 + 4*2400 = 18100 units
    n_eval_full = 18100;
    n_units = ternary(ctx.smoke, 12, n_eval_full);

    pf = struct( ...
        'unit', 'eval', ...
        'sec_per_unit', sec_per_eval, ...
        'basis', basis_eval, ...
        'n_units_total', n_units, ...
        'proj_hours', (sec_per_eval * n_units) / 3600, ...
        'note', sprintf('r1c preflight: %.4f s/eval (basis %.4f s), projected %.2f h for %d units', ...
                        sec_per_eval, basis_eval, (sec_per_eval * n_units) / 3600, n_units) ...
    );
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
