function pf = stage_eot_preflight(ctx)
% stage_eot_preflight  Preflight timing for stage eot.
% Disjoint preflight trace range 1050001-1050020 (calibration 60001-60020 in smoke).

    addpath(ctx.v17);
    addpath(fullfile(ctx.root, 'eot'));
    addpath(fullfile(ctx.root, 'g6'));
    addpath(fullfile(ctx.root, 'nr1'));
    addpath(ctx.root);
    v17_setup;

    if ctx.smoke
        pf_base = 60000;
        crn_base = 62000;
    else
        pf_base = 1050000;
        crn_base = 1060000;
        assert(pf_base >= 1050000 && pf_base + 20 <= 1070000, 'Preflight trace range assertion');
    end

    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(ctx.v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data.results; envE = R_M1.env;
    envE.eot_mode = 'resolved';

    nT = 20;
    t0 = tic;
    for j = 1:nT
        rng(pf_base + j, 'twister');
        [Strue, ~, meta] = generateChannel_v17(o.simTime, envE);
        obsS = cqiFeedback_v17(Strue, envE, meta.delays);
        meta.trace_id = pf_base + j;
        rng(crn_base + j, 'twister');
        U = rand(o.simTime, envE.N);
        [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('baseline', [], Strue, obsS, envE, meta, U);
    end
    elapsed = toc(t0);

    sec_per_eval = elapsed / nT;
    basis_eval = 0.095; % Basis s/eval from cfg.basis.eval

    n_eval_full = 56500; % Total evaluations across M1, NR2, G2, G3 in Task 2
    n_units = ternary(ctx.smoke, 80, n_eval_full);

    pf = struct( ...
        'unit', 'eval', ...
        'sec_per_unit', sec_per_eval, ...
        'basis', basis_eval, ...
        'n_units_total', n_units, ...
        'proj_hours', (sec_per_eval * n_units) / 3600, ...
        'note', sprintf('eot preflight: %.4f s/eval (basis %.4f s), projected %.2f h for %d units', ...
                        sec_per_eval, basis_eval, (sec_per_eval * n_units) / 3600, n_units) ...
    );
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
