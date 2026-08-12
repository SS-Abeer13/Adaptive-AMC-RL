function [thetas, Vs, tp_per_user, bler_per_user, learning_curve] = ...
            AC_AMC_Multi_v3(simTime, num_episodes, seed, reward_mode, scheduler_mode)
% Tabular Actor-Critic for 5-user AMC. v3 fixes for under-baseline issue:
%   (1) theta(:,:,:, no_op, :) = +1.0 -> softmax starts ~75% on no-offset
%   (2) Reward shaping: lambda * potential reward when not scheduled
%   (3) Imitation bonus: small +0.05 reward when chosen action equals 0 (no offset)
%   (4) 500 episode default
%   (5) Reward normalization /30

    if nargin < 1 || isempty(simTime),        simTime = 100;              end
    if nargin < 2 || isempty(num_episodes),   num_episodes = 500;         end
    if nargin >= 3 && ~isempty(seed),         rng(seed);                  end
    if nargin < 4 || isempty(reward_mode),    reward_mode = 'throughput'; end
    if nargin < 5 || isempty(scheduler_mode), scheduler_mode = 'pf';      end

    N        = 5;
    bsPos    = [500, 500];
    fc       = 2e9; hBS = 30; txPower = 43; BW = 10e6;
    total_RB = 110;

    max_CQI = 15; min_CQI = 1;
    max_delta = 5; min_delta = -5;
    SINR_bins = linspace(-10, 30, 20);
    num_SINR_bins = numel(SINR_bins);

    actions     = [-2, -1, 0, 1, 2];
    num_actions = numel(actions);
    no_op_idx   = find(actions == 0);

    alpha_theta  = 0.05;
    alpha_v      = 0.10;
    gamma        = 0.90;
    reward_scale = 30;
    ema_alpha    = 0.05;
    lambda_potential = 0.1;
    imit_bonus   = 0.05;

    thetas = zeros(max_CQI, max_delta-min_delta+1, num_SINR_bins, num_actions, N);
    thetas(:,:,:, no_op_idx, :) = 1.0;
    Vs     = zeros(max_CQI, max_delta-min_delta+1, num_SINR_bins, N);

    learning_curve = zeros(num_episodes, 1);
    tp_per_user    = zeros(simTime, N);
    bler_per_user  = zeros(simTime, N);

    CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                      11.7, 14.1, 16.3, 18.7, 21.0, 22.7];

    try, hwb = waitbar(0, 'Tabular AC v3', 'Name', 'AC v3 training');
    catch, hwb = []; end

    for episode = 1:num_episodes
        [S1,S2,S3,S4,S5,~,~,~,~,~] = calculateControlledSINR2(simTime, fc, hBS, txPower, BW, N, bsPos);
        SINR_values = [S1, S2, S3, S4, S5];

        cur_CQI = zeros(1, N); prev_CQI = zeros(1, N); delta_CQI = zeros(1, N);
        for i = 1:N
            idx = find(SINR_values(1, i) >= CQI_thresholds, 1, 'last');
            if isempty(idx), idx = min_CQI; end
            cur_CQI(i)  = max(min_CQI, min(max_CQI, idx));
            prev_CQI(i) = cur_CQI(i);
        end
        R_emas = zeros(1, N);
        episode_tp_sum = 0;

        for t = 1:simTime
            action_idx = zeros(1, N); new_CQI = zeros(1, N);
            BLER_now = zeros(1, N);
            potential_rates = zeros(1, N); potential_TBS = zeros(1, N);
            pi_state = cell(1, N); state_idx = zeros(N, 3);

            for i = 1:N
                sinr_i = SINR_values(t, i);
                [~, sinr_bin] = min(abs(SINR_bins - sinr_i));
                s_cqi   = cur_CQI(i);
                s_delta = delta_CQI(i) + max_delta + 1;
                state_idx(i, :) = [s_cqi, s_delta, sinr_bin];

                prefs = squeeze(thetas(s_cqi, s_delta, sinr_bin, :, i));
                prefs = prefs - max(prefs);
                pi_s  = exp(prefs) / sum(exp(prefs));
                pi_state{i} = pi_s;

                a_idx = find(rand() <= cumsum(pi_s), 1, 'first');
                if isempty(a_idx), a_idx = num_actions; end
                action_idx(i) = a_idx;

                new_CQI(i) = max(min_CQI, min(max_CQI, cur_CQI(i) + actions(a_idx)));
                mcs_i      = new_CQI(i) - 1;
                BLER_now(i) = estimateBLER_Enhanced(sinr_i, mcs_i);
                potential_TBS(i)   = tbsFromMCSandRB(mcs_i, total_RB);
                potential_rates(i) = (1 - BLER_now(i)) * potential_TBS(i) * 1e-3;
            end

            rb_alloc = schedule_users(scheduler_mode, t, N, R_emas, potential_rates, total_RB);

            tp_now = zeros(1, N);
            for i = 1:N
                if rb_alloc(i) > 0
                    tp_now(i) = (1 - BLER_now(i)) * tbsFromMCSandRB(new_CQI(i)-1, rb_alloc(i)) * 1e-3;
                end
            end
            R_emas = (1 - ema_alpha) * R_emas + ema_alpha * tp_now;
            episode_tp_sum = episode_tp_sum + sum(tp_now);

            if episode == num_episodes
                tp_per_user(t, :)   = tp_now;
                bler_per_user(t, :) = BLER_now;
            end

            for i = 1:N
                if rb_alloc(i) > 0
                    actual_tbs = tbsFromMCSandRB(new_CQI(i) - 1, rb_alloc(i));
                    raw_reward = computeReward(BLER_now(i), actual_tbs, reward_mode);
                else
                    raw_reward = lambda_potential * computeReward(BLER_now(i), potential_TBS(i), reward_mode);
                end
                % Imitation bonus when agent matches "no offset" (helps converge to baseline first)
                if action_idx(i) == no_op_idx
                    raw_reward = raw_reward + imit_bonus * reward_scale;
                end
                reward = raw_reward / reward_scale;

                new_delta = max(min_delta, min(max_delta, new_CQI(i) - prev_CQI(i)));
                next_SINR = SINR_values(min(t+1, simTime), i);
                [~, next_sinr_bin] = min(abs(SINR_bins - next_SINR));

                s_cqi   = state_idx(i, 1);
                s_delta = state_idx(i, 2);
                s_sinr  = state_idx(i, 3);

                V_s      = Vs(s_cqi, s_delta, s_sinr, i);
                V_sprime = Vs(new_CQI(i), new_delta + max_delta + 1, next_sinr_bin, i);
                delta    = reward + gamma * V_sprime - V_s;

                Vs(s_cqi, s_delta, s_sinr, i) = V_s + alpha_v * delta;

                grad_log = -pi_state{i};
                grad_log(action_idx(i)) = grad_log(action_idx(i)) + 1;
                thetas(s_cqi, s_delta, s_sinr, :, i) = ...
                    squeeze(thetas(s_cqi, s_delta, s_sinr, :, i)) + alpha_theta * delta * grad_log;

                prev_CQI(i)  = cur_CQI(i);
                cur_CQI(i)   = new_CQI(i);
                delta_CQI(i) = new_delta;
            end
        end

        learning_curve(episode) = episode_tp_sum / simTime;
        if ~isempty(hwb) && isvalid(hwb)
            waitbar(episode/num_episodes, hwb, sprintf('AC v3 ep %d/%d  Tp=%.2f', episode, num_episodes, learning_curve(episode)));
        end
    end
    if ~isempty(hwb) && isvalid(hwb), delete(hwb); end
end
