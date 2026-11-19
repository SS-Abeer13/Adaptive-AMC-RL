function out = eval_set_eot(set_name, eot_mode, n_eval, ctx)
% eval_set_eot  Evaluator for one trace set (NR2, M1, G2, G3) under eot_mode ('asrun' | 'resolved').
% Under 'asrun', asserts exact bit-identity against stored per-trace values for all schemes.
% Any difference stops with an error reporting (scheme, set, trace, diff).
% Exposure counters (n_counted_asrun, n_counted_resolved, n_late_ack_asrun, n_censored_asrun)
% are recorded from the asrun pass only.

    here = fileparts(mfilename('fullpath'));
    v17x_dir = fileparts(here);
    v17_dir = fullfile(fileparts(v17x_dir), 'v17');
    addpath(here); addpath(v17x_dir); addpath(v17_dir);
    addpath(fullfile(v17x_dir, 'g6')); addpath(fullfile(v17x_dir, 'nr1'));
    v17_setup;

    ctx.hbf(sprintf('eval_set_eot: starting set=%s, mode=%s, n_eval=%d', set_name, eot_mode, n_eval));
    out = struct('set', set_name, 'eot_mode', eot_mode, 'n_eval', n_eval);

    switch upper(set_name)
        case 'NR2'
            out = eval_nr2_all(eot_mode, n_eval, ctx, v17x_dir, v17_dir, base, C);
        case 'M1'
            out = eval_m1_all(eot_mode, n_eval, ctx, v17x_dir, v17_dir, base, C);
        case 'G2'
            out = eval_g2_all(eot_mode, n_eval, ctx, v17x_dir, v17_dir, base, C);
        case 'G3'
            out = eval_g3_all(eot_mode, n_eval, ctx, v17x_dir, v17_dir, base, C);
        otherwise
            error('Unknown set_name: %s', set_name);
    end
    ctx.hbf(sprintf('eval_set_eot: completed set=%s, mode=%s', set_name, eot_mode));
end

% =========================================================================
% NR2 Evaluation
% =========================================================================
function res = eval_nr2_all(eot_mode, n_eval, ctx, v17x_dir, v17_dir, base, C)
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data_m1 = load(fullfile(v17_dir, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data_m1.results;
    env_m1 = R_M1.env;
    envN2 = env_m1;
    envN2.base_rule_force = 'fixed';
    envN2.fixed_offset = -2;
    envN2 = selectBaseRule_v17n(envN2, 2, o.simTime);
    envN2.scheduler = 'pf';
    envN2.eot_mode = eot_mode;
    N = envN2.N; b0 = min(envN2.burn_in, o.simTime - 1);

    % Comparators setup
    txt_single = fileread(fullfile(v17x_dir, 'Dataset', 'cal500_single.txt'));
    f_off = parse_int(txt_single, 'Fixed-500: offset = ([+-]?[0-9]+)');
    comp_ckpt = fullfile(v17x_dir, 'Dataset', 'ckpt', 'g6a', 'composite_table.mat');
    if exist(comp_ckpt, 'file')
        S_comp = load(comp_ckpt); pu_tab = S_comp.out.fixedpu_tab; ctx_tab = S_comp.out.ctx_tab; olla_set = S_comp.out.olla_setting;
    else
        pu_tab = env_m1.class_tab; ctx_tab = env_m1.ctx_tab; olla_set = [env_m1.olla_target, 0.5];
    end
    ctxj_tab = read_ctxj_from_tables(fullfile(v17x_dir, 'Dataset', 'cal500_tables.txt'));

    e_f = envN2; e_f.fixed_offset = f_off;
    e_pu = envN2; e_pu.fixed_class_tab = pu_tab; e_pu.class_tab = pu_tab;
    e_ctx = envN2; e_ctx.ctx_tab = ctx_tab;
    e_olla = envN2; e_olla.olla_target = olla_set(1); e_olla.olla_target_tuned = olla_set(1); e_olla.olla_step_down = olla_set(2);
    e_ctxj = envN2; e_ctxj.ctxj_tab = ctxj_tab;

    % Policies
    nr2_pols = cell(1, 10);
    for s = 1:10
        f_s = fullfile(v17x_dir, 'Dataset', 'ckpt', 'nr2', sprintf('train_seed_%d.mat', s));
        S = load(f_s); nr2_pols{s} = S.out.a2c;
    end
    m1_pols = R_M1.policies.A2C(1:10);

    % R6a
    envFull = envN2; envFull.resid_actions = -2:4;
    r6a_pols = cell(1, 10);
    for s = 1:10
        f_s = fullfile(v17x_dir, 'Dataset', 'ckpt', 'r6_fullaction', sprintf('train_%d.mat', s));
        S = load(f_s); r6a_pols{s} = S.out.a2c;
    end

    % GBT models
    r1b_mat = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1b_ack', 'equiv.mat'));
    gbt_m1_1 = r1b_mat.out;
    gbt_m1_trees = cell(1, 4); gbt_m1_trees{1} = gbt_m1_1;
    for k = 2:4
        S = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1c', sprintf('r1c_trees_m1_%d.mat', k)));
        m = S.trees_export;
        if isstruct(m.trees) && numel(m.trees) > 1
            tc = cell(1, numel(m.trees)); for it = 1:numel(m.trees), tc{it} = m.trees(it); end
            m.trees = tc;
        end
        gbt_m1_trees{k} = m;
    end

    r1_gbt_mat = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1_gbt', 'equiv.mat'));
    r1_model = r1_gbt_mat.out;

    % Pre-generate traces
    traces = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    for j = 1:n_eval
        tr_seed = 1000000 + j; crn_seed = 1010000 + j;
        rng(tr_seed, 'twister'); [Strue, ~, meta] = generateChannel_v17(o.simTime, envN2);
        obsS = cqiFeedback_v17(Strue, envN2, meta.delays);
        meta.trace_id = j;
        rng(crn_seed, 'twister'); U = rand(o.simTime, N);
        traces(j).SINR = Strue; traces(j).obsS = obsS; traces(j).meta = meta; traces(j).U = U;
    end

    % Storage
    nr2_seeds = zeros(10, n_eval); nr2_ens = zeros(1, n_eval); m1_seeds = zeros(10, n_eval);
    cmp = struct('baseline', zeros(1, n_eval), 'olla', zeros(1, n_eval), 'olla_tuned500', zeros(1, n_eval), ...
                 'multi_olla', zeros(1, n_eval), 'fixed500', zeros(1, n_eval), 'fixedpu500', zeros(1, n_eval), ...
                 'ctx500', zeros(1, n_eval), 'ctxj500', zeros(1, n_eval));
    r6a_vals = zeros(10, n_eval);
    gbt_res_ack = zeros(4, n_eval); gbt_full_ack = zeros(4, n_eval);
    r1_gbt_res = zeros(1, n_eval); r1_gbt_full = zeros(1, n_eval);
    r2_rule = zeros(1, n_eval); r2_rule_cal = zeros(1, n_eval);

    % Exposure accumulation
    exp_c_asrun = 0; exp_c_res = 0; exp_late_ack = 0; exp_cens = 0;

    st_sel = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r2_rule', 'select.mat'));
    chosen_th = st_sel.out;

    is_asrun = strcmp(eot_mode, 'asrun');
    if is_asrun
        st_nr2 = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'nr2', 'eval.mat'));
        st_r6 = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r6_fullaction', 'eval.mat'));
        st_r1b = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1b_ack', 'eval_NR2.mat'));
        st_r1c = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1c', 'eval_nr2.mat'));
        st_r1 = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1_gbt', 'eval_NR2.mat'));
        st_r2 = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r2_rule', 'eval_NR2.mat'));
    end

    % 1. NR2 seeds 1..10
    for s = 1:10
        pol = nr2_pols{s};
        for j = 1:n_eval
            rng(1020000 + 100*j + 10*8 + s);
            [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('a2c_v17', pol, traces(j).SINR, traces(j).obsS, envN2, traces(j).meta, traces(j).U);
            [~, ~, val] = userMetric_v17(envN2, tp, inf, b0);
            nr2_seeds(s, j) = val;
            if is_asrun
                check_repro('NR2', sprintf('nr2_seed_%d', s), j, val, st_nr2.out.nr2_seeds(s, j));
                exp_c_asrun = exp_c_asrun + inf.n_counted_asrun;
                exp_c_res = exp_c_res + inf.n_counted_resolved;
                exp_late_ack = exp_late_ack + inf.n_late_ack_asrun;
                exp_cens = exp_cens + inf.n_censored_asrun;
            end
        end
    end

    % 2. NR2 ensemble
    for j = 1:n_eval
        rng(1020000 + 100*j + 10*10 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('a2c_ens', nr2_pols, traces(j).SINR, traces(j).obsS, envN2, traces(j).meta, traces(j).U);
        [~, ~, val] = userMetric_v17(envN2, tp, inf, b0);
        nr2_ens(j) = val;
        if is_asrun, check_repro('NR2', 'nr2_ens', j, val, st_nr2.out.nr2_ens(j)); end
    end

    % 3. M1 seeds 1..10
    env_m1_e = env_m1; env_m1_e.scheduler = 'pf'; env_m1_e.eot_mode = eot_mode;
    for s = 1:10
        pol = m1_pols{s};
        for j = 1:n_eval
            rng(1020000 + 100*j + 10*8 + s);
            [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('a2c_v17', pol, traces(j).SINR, traces(j).obsS, env_m1_e, traces(j).meta, traces(j).U);
            [~, ~, val] = userMetric_v17(env_m1_e, tp, inf, b0);
            m1_seeds(s, j) = val;
            if is_asrun, check_repro('NR2', sprintf('m1_seed_%d', s), j, val, st_nr2.out.m1_seeds(s, j)); end
        end
    end

    % 4. Comparators
    for j = 1:n_eval
        rng(1020000 + 100*j + 10*1 + 1); [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('baseline', [], traces(j).SINR, traces(j).obsS, envN2, traces(j).meta, traces(j).U);
        [~, ~, v] = userMetric_v17(envN2, tp, inf, b0); cmp.baseline(j) = v;
        if is_asrun, check_repro('NR2', 'baseline', j, v, st_nr2.out.cmp.baseline(j)); end

        rng(1020000 + 100*j + 10*2 + 1); [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('olla', [], traces(j).SINR, traces(j).obsS, envN2, traces(j).meta, traces(j).U);
        [~, ~, v] = userMetric_v17(envN2, tp, inf, b0); cmp.olla(j) = v;
        if is_asrun, check_repro('NR2', 'olla', j, v, st_nr2.out.cmp.olla(j)); end

        rng(1020000 + 100*j + 10*3 + 1); [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('olla_tuned', [], traces(j).SINR, traces(j).obsS, e_olla, traces(j).meta, traces(j).U);
        [~, ~, v] = userMetric_v17(e_olla, tp, inf, b0); cmp.olla_tuned500(j) = v;
        if is_asrun, check_repro('NR2', 'olla_tuned500', j, v, st_nr2.out.cmp.olla_tuned500(j)); end

        rng(1020000 + 100*j + 10*4 + 1); [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('multi_olla', [], traces(j).SINR, traces(j).obsS, envN2, traces(j).meta, traces(j).U);
        [~, ~, v] = userMetric_v17(envN2, tp, inf, b0); cmp.multi_olla(j) = v;
        if is_asrun, check_repro('NR2', 'multi_olla', j, v, st_nr2.out.cmp.multi_olla(j)); end

        rng(1020000 + 100*j + 10*5 + 1); [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('fixed', [], traces(j).SINR, traces(j).obsS, e_f, traces(j).meta, traces(j).U);
        [~, ~, v] = userMetric_v17(e_f, tp, inf, b0); cmp.fixed500(j) = v;
        if is_asrun, check_repro('NR2', 'fixed500', j, v, st_nr2.out.cmp.fixed500(j)); end

        rng(1020000 + 100*j + 10*6 + 1); [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('fixed_class', [], traces(j).SINR, traces(j).obsS, e_pu, traces(j).meta, traces(j).U);
        [~, ~, v] = userMetric_v17(e_pu, tp, inf, b0); cmp.fixedpu500(j) = v;
        if is_asrun, check_repro('NR2', 'fixedpu500', j, v, st_nr2.out.cmp.fixedpu500(j)); end

        rng(1020000 + 100*j + 10*7 + 1); [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('ctxtab', [], traces(j).SINR, traces(j).obsS, e_ctx, traces(j).meta, traces(j).U);
        [~, ~, v] = userMetric_v17(e_ctx, tp, inf, b0); cmp.ctx500(j) = v;
        if is_asrun, check_repro('NR2', 'ctx500', j, v, st_nr2.out.cmp.ctx500(j)); end

        rng(1020000 + 100*j + 10*99 + 1); [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('ctxj', [], traces(j).SINR, traces(j).obsS, e_ctxj, traces(j).meta, traces(j).U);
        [~, ~, v] = userMetric_v17(e_ctxj, tp, inf, b0); cmp.ctxj500(j) = v;
        if is_asrun, check_repro('NR2', 'ctxj500', j, v, st_nr2.out.cmp.ctxj500(j)); end
    end

    % 5. R6a seeds 1..10
    for s = 1:10
        pol = r6a_pols{s};
        for j = 1:n_eval
            rng(2340000 + 100*j + s);
            [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('a2c_v17', pol, traces(j).SINR, traces(j).obsS, envFull, traces(j).meta, traces(j).U);
            [~, ~, val] = userMetric_v17(envFull, tp, inf, b0);
            r6a_vals(s, j) = val;
            if is_asrun, check_repro('NR2', sprintf('r6a_seed_%d', s), j, val, st_r6.out.rlfull_vals(s, j)); end
        end
    end

    % 6. GBT-res-ACK & GBT-full-ACK fits 1..4
    for k = 1:4
        m = gbt_m1_trees{k};
        for j = 1:n_eval
            [tp_r, ~, ~, ~, inf_r] = evalPolicy_presub_eot('gbt_res_ack', m, traces(j).SINR, traces(j).obsS, envN2, traces(j).meta, traces(j).U);
            [~, ~, vr] = userMetric_v17(envN2, tp_r, inf_r, b0);
            gbt_res_ack(k, j) = vr;

            [tp_f, ~, ~, ~, inf_f] = evalPolicy_presub_eot('gbt_full_ack', m, traces(j).SINR, traces(j).obsS, envN2, traces(j).meta, traces(j).U);
            [~, ~, vf] = userMetric_v17(envN2, tp_f, inf_f, b0);
            gbt_full_ack(k, j) = vf;

            if is_asrun
                if k == 1
                    check_repro('NR2', 'gbt_res_ack_fit1', j, vr, st_r1b.out.gbt_res(j));
                    check_repro('NR2', 'gbt_full_ack_fit1', j, vf, st_r1b.out.gbt_full(j));
                else
                    check_repro('NR2', sprintf('gbt_res_ack_fit%d', k), j, vr, st_r1c.out.res(k, j));
                    check_repro('NR2', sprintf('gbt_full_ack_fit%d', k), j, vf, st_r1c.out.full(k, j));
                end
            end
        end
    end

    % 7. R1 true-SINR GBT & R2 rules
    for j = 1:n_eval
        [tp_r, ~, ~, ~, inf_r] = evalPolicy_presub_eot('gbt_res', r1_model, traces(j).SINR, traces(j).obsS, envN2, traces(j).meta, traces(j).U);
        [~, ~, vr] = userMetric_v17(envN2, tp_r, inf_r, b0); r1_gbt_res(j) = vr;

        [tp_f, ~, ~, ~, inf_f] = evalPolicy_presub_eot('gbt_full', r1_model, traces(j).SINR, traces(j).obsS, envN2, traces(j).meta, traces(j).U);
        [~, ~, vf] = userMetric_v17(envN2, tp_f, inf_f, b0); r1_gbt_full(j) = vf;

        rng(1020000 + 100*j + 10*8 + 1);
        [tp_ru, ~, ~, ~, inf_ru] = evalPolicy_presub_eot('rule', [], traces(j).SINR, traces(j).obsS, envN2, traces(j).meta, traces(j).U);
        [~, ~, vru] = userMetric_v17(envN2, tp_ru, inf_ru, b0); r2_rule(j) = vru;

        rng(1020000 + 100*j + 10*8 + 1);
        [tp_cal, ~, ~, ~, inf_cal] = evalPolicy_presub_eot('rule_cal', chosen_th, traces(j).SINR, traces(j).obsS, envN2, traces(j).meta, traces(j).U);
        [~, ~, vcal] = userMetric_v17(envN2, tp_cal, inf_cal, b0); r2_rule_cal(j) = vcal;

        if is_asrun
            check_repro('NR2', 'r1_gbt_res', j, vr, st_r1.out.gbt_res(j));
            check_repro('NR2', 'r1_gbt_full', j, vf, st_r1.out.gbt_full(j));
            check_repro('NR2', 'r2_rule', j, vru, st_r2.out.rule(j));
            check_repro('NR2', 'r2_rule_cal', j, vcal, st_r2.out.rule_cal(j));
        end
    end

    res = struct('nr2_seeds', nr2_seeds, 'nr2_ens', nr2_ens, 'm1_seeds', m1_seeds, ...
                 'cmp', cmp, 'r6a_vals', r6a_vals, 'gbt_res_ack', gbt_res_ack, 'gbt_full_ack', gbt_full_ack, ...
                 'r1_gbt_res', r1_gbt_res, 'r1_gbt_full', r1_gbt_full, 'r2_rule', r2_rule, 'r2_rule_cal', r2_rule_cal);
    if is_asrun
        res.exposure = struct('n_counted_asrun', exp_c_asrun, 'n_counted_resolved', exp_c_res, ...
                              'n_late_ack_asrun', exp_late_ack, 'n_censored_asrun', exp_cens);
    end
end

% =========================================================================
% M1 Evaluation
% =========================================================================
function res = eval_m1_all(eot_mode, n_eval, ctx, v17x_dir, v17_dir, base, C)
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data_m1 = load(fullfile(v17_dir, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data_m1.results;
    env_m1 = R_M1.env;
    env_m1.scheduler = 'pf';
    env_m1.eot_mode = eot_mode;
    N = env_m1.N; b0 = min(env_m1.burn_in, o.simTime - 1);

    m1_pols = R_M1.policies.A2C(1:10);

    % Pre-generate traces (M1 seed range: 500000+j, CRN: 510000+j)
    traces = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    for j = 1:n_eval
        tr_seed = 500000 + j; crn_seed = 510000 + j;
        rng(tr_seed, 'twister'); [Strue, ~, meta] = generateChannel_v17(o.simTime, env_m1);
        obsS = cqiFeedback_v17(Strue, env_m1, meta.delays);
        meta.trace_id = j;
        rng(crn_seed, 'twister'); U = rand(o.simTime, N);
        traces(j).SINR = Strue; traces(j).obsS = obsS; traces(j).meta = meta; traces(j).U = U;
    end

    m1_seeds = zeros(10, n_eval);
    m1_ens   = zeros(1, n_eval);
    is_asrun = strcmp(eot_mode, 'asrun');
    st_g6c = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'g6c', 'eval.mat'));

    exp_c_asrun = 0; exp_c_res = 0; exp_late_ack = 0; exp_cens = 0;

    for s = 1:10
        pol = m1_pols{s};
        for j = 1:n_eval
            rng(77000 + 100*j + 10*8 + s);
            [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('a2c_v17', pol, traces(j).SINR, traces(j).obsS, env_m1, traces(j).meta, traces(j).U);
            [~, ~, val] = userMetric_v17(env_m1, tp, inf, b0);
            m1_seeds(s, j) = val;
            if is_asrun
                check_repro('M1', sprintf('m1_seed_%d', s), j, val, R_M1.metrics.primary{8}(s, j));
                exp_c_asrun = exp_c_asrun + inf.n_counted_asrun;
                exp_c_res = exp_c_res + inf.n_counted_resolved;
                exp_late_ack = exp_late_ack + inf.n_late_ack_asrun;
                exp_cens = exp_cens + inf.n_censored_asrun;
            end
        end
    end

    % M1 ensemble
    for j = 1:n_eval
        rng(77000 + 100*j + 10*10 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('a2c_ens', m1_pols, traces(j).SINR, traces(j).obsS, env_m1, traces(j).meta, traces(j).U);
        [~, ~, val] = userMetric_v17(env_m1, tp, inf, b0);
        m1_ens(j) = val;
        if is_asrun, check_repro('M1', 'm1_ens', j, val, R_M1.metrics.primary{10}(1, j)); end
    end

    % 500-trace comparators (G6c)
    cmp_g6c = struct('prim_fixed500', zeros(1, n_eval), 'prim_pu500', zeros(1, n_eval), ...
                     'prim_ctx500', zeros(1, n_eval), 'prim_ctxj500', zeros(1, n_eval), ...
                     'prim_olla500', zeros(1, n_eval));

    txt_single = fileread(fullfile(v17x_dir, 'Dataset', 'cal500_single.txt'));
    f_off = parse_int(txt_single, 'Fixed-500: offset = ([+-]?[0-9]+)');
    comp_ckpt = fullfile(v17x_dir, 'Dataset', 'ckpt', 'g6a', 'composite_table.mat');
    if exist(comp_ckpt, 'file')
        S_comp = load(comp_ckpt); pu_tab = S_comp.out.fixedpu_tab; ctx_tab = S_comp.out.ctx_tab; olla_set = S_comp.out.olla_setting;
    else
        pu_tab = env_m1.class_tab; ctx_tab = env_m1.ctx_tab; olla_set = [env_m1.olla_target, 0.5];
    end
    ctxj_tab = read_ctxj_from_tables(fullfile(v17x_dir, 'Dataset', 'cal500_tables.txt'));

    e_f = env_m1; e_f.fixed_offset = f_off;
    e_pu = env_m1; e_pu.fixed_class_tab = pu_tab; e_pu.class_tab = pu_tab;
    e_ctx = env_m1; e_ctx.ctx_tab = ctx_tab;
    e_olla = env_m1; e_olla.olla_target = olla_set(1); e_olla.olla_target_tuned = olla_set(1); e_olla.olla_step_down = olla_set(2);
    e_ctxj = env_m1; e_ctxj.ctxj_tab = ctxj_tab;

    for j = 1:n_eval
        rng(77000 + 100*j + 10*5 + 1); [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('fixed', [], traces(j).SINR, traces(j).obsS, e_f, traces(j).meta, traces(j).U);
        [~, ~, v] = userMetric_v17(e_f, tp, inf, b0); cmp_g6c.prim_fixed500(j) = v;
        if is_asrun, check_repro('M1', 'prim_fixed500', j, v, st_g6c.out.prim_fixed500(j)); end

        rng(77000 + 100*j + 10*6 + 1); [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('fixed_class', [], traces(j).SINR, traces(j).obsS, e_pu, traces(j).meta, traces(j).U);
        [~, ~, v] = userMetric_v17(e_pu, tp, inf, b0); cmp_g6c.prim_pu500(j) = v;
        if is_asrun, check_repro('M1', 'prim_pu500', j, v, st_g6c.out.prim_pu500(j)); end

        rng(77000 + 100*j + 10*7 + 1); [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('ctxtab', [], traces(j).SINR, traces(j).obsS, e_ctx, traces(j).meta, traces(j).U);
        [~, ~, v] = userMetric_v17(e_ctx, tp, inf, b0); cmp_g6c.prim_ctx500(j) = v;
        if is_asrun, check_repro('M1', 'prim_ctx500', j, v, st_g6c.out.prim_ctx500(j)); end

        rng(77000 + 100*j + 10*99 + 1); [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('ctxj', [], traces(j).SINR, traces(j).obsS, e_ctxj, traces(j).meta, traces(j).U);
        [~, ~, v] = userMetric_v17(e_ctxj, tp, inf, b0); cmp_g6c.prim_ctxj500(j) = v;
        if is_asrun, check_repro('M1', 'prim_ctxj500', j, v, st_g6c.out.prim_ctxj500(j)); end

        rng(77000 + 100*j + 10*3 + 1); [tp, ~, ~, ~, inf] = evalPolicy_g6_eot('olla_tuned', [], traces(j).SINR, traces(j).obsS, e_olla, traces(j).meta, traces(j).U);
        [~, ~, v] = userMetric_v17(e_olla, tp, inf, b0); cmp_g6c.prim_olla500(j) = v;
        if is_asrun, check_repro('M1', 'prim_olla500', j, v, st_g6c.out.prim_olla500(j)); end
    end

    res = struct('m1_seeds', m1_seeds, 'm1_ens', m1_ens, 'cmp_g6c', cmp_g6c);
    if is_asrun
        res.exposure = struct('n_counted_asrun', exp_c_asrun, 'n_counted_resolved', exp_c_res, ...
                              'n_late_ack_asrun', exp_late_ack, 'n_censored_asrun', exp_cens);
    end
end

% =========================================================================
% G2 Evaluation
% =========================================================================
function res = eval_g2_all(eot_mode, n_eval, ctx, v17x_dir, v17_dir, base, C)
    % G2 cell config with pkt_bits = 14000 (Deviation D1)
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    s2 = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'g10', 'calib_single_G2_hi_d10.mat'));
    env = s2.out.env;
    env.base_rule_force = 'fixed';
    env.fixed_offset = s2.out.fixed_offset;
    env = selectBaseRule_v17n(env, 2, 1000);
    env.scheduler = 'pf';
    env.eot_mode = eot_mode;
    b0 = min(env.burn_in, o.simTime - 1);

    % Policies
    st_g2 = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'nr_g10', 'eval_G2_hi_d10.mat'));
    g2_rederive = load(fullfile(v17x_dir, 'Dataset', 'g2_rederive_results.mat'));
    g2_pols = cell(1, 10);
    for s = 1:5
        S = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'nr_g10', sprintf('train_seed_G2_hi_d10_%d.mat', s)));
        g2_pols{s} = S.out.a2c;
    end
    for s = 6:10
        S = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r5_seeds', sprintf('train_G2_hi_d10_%d.mat', s)));
        g2_pols{s} = S.out.a2c;
    end

    % Fits 1..4
    trees_cell = cell(1, 4); trees_transfer = cell(1, 4);
    for k = 1:4
        Sc = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1c', sprintf('r1c_trees_g2_%d.mat', k)));
        m = Sc.trees_export;
        if isstruct(m.trees) && numel(m.trees) > 1
            tc = cell(1, numel(m.trees)); for it = 1:numel(m.trees), tc{it} = m.trees(it); end
            m.trees = tc;
        end
        trees_cell{k} = m;
        if k == 1
            Sr = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1b_ack', 'equiv.mat'));
            trees_transfer{1} = Sr.out;
        else
            St = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1c', sprintf('r1c_trees_m1_%d.mat', k)));
            m = St.trees_export;
            if isstruct(m.trees) && numel(m.trees) > 1
                tc = cell(1, numel(m.trees)); for it = 1:numel(m.trees), tc{it} = m.trees(it); end
                m.trees = tc;
            end
            trees_transfer{k} = m;
        end
    end

    % Traces
    traces = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    for j = 1:n_eval
        tr_seed = 720000 + j; crn_seed = 730000 + j;
        rng(tr_seed, 'twister'); [Strue, ~, meta] = generateChannel_v17(o.simTime, env);
        obsS = cqiFeedback_v17(Strue, env, meta.delays);
        meta.trace_id = j;
        rng(crn_seed, 'twister'); U = rand(o.simTime, env.N);
        traces(j).SINR = Strue; traces(j).obsS = obsS; traces(j).meta = meta; traces(j).U = U;
    end

    rl_seeds = zeros(10, n_eval);
    cellfit_res = zeros(4, n_eval); cellfit_full = zeros(4, n_eval);
    transfer_res = zeros(4, n_eval); transfer_full = zeros(4, n_eval);
    is_asrun = strcmp(eot_mode, 'asrun');
    st_r1c_cell = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1c', 'eval_g2_cellfit.mat'));
    st_r1c_trans = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1c', 'eval_g2_transfer.mat'));

    exp_c_asrun = 0; exp_c_res = 0; exp_late_ack = 0; exp_cens = 0;

    for s = 1:10
        pol = g2_pols{s};
        for j = 1:n_eval
            rng(77000 + 100*j + 10*8 + s);
            [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('a2c_v17', pol, traces(j).SINR, traces(j).obsS, env, traces(j).meta, traces(j).U);
            [~, ~, val] = userMetric_v17(env, tp, inf, b0);
            rl_seeds(s, j) = val;
            if is_asrun
                if s <= 5
                    stored_v = st_g2.out.rl_seeds(s, j);
                else
                    stored_v = g2_rederive.vals_A(s - 5, j);
                end
                check_repro('G2', sprintf('rl_seed_%d', s), j, val, stored_v);
                exp_c_asrun = exp_c_asrun + inf.n_counted_asrun;
                exp_c_res = exp_c_res + inf.n_counted_resolved;
                exp_late_ack = exp_late_ack + inf.n_late_ack_asrun;
                exp_cens = exp_cens + inf.n_censored_asrun;
            end
        end
    end

    for k = 1:4
        mc = trees_cell{k}; mt = trees_transfer{k};
        for j = 1:n_eval
            [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('gbt_res_ack', mc, traces(j).SINR, traces(j).obsS, env, traces(j).meta, traces(j).U);
            [~, ~, vcr] = userMetric_v17(env, tp, inf, b0); cellfit_res(k, j) = vcr;

            [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('gbt_full_ack', mc, traces(j).SINR, traces(j).obsS, env, traces(j).meta, traces(j).U);
            [~, ~, vcf] = userMetric_v17(env, tp, inf, b0); cellfit_full(k, j) = vcf;

            [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('gbt_res_ack', mt, traces(j).SINR, traces(j).obsS, env, traces(j).meta, traces(j).U);
            [~, ~, vtr] = userMetric_v17(env, tp, inf, b0); transfer_res(k, j) = vtr;

            [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('gbt_full_ack', mt, traces(j).SINR, traces(j).obsS, env, traces(j).meta, traces(j).U);
            [~, ~, vtf] = userMetric_v17(env, tp, inf, b0); transfer_full(k, j) = vtf;

            if is_asrun
                check_repro('G2', sprintf('cellfit_res_%d', k), j, vcr, st_r1c_cell.out.res(k, j));
                check_repro('G2', sprintf('cellfit_full_%d', k), j, vcf, st_r1c_cell.out.full(k, j));
                check_repro('G2', sprintf('transfer_res_%d', k), j, vtr, st_r1c_trans.out.res(k, j));
                check_repro('G2', sprintf('transfer_full_%d', k), j, vtf, st_r1c_trans.out.full(k, j));
            end
        end
    end

    res = struct('rl_seeds', rl_seeds, 'cellfit_res', cellfit_res, 'cellfit_full', cellfit_full, ...
                 'transfer_res', transfer_res, 'transfer_full', transfer_full);
    if is_asrun
        res.exposure = struct('n_counted_asrun', exp_c_asrun, 'n_counted_resolved', exp_c_res, ...
                              'n_late_ack_asrun', exp_late_ack, 'n_censored_asrun', exp_cens);
    end
end

% =========================================================================
% G3 Evaluation
% =========================================================================
function res = eval_g3_all(eot_mode, n_eval, ctx, v17x_dir, v17_dir, base, C)
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    s3 = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'g10', 'calib_single_G3_lo_d18.mat'));
    env = s3.out.env;
    env.base_rule_force = 'fixed';
    env.fixed_offset = s3.out.fixed_offset;
    env = selectBaseRule_v17n(env, 2, 1000);
    env.scheduler = 'pf';
    env.eot_mode = eot_mode;
    b0 = min(env.burn_in, o.simTime - 1);

    st_g3 = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'nr_g10', 'eval_G3_lo_d18.mat'));
    st_r5_g3 = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r5_seeds', 'eval.mat'));
    g3_pols = cell(1, 10);
    for s = 1:5
        S = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'nr_g10', sprintf('train_seed_G3_lo_d18_%d.mat', s)));
        g3_pols{s} = S.out.a2c;
    end
    for s = 6:10
        S = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r5_seeds', sprintf('train_G3_lo_d18_%d.mat', s)));
        g3_pols{s} = S.out.a2c;
    end

    trees_cell = cell(1, 4); trees_transfer = cell(1, 4);
    for k = 1:4
        Sc = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1c', sprintf('r1c_trees_g3_%d.mat', k)));
        m = Sc.trees_export;
        if isstruct(m.trees) && numel(m.trees) > 1
            tc = cell(1, numel(m.trees)); for it = 1:numel(m.trees), tc{it} = m.trees(it); end
            m.trees = tc;
        end
        trees_cell{k} = m;
        if k == 1
            Sr = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1b_ack', 'equiv.mat'));
            trees_transfer{1} = Sr.out;
        else
            St = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1c', sprintf('r1c_trees_m1_%d.mat', k)));
            m = St.trees_export;
            if isstruct(m.trees) && numel(m.trees) > 1
                tc = cell(1, numel(m.trees)); for it = 1:numel(m.trees), tc{it} = m.trees(it); end
                m.trees = tc;
            end
            trees_transfer{k} = m;
        end
    end

    traces = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    for j = 1:n_eval
        tr_seed = 740000 + j; crn_seed = 750000 + j;
        rng(tr_seed, 'twister'); [Strue, ~, meta] = generateChannel_v17(o.simTime, env);
        obsS = cqiFeedback_v17(Strue, env, meta.delays);
        meta.trace_id = j;
        rng(crn_seed, 'twister'); U = rand(o.simTime, env.N);
        traces(j).SINR = Strue; traces(j).obsS = obsS; traces(j).meta = meta; traces(j).U = U;
    end

    rl_seeds = zeros(10, n_eval);
    cellfit_res = zeros(4, n_eval); cellfit_full = zeros(4, n_eval);
    transfer_res = zeros(4, n_eval); transfer_full = zeros(4, n_eval);
    is_asrun = strcmp(eot_mode, 'asrun');
    st_r1c_cell = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1c', 'eval_g3_cellfit.mat'));
    st_r1c_trans = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1c', 'eval_g3_transfer.mat'));

    exp_c_asrun = 0; exp_c_res = 0; exp_late_ack = 0; exp_cens = 0;

    for s = 1:10
        pol = g3_pols{s};
        for j = 1:n_eval
            rng(77000 + 100*j + 10*8 + s);
            [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('a2c_v17', pol, traces(j).SINR, traces(j).obsS, env, traces(j).meta, traces(j).U);
            [~, ~, val] = userMetric_v17(env, tp, inf, b0);
            rl_seeds(s, j) = val;
            if is_asrun
                if s <= 5
                    stored_v = st_g3.out.rl_seeds(s, j);
                else
                    stored_v = st_r5_g3.out.g3_fresh_vals(s - 5, j);
                end
                check_repro('G3', sprintf('rl_seed_%d', s), j, val, stored_v);
                exp_c_asrun = exp_c_asrun + inf.n_counted_asrun;
                exp_c_res = exp_c_res + inf.n_counted_resolved;
                exp_late_ack = exp_late_ack + inf.n_late_ack_asrun;
                exp_cens = exp_cens + inf.n_censored_asrun;
            end
        end
    end

    for k = 1:4
        mc = trees_cell{k}; mt = trees_transfer{k};
        for j = 1:n_eval
            [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('gbt_res_ack', mc, traces(j).SINR, traces(j).obsS, env, traces(j).meta, traces(j).U);
            [~, ~, vcr] = userMetric_v17(env, tp, inf, b0); cellfit_res(k, j) = vcr;

            [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('gbt_full_ack', mc, traces(j).SINR, traces(j).obsS, env, traces(j).meta, traces(j).U);
            [~, ~, vcf] = userMetric_v17(env, tp, inf, b0); cellfit_full(k, j) = vcf;

            [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('gbt_res_ack', mt, traces(j).SINR, traces(j).obsS, env, traces(j).meta, traces(j).U);
            [~, ~, vtr] = userMetric_v17(env, tp, inf, b0); transfer_res(k, j) = vtr;

            [tp, ~, ~, ~, inf] = evalPolicy_presub_eot('gbt_full_ack', mt, traces(j).SINR, traces(j).obsS, env, traces(j).meta, traces(j).U);
            [~, ~, vtf] = userMetric_v17(env, tp, inf, b0); transfer_full(k, j) = vtf;

            if is_asrun
                check_repro('G3', sprintf('cellfit_res_%d', k), j, vcr, st_r1c_cell.out.res(k, j));
                check_repro('G3', sprintf('cellfit_full_%d', k), j, vcf, st_r1c_cell.out.full(k, j));
                check_repro('G3', sprintf('transfer_res_%d', k), j, vtr, st_r1c_trans.out.res(k, j));
                check_repro('G3', sprintf('transfer_full_%d', k), j, vtf, st_r1c_trans.out.full(k, j));
            end
        end
    end

    res = struct('rl_seeds', rl_seeds, 'cellfit_res', cellfit_res, 'cellfit_full', cellfit_full, ...
                 'transfer_res', transfer_res, 'transfer_full', transfer_full);
    if is_asrun
        res.exposure = struct('n_counted_asrun', exp_c_asrun, 'n_counted_resolved', exp_c_res, ...
                              'n_late_ack_asrun', exp_late_ack, 'n_censored_asrun', exp_cens);
    end
end

% =========================================================================
% Repro assertion helper
% =========================================================================
function check_repro(set_name, scheme_name, trace_idx, val, stored_val)
    diff = abs(val - stored_val);
    if diff > 1e-9
        error('EOT:asrun_mismatch', ...
            'ASRUN REPRO FAIL: set=%s, scheme=%s, trace=%d, computed=%.6f, stored=%.6f, diff=%g', ...
            set_name, scheme_name, trace_idx, val, stored_val, diff);
    end
end

function val = parse_int(txt, pattern)
    tok = regexp(txt, pattern, 'tokens');
    if isempty(tok), error('Pattern not found: %s', pattern); end
    val = str2double(tok{1}{1});
end

function tab = read_ctxj_from_tables(fpath)
    tab = zeros(3, 2, 3, 2);
    lines = strsplit(fileread(fpath), sprintf('\n'));
    for i = 1:numel(lines)
        line = strtrim(lines{i});
        tok = regexp(line, 'cell\((\d+),(\d+),(\d+),(\d+)\) = ([+-]?\d+)', 'tokens', 'once');
        if ~isempty(tok)
            b = str2double(tok{1});
            d = str2double(tok{2});
            v = str2double(tok{3});
            u = str2double(tok{4}) + 1;
            off = str2double(tok{5});
            tab(b, d, v, u) = off;
        end
    end
end
