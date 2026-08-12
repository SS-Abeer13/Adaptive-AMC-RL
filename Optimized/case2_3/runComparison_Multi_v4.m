function results = runComparison_Multi_v4(N, simTime, num_episodes_tabular, num_episodes_deep, seed, scheduler_mode)
% v4 harness: baseline-relative CQI + shared parameters across all N users.
% Defaults to N=50 to expose Deep A2C's sample-efficiency advantage.
% All three algorithms use shared parameters (one Q-table, one theta, one network).

    if nargin < 1 || isempty(N),                    N = 50;                     end
    if nargin < 2 || isempty(simTime),              simTime = 100;             end
    if nargin < 3 || isempty(num_episodes_tabular), num_episodes_tabular = 300; end
    if nargin < 4 || isempty(num_episodes_deep),    num_episodes_deep = 200;   end
    if nargin < 5 || isempty(seed),                 seed = 42;                 end
    if nargin < 6 || isempty(scheduler_mode),       scheduler_mode = 'pf';     end

    bsPos = [500, 500]; fc = 2e9; hBS = 30; txPower = 43; BW = 10e6; total_RB = 110;
    reward_mode = 'throughput';

    here = fileparts(mfilename('fullpath'));
    log_path = fullfile(here, sprintf('comparison_log_v4_N%d.txt', N));
    log_fid  = fopen(log_path, 'w');
    log = @(varargin) fprintf(log_fid, '[%s] %s\n', datestr(now,'HH:MM:SS'), sprintf(varargin{:}));
    log('runComparison_Multi_v4 start: N=%d simTime=%d ep_tab=%d ep_deep=%d sched=%s', ...
        N, simTime, num_episodes_tabular, num_episodes_deep, scheduler_mode);
    fprintf('Multi-user AMC Comparison V4 [N=%d, scheduler=%s]\n', N, scheduler_mode);

    try
        h_top = waitbar(0, sprintf('Phase 1/3: Q-Learning (N=%d)', N), 'Name', sprintf('v4 N=%d Comparison', N));

        fprintf('[1/3] Training shared tabular Q-Learning ...\n');
        rng(seed);
        [Q_table, ql_curve] = trainQLearning_SharedN(N, simTime, num_episodes_tabular, reward_mode, scheduler_mode);
        waitbar(1/3, h_top, sprintf('Phase 2/3: Tabular AC (N=%d)', N));

        fprintf('[2/3] Training shared tabular Actor-Critic ...\n');
        [theta, ~, ~, ~, ac_curve] = AC_AMC_SharedN(N, simTime, num_episodes_tabular, seed, reward_mode, scheduler_mode);
        waitbar(2/3, h_top, sprintf('Phase 3/3: Deep A2C (N=%d, GPU)', N));

        fprintf('[3/3] Training Deep A2C v4 (GPU) ...\n');
        [actorNet, ~, ~, ~, dac_curve] = DeepAC_AMC_Multi_GPU_v4(simTime, num_episodes_deep, seed, reward_mode, scheduler_mode, N);
        waitbar(1, h_top, 'Evaluation ...');

        rng(seed + 999);
        [SINR_eval, uePos] = calculateControlledSINR_N(simTime, fc, hBS, txPower, BW, N, bsPos);

        distance = zeros(simTime, N);
        for i = 1:N
            for t = 1:simTime
                distance(t,i) = norm(squeeze(uePos(t,:,i)) - bsPos);
            end
        end

        [tp_base, bler_base] = eval_Baseline_N (SINR_eval, scheduler_mode, total_RB);
        [tp_ql,   bler_ql  ] = eval_QLearningShared_N(SINR_eval, Q_table, scheduler_mode, total_RB);
        [tp_ac,   bler_ac  ] = eval_TabACShared_N (SINR_eval, theta,   scheduler_mode, total_RB);
        [tp_dac,  bler_dac ] = eval_DeepAC_N    (SINR_eval, actorNet, scheduler_mode, total_RB);

        schemes  = {'Baseline', 'Q-Learn v4', 'Tab AC v4', 'Deep A2C v4'};
        tp_cells = {tp_base, tp_ql, tp_ac, tp_dac};
        bl_cells = {bler_base, bler_ql, bler_ac, bler_dac};

        cell_tp = zeros(1, 4); mean_bler = zeros(1, 4); jain = zeros(1, 4); se_bphz = zeros(1, 4);
        for k = 1:4
            per_user_avg = mean(tp_cells{k}, 1);
            cell_tp(k)   = sum(per_user_avg);
            m            = tp_cells{k} > 0;
            if any(m(:)), mean_bler(k) = mean(bl_cells{k}(m)); else, mean_bler(k) = NaN; end
            s  = sum(per_user_avg); s2 = sum(per_user_avg.^2);
            jain(k)    = (s.^2) / (N * max(s2, eps));
            se_bphz(k) = cell_tp(k) * 1e6 / BW;
        end

        log('Results N=%d: cell_tp = [%s]', N, sprintf('%.3f ', cell_tp));
        fprintf('\n%-15s | %10s | %8s | %12s | %12s\n', 'Scheme', 'Tp(Mbps)', 'BLER', 'SE(b/s/Hz)', 'Jain');
        fprintf('----------------+------------+----------+--------------+--------------\n');
        for k = 1:4
            fprintf('%-15s | %10.3f | %8.4f | %12.3f | %12.3f\n', ...
                    schemes{k}, cell_tp(k), mean_bler(k), se_bphz(k), jain(k));
        end

        figure('Position',[60 60 1100 380]);
        subplot(1,3,1); bar(cell_tp);   set(gca,'XTickLabel',schemes,'XTickLabelRotation',30);
                        ylabel('Cell Tp (Mbps)'); title(sprintf('Aggregate Tp (N=%d)', N)); grid on;
        subplot(1,3,2); bar(mean_bler); set(gca,'XTickLabel',schemes,'XTickLabelRotation',30);
                        ylabel('Mean BLER'); title('BLER (served TTIs)'); grid on;
        subplot(1,3,3); bar(jain);      set(gca,'XTickLabel',schemes,'XTickLabelRotation',30);
                        ylabel('Jain index'); title('Fairness'); grid on; ylim([0 1.05]);

        figure('Position',[60 60 950 500]);
        plot(ql_curve, 'r', 'LineWidth', 1.5); hold on;
        plot(ac_curve, 'b', 'LineWidth', 1.5);
        x_deep = linspace(1, numel(ql_curve), numel(dac_curve));
        plot(x_deep, dac_curve, 'g', 'LineWidth', 1.8);
        grid on; xlabel('Episode (relative)'); ylabel('Cell Tp per episode (Mbps)');
        title(sprintf('Learning Curves v4 (N=%d)', N));
        legend({'Q-Learn v4','Tab AC v4','Deep A2C v4'}, 'Location','best');

        colors = {[0 0 0], [0.85 0.15 0.15], [0.15 0.3 0.85], [0.1 0.65 0.2]};
        styles = {'--', '-', '-', '-'};
        plot_distance_curve(distance, tp_cells, schemes, colors, styles, ...
            sprintf('Throughput vs Distance (N=%d)', N), 'Throughput (Mbps)', false);
        plot_distance_curve(distance, bl_cells, schemes, colors, styles, ...
            sprintf('BLER vs Distance (N=%d)', N), 'BLER', true);

        results.N               = N;
        results.schemes         = schemes;
        results.scheduler_mode  = scheduler_mode;
        results.cell_throughput = cell_tp;
        results.mean_BLER       = mean_bler;
        results.SE_bphz         = se_bphz;
        results.jain            = jain;
        results.distance        = distance;
        results.SINR_eval       = SINR_eval;
        results.tp.baseline     = tp_base;
        results.tp.ql           = tp_ql;
        results.tp.ac           = tp_ac;
        results.tp.dac          = tp_dac;
        results.bler.baseline   = bler_base;
        results.bler.ql         = bler_ql;
        results.bler.ac         = bler_ac;
        results.bler.dac        = bler_dac;
        results.learning.ql     = ql_curve;
        results.learning.ac     = ac_curve;
        results.learning.dac    = dac_curve;

        save(fullfile(here, sprintf('multi_results_v4_N%d_%s.mat', N, scheduler_mode)), 'results');
        log('Saved multi_results_v4_N%d_%s.mat', N, scheduler_mode);

        if isvalid(h_top), delete(h_top); end
        fclose(log_fid);
    catch ME
        log('FATAL: %s', ME.message);
        for kk = 1:numel(ME.stack), log('  at %s:%d (%s)', ME.stack(kk).file, ME.stack(kk).line, ME.stack(kk).name); end
        try, if isvalid(h_top), delete(h_top); end, catch, end
        fclose(log_fid);
        rethrow(ME);
    end
end


function [Q_table, learning_curve] = trainQLearning_SharedN(N, simTime, num_episodes, reward_mode, scheduler_mode)
% Shared Q-table across all N users -> 50x more samples per state-action cell.
    bsPos = [500,500]; fc = 2e9; hBS = 30; txPower = 43; BW = 10e6; total_RB = 110;
    alpha = 0.1; gamma = 0.9; epsilon = 0.2; epsilon_decay = 0.995; ema_alpha = 0.05;
    lambda_potential = 0.1;
    max_CQI = 15; min_CQI = 1; max_delta = 5; min_delta = -5;
    SINR_bins = linspace(-10, 30, 20);
    actions = [-2,-1,0,1,2]; num_actions = numel(actions);
    no_op_idx = find(actions == 0);

    Q_table = zeros(max_CQI, max_delta-min_delta+1, numel(SINR_bins), num_actions);
    Q_table(:,:,:, no_op_idx) = 0.5;
    learning_curve = zeros(num_episodes, 1);
    CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                      11.7, 14.1, 16.3, 18.7, 21.0, 22.7];

    try, hwb = waitbar(0, 'QL-shared', 'Name', 'Shared QL training'); catch, hwb = []; end

    for episode = 1:num_episodes
        [SINR_values, ~] = calculateControlledSINR_N(simTime, fc, hBS, txPower, BW, N, bsPos);
        prev_base = zeros(1,N);
        for i = 1:N
            idx = find(SINR_values(1,i) >= CQI_thresholds, 1, 'last');
            if isempty(idx), idx = min_CQI; end
            prev_base(i) = max(min_CQI, min(max_CQI, idx));
        end
        R_emas = zeros(1,N); ep_tp = 0;
        for t = 1:simTime
            base_CQI = zeros(1,N);
            for i = 1:N
                idx = find(SINR_values(t,i) >= CQI_thresholds, 1, 'last');
                if isempty(idx), idx = min_CQI; end
                base_CQI(i) = max(min_CQI, min(max_CQI, idx));
            end
            d = max(min_delta, min(max_delta, base_CQI - prev_base));

            a_idx = zeros(1,N); sent_CQI = zeros(1,N); bler = zeros(1,N);
            potential = zeros(1,N); potential_TBS = zeros(1,N);
            for i = 1:N
                [~, si] = min(abs(SINR_bins - SINR_values(t,i)));
                s_d = d(i) + max_delta + 1;
                if rand() < epsilon, a_idx(i) = randi(num_actions);
                else, [~, a_idx(i)] = max(Q_table(base_CQI(i), s_d, si, :)); end
                sent_CQI(i) = max(min_CQI, min(max_CQI, base_CQI(i) + actions(a_idx(i))));
                bler(i)     = estimateBLER_Enhanced(SINR_values(t,i), sent_CQI(i)-1);
                potential_TBS(i) = tbsFromMCSandRB(sent_CQI(i)-1, total_RB);
                potential(i)     = (1 - bler(i)) * potential_TBS(i) * 1e-3;
            end
            rb_alloc = schedule_users(scheduler_mode, t, N, R_emas, potential, total_RB);

            tp_now = zeros(1,N);
            for i = 1:N
                if rb_alloc(i) > 0
                    tp_now(i) = (1 - bler(i)) * tbsFromMCSandRB(sent_CQI(i)-1, rb_alloc(i)) * 1e-3;
                end
            end
            R_emas = (1 - ema_alpha) * R_emas + ema_alpha * tp_now;
            ep_tp  = ep_tp + sum(tp_now);

            for i = 1:N
                [~, si] = min(abs(SINR_bins - SINR_values(t,i)));
                s_d = d(i) + max_delta + 1;
                if rb_alloc(i) > 0
                    actual_tbs = tbsFromMCSandRB(sent_CQI(i)-1, rb_alloc(i));
                    r = computeReward(bler(i), actual_tbs, reward_mode);
                else
                    r = lambda_potential * computeReward(bler(i), potential_TBS(i), reward_mode);
                end
                if t < simTime
                    next_base = find(SINR_values(t+1,i) >= CQI_thresholds, 1, 'last');
                    if isempty(next_base), next_base = min_CQI; end
                    next_base = max(min_CQI, min(max_CQI, next_base));
                else
                    next_base = base_CQI(i);
                end
                next_d  = max(min_delta, min(max_delta, next_base - base_CQI(i)));
                [~, next_si] = min(abs(SINR_bins - SINR_values(min(t+1,simTime), i)));
                max_nextQ = max(Q_table(next_base, next_d+max_delta+1, next_si, :));
                Q_table(base_CQI(i), s_d, si, a_idx(i)) = Q_table(base_CQI(i), s_d, si, a_idx(i)) + ...
                    alpha * (r + gamma * max_nextQ - Q_table(base_CQI(i), s_d, si, a_idx(i)));
            end
            prev_base = base_CQI;
        end
        learning_curve(episode) = ep_tp / simTime;
        epsilon = epsilon * epsilon_decay;
        if ~isempty(hwb) && isvalid(hwb)
            waitbar(episode/num_episodes, hwb, sprintf('QL ep %d/%d  Tp=%.1f', episode, num_episodes, learning_curve(episode)));
        end
    end
    if ~isempty(hwb) && isvalid(hwb), delete(hwb); end
end


function [theta, V, tp_per_user, bler_per_user, learning_curve] = AC_AMC_SharedN(N, simTime, num_episodes, seed, reward_mode, scheduler_mode)
% Shared theta + V across all N users; baseline-relative CQI design.
    if nargin >= 4 && ~isempty(seed), rng(seed); end
    bsPos = [500,500]; fc = 2e9; hBS = 30; txPower = 43; BW = 10e6; total_RB = 110;
    max_CQI = 15; min_CQI = 1; max_delta = 5; min_delta = -5;
    SINR_bins = linspace(-10, 30, 20); num_SINR_bins = numel(SINR_bins);
    actions = [-2,-1,0,1,2]; num_actions = numel(actions);
    no_op_idx = find(actions == 0);
    alpha_theta = 0.05; alpha_v = 0.10; gamma = 0.90;
    reward_scale = 30; ema_alpha = 0.05;
    lambda_potential = 0.1;

    theta = zeros(max_CQI, max_delta-min_delta+1, num_SINR_bins, num_actions);
    theta(:,:,:, no_op_idx) = 1.0;
    V     = zeros(max_CQI, max_delta-min_delta+1, num_SINR_bins);
    learning_curve = zeros(num_episodes, 1);
    tp_per_user    = zeros(simTime, N);
    bler_per_user  = zeros(simTime, N);
    CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                      11.7, 14.1, 16.3, 18.7, 21.0, 22.7];

    try, hwb = waitbar(0, 'AC-shared', 'Name', 'Shared AC training'); catch, hwb = []; end

    for episode = 1:num_episodes
        [SINR_values, ~] = calculateControlledSINR_N(simTime, fc, hBS, txPower, BW, N, bsPos);
        prev_base = zeros(1,N);
        for i = 1:N
            idx = find(SINR_values(1,i) >= CQI_thresholds, 1, 'last');
            if isempty(idx), idx = min_CQI; end
            prev_base(i) = max(min_CQI, min(max_CQI, idx));
        end
        R_emas = zeros(1,N); ep_tp = 0;
        for t = 1:simTime
            base_CQI = zeros(1,N);
            for i = 1:N
                idx = find(SINR_values(t,i) >= CQI_thresholds, 1, 'last');
                if isempty(idx), idx = min_CQI; end
                base_CQI(i) = max(min_CQI, min(max_CQI, idx));
            end
            d = max(min_delta, min(max_delta, base_CQI - prev_base));

            action_idx = zeros(1,N); sent_CQI = zeros(1,N); BLER_now = zeros(1,N);
            potential = zeros(1,N); potential_TBS = zeros(1,N);
            pi_state = cell(1,N); state_idx = zeros(N,3);

            for i = 1:N
                [~, sinr_bin] = min(abs(SINR_bins - SINR_values(t,i)));
                s_cqi = base_CQI(i); s_delta = d(i) + max_delta + 1;
                state_idx(i,:) = [s_cqi, s_delta, sinr_bin];
                prefs = squeeze(theta(s_cqi, s_delta, sinr_bin, :));
                prefs = prefs - max(prefs);
                pi_s  = exp(prefs) / sum(exp(prefs));
                pi_state{i} = pi_s;
                a_idx = find(rand() <= cumsum(pi_s), 1, 'first');
                if isempty(a_idx), a_idx = num_actions; end
                action_idx(i) = a_idx;
                sent_CQI(i) = max(min_CQI, min(max_CQI, base_CQI(i) + actions(a_idx)));
                BLER_now(i) = estimateBLER_Enhanced(SINR_values(t,i), sent_CQI(i)-1);
                potential_TBS(i) = tbsFromMCSandRB(sent_CQI(i)-1, total_RB);
                potential(i) = (1 - BLER_now(i)) * potential_TBS(i) * 1e-3;
            end

            rb_alloc = schedule_users(scheduler_mode, t, N, R_emas, potential, total_RB);

            tp_now = zeros(1,N);
            for i = 1:N
                if rb_alloc(i) > 0
                    tp_now(i) = (1 - BLER_now(i)) * tbsFromMCSandRB(sent_CQI(i)-1, rb_alloc(i)) * 1e-3;
                end
            end
            R_emas = (1 - ema_alpha) * R_emas + ema_alpha * tp_now;
            ep_tp  = ep_tp + sum(tp_now);

            if episode == num_episodes
                tp_per_user(t,:)   = tp_now;
                bler_per_user(t,:) = BLER_now;
            end

            for i = 1:N
                if rb_alloc(i) > 0
                    actual_tbs = tbsFromMCSandRB(sent_CQI(i) - 1, rb_alloc(i));
                    raw_reward = computeReward(BLER_now(i), actual_tbs, reward_mode);
                else
                    raw_reward = lambda_potential * computeReward(BLER_now(i), potential_TBS(i), reward_mode);
                end
                reward = raw_reward / reward_scale;

                if t < simTime
                    next_base = find(SINR_values(t+1,i) >= CQI_thresholds, 1, 'last');
                    if isempty(next_base), next_base = min_CQI; end
                    next_base = max(min_CQI, min(max_CQI, next_base));
                else
                    next_base = base_CQI(i);
                end
                next_d = max(min_delta, min(max_delta, next_base - base_CQI(i)));
                [~, next_sinr_bin] = min(abs(SINR_bins - SINR_values(min(t+1,simTime),i)));

                s_cqi = state_idx(i,1); s_delta = state_idx(i,2); s_sinr = state_idx(i,3);
                V_s      = V(s_cqi, s_delta, s_sinr);
                V_sprime = V(next_base, next_d + max_delta + 1, next_sinr_bin);
                delta    = reward + gamma * V_sprime - V_s;
                V(s_cqi, s_delta, s_sinr) = V_s + alpha_v * delta;

                grad_log = -pi_state{i};
                grad_log(action_idx(i)) = grad_log(action_idx(i)) + 1;
                theta(s_cqi, s_delta, s_sinr, :) = squeeze(theta(s_cqi, s_delta, s_sinr, :)) + alpha_theta * delta * grad_log;
            end
            prev_base = base_CQI;
        end
        learning_curve(episode) = ep_tp / simTime;
        if ~isempty(hwb) && isvalid(hwb)
            waitbar(episode/num_episodes, hwb, sprintf('AC ep %d/%d  Tp=%.1f', episode, num_episodes, learning_curve(episode)));
        end
    end
    if ~isempty(hwb) && isvalid(hwb), delete(hwb); end
end


% ===== Evaluation helpers =====

function [tp, bler] = eval_Baseline_N(SINR_values, scheduler_mode, total_RB)
    [T, N] = size(SINR_values); tp = zeros(T,N); bler = zeros(T,N);
    R_emas = zeros(1,N); ema_alpha = 0.05;
    CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                      11.7, 14.1, 16.3, 18.7, 21.0, 22.7];
    for t = 1:T
        potential = zeros(1,N); bler_now = zeros(1,N); mcs_now = zeros(1,N);
        for i = 1:N
            cqi = find(SINR_values(t,i) >= CQI_thresholds, 1, 'last');
            if isempty(cqi), cqi = 1; end
            cqi = max(1, min(15, cqi));
            mcs_now(i) = cqi - 1;
            bler_now(i) = estimateBLER_Enhanced(SINR_values(t,i), mcs_now(i));
            potential(i) = (1 - bler_now(i)) * tbsFromMCSandRB(mcs_now(i), total_RB) * 1e-3;
        end
        rb_alloc = schedule_users(scheduler_mode, t, N, R_emas, potential, total_RB);
        for i = 1:N
            bler(t,i) = bler_now(i);
            if rb_alloc(i) > 0
                tp(t,i) = (1 - bler_now(i)) * tbsFromMCSandRB(mcs_now(i), rb_alloc(i)) * 1e-3;
            end
        end
        R_emas = (1 - ema_alpha) * R_emas + ema_alpha * tp(t,:);
    end
end


function [tp, bler] = eval_QLearningShared_N(SINR_values, Q_table, scheduler_mode, total_RB)
    [T, N] = size(SINR_values); tp = zeros(T,N); bler = zeros(T,N);
    max_CQI = 15; min_CQI = 1; max_delta = 5; min_delta = -5;
    SINR_bins = linspace(-10, 30, 20); actions = [-2,-1,0,1,2];
    CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                      11.7, 14.1, 16.3, 18.7, 21.0, 22.7];
    prev_base = zeros(1,N);
    for i = 1:N
        idx = find(SINR_values(1,i) >= CQI_thresholds, 1, 'last');
        if isempty(idx), idx = min_CQI; end
        prev_base(i) = max(min_CQI, min(max_CQI, idx));
    end
    R_emas = zeros(1,N); ema_alpha = 0.05;
    for t = 1:T
        base_CQI = zeros(1,N);
        for i = 1:N
            idx = find(SINR_values(t,i) >= CQI_thresholds, 1, 'last');
            if isempty(idx), idx = min_CQI; end
            base_CQI(i) = max(min_CQI, min(max_CQI, idx));
        end
        d = max(min_delta, min(max_delta, base_CQI - prev_base));
        sent_CQI = zeros(1,N); bler_now = zeros(1,N); potential = zeros(1,N);
        for i = 1:N
            [~, si] = min(abs(SINR_bins - SINR_values(t,i)));
            s_d = d(i) + max_delta + 1;
            [~, a_idx] = max(Q_table(base_CQI(i), s_d, si, :));
            sent_CQI(i) = max(min_CQI, min(max_CQI, base_CQI(i) + actions(a_idx)));
            bler_now(i) = estimateBLER_Enhanced(SINR_values(t,i), sent_CQI(i)-1);
            potential(i) = (1 - bler_now(i)) * tbsFromMCSandRB(sent_CQI(i)-1, total_RB) * 1e-3;
        end
        rb_alloc = schedule_users(scheduler_mode, t, N, R_emas, potential, total_RB);
        for i = 1:N
            bler(t,i) = bler_now(i);
            if rb_alloc(i) > 0
                tp(t,i) = (1 - bler_now(i)) * tbsFromMCSandRB(sent_CQI(i)-1, rb_alloc(i)) * 1e-3;
            end
        end
        R_emas = (1 - ema_alpha) * R_emas + ema_alpha * tp(t,:);
        prev_base = base_CQI;
    end
end


function [tp, bler] = eval_TabACShared_N(SINR_values, theta, scheduler_mode, total_RB)
    [T, N] = size(SINR_values); tp = zeros(T,N); bler = zeros(T,N);
    max_CQI = 15; min_CQI = 1; max_delta = 5; min_delta = -5;
    SINR_bins = linspace(-10, 30, 20); actions = [-2,-1,0,1,2];
    CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                      11.7, 14.1, 16.3, 18.7, 21.0, 22.7];
    prev_base = zeros(1,N);
    for i = 1:N
        idx = find(SINR_values(1,i) >= CQI_thresholds, 1, 'last');
        if isempty(idx), idx = min_CQI; end
        prev_base(i) = max(min_CQI, min(max_CQI, idx));
    end
    R_emas = zeros(1,N); ema_alpha = 0.05;
    for t = 1:T
        base_CQI = zeros(1,N);
        for i = 1:N
            idx = find(SINR_values(t,i) >= CQI_thresholds, 1, 'last');
            if isempty(idx), idx = min_CQI; end
            base_CQI(i) = max(min_CQI, min(max_CQI, idx));
        end
        d = max(min_delta, min(max_delta, base_CQI - prev_base));
        sent_CQI = zeros(1,N); bler_now = zeros(1,N); potential = zeros(1,N);
        for i = 1:N
            [~, si] = min(abs(SINR_bins - SINR_values(t,i)));
            s_d = d(i) + max_delta + 1;
            prefs = squeeze(theta(base_CQI(i), s_d, si, :));
            prefs = prefs - max(prefs);
            pi_s  = exp(prefs) / sum(exp(prefs));
            [~, a_idx] = max(pi_s);
            sent_CQI(i) = max(min_CQI, min(max_CQI, base_CQI(i) + actions(a_idx)));
            bler_now(i) = estimateBLER_Enhanced(SINR_values(t,i), sent_CQI(i)-1);
            potential(i) = (1 - bler_now(i)) * tbsFromMCSandRB(sent_CQI(i)-1, total_RB) * 1e-3;
        end
        rb_alloc = schedule_users(scheduler_mode, t, N, R_emas, potential, total_RB);
        for i = 1:N
            bler(t,i) = bler_now(i);
            if rb_alloc(i) > 0
                tp(t,i) = (1 - bler_now(i)) * tbsFromMCSandRB(sent_CQI(i)-1, rb_alloc(i)) * 1e-3;
            end
        end
        R_emas = (1 - ema_alpha) * R_emas + ema_alpha * tp(t,:);
        prev_base = base_CQI;
    end
end


function [tp, bler] = eval_DeepAC_N(SINR_values, actorNet, scheduler_mode, total_RB)
    [T, N] = size(SINR_values); tp = zeros(T,N); bler = zeros(T,N);
    max_CQI = 15; min_CQI = 1; max_delta = 5; min_delta = -5;
    actions = [-2,-1,0,1,2];
    CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                      11.7, 14.1, 16.3, 18.7, 21.0, 22.7];
    prev_base = zeros(1,N);
    for i = 1:N
        idx = find(SINR_values(1,i) >= CQI_thresholds, 1, 'last');
        if isempty(idx), idx = min_CQI; end
        prev_base(i) = max(min_CQI, min(max_CQI, idx));
    end
    onGPU = isa(extractdata(actorNet.Learnables.Value{1}), 'gpuArray');
    R_emas = zeros(1,N); ema_alpha = 0.05;
    for t = 1:T
        base_CQI = zeros(1,N);
        for i = 1:N
            idx = find(SINR_values(t,i) >= CQI_thresholds, 1, 'last');
            if isempty(idx), idx = min_CQI; end
            base_CQI(i) = max(min_CQI, min(max_CQI, idx));
        end
        d = max(min_delta, min(max_delta, base_CQI - prev_base));

        S = single([base_CQI/15; d/5; SINR_values(t,:)/30]);
        if onGPU, S = gpuArray(S); end
        probs = gather(extractdata(predict(actorNet, dlarray(S, 'CB'))));

        sent_CQI = zeros(1,N); bler_now = zeros(1,N); potential = zeros(1,N);
        for i = 1:N
            [~, a_idx] = max(probs(:, i));
            sent_CQI(i) = max(min_CQI, min(max_CQI, base_CQI(i) + actions(a_idx)));
            bler_now(i) = estimateBLER_Enhanced(SINR_values(t,i), sent_CQI(i)-1);
            potential(i) = (1 - bler_now(i)) * tbsFromMCSandRB(sent_CQI(i)-1, total_RB) * 1e-3;
        end
        rb_alloc = schedule_users(scheduler_mode, t, N, R_emas, potential, total_RB);
        for i = 1:N
            bler(t,i) = bler_now(i);
            if rb_alloc(i) > 0
                tp(t,i) = (1 - bler_now(i)) * tbsFromMCSandRB(sent_CQI(i)-1, rb_alloc(i)) * 1e-3;
            end
        end
        R_emas = (1 - ema_alpha) * R_emas + ema_alpha * tp(t,:);
        prev_base = base_CQI;
    end
end


function plot_distance_curve(distance, data_cells, schemes, colors, styles, ttl, ylab, include_zeros)
    K = numel(data_cells);
    d_flat = distance(:);
    num_bins = 25;
    dmin = min(d_flat); dmax = max(d_flat);
    edges = linspace(dmin, dmax, num_bins + 1);
    centers = (edges(1:end-1) + edges(2:end)) / 2;
    figure('Position',[60 60 1000 500]);
    hold on; grid on;
    for k = 1:K
        v_flat = data_cells{k}(:);
        if ~include_zeros, mask_pos = v_flat > 0;
        else, mask_pos = true(size(v_flat)); end
        binned = nan(1, num_bins);
        for b = 1:num_bins
            in_bin = (d_flat >= edges(b)) & (d_flat < edges(b+1)) & mask_pos;
            if any(in_bin), binned(b) = mean(v_flat(in_bin)); end
        end
        plot(centers, binned, styles{k}, 'Color', colors{k}, 'LineWidth', 1.7);
    end
    xlabel('Distance from BS (m)'); ylabel(ylab); title(ttl);
    legend(schemes, 'Location', 'best');
end
