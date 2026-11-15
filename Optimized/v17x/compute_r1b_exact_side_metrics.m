function res = compute_r1b_exact_side_metrics()
    here = fileparts(mfilename('fullpath'));
    v17 = fullfile(fileparts(here), 'v17');
    addpath(v17);
    addpath(fullfile(v17, 'headroom'));
    v17_setup;
    addpath(here);
    addpath(fullfile(here, 'g6'));
    addpath(fullfile(here, 'nr1'));

    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data.results; envFixed = R_M1.env;
    envFixed.base_rule_force = 'fixed';
    envFixed.fixed_offset = -2;
    [envFixed, ~] = selectBaseRule_v17n(envFixed, 2, o.simTime);
    b0 = min(envFixed.burn_in, o.simTime - 1);
    N = envFixed.N;
    simTime = o.simTime;
    nT = 500;

    % Load r1b trees
    s_tr = load(fullfile(here, 'Dataset', 'ckpt', 'r1b_ack', 'r1b_trees.mat'));
    model = s_tr.trees_export;
    if isstruct(model.trees)
        t_cell = cell(1, numel(model.trees));
        for k = 1:numel(model.trees), t_cell{k} = model.trees(k); end
        model.trees = t_cell;
    end

    % Load stored r1b evaluation for verification
    st_r1b = load(fullfile(here, 'Dataset', 'ckpt', 'r1b_ack', 'eval_NR2.mat'));

    fprintf('\n=== Evaluating GBT-res-ACK on 500 NR2 traces ===\n');
    res_ack_ontime = zeros(1, nT);
    res_ack_gp = zeros(1, nT);
    u_ot_res_ack = zeros(nT, N);
    bler1_res_ack = cell(1, nT);

    for j = 1:nT
        tr_seed = 1000000 + j;
        crn_seed = 1010000 + j;
        rng(tr_seed, 'twister'); [Strue, ~, meta] = generateChannel_v17(simTime, envFixed);
        obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
        meta.trace_id = j;
        rng(crn_seed, 'twister'); U = rand(simTime, N);

        [tp, bler, ~, ~, inf] = evalPolicy_presub('gbt_res_ack', model, Strue, obsS, envFixed, meta, U);
        [num, den, p_val] = userMetric_v17(envFixed, tp, inf, b0);
        res_ack_ontime(j) = p_val;
        res_ack_gp(j) = sum(mean(tp(b0+1:end, :), 1));
        u_ot_res_ack(j, :) = num ./ max(den, 1);
        b_sub = bler(b0+1:end, :);
        valid_b = b_sub(~isnan(b_sub));
        bler1_res_ack{j} = valid_b(:);
    end

    max_d_res = max(abs(res_ack_ontime - st_r1b.out.gbt_res));
    fprintf('GBT-res-ACK vs stored max diff: %.6e\n', max_d_res);
    assert(max_d_res == 0, 'GBT-res-ACK must reproduce stored values exactly');

    jain_res_t = zeros(1, nT);
    for j = 1:nT
        v = u_ot_res_ack(j, :);
        jain_res_t(j) = (sum(v)^2) / (N * sum(v.^2));
    end
    all_u_res = u_ot_res_ack(:);
    e5_res = prctile(all_u_res, 5);
    e10_res = prctile(all_u_res, 10);
    bot_dec_res = mean(all_u_res(all_u_res <= e10_res));
    all_b_res = vertcat(bler1_res_ack{:});

    % Save GBT_res_ACK immediately
    s_audit = load(fullfile(here, 'Dataset', 'audit_exact_side_metrics.mat'));
    res = s_audit.res;
    res.GBT_res_ACK = struct('ontime', mean(res_ack_ontime), 'goodput', mean(res_ack_gp), ...
        'bler1', mean(all_b_res), 'jain', mean(jain_res_t), 'edge5', e5_res, 'edge10', e10_res, 'bot_dec', bot_dec_res);
    save(fullfile(here, 'Dataset', 'audit_exact_side_metrics.mat'), 'res');
    fprintf('Saved GBT-res-ACK metrics: ontime=%.4f, goodput=%.2fM, bler1=%.2f%%, jain=%.4f\n', ...
        res.GBT_res_ACK.ontime, res.GBT_res_ACK.goodput, res.GBT_res_ACK.bler1*100, res.GBT_res_ACK.jain);

    fprintf('\n=== Evaluating GBT-full-ACK on 500 NR2 traces ===\n');
    full_ack_ontime = zeros(1, nT);
    full_ack_gp = zeros(1, nT);
    u_ot_full_ack = zeros(nT, N);
    bler1_full_ack = cell(1, nT);

    for j = 1:nT
        tr_seed = 1000000 + j;
        crn_seed = 1010000 + j;
        rng(tr_seed, 'twister'); [Strue, ~, meta] = generateChannel_v17(simTime, envFixed);
        obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
        meta.trace_id = j;
        rng(crn_seed, 'twister'); U = rand(simTime, N);

        [tp, bler, ~, ~, inf] = evalPolicy_presub('gbt_full_ack', model, Strue, obsS, envFixed, meta, U);
        [num, den, p_val] = userMetric_v17(envFixed, tp, inf, b0);
        full_ack_ontime(j) = p_val;
        full_ack_gp(j) = sum(mean(tp(b0+1:end, :), 1));
        u_ot_full_ack(j, :) = num ./ max(den, 1);
        b_sub = bler(b0+1:end, :);
        valid_b = b_sub(~isnan(b_sub));
        bler1_full_ack{j} = valid_b(:);
    end

    max_d_full = max(abs(full_ack_ontime - st_r1b.out.gbt_full));
    fprintf('GBT-full-ACK vs stored max diff: %.6e\n', max_d_full);
    assert(max_d_full == 0, 'GBT-full-ACK must reproduce stored values exactly');

    jain_full_t = zeros(1, nT);
    for j = 1:nT
        v = u_ot_full_ack(j, :);
        jain_full_t(j) = (sum(v)^2) / (N * sum(v.^2));
    end
    all_u_full = u_ot_full_ack(:);
    e5_full = prctile(all_u_full, 5);
    e10_full = prctile(all_u_full, 10);
    bot_dec_full = mean(all_u_full(all_u_full <= e10_full));
    all_b_full = vertcat(bler1_full_ack{:});

    % Load existing audit metrics
    s_audit = load(fullfile(here, 'Dataset', 'audit_exact_side_metrics.mat'));
    res = s_audit.res;

    res.GBT_res_ACK = struct('ontime', mean(res_ack_ontime), 'goodput', mean(res_ack_gp), ...
        'bler1', mean(all_b_res), 'jain', mean(jain_res_t), 'edge5', e5_res, 'edge10', e10_res, 'bot_dec', bot_dec_res);

    res.GBT_full_ACK = struct('ontime', mean(full_ack_ontime), 'goodput', mean(full_ack_gp), ...
        'bler1', mean(all_b_full), 'jain', mean(jain_full_t), 'edge5', e5_full, 'edge10', e10_full, 'bot_dec', bot_dec_full);

    save(fullfile(here, 'Dataset', 'audit_exact_side_metrics.mat'), 'res');

    fprintf('\n=== ALL SIX SCHEMES EXACT AUDIT METRICS ===\n');
    fprintf('%-16s | %-8s | %-8s | %-8s | %-8s | %-8s | %-8s | %-8s\n', ...
        'Scheme', 'On-Time', 'Goodput', 'BLER1', 'Jain', 'Edge-5', 'Edge-10', 'Bot-Dec');
    fprintf('------------------------------------------------------------------------------------------\n');
    f_list = {'Context_joint', 'NR2', 'GBT_res', 'GBT_full', 'GBT_res_ACK', 'GBT_full_ACK'};
    for i = 1:numel(f_list)
        fn = f_list{i};
        r = res.(fn);
        fprintf('%-16s | %8.4f | %6.2f M | %6.2f %% | %8.4f | %8.4f | %8.4f | %8.4f\n', ...
            fn, r.ontime, r.goodput, r.bler1*100, r.jain, r.edge5, r.edge10, r.bot_dec);
    end
end
