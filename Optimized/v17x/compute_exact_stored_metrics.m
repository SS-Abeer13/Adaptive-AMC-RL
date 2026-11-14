function compute_exact_stored_metrics()
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

    % 1. CONTEXT-JOINT from stored eval.mat
    fprintf('\n=========================================\n');
    fprintf('=== 1. CONTEXT-JOINT (Exact Stored) ===\n');
    fprintf('=========================================\n');
    cj_ontime_per_trace = st_nr2.out.cmp.ctxj500;
    fprintf('On-time (trace mean): %.4f (target 0.6000)\n', mean(cj_ontime_per_trace));

    okU_cj = st_nr2.out.okU_ctxj;   % 500 x 10
    resU_cj = st_nr2.out.resU_ctxj; % 500 x 10
    u_ot_cj = okU_cj ./ max(resU_cj, 1); % 500 x 10

    % Jain fairness per trace
    jain_cj_traces = zeros(1, nT);
    for j = 1:nT
        v = u_ot_cj(j, :);
        jain_cj_traces(j) = (sum(v)^2) / (N * sum(v.^2));
    end
    jain_cj = mean(jain_cj_traces);

    % User-trace on-time distribution
    all_u_cj = u_ot_cj(:);
    edge5_cj = prctile(all_u_cj, 5);
    edge10_cj = prctile(all_u_cj, 10);
    bot_dec_cj = mean(all_u_cj(all_u_cj <= edge10_cj));

    fprintf('  Jain:              %.4f\n', jain_cj);
    fprintf('  Edge-5:            %.4f\n', edge5_cj);
    fprintf('  Edge-10:           %.4f\n', edge10_cj);
    fprintf('  Bottom-Decile Mean:%.4f\n', bot_dec_cj);

    % 2. NR2 from stored eval.mat
    fprintf('\n=========================================\n');
    fprintf('=== 2. NR2 (Exact Stored, 10 seeds) ===\n');
    fprintf('=========================================\n');
    nr2_seeds = st_nr2.out.nr2_seeds; % 10 x 500
    fprintf('On-time (mean of 10 seeds): %.4f (target 0.6201)\n', mean(mean(nr2_seeds)));

    okU_nr2 = st_nr2.out.okU_nr2;   % 10 x 500 x 10
    resU_nr2 = st_nr2.out.resU_nr2; % 10 x 500 x 10

    jain_nr2_seeds = zeros(10, nT);
    all_u_nr2_seeds = cell(1, 10);
    edge5_nr2_s = zeros(1, 10);
    edge10_nr2_s = zeros(1, 10);
    bot_dec_nr2_s = zeros(1, 10);

    for s = 1:10
        ok_s = squeeze(okU_nr2(s, :, :));   % 500 x 10
        res_s = squeeze(resU_nr2(s, :, :)); % 500 x 10
        u_ot_s = ok_s ./ max(res_s, 1);
        for j = 1:nT
            v = u_ot_s(j, :);
            jain_nr2_seeds(s, j) = (sum(v)^2) / (N * sum(v.^2));
        end
        vals_s = u_ot_s(:);
        all_u_nr2_seeds{s} = vals_s;
        edge5_nr2_s(s) = prctile(vals_s, 5);
        edge10_nr2_s(s) = prctile(vals_s, 10);
        bot_dec_nr2_s(s) = mean(vals_s(vals_s <= edge10_nr2_s(s)));
    end
    jain_nr2 = mean(mean(jain_nr2_seeds));
    edge5_nr2 = mean(edge5_nr2_s);
    edge10_nr2 = mean(edge10_nr2_s);
    bot_dec_nr2 = mean(bot_dec_nr2_s);

    fprintf('  Jain:              %.4f\n', jain_nr2);
    fprintf('  Edge-5:            %.4f\n', edge5_nr2);
    fprintf('  Edge-10:           %.4f\n', edge10_nr2);
    fprintf('  Bottom-Decile Mean:%.4f\n', bot_dec_nr2);

    % Granularity analysis: packets resolved per user
    mean_res_u = mean(resU_cj(:));
    fprintf('\nGranularity: mean packets resolved per user per trace = %.1f (quantum ~ %.4f = 1/%.0f)\n', ...
        mean_res_u, 1/mean_res_u, mean_res_u);

    % Save results
    save('Optimized/v17x/Dataset/exact_stored_side_metrics.mat', ...
        'cj_ontime_per_trace', 'jain_cj', 'edge5_cj', 'edge10_cj', 'bot_dec_cj', ...
        'nr2_seeds', 'jain_nr2', 'edge5_nr2', 'edge10_nr2', 'bot_dec_nr2', 'mean_res_u');
end
