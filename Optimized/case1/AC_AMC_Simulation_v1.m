function [theta, V, ac_throughputs, ac_bler, ac_se, learning_curve_ac] = AC_AMC_Simulation_v1(simTime, num_episodes, seed, reward_mode)
% Tabular one-step Actor-Critic for AMC.
% State: (CQI, delta_CQI, SINR_bin). Action: CQI offset in {-2..+2}.
% Actor = softmax over theta(s,a). Critic = tabular V(s). TD(0) updates.

    if nargin < 1 || isempty(simTime),      simTime = 1000;             end
    if nargin < 2 || isempty(num_episodes), num_episodes = 1000;        end
    if nargin >= 3 && ~isempty(seed),       rng(seed);                  end
    if nargin < 4 || isempty(reward_mode),  reward_mode = 'throughput'; end

    % Channel parameters
    cellRadius = 500; fc = 2e9; hBS = 30; hUE = 1.5; txPower = 43; BW = 10e6;

    % State space
    max_CQI = 15;  min_CQI = 1;
    max_delta = 5; min_delta = -5;
    SINR_bins = linspace(-10, 30, 20);
    num_SINR_bins = numel(SINR_bins);

    % Action space
    actions     = [-2, -1, 0, 1, 2];
    num_actions = numel(actions);

    % Hyper-parameters
    alpha_theta  = 0.05;
    alpha_v      = 0.10;
    gamma        = 0.90;
    reward_scale = 30;     % normalize Mbps reward to keep softmax updates stable

    % Tables
    theta = zeros(max_CQI, max_delta-min_delta+1, num_SINR_bins, num_actions);
    V     = zeros(max_CQI, max_delta-min_delta+1, num_SINR_bins);

    learning_curve_ac = zeros(num_episodes, 1);
    ac_throughputs    = zeros(simTime, 1);
    ac_bler           = zeros(simTime, 1);
    ac_se             = zeros(simTime, 1);

    CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                      11.7, 14.1, 16.3, 18.7, 21.0, 22.7];

    for episode = 1:num_episodes

        [SINR_values, ~] = calculateControlledSINR2(simTime, cellRadius, fc, ...
                                                    hBS, hUE, txPower, BW);

        current_CQI = find(SINR_values(1) >= CQI_thresholds, 1, 'last');
        current_CQI = max(min_CQI, min(max_CQI, current_CQI));
        prev_CQI    = current_CQI;
        delta_CQI   = 0;
        episode_tp  = 0;

        for t = 1:simTime
            current_SINR  = SINR_values(t);
            [~, sinr_idx] = min(abs(SINR_bins - current_SINR));

            s_cqi   = current_CQI;
            s_delta = delta_CQI + max_delta + 1;
            s_sinr  = sinr_idx;

            % Softmax policy
            prefs = squeeze(theta(s_cqi, s_delta, s_sinr, :));
            prefs = prefs - max(prefs);
            pi_s  = exp(prefs) / sum(exp(prefs));

            action_idx = find(rand() <= cumsum(pi_s), 1, 'first');
            if isempty(action_idx), action_idx = num_actions; end
            action = actions(action_idx);

            new_CQI = max(min_CQI, min(max_CQI, current_CQI + action));

            % Environment step
            ac_MCS = new_CQI - 1;
            [ac_TBS, ~, ~] = selectTBSFromSINR(current_SINR);
            BLER_t   = estimateBLER_Enhanced(current_SINR, ac_MCS);
            tp_Mbps  = (1 - BLER_t) * ac_TBS * 1e-3;
            se_bphz  = tp_Mbps * 1e6 / BW;

            if episode == num_episodes
                ac_throughputs(t) = tp_Mbps;
                ac_bler(t)        = BLER_t;
                ac_se(t)          = se_bphz;
            end
            episode_tp = episode_tp + tp_Mbps;

            % Next state
            new_delta = max(min_delta, min(max_delta, new_CQI - prev_CQI));
            next_SINR = SINR_values(min(t+1, simTime));
            [~, next_sinr_i] = min(abs(SINR_bins - next_SINR));

            ns_cqi   = new_CQI;
            ns_delta = new_delta + max_delta + 1;

            % TD error
            reward   = computeReward(BLER_t, ac_TBS, reward_mode) / reward_scale;
            V_s      = V(s_cqi, s_delta, s_sinr);
            V_sprime = V(ns_cqi, ns_delta, next_sinr_i);
            delta    = reward + gamma * V_sprime - V_s;

            % Critic update
            V(s_cqi, s_delta, s_sinr) = V_s + alpha_v * delta;

            % Actor update: grad log pi(a|s) = 1{a'=a} - pi(a'|s)
            grad_log = -pi_s;
            grad_log(action_idx) = grad_log(action_idx) + 1;
            theta(s_cqi, s_delta, s_sinr, :) = ...
                squeeze(theta(s_cqi, s_delta, s_sinr, :)) + alpha_theta * delta * grad_log;

            prev_CQI    = current_CQI;
            current_CQI = new_CQI;
            delta_CQI   = new_delta;
        end

        learning_curve_ac(episode) = episode_tp / simTime;
    end
end
