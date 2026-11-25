function pf = stage_ft_preflight(ctx)
% stage_ft_preflight  Preflight timing for stage ft (Amendment 13/14).
% Runs 5 calibration traces (60001-60005) across all 37 schemes,
% projects total hours for 500 FT traces (asrun + resolved = 37,000 evals).

    addpath(ctx.v17);
    addpath(fullfile(ctx.root, 'ft'));
    addpath(fullfile(ctx.root, 'eot'));
    addpath(fullfile(ctx.root, 'g6'));
    addpath(fullfile(ctx.root, 'nr1'));
    addpath(ctx.root);
    v17_setup;

    objs = ft_load_objects(ctx.root, ctx.v17, false); % skip full sha256 in preflight
    envFT = objs.envFT;
    envFT.eot_mode = 'asrun';
    envFull = envFT; envFull.resid_actions = -2:4;

    nT = 5;
    t0 = tic;
    for j = 1:nT
        tr_seed = 60000 + j;
        crn_seed = 62000 + j;
        rng(tr_seed, 'twister');
        [Strue, ~, meta] = generateChannel_v17(objs.simTime, envFT);
        obsS = cqiFeedback_v17(Strue, envFT, meta.delays);
        meta.trace_id = tr_seed;
        rng(crn_seed, 'twister');
        U = rand(objs.simTime, envFT.N);

        % Time all 37 schemes
        for s = 1:10
            rng(61000 + 100*j + s);
            evalPolicy_presub_eot('a2c_v17', objs.nr2_pols{s}, Strue, obsS, envFT, meta, U);
            rng(61000 + 100*j + 20 + s);
            evalPolicy_presub_eot('a2c_v17', objs.r6a_pols{s}, Strue, obsS, envFull, meta, U);
        end
        for k = 1:4
            evalPolicy_presub_eot('gbt_res_ack', objs.gbt_trees{k}, Strue, obsS, envFT, meta, U);
            evalPolicy_presub_eot('gbt_full_ack', objs.gbt_trees{k}, Strue, obsS, envFT, meta, U);
        end
        evalPolicy_presub_eot('baseline', [], Strue, obsS, envFT, meta, U);
        evalPolicy_presub_eot('olla', [], Strue, obsS, envFT, meta, U);
        evalPolicy_presub_eot('olla_tuned', [], Strue, obsS, objs.e_olla, meta, U);
        evalPolicy_presub_eot('multi_olla', [], Strue, obsS, envFT, meta, U);
        evalPolicy_presub_eot('fixed', [], Strue, obsS, objs.e_f, meta, U);
        evalPolicy_presub_eot('ctxtab', [], Strue, obsS, objs.e_ctx, meta, U);
        evalPolicy_presub_eot('ctxj', [], Strue, obsS, objs.e_ctxj, meta, U);
        evalPolicy_presub_eot('rule', [], Strue, obsS, envFT, meta, U);
        evalPolicy_presub_eot('rule_cal', objs.chosen_th, Strue, obsS, envFT, meta, U);
    end
    elapsed = toc(t0);

    sec_per_eval = elapsed / (nT * 37);
    basis_eval = 0.095;
    n_eval_total = ternary(ctx.smoke, 5 * 37, 500 * 37 * 2); % asrun + resolved

    pf = struct( ...
        'unit', 'eval', ...
        'sec_per_unit', sec_per_eval, ...
        'basis', basis_eval, ...
        'n_units_total', n_eval_total, ...
        'proj_hours', (sec_per_eval * n_eval_total) / 3600, ...
        'note', sprintf('ft preflight (5 calib traces x 37 schemes): %.4f s/eval (basis %.4f s), projected %.2f h for %d evals', ...
                        sec_per_eval, basis_eval, (sec_per_eval * n_eval_total) / 3600, n_eval_total) ...
    );
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
