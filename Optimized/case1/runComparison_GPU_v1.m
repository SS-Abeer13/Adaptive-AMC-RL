function results = runComparison_GPU_v1(simTime, num_episodes_tabular, num_episodes_deep, seed)
% Optimized Case 1 comparison harness: GPU Deep A2C, dual reward.
% Drop-in replacement for runComparison.m that uses DeepAC_AMC_Simulation_GPU_v1.

    if nargin < 1 || isempty(simTime),              simTime = 1000;             end
    if nargin < 2 || isempty(num_episodes_tabular), num_episodes_tabular = 500; end
    if nargin < 3 || isempty(num_episodes_deep),    num_episodes_deep = 200;    end
    if nargin < 4 || isempty(seed),                 seed = 42;                  end

    cellRadius = 500; fc = 2e9; hBS = 30; hUE = 1.5; txPower = 43; BW = 10e6;

    reward_modes = {'throughput', 'bler_target'};
    rm_labels    = {'R2 (Tp)',    'R1 (BLER)'};

    fprintf('Case 1 - AMC Comparison (GPU): 3 algos x 2 rewards\n');

    Q_tables = cell(1,2);  ql_curves  = cell(1,2);
    thetas   = cell(1,2);  ac_curves  = cell(1,2);  Vs = cell(1,2);
    actors   = cell(1,2);  dac_curves = cell(1,2);

    step = 0;
    for k = 1:numel(reward_modes)
        rm = reward_modes{k};

        step = step + 1;
        fprintf('[%d/6] Q-Learning  (%s)\n', step, rm);
        rng(seed);
        [Q_tables{k}, ql_curves{k}] = trainQLearning(simTime, num_episodes_tabular, rm);

        step = step + 1;
        fprintf('[%d/6] Tabular AC  (%s)\n', step, rm);
        [thetas{k}, Vs{k}, ~, ~, ~, ac_curves{k}] = ...
            AC_AMC_Simulation_v1(simTime, num_episodes_tabular, seed, rm);

        step = step + 1;
        fprintf('[%d/6] Deep A2C (GPU) (%s)\n', step, rm);
        [actors{k}, ~, ~, ~, ~, dac_curves{k}] = ...
            DeepAC_AMC_Simulation_GPU_v1(simTime, num_episodes_deep, seed, rm);
    end

    rng(seed + 999);
    [SINR_eval, uePos_eval] = calculateControlledSINR2(simTime, cellRadius, ...
                                                       fc, hBS, hUE, txPower, BW);
    distance_eval = sqrt(sum(uePos_eval.^2, 2));

    [tp_base, bler_base, se_base] = eval_Baseline(SINR_eval, BW);
    tp = cell(3,2); bler = cell(3,2); se = cell(3,2);
    for k = 1:2
        [tp{1,k}, bler{1,k}, se{1,k}] = eval_QLearning(SINR_eval, BW, Q_tables{k});
        [tp{2,k}, bler{2,k}, se{2,k}] = eval_TabularAC(SINR_eval, BW, thetas{k});
        [tp{3,k}, bler{3,k}, se{3,k}] = eval_DeepAC  (SINR_eval, BW, actors{k});
    end

    schemes = {'Baseline', ...
               'QL (R2 Tp)',  'QL (R1 BLER)', ...
               'AC (R2 Tp)',  'AC (R1 BLER)', ...
               'DAC (R2 Tp)', 'DAC (R1 BLER)'};

    avg_tp   = [mean(tp_base),   mean(tp{1,1}),   mean(tp{1,2}), mean(tp{2,1}), mean(tp{2,2}), mean(tp{3,1}), mean(tp{3,2})];
    avg_bler = [mean(bler_base), mean(bler{1,1}), mean(bler{1,2}), mean(bler{2,1}), mean(bler{2,2}), mean(bler{3,1}), mean(bler{3,2})];
    avg_se   = [mean(se_base),   mean(se{1,1}),   mean(se{1,2}), mean(se{2,1}), mean(se{2,2}), mean(se{3,1}), mean(se{3,2})];

    fprintf('\n%-15s | %10s | %8s | %12s\n', 'Scheme', 'Tp(Mbps)', 'BLER', 'SE(b/s/Hz)');
    fprintf('----------------+------------+----------+--------------\n');
    for s = 1:numel(schemes)
        fprintf('%-15s | %10.3f | %8.4f | %12.3f\n', schemes{s}, avg_tp(s), avg_bler(s), avg_se(s));
    end

    delta_pct = zeros(3,2);
    for a = 1:3
        for k = 1:2
            delta_pct(a,k) = 100 * (mean(tp{a,k}) - mean(tp_base)) / max(mean(tp_base), eps);
        end
    end
    figure('Position',[60 60 600 400]);
    imagesc(delta_pct); colormap(parula); colorbar;
    set(gca,'XTick',1:2,'XTickLabel',rm_labels);
    set(gca,'YTick',1:3,'YTickLabel',{'Q-Learning','Tabular AC','Deep A2C'});
    title('Throughput Gain vs Baseline (%)');
    for a = 1:3
        for k = 1:2
            text(k, a, sprintf('%+.1f%%', delta_pct(a,k)), 'HorizontalAlignment','center','Color','w','FontWeight','bold');
        end
    end

    results.schemes        = schemes;
    results.reward_modes   = reward_modes;
    results.avg_throughput = avg_tp;
    results.avg_bler       = avg_bler;
    results.avg_se         = avg_se;
    results.delta_pct      = delta_pct;
    results.SINR_eval      = SINR_eval;
    results.distance_eval  = distance_eval;
    results.throughput.baseline = tp_base;
    results.throughput.grid     = tp;
    results.bler.baseline       = bler_base;
    results.bler.grid           = bler;
    results.se.baseline         = se_base;
    results.se.grid             = se;
    results.learning.ql         = ql_curves;
    results.learning.ac         = ac_curves;
    results.learning.dac        = dac_curves;
    results.policies.Q_tables   = Q_tables;
    results.policies.thetas     = thetas;
    results.policies.Vs         = Vs;
    results.policies.actors     = actors;

    save(fullfile(fileparts(mfilename('fullpath')), 'comparison_results_gpu.mat'), 'results');
end


function [Q_table, learning_curve] = trainQLearning(simTime, num_episodes, reward_mode)
    if nargin < 3 || isempty(reward_mode), reward_mode = 'throughput'; end
    cellRadius = 500; fc = 2e9; hBS = 30; hUE = 1.5; txPower = 43; BW = 10e6;
    alpha = 0.1; gamma = 0.9; epsilon = 0.2; epsilon_decay = 0.995;
    max_CQI = 15; min_CQI = 1; max_delta = 5; min_delta = -5;
    SINR_bins = linspace(-10, 30, 20);
    actions = [-2,-1,0,1,2]; num_actions = numel(actions);
    Q_table = zeros(max_CQI, max_delta-min_delta+1, numel(SINR_bins), num_actions);
    learning_curve = zeros(num_episodes, 1);
    CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                      11.7, 14.1, 16.3, 18.7, 21.0, 22.7];
    for episode = 1:num_episodes
        [SINR_values, ~] = calculateControlledSINR2(simTime, cellRadius, fc, hBS, hUE, txPower, BW);
        cur = find(SINR_values(1) >= CQI_thresholds, 1, 'last');
        cur = max(min_CQI, min(max_CQI, cur));
        prev = cur; d = 0; ep_tp = 0;
        for t = 1:simTime
            [~, si] = min(abs(SINR_bins - SINR_values(t)));
            s_d = d + max_delta + 1;
            if rand() < epsilon, a_idx = randi(num_actions);
            else, [~, a_idx] = max(Q_table(cur, s_d, si, :)); end
            new_CQI = max(min_CQI, min(max_CQI, cur + actions(a_idx)));
            [tbs, ~, ~] = selectTBSFromSINR(SINR_values(t));
            bler = estimateBLER_Enhanced(SINR_values(t), new_CQI-1);
            tp = (1 - bler) * tbs * 1e-3; ep_tp = ep_tp + tp;
            r = computeReward(bler, tbs, reward_mode);
            new_delta = max(min_delta, min(max_delta, new_CQI - prev));
            next_SINR = SINR_values(min(t+1, simTime));
            [~, next_si] = min(abs(SINR_bins - next_SINR));
            max_nextQ = max(Q_table(new_CQI, new_delta+max_delta+1, next_si, :));
            Q_table(cur, s_d, si, a_idx) = Q_table(cur, s_d, si, a_idx) + ...
                alpha * (r + gamma * max_nextQ - Q_table(cur, s_d, si, a_idx));
            prev = cur; cur = new_CQI; d = new_delta;
        end
        learning_curve(episode) = ep_tp / simTime;
        epsilon = epsilon * epsilon_decay;
    end
end


function [tp, bler, se] = eval_Baseline(SINR_values, BW)
    T = numel(SINR_values); tp = zeros(T,1); bler = zeros(T,1); se = zeros(T,1);
    for t = 1:T
        [tbs, ~, mcs] = selectTBSFromSINR(SINR_values(t));
        bler(t) = estimateBLER_Enhanced(SINR_values(t), mcs);
        tp(t)   = (1 - bler(t)) * tbs * 1e-3;
        se(t)   = tp(t) * 1e6 / BW;
    end
end

function [tp, bler, se] = eval_QLearning(SINR_values, BW, Q_table)
    T = numel(SINR_values); tp = zeros(T,1); bler = zeros(T,1); se = zeros(T,1);
    max_CQI = 15; min_CQI = 1; max_delta = 5; min_delta = -5;
    SINR_bins = linspace(-10, 30, 20); actions = [-2,-1,0,1,2];
    CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                      11.7, 14.1, 16.3, 18.7, 21.0, 22.7];
    cur = find(SINR_values(1) >= CQI_thresholds, 1, 'last');
    cur = max(min_CQI, min(max_CQI, cur)); prev = cur; d = 0;
    for t = 1:T
        [~, si] = min(abs(SINR_bins - SINR_values(t)));
        s_d = d + max_delta + 1;
        [~, a_idx] = max(Q_table(cur, s_d, si, :));
        new_CQI = max(min_CQI, min(max_CQI, cur + actions(a_idx)));
        [tbs, ~, ~] = selectTBSFromSINR(SINR_values(t));
        bler(t) = estimateBLER_Enhanced(SINR_values(t), new_CQI-1);
        tp(t)   = (1 - bler(t)) * tbs * 1e-3;
        se(t)   = tp(t) * 1e6 / BW;
        d = max(min_delta, min(max_delta, new_CQI - prev));
        prev = cur; cur = new_CQI;
    end
end

function [tp, bler, se] = eval_TabularAC(SINR_values, BW, theta)
    T = numel(SINR_values); tp = zeros(T,1); bler = zeros(T,1); se = zeros(T,1);
    max_CQI = 15; min_CQI = 1; max_delta = 5; min_delta = -5;
    SINR_bins = linspace(-10, 30, 20); actions = [-2,-1,0,1,2];
    CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                      11.7, 14.1, 16.3, 18.7, 21.0, 22.7];
    cur = find(SINR_values(1) >= CQI_thresholds, 1, 'last');
    cur = max(min_CQI, min(max_CQI, cur)); prev = cur; d = 0;
    for t = 1:T
        [~, si] = min(abs(SINR_bins - SINR_values(t)));
        s_d = d + max_delta + 1;
        prefs = squeeze(theta(cur, s_d, si, :));
        prefs = prefs - max(prefs);
        pi_s  = exp(prefs) / sum(exp(prefs));
        [~, a_idx] = max(pi_s);
        new_CQI = max(min_CQI, min(max_CQI, cur + actions(a_idx)));
        [tbs, ~, ~] = selectTBSFromSINR(SINR_values(t));
        bler(t) = estimateBLER_Enhanced(SINR_values(t), new_CQI-1);
        tp(t)   = (1 - bler(t)) * tbs * 1e-3;
        se(t)   = tp(t) * 1e6 / BW;
        d = max(min_delta, min(max_delta, new_CQI - prev));
        prev = cur; cur = new_CQI;
    end
end

function [tp, bler, se] = eval_DeepAC(SINR_values, BW, actorNet)
    T = numel(SINR_values); tp = zeros(T,1); bler = zeros(T,1); se = zeros(T,1);
    max_CQI = 15; min_CQI = 1; max_delta = 5; min_delta = -5;
    actions = [-2,-1,0,1,2];
    CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                      11.7, 14.1, 16.3, 18.7, 21.0, 22.7];
    cur = find(SINR_values(1) >= CQI_thresholds, 1, 'last');
    cur = max(min_CQI, min(max_CQI, cur)); prev = cur; d = 0;
    % Check if network is on GPU by looking at first learnable
    onGPU = isa(extractdata(actorNet.Learnables.Value{1}), 'gpuArray');
    for t = 1:T
        s_vec = single([cur/15; d/5; SINR_values(t)/30]);
        if onGPU, s_vec_g = gpuArray(s_vec); else, s_vec_g = s_vec; end
        probs = gather(extractdata(predict(actorNet, dlarray(s_vec_g, 'CB'))));
        [~, a_idx] = max(probs);
        new_CQI = max(min_CQI, min(max_CQI, cur + actions(a_idx)));
        [tbs, ~, ~] = selectTBSFromSINR(SINR_values(t));
        bler(t) = estimateBLER_Enhanced(SINR_values(t), new_CQI-1);
        tp(t)   = (1 - bler(t)) * tbs * 1e-3;
        se(t)   = tp(t) * 1e6 / BW;
        d = max(min_delta, min(max_delta, new_CQI - prev));
        prev = cur; cur = new_CQI;
    end
end
