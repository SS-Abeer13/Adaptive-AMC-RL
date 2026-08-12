function results = runComparison_Multi_GPU_v1(simTime, num_episodes_tabular, num_episodes_deep, seed, scheduler_mode)
% Multi-user RL-AMC comparison with GPU Deep A2C, logging, waitbar, and
% distance-sorted throughput / BLER plots per scheme.

    if nargin < 1 || isempty(simTime),              simTime = 100;             end
    if nargin < 2 || isempty(num_episodes_tabular), num_episodes_tabular = 200; end
    if nargin < 3 || isempty(num_episodes_deep),    num_episodes_deep = 100;   end
    if nargin < 4 || isempty(seed),                 seed = 42;                 end
    if nargin < 5 || isempty(scheduler_mode),       scheduler_mode = 'pf';     end

    N        = 5;
    bsPos    = [500, 500];
    fc       = 2e9;
    hBS      = 30;
    txPower  = 43;
    BW       = 10e6;
    total_RB = 110;
    reward_mode = 'throughput';

    here = fileparts(mfilename('fullpath'));
    log_path = fullfile(here, 'comparison_log.txt');
    log_fid  = fopen(log_path, 'w');
    log = @(varargin) fprintf(log_fid, '[%s] %s\n', datestr(now,'HH:MM:SS'), sprintf(varargin{:}));

    log('runComparison_Multi_GPU start: simTime=%d ep_tab=%d ep_deep=%d seed=%d sched=%s', ...
        simTime, num_episodes_tabular, num_episodes_deep, seed, scheduler_mode);
    fprintf('Multi-user AMC Comparison (GPU) [N=%d, scheduler=%s]\n', N, scheduler_mode);

    try
        % ===== TRAIN =====
        h_top = waitbar(0, 'Phase 1/3: Q-Learning', 'Name', 'Multi-user Comparison');

        log('Training tabular Q-Learning ...');
        fprintf('[1/3] Training tabular Q-Learning ...\n');
        rng(seed);
        [Q_tables, ql_curve] = trainQLearning_Multi(simTime, num_episodes_tabular, reward_mode, scheduler_mode);
        waitbar(1/3, h_top, 'Phase 2/3: Tabular AC');

        log('Training tabular Actor-Critic ...');
        fprintf('[2/3] Training tabular Actor-Critic ...\n');
        [thetas, ~, ~, ~, ac_curve] = AC_AMC_Multi_v1(simTime, num_episodes_tabular, seed, reward_mode, scheduler_mode);
        waitbar(2/3, h_top, 'Phase 3/3: Deep A2C (GPU)');

        log('Training Deep A2C (GPU) ...');
        fprintf('[3/3] Training Deep A2C (GPU) ...\n');
        [actorNet, ~, ~, ~, dac_curve] = DeepAC_AMC_Multi_GPU_v1(simTime, num_episodes_deep, seed, reward_mode, scheduler_mode);
        waitbar(1, h_top, 'Evaluation ...');

        % ===== EVAL =====
        log('Generating evaluation trace seed=%d', seed + 999);
        rng(seed + 999);
        [S1,S2,S3,S4,S5,U1,U2,U3,U4,U5] = calculateControlledSINR2(simTime, fc, hBS, txPower, BW, N, bsPos);
        SINR_eval = [S1, S2, S3, S4, S5];
        uePos = zeros(simTime, 2, N);
        uePos(:,:,1) = U1; uePos(:,:,2) = U2; uePos(:,:,3) = U3; uePos(:,:,4) = U4; uePos(:,:,5) = U5;

        % Distance per (t, i) and (BS distance)
        distance = zeros(simTime, N);
        for i = 1:N
            for t = 1:simTime
                distance(t,i) = norm(squeeze(uePos(t,:,i)) - bsPos);
            end
        end

        [tp_base, bler_base] = eval_Baseline_Multi  (SINR_eval, scheduler_mode, total_RB);
        [tp_ql,   bler_ql  ] = eval_QLearning_Multi (SINR_eval, Q_tables, scheduler_mode, total_RB);
        [tp_ac,   bler_ac  ] = eval_TabularAC_Multi (SINR_eval, thetas,   scheduler_mode, total_RB);
        [tp_dac,  bler_dac ] = eval_DeepAC_Multi_GPU(SINR_eval, actorNet, scheduler_mode, total_RB);

        schemes  = {'Baseline', 'Q-Learning', 'Tabular AC', 'Deep A2C (GPU)'};
        tp_cells = {tp_base, tp_ql, tp_ac, tp_dac};
        bl_cells = {bler_base, bler_ql, bler_ac, bler_dac};

        % ===== AGGREGATE METRICS =====
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

        log('Results: cell_tp = [%s]', sprintf('%.3f ', cell_tp));
        fprintf('\n%-15s | %10s | %8s | %12s | %12s\n', 'Scheme', 'Tp(Mbps)', 'BLER', 'SE(b/s/Hz)', 'Jain');
        fprintf('----------------+------------+----------+--------------+--------------\n');
        for k = 1:4
            fprintf('%-15s | %10.3f | %8.4f | %12.3f | %12.3f\n', ...
                    schemes{k}, cell_tp(k), mean_bler(k), se_bphz(k), jain(k));
        end

        % ===== PLOTS =====
        % (1) KPI bar chart
        figure('Position',[60 60 1100 380]);
        subplot(1,3,1); bar(cell_tp);   set(gca,'XTickLabel',schemes,'XTickLabelRotation',30);
                        ylabel('Cell Tp (Mbps)'); title('Aggregate Throughput'); grid on;
        subplot(1,3,2); bar(mean_bler); set(gca,'XTickLabel',schemes,'XTickLabelRotation',30);
                        ylabel('Mean BLER');      title('BLER (served TTIs)'); grid on;
        subplot(1,3,3); bar(jain);      set(gca,'XTickLabel',schemes,'XTickLabelRotation',30);
                        ylabel('Jain index');     title('Fairness'); grid on; ylim([0 1.05]);

        % (2) Learning curves
        figure('Position',[60 60 950 500]);
        plot(ql_curve, 'r', 'LineWidth', 1.5); hold on;
        plot(ac_curve, 'b', 'LineWidth', 1.5);
        x_deep = linspace(1, numel(ql_curve), numel(dac_curve));
        plot(x_deep, dac_curve, 'g', 'LineWidth', 1.8);
        grid on; xlabel('Episode (relative)'); ylabel('Cell Tp per episode (Mbps)');
        title('Learning Curves'); legend({'Q-Learn','Tab AC','Deep A2C (GPU)'}, 'Location','best');

        % (3) Throughput vs distance (sorted, binned)
        colors = {[0 0 0], [0.85 0.15 0.15], [0.15 0.3 0.85], [0.1 0.65 0.2]};
        styles = {'--', '-', '-', '-'};
        plot_distance_curve(distance, tp_cells, schemes, colors, styles, ...
            'Throughput vs Distance', 'Throughput (Mbps)', false);

        % (4) BLER vs distance (sorted, binned)
        plot_distance_curve(distance, bl_cells, schemes, colors, styles, ...
            'BLER vs Distance', 'BLER', true);

        % (5) Per-scheme per-user throughput vs sorted distance (4-panel)
        figure('Position',[60 60 1100 700]);
        for k = 1:4
            subplot(2,2,k);
            hold on; grid on;
            for i = 1:N
                d_i  = distance(:, i);
                tp_i = tp_cells{k}(:, i);
                [d_sorted, idx] = sort(d_i);
                tp_sorted = tp_i(idx);
                plot(d_sorted, smooth_safe(tp_sorted, 10), 'LineWidth', 1.2);
            end
            xlabel('Distance from BS (m)'); ylabel('Tp_i (Mbps)');
            title(schemes{k});
            if k == 1
                legend(arrayfun(@(i) sprintf('UE %d', i), 1:N, 'UniformOutput', false), 'Location','best');
            end
        end
        sgtitle('Per-User Throughput vs Distance (sorted)');

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

        save(fullfile(here, sprintf('multi_results_gpu_%s.mat', scheduler_mode)), 'results');
        log('Saved comparison_results to multi_results_gpu_%s.mat', scheduler_mode);

        if isvalid(h_top), delete(h_top); end
        fclose(log_fid);

    catch ME
        log('FATAL: %s', ME.message);
        for kk = 1:numel(ME.stack)
            log('  at %s:%d (%s)', ME.stack(kk).file, ME.stack(kk).line, ME.stack(kk).name);
        end
        try, if isvalid(h_top), delete(h_top); end, catch, end
        fclose(log_fid);
        rethrow(ME);
    end
end


function plot_distance_curve(distance, data_cells, schemes, colors, styles, ttl, ylab, include_zeros)
% Bin (distance, value) pairs over all users into 25 distance bins and plot
% mean value per bin for each scheme.

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
        if ~include_zeros
            mask_pos = v_flat > 0;
        else
            mask_pos = true(size(v_flat));
        end
        binned = nan(1, num_bins);
        for b = 1:num_bins
            in_bin = (d_flat >= edges(b)) & (d_flat < edges(b+1)) & mask_pos;
            if any(in_bin), binned(b) = mean(v_flat(in_bin)); end
        end
        plot(centers, binned, styles{k}, 'Color', colors{k}, 'LineWidth', 1.7);
    end
    xlabel('Distance from BS (m)');
    ylabel(ylab);
    title(ttl);
    legend(schemes, 'Location', 'best');
end


function y = smooth_safe(x, win)
    if numel(x) < win, y = x; return; end
    y = movmean(x, win);
end


function [Q_table, learning_curve] = trainQLearning_Multi(simTime, num_episodes, reward_mode, scheduler_mode)
    N = 5; bsPos = [500,500]; fc = 2e9; hBS = 30; txPower = 43; BW = 10e6; total_RB = 110;
    alpha = 0.1; gamma = 0.9; epsilon = 0.2; epsilon_decay = 0.995; ema_alpha = 0.05;
    max_CQI = 15; min_CQI = 1; max_delta = 5; min_delta = -5;
    SINR_bins = linspace(-10, 30, 20);
    actions = [-2,-1,0,1,2]; num_actions = numel(actions);
    Q_table = zeros(max_CQI, max_delta-min_delta+1, numel(SINR_bins), num_actions, N);
    learning_curve = zeros(num_episodes, 1);
    CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                      11.7, 14.1, 16.3, 18.7, 21.0, 22.7];
    try
        hwb = waitbar(0, 'Q-Learning', 'Name', 'Q-Learning training');
    catch, hwb = []; end
    for episode = 1:num_episodes
        [S1,S2,S3,S4,S5,~,~,~,~,~] = calculateControlledSINR2(simTime, fc, hBS, txPower, BW, N, bsPos);
        SINR_values = [S1, S2, S3, S4, S5];
        cur = zeros(1,N); prev = zeros(1,N); d = zeros(1,N);
        for i = 1:N
            idx = find(SINR_values(1,i) >= CQI_thresholds, 1, 'last');
            if isempty(idx), idx = min_CQI; end
            cur(i) = max(min_CQI, min(max_CQI, idx)); prev(i) = cur(i);
        end
        R_emas = zeros(1,N); ep_tp = 0;
        for t = 1:simTime
            a_idx = zeros(1,N); new_CQI = zeros(1,N); bler = zeros(1,N); potential = zeros(1,N);
            for i = 1:N
                sinr_i = SINR_values(t,i);
                [~, si] = min(abs(SINR_bins - sinr_i)); s_d = d(i) + max_delta + 1;
                if rand() < epsilon, a_idx(i) = randi(num_actions);
                else, [~, a_idx(i)] = max(Q_table(cur(i), s_d, si, :, i)); end
                new_CQI(i)   = max(min_CQI, min(max_CQI, cur(i) + actions(a_idx(i))));
                bler(i)      = estimateBLER_Enhanced(sinr_i, new_CQI(i)-1);
                potential(i) = (1 - bler(i)) * tbsFromMCSandRB(new_CQI(i)-1, total_RB) * 1e-3;
            end
            rb_alloc = schedule_users(scheduler_mode, t, N, R_emas, potential, total_RB);
            tp_now = zeros(1,N);
            for i = 1:N
                if rb_alloc(i) > 0
                    tp_now(i) = (1 - bler(i)) * tbsFromMCSandRB(new_CQI(i)-1, rb_alloc(i)) * 1e-3;
                end
            end
            R_emas = (1 - ema_alpha) * R_emas + ema_alpha * tp_now; ep_tp = ep_tp + sum(tp_now);
            for i = 1:N
                [~, si] = min(abs(SINR_bins - SINR_values(t,i)));
                s_d = d(i) + max_delta + 1;
                if rb_alloc(i) > 0
                    actual_tbs = tbsFromMCSandRB(new_CQI(i)-1, rb_alloc(i));
                    r = computeReward(bler(i), actual_tbs, reward_mode);
                else, r = 0; end
                new_delta = max(min_delta, min(max_delta, new_CQI(i) - prev(i)));
                next_SINR = SINR_values(min(t+1, simTime), i);
                [~, next_si] = min(abs(SINR_bins - next_SINR));
                max_nextQ = max(Q_table(new_CQI(i), new_delta+max_delta+1, next_si, :, i));
                Q_table(cur(i), s_d, si, a_idx(i), i) = Q_table(cur(i), s_d, si, a_idx(i), i) + ...
                    alpha * (r + gamma * max_nextQ - Q_table(cur(i), s_d, si, a_idx(i), i));
                prev(i) = cur(i); cur(i) = new_CQI(i); d(i) = new_delta;
            end
        end
        learning_curve(episode) = ep_tp / simTime;
        epsilon = epsilon * epsilon_decay;
        if ~isempty(hwb) && isvalid(hwb)
            waitbar(episode/num_episodes, hwb, sprintf('QL ep %d/%d  Tp=%.2f', episode, num_episodes, learning_curve(episode)));
        end
    end
    if ~isempty(hwb) && isvalid(hwb), delete(hwb); end
end


function [tp, bler] = eval_Baseline_Multi(SINR_values, scheduler_mode, total_RB)
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


function [tp, bler] = eval_QLearning_Multi(SINR_values, Q_table, scheduler_mode, total_RB)
    [T, N] = size(SINR_values); tp = zeros(T,N); bler = zeros(T,N);
    max_CQI = 15; min_CQI = 1; max_delta = 5; min_delta = -5;
    SINR_bins = linspace(-10, 30, 20); actions = [-2,-1,0,1,2];
    CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                      11.7, 14.1, 16.3, 18.7, 21.0, 22.7];
    cur = zeros(1,N); prev = zeros(1,N); d = zeros(1,N);
    for i = 1:N
        idx = find(SINR_values(1,i) >= CQI_thresholds, 1, 'last');
        if isempty(idx), idx = min_CQI; end
        cur(i) = max(min_CQI, min(max_CQI, idx)); prev(i) = cur(i);
    end
    R_emas = zeros(1,N); ema_alpha = 0.05;
    for t = 1:T
        new_CQI = zeros(1,N); bler_now = zeros(1,N); potential = zeros(1,N);
        for i = 1:N
            [~, si] = min(abs(SINR_bins - SINR_values(t,i)));
            s_d = d(i) + max_delta + 1;
            [~, a_idx] = max(Q_table(cur(i), s_d, si, :, i));
            new_CQI(i) = max(min_CQI, min(max_CQI, cur(i) + actions(a_idx)));
            bler_now(i) = estimateBLER_Enhanced(SINR_values(t,i), new_CQI(i)-1);
            potential(i) = (1 - bler_now(i)) * tbsFromMCSandRB(new_CQI(i)-1, total_RB) * 1e-3;
        end
        rb_alloc = schedule_users(scheduler_mode, t, N, R_emas, potential, total_RB);
        for i = 1:N
            bler(t,i) = bler_now(i);
            if rb_alloc(i) > 0
                tp(t,i) = (1 - bler_now(i)) * tbsFromMCSandRB(new_CQI(i)-1, rb_alloc(i)) * 1e-3;
            end
            new_delta = max(min_delta, min(max_delta, new_CQI(i) - prev(i)));
            prev(i) = cur(i); cur(i) = new_CQI(i); d(i) = new_delta;
        end
        R_emas = (1 - ema_alpha) * R_emas + ema_alpha * tp(t,:);
    end
end


function [tp, bler] = eval_TabularAC_Multi(SINR_values, theta, scheduler_mode, total_RB)
    [T, N] = size(SINR_values); tp = zeros(T,N); bler = zeros(T,N);
    max_CQI = 15; min_CQI = 1; max_delta = 5; min_delta = -5;
    SINR_bins = linspace(-10, 30, 20); actions = [-2,-1,0,1,2];
    CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                      11.7, 14.1, 16.3, 18.7, 21.0, 22.7];
    cur = zeros(1,N); prev = zeros(1,N); d = zeros(1,N);
    for i = 1:N
        idx = find(SINR_values(1,i) >= CQI_thresholds, 1, 'last');
        if isempty(idx), idx = min_CQI; end
        cur(i) = max(min_CQI, min(max_CQI, idx)); prev(i) = cur(i);
    end
    R_emas = zeros(1,N); ema_alpha = 0.05;
    for t = 1:T
        new_CQI = zeros(1,N); bler_now = zeros(1,N); potential = zeros(1,N);
        for i = 1:N
            [~, si] = min(abs(SINR_bins - SINR_values(t,i)));
            s_d = d(i) + max_delta + 1;
            prefs = squeeze(theta(cur(i), s_d, si, :, i));
            prefs = prefs - max(prefs);
            pi_s  = exp(prefs) / sum(exp(prefs));
            [~, a_idx] = max(pi_s);
            new_CQI(i) = max(min_CQI, min(max_CQI, cur(i) + actions(a_idx)));
            bler_now(i) = estimateBLER_Enhanced(SINR_values(t,i), new_CQI(i)-1);
            potential(i) = (1 - bler_now(i)) * tbsFromMCSandRB(new_CQI(i)-1, total_RB) * 1e-3;
        end
        rb_alloc = schedule_users(scheduler_mode, t, N, R_emas, potential, total_RB);
        for i = 1:N
            bler(t,i) = bler_now(i);
            if rb_alloc(i) > 0
                tp(t,i) = (1 - bler_now(i)) * tbsFromMCSandRB(new_CQI(i)-1, rb_alloc(i)) * 1e-3;
            end
            new_delta = max(min_delta, min(max_delta, new_CQI(i) - prev(i)));
            prev(i) = cur(i); cur(i) = new_CQI(i); d(i) = new_delta;
        end
        R_emas = (1 - ema_alpha) * R_emas + ema_alpha * tp(t,:);
    end
end


function [tp, bler] = eval_DeepAC_Multi_GPU(SINR_values, actorNet, scheduler_mode, total_RB)
    [T, N] = size(SINR_values); tp = zeros(T,N); bler = zeros(T,N);
    max_CQI = 15; min_CQI = 1; max_delta = 5; min_delta = -5;
    actions = [-2,-1,0,1,2];
    CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                      11.7, 14.1, 16.3, 18.7, 21.0, 22.7];
    cur = zeros(1,N); prev = zeros(1,N); d = zeros(1,N);
    for i = 1:N
        idx = find(SINR_values(1,i) >= CQI_thresholds, 1, 'last');
        if isempty(idx), idx = min_CQI; end
        cur(i) = max(min_CQI, min(max_CQI, idx)); prev(i) = cur(i);
    end
    onGPU = isa(extractdata(actorNet.Learnables.Value{1}), 'gpuArray');
    R_emas = zeros(1,N); ema_alpha = 0.05;
    for t = 1:T
        S = single([cur/15; d/5; SINR_values(t,:)/30]);
        if onGPU, S = gpuArray(S); end
        probs = gather(extractdata(predict(actorNet, dlarray(S, 'CB'))));
        new_CQI = zeros(1,N); bler_now = zeros(1,N); potential = zeros(1,N);
        for i = 1:N
            [~, a_idx] = max(probs(:, i));
            new_CQI(i) = max(min_CQI, min(max_CQI, cur(i) + actions(a_idx)));
            bler_now(i) = estimateBLER_Enhanced(SINR_values(t,i), new_CQI(i)-1);
            potential(i) = (1 - bler_now(i)) * tbsFromMCSandRB(new_CQI(i)-1, total_RB) * 1e-3;
        end
        rb_alloc = schedule_users(scheduler_mode, t, N, R_emas, potential, total_RB);
        for i = 1:N
            bler(t,i) = bler_now(i);
            if rb_alloc(i) > 0
                tp(t,i) = (1 - bler_now(i)) * tbsFromMCSandRB(new_CQI(i)-1, rb_alloc(i)) * 1e-3;
            end
            new_delta = max(min_delta, min(max_delta, new_CQI(i) - prev(i)));
            prev(i) = cur(i); cur(i) = new_CQI(i); d(i) = new_delta;
        end
        R_emas = (1 - ema_alpha) * R_emas + ema_alpha * tp(t,:);
    end
end
