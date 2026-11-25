function out = eval_ft_pass(mode, n_eval, ctx)
% eval_ft_pass  Run REPRO gate (when mode='repro') or full FT pass (mode='asrun'|'resolved').

    here = fileparts(mfilename('fullpath'));
    v17x_dir = fileparts(here);
    v17_dir = fullfile(fileparts(v17x_dir), 'v17');
    addpath(here); addpath(v17x_dir); addpath(v17_dir);
    addpath(fullfile(v17x_dir, 'eot'));
    addpath(fullfile(v17x_dir, 'g6'));
    addpath(fullfile(v17x_dir, 'nr1'));
    v17_setup;

    objs = ft_load_objects(v17x_dir, v17_dir, true);

    if strcmp(mode, 'repro')
        out = run_repro_gate(objs, n_eval, v17x_dir, ctx);
        return;
    end

    assert(any(strcmp(mode, {'asrun', 'resolved'})), 'Invalid mode: %s', mode);
    out = run_ft_traces(objs, mode, n_eval, v17x_dir, ctx);
end

function out = run_repro_gate(objs, n_repro, v17x_dir, ctx)
    ctx.hbf(sprintf('ft_repro_gate: verifying all 37 schemes on NR2 traces 1..%d', n_repro));
    envN2 = objs.envN2; envN2.eot_mode = 'asrun';
    envFull = envN2; envFull.resid_actions = -2:4;
    e_f = objs.e_f; e_f.eot_mode = 'asrun';
    e_ctx = objs.e_ctx; e_ctx.eot_mode = 'asrun';
    e_olla = objs.e_olla; e_olla.eot_mode = 'asrun';
    e_ctxj = objs.e_ctxj; e_ctxj.eot_mode = 'asrun';
    b0 = min(envN2.burn_in, objs.simTime - 1);

    st_nr2 = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'nr2', 'eval.mat'));
    st_r6  = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r6_fullaction', 'eval.mat'));
    st_r1b = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1b_ack', 'eval_NR2.mat'));
    st_r1c = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1c', 'eval_nr2.mat'));
    st_r2  = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r2_rule', 'eval_NR2.mat'));

    max_diff = 0.0;
    n_checks = 0;

    for j = 1:n_repro
        rng(1000000 + j, 'twister'); [Strue, ~, meta] = generateChannel_v17(objs.simTime, envN2);
        obsS = cqiFeedback_v17(Strue, envN2, meta.delays);
        meta.trace_id = j;
        rng(1010000 + j, 'twister'); U = rand(objs.simTime, envN2.N);

        % 1. NR2 seeds 1..10
        for s = 1:10
            rng(1020000 + 100*j + 10*8 + s);
            [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('a2c_v17', objs.nr2_pols{s}, Strue, obsS, envN2, meta, U);
            [~, ~, val] = userMetric_v17(envN2, tp, inf, b0);
            d = abs(val - st_nr2.out.nr2_seeds(s, j));
            assert(d < 1e-12, 'REPRO FAIL NR2 seed %d trace %d: diff=%.3e', s, j, d);
            max_diff = max(max_diff, d); n_checks = n_checks + 1;
        end

        % 2. RL-full seeds 1..10
        for s = 1:10
            rng(2340000 + 100*j + s);
            [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('a2c_v17', objs.r6a_pols{s}, Strue, obsS, envFull, meta, U);
            [~, ~, val] = userMetric_v17(envFull, tp, inf, b0);
            d = abs(val - st_r6.out.rlfull_vals(s, j));
            assert(d < 1e-12, 'REPRO FAIL RL-full seed %d trace %d: diff=%.3e', s, j, d);
            max_diff = max(max_diff, d); n_checks = n_checks + 1;
        end

        % 3. GBT-res-ACK & GBT-full-ACK fits 1..4
        for k = 1:4
            [tp_r, ~, ~, ~, inf_r] = evalPolicy_presub_eot('gbt_res_ack', objs.gbt_trees{k}, Strue, obsS, envN2, meta, U);
            [~, ~, vr] = userMetric_v17(envN2, tp_r, inf_r, b0);
            [tp_f, ~, ~, ~, inf_f] = evalPolicy_presub_eot('gbt_full_ack', objs.gbt_trees{k}, Strue, obsS, envN2, meta, U);
            [~, ~, vf] = userMetric_v17(envN2, tp_f, inf_f, b0);
            if k == 1
                dr = abs(vr - st_r1b.out.gbt_res(j));
                df = abs(vf - st_r1b.out.gbt_full(j));
            else
                dr = abs(vr - st_r1c.out.res(k, j));
                df = abs(vf - st_r1c.out.full(k, j));
            end
            assert(dr < 1e-12, 'REPRO FAIL GBT-res-ACK fit %d trace %d: diff=%.3e', k, j, dr);
            assert(df < 1e-12, 'REPRO FAIL GBT-full-ACK fit %d trace %d: diff=%.3e', k, j, df);
            max_diff = max([max_diff, dr, df]); n_checks = n_checks + 2;
        end

        % 4. 9 Rules / Comparators
        rng(1020000 + 100*j + 10*1 + 1); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('baseline', [], Strue, obsS, envN2, meta, U);
        [~, ~, v] = userMetric_v17(envN2, tp, inf, b0); d = abs(v - st_nr2.out.cmp.baseline(j));
        assert(d < 1e-12, 'REPRO FAIL baseline trace %d', j); max_diff = max(max_diff, d); n_checks = n_checks + 1;

        rng(1020000 + 100*j + 10*2 + 1); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('olla', [], Strue, obsS, envN2, meta, U);
        [~, ~, v] = userMetric_v17(envN2, tp, inf, b0); d = abs(v - st_nr2.out.cmp.olla(j));
        assert(d < 1e-12, 'REPRO FAIL olla trace %d', j); max_diff = max(max_diff, d); n_checks = n_checks + 1;

        rng(1020000 + 100*j + 10*3 + 1); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('olla_tuned', [], Strue, obsS, e_olla, meta, U);
        [~, ~, v] = userMetric_v17(e_olla, tp, inf, b0); d = abs(v - st_nr2.out.cmp.olla_tuned500(j));
        assert(d < 1e-12, 'REPRO FAIL olla_tuned500 trace %d', j); max_diff = max(max_diff, d); n_checks = n_checks + 1;

        rng(1020000 + 100*j + 10*4 + 1); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('multi_olla', [], Strue, obsS, envN2, meta, U);
        [~, ~, v] = userMetric_v17(envN2, tp, inf, b0); d = abs(v - st_nr2.out.cmp.multi_olla(j));
        assert(d < 1e-12, 'REPRO FAIL multi_olla trace %d', j); max_diff = max(max_diff, d); n_checks = n_checks + 1;

        rng(1020000 + 100*j + 10*5 + 1); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('fixed', [], Strue, obsS, e_f, meta, U);
        [~, ~, v] = userMetric_v17(e_f, tp, inf, b0); d = abs(v - st_nr2.out.cmp.fixed500(j));
        assert(d < 1e-12, 'REPRO FAIL fixed500 trace %d', j); max_diff = max(max_diff, d); n_checks = n_checks + 1;

        rng(1020000 + 100*j + 10*7 + 1); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('ctxtab', [], Strue, obsS, e_ctx, meta, U);
        [~, ~, v] = userMetric_v17(e_ctx, tp, inf, b0); d = abs(v - st_nr2.out.cmp.ctx500(j));
        assert(d < 1e-12, 'REPRO FAIL ctx500 trace %d', j); max_diff = max(max_diff, d); n_checks = n_checks + 1;

        rng(1020000 + 100*j + 10*99 + 1); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('ctxj', [], Strue, obsS, e_ctxj, meta, U);
        [~, ~, v] = userMetric_v17(e_ctxj, tp, inf, b0); d = abs(v - st_nr2.out.cmp.ctxj500(j));
        assert(d < 1e-12, 'REPRO FAIL ctxj500 trace %d', j); max_diff = max(max_diff, d); n_checks = n_checks + 1;

        rng(1020000 + 100*j + 10*8 + 1); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('rule', [], Strue, obsS, envN2, meta, U);
        [~, ~, v] = userMetric_v17(envN2, tp, inf, b0); d = abs(v - st_r2.out.rule(j));
        assert(d < 1e-12, 'REPRO FAIL Rule trace %d', j); max_diff = max(max_diff, d); n_checks = n_checks + 1;

        rng(1020000 + 100*j + 10*8 + 1); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('rule_cal', objs.chosen_th, Strue, obsS, envN2, meta, U);
        [~, ~, v] = userMetric_v17(envN2, tp, inf, b0); d = abs(v - st_r2.out.rule_cal(j));
        assert(d < 1e-12, 'REPRO FAIL Rule-cal trace %d', j); max_diff = max(max_diff, d); n_checks = n_checks + 1;
    end

    ft_ds = fullfile(v17x_dir, 'Dataset', 'ft');
    if ~exist(ft_ds, 'dir'), mkdir(ft_ds); end
    rep_f = fullfile(ft_ds, 'ft_repro.txt');
    fid = fopen(rep_f, 'w');
    fprintf(fid, 'FT REPRO GATE (NR2 traces 1..%d, all 37 schemes)\n', n_repro);
    fprintf(fid, 'Total checks: %d | Max abs diff: %.3e | Status: EXACT PASS\n', n_checks, max_diff);
    fclose(fid);
    ctx.hbf(sprintf('ft_repro_gate: EXACT PASS (%d checks, max_diff=%.3e)', n_checks, max_diff));
    out = struct('n_checks', n_checks, 'max_diff', max_diff);
end

function out = run_ft_traces(objs, mode, n_eval, v17x_dir, ctx)
    ctx.hbf(sprintf('run_ft_traces: starting mode=%s, n_eval=%d (no-peeking active)', mode, n_eval));

    envFT = objs.envFT; envFT.eot_mode = mode;
    envFull = envFT; envFull.resid_actions = -2:4;
    e_f = objs.e_f; e_f.eot_mode = mode;
    e_ctx = objs.e_ctx; e_ctx.eot_mode = mode;
    e_olla = objs.e_olla; e_olla.eot_mode = mode;
    e_ctxj = objs.e_ctxj; e_ctxj.eot_mode = mode;
    b0 = min(envFT.burn_in, objs.simTime - 1);

    % Storage for all 37 schemes across n_eval traces
    nr2_vals  = zeros(10, n_eval);
    r6a_vals  = zeros(10, n_eval);
    gbt_res   = zeros(4, n_eval);
    gbt_full  = zeros(4, n_eval);
    c_base    = zeros(1, n_eval);
    c_olla    = zeros(1, n_eval);
    c_ollat   = zeros(1, n_eval);
    c_molla   = zeros(1, n_eval);
    c_fixed   = zeros(1, n_eval);
    c_ctx     = zeros(1, n_eval);
    c_ctxj    = zeros(1, n_eval);
    c_rule    = zeros(1, n_eval);
    c_rulecal = zeros(1, n_eval);

    exp_c_asrun = 0; exp_c_res = 0; exp_late_ack = 0; exp_cens = 0;
    is_asrun = strcmp(mode, 'asrun');

    for j = 1:n_eval
        tr_seed = 7000000 + j;
        crn_seed = 7100000 + j;
        rng(tr_seed, 'twister');
        [Strue, ~, meta] = generateChannel_v17(objs.simTime, envFT);
        obsS = cqiFeedback_v17(Strue, envFT, meta.delays);
        meta.trace_id = j;
        rng(crn_seed, 'twister');
        U = rand(objs.simTime, envFT.N);

        % Scheme indices 1..10: NR2 seeds 1..10
        for s = 1:10
            rng(7200000 + 100*j + s);
            [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('a2c_v17', objs.nr2_pols{s}, Strue, obsS, envFT, meta, U);
            [~, ~, nr2_vals(s, j)] = userMetric_v17(envFT, tp, inf, b0);
            if is_asrun
                exp_c_asrun = exp_c_asrun + inf.n_counted_asrun;
                exp_c_res   = exp_c_res   + inf.n_counted_resolved;
                exp_late_ack = exp_late_ack + inf.n_late_ack_asrun;
                exp_cens    = exp_cens    + inf.n_censored_asrun;
            end
        end

        % Scheme indices 11..20: RL-full seeds 1..10
        for s = 1:10
            rng(7200000 + 100*j + 10 + s);
            [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('a2c_v17', objs.r6a_pols{s}, Strue, obsS, envFull, meta, U);
            [~, ~, r6a_vals(s, j)] = userMetric_v17(envFull, tp, inf, b0);
        end

        % Scheme indices 21..24: GBT-res-ACK fits 1..4
        % Scheme indices 25..28: GBT-full-ACK fits 1..4
        for k = 1:4
            rng(7200000 + 100*j + 20 + k);
            [tp_r, ~, ~, ~, inf_r] = evalPolicy_presub_eot('gbt_res_ack', objs.gbt_trees{k}, Strue, obsS, envFT, meta, U);
            [~, ~, gbt_res(k, j)] = userMetric_v17(envFT, tp_r, inf_r, b0);

            rng(7200000 + 100*j + 24 + k);
            [tp_f, ~, ~, ~, inf_f] = evalPolicy_presub_eot('gbt_full_ack', objs.gbt_trees{k}, Strue, obsS, envFT, meta, U);
            [~, ~, gbt_full(k, j)] = userMetric_v17(envFT, tp_f, inf_f, b0);
        end

        % Scheme indices 29..37: 9 rules / comparators
        rng(7200000 + 100*j + 29); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('baseline', [], Strue, obsS, envFT, meta, U);
        [~, ~, c_base(j)] = userMetric_v17(envFT, tp, inf, b0);

        rng(7200000 + 100*j + 30); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('olla', [], Strue, obsS, envFT, meta, U);
        [~, ~, c_olla(j)] = userMetric_v17(envFT, tp, inf, b0);

        rng(7200000 + 100*j + 31); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('olla_tuned', [], Strue, obsS, e_olla, meta, U);
        [~, ~, c_ollat(j)] = userMetric_v17(e_olla, tp, inf, b0);

        rng(7200000 + 100*j + 32); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('multi_olla', [], Strue, obsS, envFT, meta, U);
        [~, ~, c_molla(j)] = userMetric_v17(envFT, tp, inf, b0);

        rng(7200000 + 100*j + 33); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('fixed', [], Strue, obsS, e_f, meta, U);
        [~, ~, c_fixed(j)] = userMetric_v17(e_f, tp, inf, b0);

        rng(7200000 + 100*j + 34); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('ctxtab', [], Strue, obsS, e_ctx, meta, U);
        [~, ~, c_ctx(j)] = userMetric_v17(e_ctx, tp, inf, b0);

        rng(7200000 + 100*j + 35); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('ctxj', [], Strue, obsS, e_ctxj, meta, U);
        [~, ~, c_ctxj(j)] = userMetric_v17(e_ctxj, tp, inf, b0);

        rng(7200000 + 100*j + 36); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('rule', [], Strue, obsS, envFT, meta, U);
        [~, ~, c_rule(j)] = userMetric_v17(envFT, tp, inf, b0);

        rng(7200000 + 100*j + 37); [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('rule_cal', objs.chosen_th, Strue, obsS, envFT, meta, U);
        [~, ~, c_rulecal(j)] = userMetric_v17(envFT, tp, inf, b0);

        if mod(j, 25) == 0
            ctx.hbf(sprintf('ft (%s): completed trace %d / %d', mode, j, n_eval));
        end
    end

    % Write pertrace_ft_<mode>.csv ONLY after all 37 schemes finish all n_eval traces
    ft_ds = fullfile(v17x_dir, 'Dataset', 'ft');
    if ~exist(ft_ds, 'dir'), mkdir(ft_ds); end
    csv_path = fullfile(ft_ds, sprintf('pertrace_ft_%s.csv', mode));
    fid = fopen(csv_path, 'w');
    fprintf(fid, 'trace_set,scheme,seed,trace,value\n');
    for s = 1:10
        for j = 1:n_eval, fprintf(fid, 'FT,NR2,%d,%d,%.15g\n', s, j, nr2_vals(s, j)); end
        for j = 1:n_eval, fprintf(fid, 'FT,RL-full,%d,%d,%.15g\n', s, j, r6a_vals(s, j)); end
    end
    for k = 1:4
        for j = 1:n_eval, fprintf(fid, 'FT,GBT-res-ACK-M1fit%d,0,%d,%.15g\n', k, j, gbt_res(k, j)); end
        for j = 1:n_eval, fprintf(fid, 'FT,GBT-full-ACK-M1fit%d,0,%d,%.15g\n', k, j, gbt_full(k, j)); end
    end
    single_names = {'baseline', 'olla', 'olla_tuned500', 'multi_olla', 'fixed500', 'ctx500', 'ctxj500', 'Rule', 'Rule-cal'};
    single_vecs  = {c_base, c_olla, c_ollat, c_molla, c_fixed, c_ctx, c_ctxj, c_rule, c_rulecal};
    for idx = 1:numel(single_names)
        nm = single_names{idx};
        vec = single_vecs{idx};
        for j = 1:n_eval
            fprintf(fid, 'FT,%s,0,%d,%.15g\n', nm, j, vec(j));
        end
    end
    fclose(fid);

    if is_asrun
        exp_path = fullfile(ft_ds, 'ft_exposure.txt');
        efid = fopen(exp_path, 'w');
        tot_exp = exp_late_ack + exp_cens;
        pct = 100 * tot_exp / max(1, exp_c_asrun);
        fprintf(efid, 'FT EXPOSURE COUNTERS (asrun pass, NR2 10 seeds, n_eval=%d):\n', n_eval);
        fprintf(efid, 'counted_asrun=%d | counted_resolved=%d | late_ack=%d | censored=%d | exposed_pct=%.2f%%\n', ...
            exp_c_asrun, exp_c_res, exp_late_ack, exp_cens, pct);
        fclose(efid);
    end

    out = struct('mode', mode, 'n_eval', n_eval, 'csv_path', csv_path);
end
