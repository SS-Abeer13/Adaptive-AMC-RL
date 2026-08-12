function [Q_table, learning_curve] = QL_AMC_Multi_v4(simTime, num_episodes, seed, env)
% QL_AMC_Multi_v4  Tabular Q-Learning on the unified v4 MDP.  (v4.1)
%   State  : (cur_CQI, delta_CQI, obs_SINR bin, trend bin)  -- observed (C2)
%   Action : CQI offset in {-2..+2} (differential)
%   Reward : computeReward_v4 on achieved TBS (0 when unscheduled)
%   No bias-init, no imitation bonus (C3/C4). gamma = env.gamma.
%   v4.1: observed-trend state dimension; greedy ties broken toward no-op
%   (plain max() picked action -2 in unvisited states and collapsed the run).

    if ~isempty(seed), rng(seed); end
    N = env.N;
    actions = env.actions; num_actions = numel(actions);
    no_op = find(actions == 0);
    SINR_bins = env.SINR_bins;
    maxC = env.max_CQI; minC = env.min_CQI;
    maxD = env.max_delta; minD = env.min_delta;
    nT = env.n_trend; te = env.trend_edges;

    alpha = 0.1;
    gamma = env.gamma;
    epsilon = 0.30;
    eps_decay = (0.05 / 0.30)^(1 / max(num_episodes, 1));

    Q_table = zeros(maxC, maxD-minD+1, numel(SINR_bins), nT, num_actions, N);
    learning_curve = zeros(num_episodes, 1);

    for ep = 1:num_episodes
        [SINR_true, ~, ~] = generateChannel_v4(simTime, env);
        [obs_SINR, obs_CQI] = cqiFeedback_v4(SINR_true, env);

        cur = obs_CQI(1, :); prev = cur; d = zeros(1, N);
        R_emas = zeros(1, N); ema_a = 0.05; ep_tp = 0;

        for t = 1:simTime
            a_idx = zeros(1,N); new_CQI = zeros(1,N);
            bler = zeros(1,N); pot = zeros(1,N);
            si = zeros(1,N); tb = zeros(1,N);
            for i = 1:N
                [~, si(i)] = min(abs(SINR_bins - obs_SINR(t, i)));
                dS = obs_SINR(t, i) - obs_SINR(max(t-1, 1), i);
                tb(i) = trendBin_v4(dS, te);
                sd = d(i) + maxD + 1;
                if rand < epsilon
                    a_idx(i) = randi(num_actions);
                else
                    a_idx(i) = argmaxNoOp_v4( ...
                        squeeze(Q_table(cur(i), sd, si(i), tb(i), :, i)), no_op);
                end
                new_CQI(i) = max(minC, min(maxC, cur(i) + actions(a_idx(i))));
                mcs = new_CQI(i) - 1;
                bler(i) = estimateBLER_v4(SINR_true(t, i), mcs);   % true channel
                pot(i)  = (1 - bler(i)) * tbsFromMCSandRB(mcs, env.total_RB) * 1e-3;
            end

            rb = schedule_users_v4(env.scheduler, t, N, R_emas, pot, env.total_RB);

            tp_now = zeros(1, N);
            for i = 1:N
                if rb(i) > 0
                    tp_now(i) = (1 - bler(i)) * ...
                                tbsFromMCSandRB(new_CQI(i)-1, rb(i)) * 1e-3;
                end
            end
            R_emas = (1 - ema_a) * R_emas + ema_a * tp_now;
            ep_tp = ep_tp + sum(tp_now);

            for i = 1:N
                if rb(i) > 0
                    r = computeReward_v4(bler(i), tbsFromMCSandRB(new_CQI(i)-1, rb(i)), env);
                else
                    r = 0;
                end
                nd = max(minD, min(maxD, new_CQI(i) - prev(i)));
                tn = min(t+1, simTime);
                [~, nsi] = min(abs(SINR_bins - obs_SINR(tn, i)));
                ntb = trendBin_v4(obs_SINR(tn, i) - obs_SINR(t, i), te);
                sd = d(i) + maxD + 1;
                maxQ = max(Q_table(new_CQI(i), nd+maxD+1, nsi, ntb, :, i));
                Q_table(cur(i), sd, si(i), tb(i), a_idx(i), i) = ...
                    Q_table(cur(i), sd, si(i), tb(i), a_idx(i), i) + ...
                    alpha * (r + gamma * maxQ - ...
                             Q_table(cur(i), sd, si(i), tb(i), a_idx(i), i));
                prev(i) = cur(i); cur(i) = new_CQI(i); d(i) = nd;
            end
        end
        learning_curve(ep) = ep_tp / simTime;
        epsilon = epsilon * eps_decay;
    end
end
