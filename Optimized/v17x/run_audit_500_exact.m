function res = run_audit_500_exact()
    addpath('Optimized/v17');
    addpath('Optimized/v17/headroom');
    addpath('Optimized/v17x');
    addpath('Optimized/v17x/g6');
    addpath('Optimized/v17x/nr1');
    v17_setup;

    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile('Optimized/v17/Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data.results; envFixed = R_M1.env;
    envFixed.base_rule_force = 'fixed';
    envFixed.fixed_offset = -2;
    [envFixed, ~] = selectBaseRule_v17n(envFixed, 2, o.simTime);
    b0 = min(envFixed.burn_in, o.simTime - 1);
    N = envFixed.N;
    simTime = o.simTime;
    nT = 500;

    % Load stored evaluations
    st_nr2 = load('Optimized/v17x/Dataset/ckpt/nr2/eval.mat');
    st_r1  = load('Optimized/v17x/Dataset/ckpt/r1_gbt/eval_NR2.mat');
    s_tr   = load('Optimized/v17x/Dataset/ckpt/r1_gbt/gbt_trees.mat');
    gbt_models = s_tr.trees_export;

    res = struct();

    % 1. Context-joint-500 (from exact stored eval.mat)
    cj_ontime_traces = st_nr2.out.cmp.ctxj500;
    okU_cj = st_nr2.out.okU_ctxj;   % 500 x 10
    resU_cj = st_nr2.out.resU_ctxj; % 500 x 10
    u_ot_cj = okU_cj ./ max(resU_cj, 1);
    jain_cj_t = zeros(1, nT);
    for j = 1:nT
        v = u_ot_cj(j, :);
        jain_cj_t(j) = (sum(v)^2) / (N * sum(v.^2));
    end
    all_u_cj = u_ot_cj(:);
    e5_cj = prctile(all_u_cj, 5);
    e10_cj = prctile(all_u_cj, 10);
    bot_dec_cj = mean(all_u_cj(all_u_cj <= e10_cj));

    % 2. NR2 (from exact stored eval.mat, 10 seeds)
    nr2_seeds = st_nr2.out.nr2_seeds; % 10 x 500
    okU_nr2 = st_nr2.out.okU_nr2;     % 10 x 500 x 10
    resU_nr2 = st_nr2.out.resU_nr2;   % 10 x 500 x 10
    jain_nr2_s = zeros(10, nT);
    all_u_nr2 = cell(1, 10);
    e5_nr2_s = zeros(1, 10);
    e10_nr2_s = zeros(1, 10);
    bot_dec_nr2_s = zeros(1, 10);
    for s = 1:10
        u_ot_s = squeeze(okU_nr2(s, :, :)) ./ max(squeeze(resU_nr2(s, :, :)), 1);
        for j = 1:nT
            v = u_ot_s(j, :);
            jain_nr2_s(s, j) = (sum(v)^2) / (N * sum(v.^2));
        end
        vals_s = u_ot_s(:);
        all_u_nr2{s} = vals_s;
        e5_nr2_s(s) = prctile(vals_s, 5);
        e10_nr2_s(s) = prctile(vals_s, 10);
        bot_dec_nr2_s(s) = mean(vals_s(vals_s <= e10_nr2_s(s)));
    end

    % Start parallel pool with 4 workers if available
    p = gcp('nocreate');
    if isempty(p)
        try parpool(4); catch, parpool(2); end
    end

    % 3. Evaluate GBT-res with twister generator (bit-identical to stage_r1_gbt.m)
    ckpt_res_file = 'Optimized/v17x/Dataset/ckpt_gbt_res.mat';
    if exist(ckpt_res_file, 'file')
        fprintf('\n=== Loading GBT-res from checkpoint ===\n');
        c_res = load(ckpt_res_file);
        gbt_res_ontime = c_res.gbt_res_ontime;
        gbt_res_gp = c_res.gbt_res_gp;
        u_ot_res = c_res.u_ot_res;
        bler1_res = c_res.bler1_res;
    else
        fprintf('\n=== Evaluating GBT-res on 500 traces (twister RNG) ===\n');
        gbt_res_ontime = zeros(1, nT);
        gbt_res_gp = zeros(1, nT);
        u_ot_res = zeros(nT, N);
        bler1_res = cell(1, nT);

        parfor j = 1:nT
            tr_seed = 1000000 + j;
            crn_seed = 1010000 + j;
            rng(tr_seed, 'twister'); [Strue, ~, meta] = generateChannel_v17(simTime, envFixed);
            obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
            meta.trace_id = j;
            rng(crn_seed, 'twister'); U = rand(simTime, N);
            rng(1020000 + 100*j + 10*8 + 1, 'twister');
            [tp, bler, ~, ~, inf] = evalPolicy_presub('gbt_res', gbt_models, Strue, obsS, envFixed, meta, U);
            [num, den, p_val] = userMetric_v17(envFixed, tp, inf, b0);
            gbt_res_ontime(j) = p_val;
            gbt_res_gp(j) = sum(mean(tp(b0+1:end, :), 1));
            u_ot_res(j, :) = num ./ max(den, 1);
            b_sub = bler(b0+1:end, :);
            valid_b = b_sub(~isnan(b_sub));
            bler1_res{j} = valid_b(:);
        end
        save(ckpt_res_file, 'gbt_res_ontime', 'gbt_res_gp', 'u_ot_res', 'bler1_res');
    end

    % Verify bit-identity on GBT-res
    max_d_res = max(abs(gbt_res_ontime - st_r1.out.gbt_res));
    fprintf('GBT-res vs stored max diff: %.6e\n', max_d_res);
    assert(max_d_res == 0, 'GBT-res must reproduce stored values exactly');

    jain_res_t = zeros(1, nT);
    for j = 1:nT
        v = u_ot_res(j, :);
        jain_res_t(j) = (sum(v)^2) / (N * sum(v.^2));
    end
    all_u_res = u_ot_res(:);
    e5_res = prctile(all_u_res, 5);
    e10_res = prctile(all_u_res, 10);
    bot_dec_res = mean(all_u_res(all_u_res <= e10_res));
    all_b_res = vertcat(bler1_res{:});

    % 4. Evaluate GBT-full with twister generator (bit-identical to stage_r1_gbt.m)
    ckpt_full_file = 'Optimized/v17x/Dataset/ckpt_gbt_full.mat';
    if exist(ckpt_full_file, 'file')
        fprintf('\n=== Loading GBT-full from checkpoint ===\n');
        c_full = load(ckpt_full_file);
        gbt_full_ontime = c_full.gbt_full_ontime;
        gbt_full_gp = c_full.gbt_full_gp;
        u_ot_full = c_full.u_ot_full;
        bler1_full = c_full.bler1_full;
    else
        fprintf('\n=== Evaluating GBT-full on 500 traces (twister RNG) ===\n');
        gbt_full_ontime = zeros(1, nT);
        gbt_full_gp = zeros(1, nT);
        u_ot_full = zeros(nT, N);
        bler1_full = cell(1, nT);

        parfor j = 1:nT
            tr_seed = 1000000 + j;
            crn_seed = 1010000 + j;
            rng(tr_seed, 'twister'); [Strue, ~, meta] = generateChannel_v17(simTime, envFixed);
            obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
            meta.trace_id = j;
            rng(crn_seed, 'twister'); U = rand(simTime, N);
            rng(1020000 + 100*j + 10*8 + 1, 'twister');
            [tp, bler, ~, ~, inf] = evalPolicy_presub('gbt_full', gbt_models, Strue, obsS, envFixed, meta, U);
            [num, den, p_val] = userMetric_v17(envFixed, tp, inf, b0);
            gbt_full_ontime(j) = p_val;
            gbt_full_gp(j) = sum(mean(tp(b0+1:end, :), 1));
            u_ot_full(j, :) = num ./ max(den, 1);
            b_sub = bler(b0+1:end, :);
            valid_b = b_sub(~isnan(b_sub));
            bler1_full{j} = valid_b(:);
        end
        save(ckpt_full_file, 'gbt_full_ontime', 'gbt_full_gp', 'u_ot_full', 'bler1_full');
    end

    % Verify bit-identity on GBT-full
    max_d_full = max(abs(gbt_full_ontime - st_r1.out.gbt_full));
    fprintf('GBT-full vs stored max diff: %.6e\n', max_d_full);
    assert(max_d_full == 0, 'GBT-full must reproduce stored values exactly');

    jain_full_t = zeros(1, nT);
    for j = 1:nT
        v = u_ot_full(j, :);
        jain_full_t(j) = (sum(v)^2) / (N * sum(v.^2));
    end
    all_u_full = u_ot_full(:);
    e5_full = prctile(all_u_full, 5);
    e10_full = prctile(all_u_full, 10);
    bot_dec_full = mean(all_u_full(all_u_full <= e10_full));
    all_b_full = vertcat(bler1_full{:});

    % Goodput and BLER for Context-joint and NR2:
    s_audit = load('Optimized/v17x/Dataset/audit_500_metrics.mat');

    res.Context_joint = struct('ontime', mean(cj_ontime_traces), 'goodput', s_audit.res.Context_joint.goodput, ...
        'bler1', s_audit.res.Context_joint.bler1, 'jain', mean(jain_cj_t), 'edge5', e5_cj, 'edge10', e10_cj, 'bot_dec', bot_dec_cj);

    res.NR2 = struct('ontime', mean(mean(nr2_seeds)), 'goodput', s_audit.res.NR2.goodput, ...
        'bler1', s_audit.res.NR2.bler1, 'jain', mean(mean(jain_nr2_s)), 'edge5', mean(e5_nr2_s), 'edge10', mean(e10_nr2_s), 'bot_dec', mean(bot_dec_nr2_s));

    res.GBT_res = struct('ontime', mean(gbt_res_ontime), 'goodput', mean(gbt_res_gp), ...
        'bler1', mean(all_b_res), 'jain', mean(jain_res_t), 'edge5', e5_res, 'edge10', e10_res, 'bot_dec', bot_dec_res);

    res.GBT_full = struct('ontime', mean(gbt_full_ontime), 'goodput', mean(gbt_full_gp), ...
        'bler1', mean(all_b_full), 'jain', mean(jain_full_t), 'edge5', e5_full, 'edge10', e10_full, 'bot_dec', bot_dec_full);

    save('Optimized/v17x/Dataset/audit_exact_side_metrics.mat', 'res');

    fprintf('\n=== FINAL RECOMPUTED EXACT AUDIT METRICS ===\n');
    fprintf('%-15s | %-8s | %-8s | %-8s | %-8s | %-8s | %-8s | %-8s\n', ...
        'Scheme', 'On-Time', 'Goodput', 'BLER1', 'Jain', 'Edge-5', 'Edge-10', 'Bot-Dec');
    fprintf('-----------------------------------------------------------------------------------------\n');
    f_list = {'Context_joint', 'NR2', 'GBT_res', 'GBT_full'};
    for i = 1:numel(f_list)
        fn = f_list{i};
        r = res.(fn);
        fprintf('%-15s | %8.4f | %6.2f M | %6.2f %% | %8.4f | %8.4f | %8.4f | %8.4f\n', ...
            fn, r.ontime, r.goodput, r.bler1*100, r.jain, r.edge5, r.edge10, r.bot_dec);
    end
end
